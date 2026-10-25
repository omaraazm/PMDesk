unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, uConfig, uApiTypes, uApiErrors, uPropertyApi,
  Vcl.StdCtrls, Vcl.ExtCtrls, Data.DB, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf,
  FireDAC.DApt.Intf, FireDAC.Comp.DataSet, FireDAC.Comp.Client, Vcl.Grids,
  Vcl.DBGrids, Vcl.ComCtrls;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    btnRefresh: TButton;
    btnSignOut: TButton;
    lblUser: TLabel;
    pnlProperties: TPanel;
    StatusBar1: TStatusBar;
    grdProperties: TDBGrid;
    mtProperties: TFDMemTable;
    dsProperties: TDataSource;
    splLeft: TSplitter;
    pgcMain: TPageControl;
    tsUnits: TTabSheet;
    gbUnits: TGroupBox;
    grdUnits: TDBGrid;
    gbLeases: TGroupBox;
    grdLeases: TDBGrid;
    gbPayments: TGroupBox;
    pnlPaymentActions: TPanel;
    btnMarkPaid: TButton;
    btnMarkUnpaid: TButton;
    lblTotals: TLabel;
    grdPayments: TDBGrid;
    tsLoans: TTabSheet;
    gbLoans: TGroupBox;
    grdLoans: TDBGrid;
    gbSchedule: TGroupBox;
    pnlScheduleSummary: TPanel;
    lblSchedule: TLabel;
    grdSchedule: TDBGrid;
    mtUnits: TFDMemTable;
    mtLeases: TFDMemTable;
    mtPayments: TFDMemTable;
    mtLoans: TFDMemTable;
    mtSchedule: TFDMemTable;
    dsLeases: TDataSource;
    dsUnits: TDataSource;
    dsSchedule: TDataSource;
    dsPayments: TDataSource;
    dsLoans: TDataSource;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnSignOutClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure mtPropertiesAfterScroll(DataSet: TDataSet);
    procedure mtUnitsAfterScroll(DataSet: TDataSet);
    procedure mtLeasesAfterScroll(DataSet: TDataSet);
    procedure mtPaymentsAfterScroll(DataSet: TDataSet);
    procedure mtLoansAfterScroll(DataSet: TDataSet);
      private
    FConfig: TAppConfig;
    FApi: TPropertyApi;
    FUser: TUserRec;
    FPending: Integer;      // requests still running
    FFilling: Boolean;      // True while code fills a table (used from g.9 on)
    procedure SetBusy(Busy: Boolean; const Status: string);
    procedure HandleApiError(const Err: TApiErrorInfo);
    procedure SignIn;
    procedure DefinePropertiesTable;
    procedure LoadProperties;
    procedure FillProperties(const Items: TPropertyArray);
    procedure DefineDetailTables;
    function SelectedId(DS: TFDMemTable): string;
    procedure ClearTable(DS: TFDMemTable);
    procedure PropertyChanged;
    procedure LoadUnits(const PropertyId: string);
    procedure FillUnits(const Items: TUnitArray);
    procedure LoadLeases(const UnitId: string);
    procedure FillLeases(const Items: TLeaseArray);
    procedure LeaseChanged;
    procedure UnitChanged;
    procedure LoadPayments(const LeaseId: string; const SelectId: string = '');
    procedure FillPayments(const List: TPaymentList; const SelectId: string);
    procedure UpdatePaymentButtons;
    procedure LoadLoans(const PropertyId: string);
    procedure FillLoans(const Items: TLoanArray);
    procedure LoanChanged;
    procedure LoadSchedule(const LoanId: string);
    procedure FillSchedule(const S: TLoanSchedule);
  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses uLogin, uAsync, uDataSets;
// 'under_construction' -> 'under construction', for display only
function Pretty(const S: string): string;
begin
  Result := StringReplace(S, '_', ' ', [rfReplaceAll]);
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FPending = 0;                 // no closing while a request runs
  if not CanClose then
    StatusBar1.SimpleText := 'Still waiting for the server - try again in a moment.';
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FApi.Free;
  FConfig.Free;
