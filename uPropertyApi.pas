unit uPropertyApi;

// Everything HTTP and JSON lives here, and only here (PLAN d.2). Forms call
// these methods on a worker thread (through TAsync) and get records back, or
// an EApiError. This unit never uses a Vcl.* unit.

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  System.Net.URLClient, System.Net.HttpClient,
  uApiTypes, uApiErrors;

type
  TPropertyApi = class
  private
    FBaseUrl: string;
    FConnectTimeoutMs: Integer;
    FResponseTimeoutMs: Integer;
    FAccessToken: string;    // memory only; written on the main thread only
    FRefreshToken: string;   // kept for the bonus token-refresh step
    function NewHttp: THTTPClient;
    function Send(const Method, Path: string; const ContentType: string = '';
      const Payload: string = ''; const Extra: TNetHeaders = nil): string;
    procedure ForEachItem(const Path: string; const Each: TProc<TJSONObject>;
      const OnPage: TProc<TJSONObject> = nil);
  public
    constructor Create(const ABaseUrl: string;
      AConnectTimeoutMs, AResponseTimeoutMs: Integer);

    // main thread only
    procedure SetTokens(const Pair: TTokenPair);
    procedure ClearTokens;

    // safe on a worker thread: every call makes its own THTTPClient
    procedure CheckHealth;
    function Login(const Email, Password: string): TTokenPair;
    function GetMe: TUserRec;
    function GetProperties: TPropertyArray;
    // >>> Sunday: new endpoint declarations go above this line
  end;

implementation

uses
  System.NetEncoding;

const
  cUserAgent = 'PMDesk/0.1 (Windows; Delphi)';

var
  // '.' as the decimal separator, whatever Windows' region says (PLAN d.7)
  ApiFormat: TFormatSettings;

{ ===== JSON helpers ===== }

// The value at Name, or nil when it is missing or JSON null.
function JValue(O: TJSONObject; const Name: string): TJSONValue;
begin
  Result := O.GetValue(Name);
  if Result is TJSONNull then
    Result := nil;
end;

function JStr(O: TJSONObject; const Name: string): string;
var
  V: TJSONValue;
begin
  V := JValue(O, Name);
  if V = nil then
    Result := ''
  else
    Result := V.Value;
end;

// Money arrives as a JSON string ("18000.00", "0", "-1500.50"), never a number.
function JCurr(O: TJSONObject; const Name: string): Currency;
var
  S: string;
begin
  S := JStr(O, Name);
  if S = '' then
    Result := 0
  else
    Result := StrToCurr(S, ApiFormat);
end;

function JInt(O: TJSONObject; const Name: string): Integer;
begin
  Result := StrToIntDef(JStr(O, Name), 0);
end;

// For counts like bathrooms (1.5). Never for money.
function JFloat(O: TJSONObject; const Name: string): Double;
var
  S: string;
begin
  S := JStr(O, Name);
  if S = '' then
    Result := 0
  else
    Result := StrToFloat(S, ApiFormat);
end;

function JBool(O: TJSONObject; const Name: string): Boolean;
begin
  Result := JValue(O, Name) is TJSONTrue;
end;

// "YYYY-MM-DD" read by position: no locale, no time zone. Missing or null -> 0.
function JDate(O: TJSONObject; const Name: string): TDate;
var
  S: string;
begin
  S := JStr(O, Name);
  if S = '' then
    Exit(0);
  Result := EncodeDate(StrToInt(Copy(S, 1, 4)), StrToInt(Copy(S, 6, 2)),
    StrToInt(Copy(S, 9, 2)));
end;

