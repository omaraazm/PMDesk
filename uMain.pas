unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, uConfig, uApiTypes, uApiErrors, uPropertyApi,
  Vcl.StdCtrls, Vcl.ExtCtrls, Data.DB, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf,
  FireDAC.DApt.Intf, FireDAC.Comp.DataSet, FireDAC.Comp.Client, Vcl.Grids,
  Vcl.DBGrids, Vcl.ComCtrls;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    btnRefresh: TButton;
    btnSignOut: TButton;
    lblUser: TLabel;
    pnlProperties: TPanel;
    StatusBar1: TStatusBar;
    grdProperties: TDBGrid;
    mtProperties: TFDMemTable;
    dsProperties: TDataSource;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnSignOutClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
      private
    FConfig: TAppConfig;
    FApi: TPropertyApi;
    FUser: TUserRec;
    FPending: Integer;      // requests still running
    FFilling: Boolean;      // True while code fills a table (used from g.9 on)
    procedure SetBusy(Busy: Boolean; const Status: string);
    procedure HandleApiError(const Err: TApiErrorInfo);
    procedure SignIn;
    procedure DefinePropertiesTable;
    procedure LoadProperties;
    procedure FillProperties(const Items: TPropertyArray);
  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses uLogin, uAsync, uDataSets;
// 'under_construction' -> 'under construction', for display only
function Pretty(const S: string): string;
begin
  Result := StringReplace(S, '_', ' ', [rfReplaceAll]);
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FPending = 0;                 // no closing while a request runs
  if not CanClose then
    StatusBar1.SimpleText := 'Still waiting for the server - try again in a moment.';
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FConfig := TAppConfig.Create;
  FConfig.Load;
  FApi := TPropertyApi.Create(FConfig.BaseUrl, FConfig.ConnectTimeoutMs,
    FConfig.ResponseTimeoutMs);
  Caption := 'PMDesk - ' + FConfig.BaseUrl;
  DefinePropertiesTable;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FApi.Free;
  FConfig.Free;
end;
procedure TfrmMain.FormShow(Sender: TObject);
begin
  // Let the main window finish appearing, then ask for the login.
  // ForceQueue: run this later, on this same (main) thread.
  TThread.ForceQueue(nil,
    procedure
    begin
      SignIn;
    end);
end;

procedure TfrmMain.SignIn;
begin
  if FConfig.IsPlaceholder then
  begin
    MessageDlg('Set BaseUrl in ' + FConfig.FileName + ', then start PMDesk again.',
      mtWarning, [mbOK], 0);
    Close;
    Exit;
  end;
  if TfrmLogin.Execute(FApi, FConfig, FUser) then
  begin
    lblUser.Caption := Format('%s  (%s)', [FUser.FullName, FUser.Email]);
    LoadProperties;
  end
  else
    Close;
end;

procedure TfrmMain.SetBusy(Busy: Boolean; const Status: string);
begin
  if Busy then
    Inc(FPending)
  else if FPending > 0 then
    Dec(FPending);
  if Status <> '' then
    StatusBar1.SimpleText := Status
  else if FPending > 0 then
    StatusBar1.SimpleText := 'Working...'
  else
    StatusBar1.SimpleText := 'Ready';
  btnRefresh.Enabled := FPending = 0;
  btnSignOut.Enabled := FPending = 0;
end;

procedure TfrmMain.HandleApiError(const Err: TApiErrorInfo);
begin
  // Saturday version: show it. g.12 replaces this with one that signs in
  // again when the token has expired.
  MessageDlg(Err.UserText, mtError, [mbOK], 0);
end;

procedure TfrmMain.btnRefreshClick(Sender: TObject);
begin
  LoadProperties;
end;

procedure TfrmMain.btnSignOutClick(Sender: TObject);
begin
  FApi.ClearTokens;                         // forgotten: nothing was ever saved
  mtProperties.EmptyDataSet;
  lblUser.Caption := 'Not signed in';
  SignIn;
end;

procedure TfrmMain.DefinePropertiesTable;
begin
  AddHidden(mtProperties, 'Id');
  AddText(mtProperties, 'Name', 'Name', 18);
  AddText(mtProperties, 'PropType', 'Type', 9);
  AddText(mtProperties, 'Status', 'Status', 17);
  AddDate(mtProperties, 'Delivery', 'Delivery');
  AddFlag(mtProperties, 'IsOwner');
  AddFlag(mtProperties, 'IsArchived');
  mtProperties.CreateDataSet;
end;

procedure TfrmMain.LoadProperties;
begin
  SetBusy(True, 'Loading properties... (a sleeping server can take up to a minute)');
  TAsync.Run<TPropertyArray>(
    function: TPropertyArray
    begin
      Result := FApi.GetProperties;         // worker thread: no controls here
    end,
    procedure(Items: TPropertyArray)
    begin
      SetBusy(False, Format('%d properties', [Length(Items)]));
      FillProperties(Items);                // main thread
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, 'Could not load properties');
      HandleApiError(Err);
    end);
end;

procedure TfrmMain.FillProperties(const Items: TPropertyArray);
var
  P: TPropertyRec;
begin
  FFilling := True;
  mtProperties.DisableControls;            // one repaint at the end, not one per row
  try
    mtProperties.EmptyDataSet;
    for P in Items do
    begin
      mtProperties.Append;
      mtProperties.FieldByName('Id').AsString := P.Id;
      mtProperties.FieldByName('Name').AsString := P.Name;
      mtProperties.FieldByName('PropType').AsString := Pretty(P.PropertyType);
      mtProperties.FieldByName('Status').AsString := Pretty(P.Status);
      if P.DeliveryDate <> 0 then          // left alone = NULL = empty cell
        mtProperties.FieldByName('Delivery').AsDateTime := P.DeliveryDate;
      mtProperties.FieldByName('IsOwner').AsBoolean := P.IsOwner;
      mtProperties.FieldByName('IsArchived').AsBoolean := P.IsArchived;
      mtProperties.Post;
    end;
    mtProperties.First;
  finally
    mtProperties.EnableControls;
    FFilling := False;
  end;
end;

end.