end;
procedure TfrmMain.FormShow(Sender: TObject);
begin
  // Let the main window finish appearing, then ask for the login.
  // ForceQueue: run this later, on this same (main) thread.
  TThread.ForceQueue(nil,
    procedure
    begin
      SignIn;
    end);
end;

procedure TfrmMain.SignIn;
begin
  if FConfig.IsPlaceholder then
  begin
    MessageDlg('Set BaseUrl in ' + FConfig.FileName + ', then start PMDesk again.',
      mtWarning, [mbOK], 0);
    Close;
    Exit;
  end;
  if TfrmLogin.Execute(FApi, FConfig, FUser) then
  begin
    lblUser.Caption := Format('%s  (%s)', [FUser.FullName, FUser.Email]);
    LoadProperties;
  end
  else
    Close;
end;

procedure TfrmMain.SetBusy(Busy: Boolean; const Status: string);
begin
  if Busy then
    Inc(FPending)
  else if FPending > 0 then
    Dec(FPending);
  if Status <> '' then
    StatusBar1.SimpleText := Status
  else if FPending > 0 then
    StatusBar1.SimpleText := 'Working...'
  else
    StatusBar1.SimpleText := 'Ready';
  btnRefresh.Enabled := FPending = 0;
  btnSignOut.Enabled := FPending = 0;
end;

procedure TfrmMain.HandleApiError(const Err: TApiErrorInfo);
begin
  // Saturday version: show it. g.12 replaces this with one that signs in
  // again when the token has expired.
  MessageDlg(Err.UserText, mtError, [mbOK], 0);
end;

procedure TfrmMain.btnRefreshClick(Sender: TObject);
begin
  LoadProperties;
end;

procedure TfrmMain.btnSignOutClick(Sender: TObject);
begin
  FApi.ClearTokens;
  ClearTable(mtProperties);
  PropertyChanged;                   // empties every detail table
  lblUser.Caption := 'Not signed in';
  SignIn;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FConfig := TAppConfig.Create;
  FConfig.Load;
  FApi := TPropertyApi.Create(FConfig.BaseUrl, FConfig.ConnectTimeoutMs,
    FConfig.ResponseTimeoutMs);
  Caption := 'PMDesk - ' + FConfig.BaseUrl;
  FFilling := True;            // opening a dataset fires AfterScroll: ignore it here
  try
    DefinePropertiesTable;
    DefineDetailTables;
  finally
    FFilling := False;
  end;
end;
procedure TfrmMain.DefinePropertiesTable;
begin
  AddHidden(mtProperties, 'Id');
  AddText(mtProperties, 'Name', 'Name', 18);
  AddText(mtProperties, 'PropType', 'Type', 9);
  AddText(mtProperties, 'Status', 'Status', 17);
  AddDate(mtProperties, 'Delivery', 'Delivery');
  AddFlag(mtProperties, 'IsOwner');
  AddFlag(mtProperties, 'IsArchived');
  mtProperties.CreateDataSet;
end;

