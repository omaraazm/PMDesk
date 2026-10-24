unit uApiErrors;

interface

uses
  System.SysUtils;

type
  TApiErrorKind = (aekNetwork, aekUnauthorized, aekForbidden, aekNotFound,
    aekConflict, aekValidation, aekRateLimited, aekServer, aekUnexpected);

  // The only exception class TPropertyApi raises on purpose.
  EApiError = class(Exception)
  private
    FKind: TApiErrorKind;
    FStatusCode: Integer;
  public
    constructor Create(AKind: TApiErrorKind; AStatusCode: Integer;
      const AMessage: string);
    property Kind: TApiErrorKind read FKind;
    property StatusCode: Integer read FStatusCode;  // 0 = no HTTP answer at all
  end;

  // A plain copy of an error. Safe to pass from a worker thread to the UI
  // thread, unlike the exception object itself.
  TApiErrorInfo = record
    Kind: TApiErrorKind;
    StatusCode: Integer;
    Message: string;
    class function FromException(E: Exception): TApiErrorInfo; static;
    function UserText: string;
  end;

implementation

{ EApiError }

constructor EApiError.Create(AKind: TApiErrorKind; AStatusCode: Integer;
  const AMessage: string);
begin
  inherited Create(AMessage);
  FKind := AKind;
  FStatusCode := AStatusCode;
end;

{ TApiErrorInfo }

class function TApiErrorInfo.FromException(E: Exception): TApiErrorInfo;
begin
  if E is EApiError then
  begin
    Result.Kind := EApiError(E).Kind;
    Result.StatusCode := EApiError(E).StatusCode;
    Result.Message := E.Message;
  end
  else
  begin
    // not raised on purpose: bad JSON, a conversion error, a bug
    Result.Kind := aekUnexpected;
    Result.StatusCode := 0;
    Result.Message := E.ClassName + ': ' + E.Message;
  end;
end;

function TApiErrorInfo.UserText: string;
begin
  case Kind of
    aekNetwork:
      Result := 'Cannot reach the server. Check the internet connection and try again.'
        + sLineBreak + sLineBreak + Message;
    aekUnauthorized:
      Result := 'Your session has expired. Please sign in again.';
    aekRateLimited:
      Result := 'Too many attempts. Wait a minute, then try again.';
    aekServer:
      Result := Format('The server had a problem (HTTP %d). Try again in a moment.',
        [StatusCode]);
  else
    // 403, 404, 409, 422 and the unexpected: the text is already a sentence
    Result := Message;
  end;
end;

end.
