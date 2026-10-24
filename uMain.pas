unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, uConfig, uApiTypes, uApiErrors, uPropertyApi,
  Vcl.StdCtrls;

type
  TfrmMain = class(TForm)
    btnTest: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnTestClick(Sender: TObject);
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

procedure TfrmMain.btnTestClick(Sender: TObject);

begin
  // TEMPORARY: removed in g.7. Runs on the UI thread on purpose.
  try
    FApi.CheckHealth;
    ShowMessage('Server is up: ' + FConfig.BaseUrl);
    FApi.GetProperties;                // not signed in yet: must fail with 401
    ShowMessage('Unexpected: properties loaded without signing in');
  except
    on E: EApiError do
      ShowMessage(Format('EApiError, HTTP %d: %s', [E.StatusCode, E.Message]));
  end;
end;

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
end.
