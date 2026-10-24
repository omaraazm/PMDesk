unit uConfig;

// Settings that change per machine, not per build: the server address and
// timeouts. No password or token ever goes in this file.

interface

type
  TAppConfig = class
  private
    FFileName: string;
    FBaseUrl: string;
    FConnectTimeoutMs: Integer;
    FResponseTimeoutMs: Integer;
    FDeviceId: string;
    FLastEmail: string;
  public
    constructor Create;
    procedure Load;
    procedure SaveLastEmail;
    function IsPlaceholder: Boolean;
    property FileName: string read FFileName;
    property BaseUrl: string read FBaseUrl;
    property ConnectTimeoutMs: Integer read FConnectTimeoutMs;
    property ResponseTimeoutMs: Integer read FResponseTimeoutMs;
    property DeviceId: string read FDeviceId;
    property LastEmail: string read FLastEmail write FLastEmail;
  end;

implementation

uses
  System.SysUtils, System.IniFiles;

const
  PlaceholderUrl = 'https://YOUR-API-HOST';

constructor TAppConfig.Create;
begin
  inherited Create;
  // next to the exe: Win32\Debug\PMDesk.ini while developing
  FFileName := ChangeFileExt(ParamStr(0), '.ini');
end;

procedure TAppConfig.Load;
var
  Ini: TIniFile;
  FirstRun: Boolean;
begin
  FirstRun := not FileExists(FFileName);
  Ini := TIniFile.Create(FFileName);
  try
    FBaseUrl := Ini.ReadString('Server', 'BaseUrl', PlaceholderUrl);
    while FBaseUrl.EndsWith('/') do      // paths below all start with '/'
      FBaseUrl := FBaseUrl.Remove(FBaseUrl.Length - 1);
    FConnectTimeoutMs := Ini.ReadInteger('Server', 'ConnectTimeoutMs', 15000);
    FResponseTimeoutMs := Ini.ReadInteger('Server', 'ResponseTimeoutMs', 90000);
    FDeviceId := Ini.ReadString('Client', 'DeviceId', '');
    FLastEmail := Ini.ReadString('Client', 'LastEmail', '');

    if FirstRun then
    begin
      // write the defaults, so there is a file to edit
      Ini.WriteString('Server', 'BaseUrl', FBaseUrl);
      Ini.WriteInteger('Server', 'ConnectTimeoutMs', FConnectTimeoutMs);
      Ini.WriteInteger('Server', 'ResponseTimeoutMs', FResponseTimeoutMs);
    end;
    if FDeviceId = '' then
    begin
      // generated once per installation; it names this PC, it is not a secret
      FDeviceId := TGUID.NewGuid.ToString.Trim(['{', '}']).ToLower;
      Ini.WriteString('Client', 'DeviceId', FDeviceId);
    end;
  finally
    Ini.Free;
  end;
end;

procedure TAppConfig.SaveLastEmail;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(FFileName);
  try
    Ini.WriteString('Client', 'LastEmail', FLastEmail);
  finally
    Ini.Free;
  end;
end;

function TAppConfig.IsPlaceholder: Boolean;
begin
  Result := SameText(FBaseUrl, PlaceholderUrl);
end;

end.
