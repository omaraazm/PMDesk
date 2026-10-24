unit uAsync;

interface

uses
  System.SysUtils, System.Classes, System.Threading,
  uApiErrors;

type
  TAsync = class
  public
    // Runs Work on a thread-pool thread. Afterwards exactly one of
    // OnSuccess or OnError runs, always on the main (UI) thread.
    class procedure Run<T>(const Work: TFunc<T>; const OnSuccess: TProc<T>;
      const OnError: TProc<TApiErrorInfo>);
  end;

implementation

class procedure TAsync.Run<T>(const Work: TFunc<T>; const OnSuccess: TProc<T>;
  const OnError: TProc<TApiErrorInfo>);
begin
  TTask.Run(
    procedure
    var
      Value: T;
      Failed: Boolean;
      Info: TApiErrorInfo;
    begin
      Value := Default(T);
      Failed := False;
      try
        Value := Work();
      except
        on E: Exception do
        begin
          // Copy it now: E is freed when this except block ends, long
          // before the queued procedure below gets to run.
          Info := TApiErrorInfo.FromException(E);
          Failed := True;
        end;
      end;

      if Failed then
        TThread.Queue(nil,
          procedure
          begin
            OnError(Info);
          end)
      else
        TThread.Queue(nil,
          procedure
          begin
            OnSuccess(Value);
          end);
    end);
end;

end.
