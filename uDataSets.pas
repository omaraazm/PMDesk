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
procedure ExportCsv(DS: TDataSet; const FileName: string);

implementation

uses
  System.SysUtils, System.Classes;

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
  F: TFMTBCDField;
begin
  // An exact decimal, never a Double. FireDAC maps a BCD field with
  // Precision 18 to its FMTBcd type, so the field must be TFMTBCDField:
  // a TBCDField here gives "Type mismatch ... expecting BCD, actual FMTBcd".
  // NOT TCurrencyField either: that one is a TFloatField, a Double (PLAN d.6).
  F := TFMTBCDField.Create(DS);
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

// Wraps a value in quotes only when it has to: when it contains the
// separator, a quote or a line break. Quotes inside are doubled (CSV rule).
function CsvQuote(const S: string; Sep: Char): string;
begin
  if (Pos(Sep, S) > 0) or (Pos('"', S) > 0) or (Pos(#13, S) > 0) or (Pos(#10, S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

// Writes the visible fields of DS to a CSV file that Excel opens correctly
// on this PC: Windows' list separator, and UTF-8 with a byte-order mark.
procedure ExportCsv(DS: TDataSet; const FileName: string);
var
  Writer: TStreamWriter;
  Sep: Char;
  Mark: TBookmark;
  Line: string;
  I: Integer;
  First: Boolean;
begin
  // ';' in Austria (where ',' is the decimal comma), ',' in English locales
  Sep := FormatSettings.ListSeparator;
  // TEncoding.UTF8 writes a byte-order mark first: Excel needs it for UTF-8
  Writer := TStreamWriter.Create(FileName, False, TEncoding.UTF8);
  try
    // header row: the grid's column titles
    Line := '';
    First := True;
    for I := 0 to DS.FieldCount - 1 do
      if DS.Fields[I].Visible then
      begin
        if not First then
          Line := Line + Sep;
        Line := Line + CsvQuote(DS.Fields[I].DisplayLabel, Sep);
        First := False;
      end;
    Writer.WriteLine(Line);

    // data rows
    Mark := DS.Bookmark;              // remember the row the user is on
    DS.DisableControls;               // no grid repaint per row
    try
      DS.First;
      while not DS.Eof do
      begin
        Line := '';
        First := True;
        for I := 0 to DS.FieldCount - 1 do
          if DS.Fields[I].Visible then
          begin
            if not First then
              Line := Line + Sep;
            // DisplayText: as the grid shows it, in the user's number format
            Line := Line + CsvQuote(DS.Fields[I].DisplayText, Sep);
            First := False;
          end;
        Writer.WriteLine(Line);
        DS.Next;
      end;
      DS.Bookmark := Mark;            // back to the row the user was on
    finally
      DS.EnableControls;
    end;
  finally
    Writer.Free;
  end;
end;

end.