procedure TfrmMain.DefineDetailTables;
begin
  AddHidden(mtUnits, 'Id');
  AddText(mtUnits, 'UnitNumber', 'Unit', 6);
  AddInt(mtUnits, 'Bedrooms', 'Bedrooms');
  AddNumber(mtUnits, 'Bathrooms', 'Bathrooms');
  AddText(mtUnits, 'Occupied', 'Occupied', 8);
  mtUnits.CreateDataSet;

  AddHidden(mtLeases, 'Id');
  AddText(mtLeases, 'Tenant', 'Tenant', 20);
  AddDate(mtLeases, 'StartDate', 'From');
  AddDate(mtLeases, 'EndDate', 'To');
  AddMoney(mtLeases, 'Rent', 'Rent / month');
  AddText(mtLeases, 'CurrencyCode', 'Cur.', 4);
  AddText(mtLeases, 'Status', 'Status', 10);
  mtLeases.CreateDataSet;

  AddHidden(mtPayments, 'Id');
  AddDate(mtPayments, 'DueDate', 'Due');
  AddMoney(mtPayments, 'Amount', 'Amount');
  AddText(mtPayments, 'Status', 'Status', 8);
  AddDate(mtPayments, 'PaidDate', 'Paid on');
  AddText(mtPayments, 'Method', 'Method', 8);
  mtPayments.CreateDataSet;

  AddHidden(mtLoans, 'Id');
  AddText(mtLoans, 'Lender', 'Lender', 16);
  AddMoney(mtLoans, 'Principal', 'Price');
  AddMoney(mtLoans, 'DownPayment', 'Down payment');
  AddDecimal(mtLoans, 'Rate', 'Rate %', 3, '0.000');
  AddText(mtLoans, 'Frequency', 'Every', 9);
  AddText(mtLoans, 'CurrencyCode', 'Cur.', 4);
  AddText(mtLoans, 'Status', 'Status', 9);
  mtLoans.CreateDataSet;

  AddInt(mtSchedule, 'Period', '#');
  AddDate(mtSchedule, 'DueDate', 'Due');
  AddMoney(mtSchedule, 'BeginBalance', 'Opening');
  AddMoney(mtSchedule, 'Amount', 'Payment');
  AddMoney(mtSchedule, 'Interest', 'Interest');
  AddMoney(mtSchedule, 'PrincipalPart', 'Principal');
  AddMoney(mtSchedule, 'EndBalance', 'Closing');
  AddDecimal(mtSchedule, 'Pct', '% of price', 4, '0.0000');
  AddText(mtSchedule, 'Status', 'Status', 12);
  AddDate(mtSchedule, 'PaidDate', 'Paid on');
  mtSchedule.CreateDataSet;
end;

function TfrmMain.SelectedId(DS: TFDMemTable): string;
begin
  if DS.IsEmpty then
    Result := ''
  else
    Result := DS.FieldByName('Id').AsString;
end;

procedure TfrmMain.ClearTable(DS: TFDMemTable);
var
  WasFilling: Boolean;
begin
  WasFilling := FFilling;
  FFilling := True;                  // EmptyDataSet fires AfterScroll: ignore it
  try
    DS.EmptyDataSet;
  finally
    FFilling := WasFilling;
  end;
end;

procedure TfrmMain.PropertyChanged;
var
  PropertyId: string;
begin
  ClearTable(mtUnits);
  UnitChanged;                       // empties leases and payments
  ClearTable(mtLoans);
  LoanChanged;                       // empties the schedule
  PropertyId := SelectedId(mtProperties);
  if PropertyId = '' then
    Exit;
  LoadUnits(PropertyId);
  LoadLoans(PropertyId);             // both requests run at the same time
end;

procedure TfrmMain.LoadUnits(const PropertyId: string);
begin
  SetBusy(True, 'Loading units...');
  TAsync.Run<TUnitArray>(
    function: TUnitArray
    begin
      Result := FApi.GetUnits(PropertyId);
    end,
    procedure(Items: TUnitArray)
    begin
      SetBusy(False, '');
      // the user may have moved on while this was loading: drop a stale answer
      if SelectedId(mtProperties) = PropertyId then
        FillUnits(Items);
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, '');
      HandleApiError(Err);
    end);
end;

procedure TfrmMain.mtLeasesAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
    LeaseChanged;
end;

procedure TfrmMain.mtLoansAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
    LoanChanged;
end;

procedure TfrmMain.mtPaymentsAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
    UpdatePaymentButtons;
end;

procedure TfrmMain.mtPropertiesAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
    PropertyChanged;
end;
procedure TfrmMain.mtUnitsAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
    UnitChanged;
end;

procedure TfrmMain.FillUnits(const Items: TUnitArray);
var
  U: TUnitRec;
