# PMDesk

A Windows desktop client, written in Delphi (VCL), for Property Manager: a
FastAPI + PostgreSQL backend I built, which also serves a React web app and a
native iOS app.

<img width="1905" height="938" alt="Screenshot 2026-10-25 180743" src="https://github.com/user-attachments/assets/37975be0-7a77-4ae6-882c-d9c33b6dd9e5" />


## Why

Many Delphi business applications talk straight to their database (two-tier).
PMDesk is the other shape: a native client of a REST API (three-tier). It
reuses the server's rules (who may see what, when a payment is late, how a
loan plan rounds) instead of copying them, and it holds no database password.

## What it does

- Sign in (OAuth2 password form; the token is kept in memory only)
- Properties → units → leases (with tenant names) → rent payments, with the server's totals
- Loan amortization schedules, including the interest/principal split
- Every request runs in the background, so the window never freezes
- Stale replies are dropped when the user has already moved to another row

## How it is built

```text
Forms (VCL) -> TAsync (TTask + TThread.Queue) -> TPropertyApi (THTTPClient + System.JSON) -> REST API
                                                 returns records, or raises EApiError
```

- Built-in libraries only: System.Net.HttpClient, System.JSON, System.Threading, FireDAC TFDMemTable.
- No HTTP or JSON code in any form; the API unit uses no VCL unit.
- Money is `Currency`, parsed from the API's decimal strings with fixed format
  settings and shown with the user's (`18.000,00` in Austria). Grid fields are
  exact decimals (`TFMTBCDField`), never `TCurrencyField` (a Double underneath).
- Records, not classes, for API data: nothing to free, safe to pass between threads.
- Master-detail drill-down driven by `AfterScroll`, with a guard flag so that
  filling a table in code does not trigger server calls.

## Run it

1. Delphi 13 (Community Edition is enough): open `PMDesk.dproj`, build for Windows 32-bit.
2. Run once. It creates `PMDesk.ini` next to the exe. Set `BaseUrl` there (see `PMDesk.example.ini`).
3. Sign in with a landlord account.
