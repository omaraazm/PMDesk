unit uDataSets;

// Creates the fields of an in-memory table in code, before CreateDataSet, so
// every column's type, caption and width is in one readable place (and in
// git), instead of hidden in the .dfm.

interface

uses
  Data.DB, FireDAC.Comp.Client;

procedure AddHidden(DS: TFDMemTable; const Name: string);       // ids
procedure AddFlag(DS: TFDMemTable; const Name: string);         // hidden Boolean
procedure AddText(DS: TFDMemTable; const Name, Caption: string; Width: Integer);
procedure AddInt(DS: TFDMemTable; const Name, Caption: string);
procedure AddNumber(DS: TFDMemTable; const Name, Caption: string); // Double, e.g. 1.5
procedure AddDate(DS: TFDMemTable; const Name, Caption: string);
procedure AddDecimal(DS: TFDMemTable; const Name, Caption: string;
  Decimals: Integer; const DisplayFormat: string);
procedure AddMoney(DS: TFDMemTable; const Name, Caption: string);

implementation

procedure AddHidden(DS: TFDMemTable; const Name: string);
var
  F: TWideStringField;
begin
  F := TWideStringField.Create(DS);   // DS owns the field and frees it
  F.FieldName := Name;
  F.Size := 40;
  F.Visible := False;                 // for code (ids), not for the grid
  F.DataSet := DS;
end;

procedure AddFlag(DS: TFDMemTable; const Name: string);
var
  F: TBooleanField;
begin
  F := TBooleanField.Create(DS);
  F.FieldName := Name;
  F.Visible := False;
  F.DataSet := DS;
end;

procedure AddText(DS: TFDMemTable; const Name, Caption: string; Width: Integer);
var
  F: TWideStringField;
begin
  // Wide = Unicode. A plain TStringField stores 8-bit text and would mangle
  // an Arabic tenant name.
  F := TWideStringField.Create(DS);
  F.FieldName := Name;
  F.Size := 200;
  F.DisplayLabel := Caption;          // the grid's column title
  F.DisplayWidth := Width;            // in characters
  F.DataSet := DS;
end;

procedure AddInt(DS: TFDMemTable; const Name, Caption: string);
var
  F: TIntegerField;
begin
  F := TIntegerField.Create(DS);
  F.FieldName := Name;
  F.DisplayLabel := Caption;
  F.DisplayWidth := 8;
  F.DataSet := DS;
end;

procedure AddNumber(DS: TFDMemTable; const Name, Caption: string);
var
  F: TFloatField;
begin
  F := TFloatField.Create(DS);
  F.FieldName := Name;
  F.DisplayFormat := '0.#';
  F.DisplayLabel := Caption;
  F.DisplayWidth := 8;
  F.DataSet := DS;
end;

procedure AddDate(DS: TFDMemTable; const Name, Caption: string);
var
  F: TDateField;
begin
  F := TDateField.Create(DS);         // shows in Windows' short date format
  F.FieldName := Name;
  F.DisplayLabel := Caption;
  F.DisplayWidth := 11;
  F.DataSet := DS;
end;

procedure AddDecimal(DS: TFDMemTable; const Name, Caption: string;
  Decimals: Integer; const DisplayFormat: string);
var
  F: TBCDField;
begin
  // An exact decimal with a Currency inside. NOT TCurrencyField: despite its
  // name, that one is a TFloatField, a Double (PLAN d.6).
  F := TBCDField.Create(DS);
  F.FieldName := Name;
  F.Precision := 18;
  F.Size := Decimals;                 // for BCD fields, Size = digits after the point
  F.DisplayFormat := DisplayFormat;
  F.DisplayLabel := Caption;
  F.DisplayWidth := 15;
  F.DataSet := DS;
end;

procedure AddMoney(DS: TFDMemTable; const Name, Caption: string);
begin
  AddDecimal(DS, Name, Caption, 2, '#,##0.00');
end;

end.