begin
  FFilling := True;
  mtUnits.DisableControls;
  try
    mtUnits.EmptyDataSet;
    for U in Items do
    begin
      mtUnits.Append;
      mtUnits.FieldByName('Id').AsString := U.Id;
      mtUnits.FieldByName('UnitNumber').AsString := U.UnitNumber;
      mtUnits.FieldByName('Bedrooms').AsInteger := U.Bedrooms;
      mtUnits.FieldByName('Bathrooms').AsFloat := U.Bathrooms;
      if U.IsOccupied then
        mtUnits.FieldByName('Occupied').AsString := 'yes'
      else
        mtUnits.FieldByName('Occupied').AsString := 'no';
      mtUnits.Post;
    end;
    mtUnits.First;
  finally
    mtUnits.EnableControls;
    FFilling := False;
  end;
  UnitChanged;
end;

procedure TfrmMain.UnitChanged;
var
  UnitId: string;
begin
  ClearTable(mtLeases);
  LeaseChanged;                      // empties payments
  UnitId := SelectedId(mtUnits);
  if UnitId <> '' then
    LoadLeases(UnitId);
end;

procedure TfrmMain.LoadLeases(const UnitId: string);
begin
  SetBusy(True, 'Loading leases...');
  TAsync.Run<TLeaseArray>(
    function: TLeaseArray
    begin
      Result := FApi.GetLeases(UnitId);     // leases + one name lookup each
    end,
    procedure(Items: TLeaseArray)
    begin
      SetBusy(False, '');
      if SelectedId(mtUnits) = UnitId then
        FillLeases(Items);
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, '');
      HandleApiError(Err);
    end);
end;

procedure TfrmMain.FillLeases(const Items: TLeaseArray);
var
  L: TLeaseRec;
begin
  FFilling := True;
  mtLeases.DisableControls;
  try
    mtLeases.EmptyDataSet;
    for L in Items do
    begin
      mtLeases.Append;
      mtLeases.FieldByName('Id').AsString := L.Id;
      mtLeases.FieldByName('Tenant').AsString := L.TenantName;
      mtLeases.FieldByName('StartDate').AsDateTime := L.StartDate;
      if L.EndDate <> 0 then                // open-ended: leave it empty
        mtLeases.FieldByName('EndDate').AsDateTime := L.EndDate;
      mtLeases.FieldByName('Rent').AsCurrency := L.RentAmount;
      mtLeases.FieldByName('CurrencyCode').AsString := L.CurrencyCode;
      mtLeases.FieldByName('Status').AsString := L.Status;
      mtLeases.Post;
    end;
    mtLeases.First;
  finally
    mtLeases.EnableControls;
    FFilling := False;
  end;
  LeaseChanged;
end;

procedure TfrmMain.LeaseChanged;
var
  LeaseId: string;
begin
  ClearTable(mtPayments);
  lblTotals.Caption := '';
  UpdatePaymentButtons;
  LeaseId := SelectedId(mtLeases);
  if LeaseId <> '' then
    LoadPayments(LeaseId);
end;

procedure TfrmMain.LoadPayments(const LeaseId: string; const SelectId: string);
begin
  SetBusy(True, 'Loading payments...');
  TAsync.Run<TPaymentList>(
    function: TPaymentList
    begin
      Result := FApi.GetPayments(LeaseId);
    end,
    procedure(List: TPaymentList)
    begin
      SetBusy(False, '');
      if SelectedId(mtLeases) = LeaseId then
        FillPayments(List, SelectId);
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, '');
      HandleApiError(Err);
    end);
end;

procedure TfrmMain.FillPayments(const List: TPaymentList; const SelectId: string);
var
  P: TPaymentRec;
