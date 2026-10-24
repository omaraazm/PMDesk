program PMDesk;

uses
  Vcl.Forms,
  uMain in 'uMain.pas' {frmMain},
  uConfig in 'uConfig.pas';

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
