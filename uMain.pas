unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, uConfig;

type
  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FConfig: TAppConfig;
  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FConfig := TAppConfig.Create;
  FConfig.Load;
  Caption := 'PMDesk - ' + FConfig.BaseUrl;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FConfig.Free;
end;

end.