begin
  FFilling := True;
  mtPayments.DisableControls;
  try
    mtPayments.EmptyDataSet;
    for P in List.Items do
    begin
      mtPayments.Append;
      mtPayments.FieldByName('Id').AsString := P.Id;
      mtPayments.FieldByName('DueDate').AsDateTime := P.DueDate;
      mtPayments.FieldByName('Amount').AsCurrency := P.Amount;
      mtPayments.FieldByName('Status').AsString := P.Status;
      if P.PaidDate <> 0 then
        mtPayments.FieldByName('PaidDate').AsDateTime := P.PaidDate;
      if P.Status = 'paid' then              // how it was paid: only once it is
        mtPayments.FieldByName('Method').AsString := Pretty(P.Method);
      mtPayments.Post;
    end;
    mtPayments.First;
    if SelectId <> '' then
      mtPayments.Locate('Id', SelectId, []);   // back to the row the user was on
  finally
    mtPayments.EnableControls;
    FFilling := False;
  end;
  lblTotals.Caption := Format('Collected %s     Outstanding %s',
    [FormatCurr('#,##0.00', List.Collected), FormatCurr('#,##0.00', List.Outstanding)]);
  UpdatePaymentButtons;
end;

procedure TfrmMain.UpdatePaymentButtons;
var
  CanWrite: Boolean;
  Status: string;
begin
  // Only the main owner may write, and never on an archived property. The
  // server enforces this anyway (403 / 409); the UI just doesn't offer it.
  CanWrite := (not mtPayments.IsEmpty) and (not mtProperties.IsEmpty)
    and mtProperties.FieldByName('IsOwner').AsBoolean
    and not mtProperties.FieldByName('IsArchived').AsBoolean;
  if mtPayments.IsEmpty then
    Status := ''
  else
    Status := mtPayments.FieldByName('Status').AsString;
  btnMarkPaid.Enabled := CanWrite and (Status <> 'paid');
  btnMarkUnpaid.Enabled := CanWrite and (Status = 'paid');
end;

procedure TfrmMain.LoadLoans(const PropertyId: string);
begin
  SetBusy(True, 'Loading loans...');
  TAsync.Run<TLoanArray>(
    function: TLoanArray
    begin
      Result := FApi.GetLoans(PropertyId);
    end,
    procedure(Items: TLoanArray)
    begin
      SetBusy(False, '');
      if SelectedId(mtProperties) = PropertyId then
        FillLoans(Items);
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, '');
      HandleApiError(Err);
    end);
end;

procedure TfrmMain.FillLoans(const Items: TLoanArray);
var
  L: TLoanRec;
begin
  FFilling := True;
  mtLoans.DisableControls;
  try
    mtLoans.EmptyDataSet;
    for L in Items do
    begin
      mtLoans.Append;
      mtLoans.FieldByName('Id').AsString := L.Id;
      mtLoans.FieldByName('Lender').AsString := L.Lender;
      mtLoans.FieldByName('Principal').AsCurrency := L.Principal;
      mtLoans.FieldByName('DownPayment').AsCurrency := L.DownPayment;
      mtLoans.FieldByName('Rate').AsCurrency := L.InterestRatePct;
      mtLoans.FieldByName('Frequency').AsString := L.Frequency;
      mtLoans.FieldByName('CurrencyCode').AsString := L.CurrencyCode;
      mtLoans.FieldByName('Status').AsString := Pretty(L.Status);
      mtLoans.Post;
    end;
    mtLoans.First;
  finally
    mtLoans.EnableControls;
    FFilling := False;
  end;
  LoanChanged;
end;

procedure TfrmMain.LoanChanged;
var
  LoanId: string;
begin
  ClearTable(mtSchedule);
  lblSchedule.Caption := '';
  LoanId := SelectedId(mtLoans);
  if LoanId <> '' then
    LoadSchedule(LoanId);
end;

procedure TfrmMain.LoadSchedule(const LoanId: string);
begin
  SetBusy(True, 'Loading schedule...');
  TAsync.Run<TLoanSchedule>(
    function: TLoanSchedule
    begin
      Result := FApi.GetSchedule(LoanId);
    end,
    procedure(S: TLoanSchedule)
    begin
      SetBusy(False, '');
      if SelectedId(mtLoans) = LoanId then
        FillSchedule(S);
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, '');
      HandleApiError(Err);
    end);
