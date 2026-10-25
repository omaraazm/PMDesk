unit uLogin;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  uApiTypes, uApiErrors, uConfig, uPropertyApi;

type
  TfrmLogin = class(TForm)
    lblServerCaption: TLabel;
    lblServer: TLabel;
    lblEmail: TLabel;
    edtEmail: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblStatus: TLabel;
    btnSignIn: TButton;
    btnCancel: TButton;
    procedure btnSignInClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FApi: TPropertyApi;
    FConfig: TAppConfig;
    FUser: TUserRec;
    FBusy: Boolean;
    procedure SetBusy(Busy: Boolean);
    procedure ShowError(const Err: TApiErrorInfo);
    procedure LoadAccount;
  public
    // Shows the dialog. True = signed in as a landlord; User says who.
    class function Execute(AApi: TPropertyApi; AConfig: TAppConfig;
      out User: TUserRec): Boolean;
  end;

var
  frmLogin: TfrmLogin;

implementation

{$R *.dfm}

uses uAsync;

procedure TfrmLogin.btnSignInClick(Sender: TObject);
var
  Email, Password: string;
begin
  // read the controls here, on the UI thread; the worker gets copies
  Email := Trim(edtEmail.Text);
  Password := edtPassword.Text;
  if (Email = '') or (Password = '') then
  begin
    lblStatus.Caption := 'Enter your email and password.';
    Exit;
  end;

  FApi.ClearTokens;
  SetBusy(True);
  lblStatus.Caption := 'Signing in... (a sleeping server can take up to a minute)';
  TAsync.Run<TTokenPair>(
    function: TTokenPair
    begin
      Result := FApi.Login(Email, Password);   // worker thread
    end,
    procedure(Pair: TTokenPair)
    begin
      FApi.SetTokens(Pair);                    // main thread only
      LoadAccount;                             // second request: who am I?
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False);
      ShowError(Err);
    end);
end;

class function TfrmLogin.Execute(AApi: TPropertyApi; AConfig: TAppConfig;
  out User: TUserRec): Boolean;
var
  Form: TfrmLogin;
begin
  Form := TfrmLogin.Create(nil);       // we own it: no auto-create, no owner
  try
    Form.FApi := AApi;
    Form.FConfig := AConfig;
    Form.lblServer.Caption := AConfig.BaseUrl;
    Form.edtEmail.Text := AConfig.LastEmail;
    if Form.edtEmail.Text <> '' then
      Form.ActiveControl := Form.edtPassword;
    Result := Form.ShowModal = mrOk;
    if Result then
      User := Form.FUser;
  finally
    Form.Free;
  end;
end;

procedure TfrmLogin.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Closing while a request runs would free this form before its reply
  // arrives, and the reply would then write to a dead form.
  CanClose := not FBusy;
end;

procedure TfrmLogin.SetBusy(Busy: Boolean);
begin
  FBusy := Busy;
  edtEmail.Enabled := not Busy;
  edtPassword.Enabled := not Busy;
  btnSignIn.Enabled := not Busy;
  btnCancel.Enabled := not Busy;
end;

procedure TfrmLogin.ShowError(const Err: TApiErrorInfo);
begin
  if Err.Kind = aekUnauthorized then
    lblStatus.Caption := Err.Message   // at login, 401 = wrong email or password
  else
    lblStatus.Caption := Err.UserText;
end;

procedure TfrmLogin.LoadAccount;
begin
  TAsync.Run<TUserRec>(
    function: TUserRec
    begin
      Result := FApi.GetMe;
    end,
    procedure(User: TUserRec)
    begin
      SetBusy(False);
      if User.Role <> 'landlord' then
      begin
        FApi.ClearTokens;
        lblStatus.Caption := 'PMDesk is for landlord accounts. This one is a '
          + User.Role + ' account.';
        Exit;
      end;
      FUser := User;
      FConfig.LastEmail := User.Email;
      FConfig.SaveLastEmail;
      ModalResult := mrOk;                     // closes the dialog
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False);
      FApi.ClearTokens;
      ShowError(Err);
    end);
end;

end.
