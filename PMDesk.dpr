program PMDesk;

uses
  Vcl.Forms,
  uMain in 'uMain.pas' {frmMain},
  uConfig in 'uConfig.pas',
  uApiErrors in 'uApiErrors.pas',
  uAsync in 'uAsync.pas',
  uApiTypes in 'uApiTypes.pas',
  uDataSets in 'uDataSets.pas',
  uPropertyApi in 'uPropertyApi.pas',
  uLogin in 'uLogin.pas' {frmLogin};

{$R *.res}

begin
{$IFDEF DEBUG}
  // Lists any object you forgot to free when the app closes (debug builds only)
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