end;

procedure TfrmMain.FillSchedule(const S: TLoanSchedule);
var
  P: TSchedulePeriodRec;
  Notes: string;
begin
  FFilling := True;
  mtSchedule.DisableControls;
  try
    mtSchedule.EmptyDataSet;
    for P in S.Periods do
    begin
      mtSchedule.Append;
      mtSchedule.FieldByName('Period').AsInteger := P.Period;
      mtSchedule.FieldByName('DueDate').AsDateTime := P.DueDate;
      mtSchedule.FieldByName('BeginBalance').AsCurrency := P.BeginningBalance;
      mtSchedule.FieldByName('Amount').AsCurrency := P.Amount;
      mtSchedule.FieldByName('Interest').AsCurrency := P.InterestAmount;
      mtSchedule.FieldByName('PrincipalPart').AsCurrency := P.PrincipalAmount;
      mtSchedule.FieldByName('EndBalance').AsCurrency := P.EndingBalance;
      mtSchedule.FieldByName('Pct').AsCurrency := P.PctOfPrincipal;
      if P.IsDownPayment then
        mtSchedule.FieldByName('Status').AsString := P.Status + ' (down)'
      else
        mtSchedule.FieldByName('Status').AsString := P.Status;
      if P.PaidDate <> 0 then
        mtSchedule.FieldByName('PaidDate').AsDateTime := P.PaidDate;
      mtSchedule.Post;
    end;
    mtSchedule.First;
  finally
    mtSchedule.EnableControls;
    FFilling := False;
  end;

  // the server's own flags, shown as words (PLAN a.4, call 12)
  Notes := '';
  if S.Drifted then
    Notes := Notes + '    Rows no longer add up to the price.';
  if not S.OnGrid then
    Notes := Notes + '    Due dates have moved off the plan.';
  lblSchedule.Caption := Format('Paid to date %s     Remaining %s     Interest %s%s',
    [FormatCurr('#,##0.00', S.PaidToDate), FormatCurr('#,##0.00', S.Remaining),
     FormatCurr('#,##0.00', S.TotalInterest), Notes]);
end;

procedure TfrmMain.LoadProperties;
begin
  SetBusy(True, 'Loading properties... (a sleeping server can take up to a minute)');
  TAsync.Run<TPropertyArray>(
    function: TPropertyArray
    begin
      Result := FApi.GetProperties;         // worker thread: no controls here
    end,
    procedure(Items: TPropertyArray)
    begin
      SetBusy(False, Format('%d properties', [Length(Items)]));
      FillProperties(Items);                // main thread
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, 'Could not load properties');
      HandleApiError(Err);
    end);
end;

procedure TfrmMain.FillProperties(const Items: TPropertyArray);
var
  P: TPropertyRec;
begin
  FFilling := True;
  mtProperties.DisableControls;
  try
    mtProperties.EmptyDataSet;
    for P in Items do
    begin
      mtProperties.Append;
      mtProperties.FieldByName('Id').AsString := P.Id;
      mtProperties.FieldByName('Name').AsString := P.Name;
      mtProperties.FieldByName('PropType').AsString := Pretty(P.PropertyType);
      mtProperties.FieldByName('Status').AsString := Pretty(P.Status);
      if P.DeliveryDate <> 0 then
        mtProperties.FieldByName('Delivery').AsDateTime := P.DeliveryDate;
      mtProperties.FieldByName('IsOwner').AsBoolean := P.IsOwner;
      mtProperties.FieldByName('IsArchived').AsBoolean := P.IsArchived;
      mtProperties.Post;
    end;
    mtProperties.First;
  finally
    mtProperties.EnableControls;
    FFilling := False;
  end;
  // AfterScroll was muted while filling: load the first property's details now
  PropertyChanged;
end;

end.
