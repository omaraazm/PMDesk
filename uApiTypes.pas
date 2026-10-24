unit uApiTypes;

// The data the API returns, as records (PLAN d.5): copying one copies the
// data, there is nothing to free, and an array of them can be handed from a
// worker thread to the UI thread as it is.

interface

type
  TTokenPair = record
    AccessToken: string;
    RefreshToken: string;
  end;

  TUserRec = record
    Id: string;
    Email: string;
    FullName: string;
    Role: string;              // 'landlord' | 'tenant'
  end;

  TPropertyRec = record
    Id: string;
    Name: string;
    Address: string;
    PropertyType: string;      // 'building' | 'villa' | 'studio' | ...
    Status: string;            // 'ready' | 'under_construction'
    DeliveryDate: TDate;       // 0 = none
    IsOwner: Boolean;          // viewer_is_owner: False = co-owner, read-only
    IsArchived: Boolean;       // archived_at is set: read-only for everyone
  end;
  TPropertyArray = TArray<TPropertyRec>;

  TUnitRec = record
    Id: string;
    UnitNumber: string;
    Bedrooms: Integer;
    Bathrooms: Double;         // a count, not money: Double is fine
    IsOccupied: Boolean;
  end;
  TUnitArray = TArray<TUnitRec>;

  TLeaseRec = record
    Id: string;
    TenantId: string;
    TenantName: string;        // from a second call: /v1/users/lookup
    StartDate: TDate;
    EndDate: TDate;            // 0 = open-ended
    RentAmount: Currency;
    CurrencyCode: string;      // not "Currency": that is the type's name
    Status: string;
  end;
  TLeaseArray = TArray<TLeaseRec>;

  TPaymentRec = record
    Id: string;
    Amount: Currency;
    DueDate: TDate;
    PaidDate: TDate;           // 0 = not paid
    Status: string;            // 'pending' | 'paid' | 'late'
    Method: string;
  end;
  TPaymentArray = TArray<TPaymentRec>;

  // a lease's payments, plus the server's totals over all of them
  TPaymentList = record
    Items: TPaymentArray;
    Collected: Currency;
    Outstanding: Currency;
  end;

  TLoanRec = record
    Id: string;
    Lender: string;
    Principal: Currency;       // the full price, not the amount borrowed
    DownPayment: Currency;
    InterestRatePct: Currency; // 3 decimals: fits Currency exactly
    StartDate: TDate;
    Frequency: string;
    CurrencyCode: string;
    Status: string;
  end;
  TLoanArray = TArray<TLoanRec>;

  TSchedulePeriodRec = record
    Period: Integer;
    DueDate: TDate;
    BeginningBalance: Currency;
    Amount: Currency;
    InterestAmount: Currency;
    PrincipalAmount: Currency;
    EndingBalance: Currency;
    PctOfPrincipal: Currency;  // 4 decimals
    Status: string;
    PaidDate: TDate;
    IsDownPayment: Boolean;
  end;

  TLoanSchedule = record
    Periods: TArray<TSchedulePeriodRec>;
    PaidToDate: Currency;
    Remaining: Currency;
    TotalInterest: Currency;
    Drifted: Boolean;
    OnGrid: Boolean;
  end;

  // bonus: the Cashflow tab
  TForecastPeriodRec = record
    Period: Integer;
    StartDate: TDate;
    BeginningBalance: Currency;
    Income: Currency;
    RentIncome: Currency;
    Payments: Currency;
    Maintenance: Currency;
    EndingBalance: Currency;
  end;

  TForecast = record
    Configured: Boolean;       // False = the server said 404 "not configured"
    CurrencyCode: string;
    FirstNegativeDate: TDate;  // 0 = never negative
    FinalBalance: Currency;
    Periods: TArray<TForecastPeriodRec>;
  end;

implementation

end.
