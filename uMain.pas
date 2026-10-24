unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, uConfig, uApiTypes, uApiErrors, uPropertyApi,
  Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    Button1: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    private
    FConfig: TAppConfig;
    FApi: TPropertyApi;
    FUser: TUserRec;
    procedure SignIn;
  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses uLogin;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FConfig := TAppConfig.Create;
  FConfig.Load;
  FApi := TPropertyApi.Create(FConfig.BaseUrl, FConfig.ConnectTimeoutMs,
    FConfig.ResponseTimeoutMs);
  Caption := 'PMDesk - ' + FConfig.BaseUrl;
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
    Caption := 'PMDesk - ' + FUser.FullName
  else
    Close;
end;

end.