// Parses a response body that must be a JSON object. The caller frees it.
function ParseObject(const Body: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(Body);
  if not (V is TJSONObject) then
  begin
    V.Free;                           // Free on nil does nothing
    raise EApiError.Create(aekUnexpected, 0,
      'The server sent something that is not a JSON object.');
  end;
  Result := TJSONObject(V);
end;

// Percent-encodes everything except A-Z a-z 0-9 - . _ ~, byte by byte over
// UTF-8: the same rule the iOS client uses for the login form.
function FormEncode(const S: string): string;
var
  B: Byte;
begin
  Result := '';
  for B in TEncoding.UTF8.GetBytes(S) do
    if CharInSet(Char(B), ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~']) then
      Result := Result + Char(B)
    else
      Result := Result + '%' + IntToHex(B, 2);
end;

// Pulls a readable message out of an error body. Handles all three shapes:
// {"detail": "text"}, {"detail": [{"loc": [...], "msg": "..."}]}, {"error": "text"}.
function ExtractDetail(const Body: string): string;
var
  Root, Detail, Item: TJSONValue;
  Arr, Loc: TJSONArray;
  Field, Msg: string;
  I: Integer;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(Body);
  if Root = nil then
    Exit;                             // not JSON: e.g. a proxy's HTML error page
  try
    if not (Root is TJSONObject) then
      Exit;                           // finally still runs: Root is freed
    Detail := TJSONObject(Root).GetValue('detail');
    if Detail is TJSONString then
      Result := TJSONString(Detail).Value
    else if Detail is TJSONArray then
    begin
      Arr := TJSONArray(Detail);
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I];
        if not Item.TryGetValue<string>('msg', Msg) then
          Msg := 'Invalid input';
        Field := '';
        if Item.TryGetValue<TJSONArray>('loc', Loc) and (Loc.Count > 0) then
          Field := Loc.Items[Loc.Count - 1].Value;   // last part: the field name
        if Field <> '' then
          Msg := Field + ': ' + Msg;
        if Result <> '' then
          Result := Result + sLineBreak;
        Result := Result + Msg;
      end;
    end
    else if not Root.TryGetValue<string>('error', Result) then   // 429
      Result := '';
  finally
    Root.Free;                        // also frees Detail, Item, Loc: the root owns them
  end;
end;

// Raises EApiError unless the status is 2xx.
procedure CheckResponse(const Resp: IHTTPResponse; const Body: string);
var
  Code: Integer;
  Detail: string;
  Kind: TApiErrorKind;
begin
  Code := Resp.StatusCode;
  if (Code >= 200) and (Code < 300) then
    Exit;

  Detail := ExtractDetail(Body);
  if Detail = '' then
    Detail := Format('HTTP %d %s', [Code, Resp.StatusText]);

  case Code of
    401: Kind := aekUnauthorized;
    403: Kind := aekForbidden;
    404: Kind := aekNotFound;
    409: Kind := aekConflict;
    422: Kind := aekValidation;
    429: Kind := aekRateLimited;
  else
    if Code >= 500 then
      Kind := aekServer
    else
      Kind := aekUnexpected;
  end;
  raise EApiError.Create(Kind, Code, Detail);
end;

{ ===== record parsers ===== }

function ParseProperty(O: TJSONObject): TPropertyRec;
begin
  Result.Id := JStr(O, 'id');
  Result.Name := JStr(O, 'name');
  Result.Address := JStr(O, 'address');
  Result.PropertyType := JStr(O, 'property_type');
  Result.Status := JStr(O, 'status');
  Result.DeliveryDate := JDate(O, 'delivery_date');
  Result.IsOwner := JBool(O, 'viewer_is_owner');
  Result.IsArchived := JValue(O, 'archived_at') <> nil;
end;

// >>> Sunday: new parser functions go above the TPropertyApi line below

{ ===== TPropertyApi ===== }

constructor TPropertyApi.Create(const ABaseUrl: string;
  AConnectTimeoutMs, AResponseTimeoutMs: Integer);
begin
  inherited Create;
  FBaseUrl := ABaseUrl;
  FConnectTimeoutMs := AConnectTimeoutMs;
  FResponseTimeoutMs := AResponseTimeoutMs;
end;

procedure TPropertyApi.SetTokens(const Pair: TTokenPair);
begin
  FAccessToken := Pair.AccessToken;
  FRefreshToken := Pair.RefreshToken;
end;

procedure TPropertyApi.ClearTokens;
begin
  FAccessToken := '';
  FRefreshToken := '';
end;

function TPropertyApi.NewHttp: THTTPClient;
begin
  Result := THTTPClient.Create;
  Result.ConnectionTimeout := FConnectTimeoutMs;
  Result.ResponseTimeout := FResponseTimeoutMs;
  Result.UserAgent := cUserAgent;
end;

// One request, start to finish: build it, send it, read it as UTF-8, and turn
// any failure into an EApiError. Every endpoint goes through here.
function TPropertyApi.Send(const Method, Path: string; const ContentType: string;
  const Payload: string; const Extra: TNetHeaders): string;
var
  Http: THTTPClient;
  Source: TStringStream;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
begin
  Http := nil;
  Source := nil;
  try
    Http := NewHttp;
    Headers := Extra;
    if FAccessToken <> '' then
      Headers := Headers + [TNetHeader.Create('Authorization', 'Bearer ' + FAccessToken)];
    if ContentType <> '' then
      Headers := Headers + [TNetHeader.Create('Content-Type', ContentType)];

    try
      if Method = 'GET' then
        Resp := Http.Get(FBaseUrl + Path, nil, Headers)
      else
      begin
        Source := TStringStream.Create(Payload, TEncoding.UTF8);
        if Method = 'POST' then
          Resp := Http.Post(FBaseUrl + Path, Source, nil, Headers)
        else if Method = 'PATCH' then
          Resp := Http.Patch(FBaseUrl + Path, Source, nil, Headers)
        else
          raise EApiError.Create(aekUnexpected, 0, 'Unsupported method: ' + Method);
      end;
    except
      // no internet, DNS, TLS, timeout: there is no HTTP answer at all
      on E: ENetException do
        raise EApiError.Create(aekNetwork, 0, E.Message);
    end;

    // UTF-8 explicitly: the server's Content-Type names no charset
    Result := Resp.ContentAsString(TEncoding.UTF8);
    CheckResponse(Resp, Result);
  finally
    Resp := nil;                      // let go of the response before its client
    Source.Free;
    Http.Free;
  end;
end;

// Calls Each for every item of a list endpoint, following next_cursor page by
// page (PLAN a.1, "Lists"). OnPage, if given, sees each page's top-level object.
procedure TPropertyApi.ForEachItem(const Path: string;
  const Each: TProc<TJSONObject>; const OnPage: TProc<TJSONObject>);
var
  Cursor, Query: string;
  Root: TJSONObject;
  Items: TJSONValue;
  I: Integer;
begin
  Cursor := '';
  repeat
    Query := 'limit=200';             // the server's maximum page size
    if Cursor <> '' then
      Query := Query + '&cursor=' + TNetEncoding.URL.Encode(Cursor);
    if Pos('?', Path) > 0 then
      Root := ParseObject(Send('GET', Path + '&' + Query))
    else
      Root := ParseObject(Send('GET', Path + '?' + Query));
    try
      Items := Root.GetValue('items');
      if not (Items is TJSONArray) then
        raise EApiError.Create(aekUnexpected, 0, 'The list from ' + Path + ' has no items.');
      for I := 0 to TJSONArray(Items).Count - 1 do
        Each(TJSONArray(Items).Items[I] as TJSONObject);
      if Assigned(OnPage) then
        OnPage(Root);
      Cursor := JStr(Root, 'next_cursor');   // '' on the last page (null)
    finally
      Root.Free;
    end;
  until Cursor = '';
end;

{ ===== endpoints ===== }

procedure TPropertyApi.CheckHealth;
begin
  Send('GET', '/health');             // raises EApiError when unreachable
end;

function TPropertyApi.Login(const Email, Password: string): TTokenPair;
var
  Root: TJSONObject;
begin
  // a form, not JSON: OAuth2PasswordRequestForm (PLAN a.4, call 2)
  Root := ParseObject(Send('POST', '/v1/auth/login',
    'application/x-www-form-urlencoded',
    'username=' + FormEncode(Email) + '&password=' + FormEncode(Password)));
  try
    Result.AccessToken := JStr(Root, 'access_token');
    Result.RefreshToken := JStr(Root, 'refresh_token');
  finally
    Root.Free;
  end;
end;

function TPropertyApi.GetMe: TUserRec;
var
  Root: TJSONObject;
begin
  Root := ParseObject(Send('GET', '/v1/auth/me'));
  try
    Result.Id := JStr(Root, 'id');
    Result.Email := JStr(Root, 'email');
    Result.FullName := JStr(Root, 'full_name');
    Result.Role := JStr(Root, 'role');
  finally
    Root.Free;
  end;
end;

function TPropertyApi.GetProperties: TPropertyArray;
var
  Items: TPropertyArray;
begin
  Items := nil;
  ForEachItem('/v1/properties',
    procedure(O: TJSONObject)
    begin
      Items := Items + [ParseProperty(O)];
    end);
  Result := Items;
end;

// >>> Sunday: new endpoint methods go above "initialization"

initialization
  ApiFormat := TFormatSettings.Create;     // start from the user's settings...
  ApiFormat.DecimalSeparator := '.';       // ...and fix what the API depends on

end.
