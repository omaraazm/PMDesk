# PMDesk: a Delphi desktop client for the Property Manager API

> **Status:** complete (sections a–i).
> **Target:** Delphi 13 Community Edition, VCL, Win32, built-in libraries only.
> **Placeholders:** the server is always written `https://YOUR-API-HOST`. The real address goes only in your local `PMDesk.ini`, which is never committed.
> **Caveat:** the Delphi code is written from knowledge of the RTL and has not been compiled. The build steps say what to check at first compile.

## Contents

- a) API summary
- b) Reachability
- c) Demo data
- d) App design
- e) Threading
- f) Error handling
- g) Build guide
- h) Recommendations
- i) Interview prep

---

## a) API summary

### a.1 Rules that apply to every call

| Topic | What the server does | What PMDesk does |
|---|---|---|
| Base path | Business endpoints live under `/v1`. `/health` has no version prefix. | `BaseUrl + '/v1/...'` |
| Auth | `Authorization: Bearer <access_token>`, a JWT signed with HS256. The access token lasts **60 minutes**. The refresh token lasts **30 days** and is tied to a device session. A refresh token cannot call the API. | Keeps both tokens in memory only. |
| Request bodies | JSON (`Content-Type: application/json`), **except login**, which is a form. | |
| Response encoding | UTF-8 JSON. The header is `Content-Type: application/json` with no `charset`. | Decodes explicitly as UTF-8, because names can be in Arabic. |
| Money | **JSON strings, never numbers**: `"18000.00"`. This is enforced by `tests/test_contract.py`. Usually 2 decimals. A sum of nothing is `"0"`. Negatives look like `"-1500.00"`. Percentages: `interest_rate_pct` has 3 decimals (`"15.000"`), `pct_of_principal` has 4 (`"2.4359"`). | Parses into `Currency` using a fixed `.` decimal separator, and sends money back as strings. |
| Calendar dates | `"YYYY-MM-DD"`: no time, no time zone. Also enforced by the contract test. | Parses by hand into `TDate`. |
| Timestamps | `created_at` and similar fields: ISO 8601 with a UTC offset. | Not needed for the MVP. |
| IDs | UUID strings. | Keeps them as `string`. |
| Enums | Lowercase strings such as `"ready"` and `"under_construction"`. `GET /v1/enums` returns every list. New values can appear at any time. | Stores them as `string` and shows unknown values as they are. |
| `late` | Never stored. A `pending` payment or instalment whose due date has passed (by the server's date) is **reported** as `late` when read. | Displays it and never sends it. |
| Lists | Returned in an envelope: `{"items": [...], "total": n, "next_cursor": ...}`. `limit` defaults to 100, max 200. `next_cursor` is a string, or null on the last page. Send it back as `?cursor=`. | The API unit follows the cursors, so a form always receives one complete array. |
| Errors | `{"detail": "a sentence"}` for business errors. `{"detail": [ {...}, ... ]}` for request validation (422). `{"error": "Rate limit exceeded: ..."}` for 429. | See section f. |

### a.2 Status codes you will meet

| Code | Meaning here | Example text |
|---|---|---|
| 200 / 201 | OK / created | |
| 204 | OK, no body (deletes) | |
| 400 | A loan rule was broken | `"On a loan with interest, a payment can only be marked paid or unpaid"` |
| 401 | Not signed in, token expired or invalid, or wrong password at login | `"Could not validate credentials"`, `"Incorrect email or password"` |
| 403 | Wrong role, or a co-owner trying to write | `"Landlord role required"`, `"Not allowed"` |
| 404 | Not found, or cashflow not set up | `"Not found"`, `"Cashflow forecasting is not configured"` |
| 409 | The thing exists, but its state forbids the change | `"This property is archived — its history stays readable, but nothing new can be written against it"` |
| 422 | Invalid input. `detail` is a string **or** a list | see call 2 below |
| 429 | Too many logins: 10 per minute, 100 per hour, per IP | the body uses `"error"`, not `"detail"` |
| 5xx | Server or proxy trouble. The body may be an HTML page, not JSON | |

### a.3 Who may do what (PMDesk is a landlord client)

- Tenants can sign in, but get `403 "Landlord role required"` on everything PMDesk shows. After login, PMDesk calls `/v1/auth/me` and politely refuses non-landlords.
- A landlord sees the properties they **own** and those they **co-own**. A co-owner can read everything and write nothing (`403 "Not allowed"`). Each property's `viewer_is_owner` field says which case applies.
- An **archived** property (`archived_at` is set) is read-only for everyone. Writes return `409`.
- The login email must match **exactly**, including upper/lower case: `Demo@...` does not match `demo@...`. PMDesk trims spaces but doesn't change case.

### a.4 The endpoints PMDesk uses

Examples are sanitized: IDs are shortened with `…`, tokens are truncated, and names are invented.

#### 1. `GET /health`: is the server up?

No auth needed, and it doesn't touch the database. Use it to test the connection and wake the server. Don't poll `/health/db`: that one wakes the database.

```json
{"status": "ok"}
```

#### 2. `POST /v1/auth/login`: sign in

- No auth.
- **Form-encoded, not JSON.** FastAPI reads it with `OAuth2PasswordRequestForm`.
- Header: `Content-Type: application/x-www-form-urlencoded`.
- Body: `username` (the email) and `password`, each URL-encoded. The other OAuth2 fields (`grant_type`, `scope`, `client_id`, `client_secret`) are optional; leave them out.
- Optional headers that name this installation (see d.10): `X-Device-Id`, `X-Device-Name`, `X-Device-Platform`, `X-App-Version`.
- Rate limit: 10 per minute and 100 per hour, per IP.

```http
POST /v1/auth/login HTTP/1.1
Host: YOUR-API-HOST
Content-Type: application/x-www-form-urlencoded
User-Agent: PMDesk/0.1 (Windows; Delphi)
X-Device-Id: 7d0c3b52-…
X-Device-Name: WIN-LAPTOP
X-Device-Platform: windows
X-App-Version: 0.1.0

username=demo.landlord%40example.com&password=YOUR-PASSWORD
```

Response 200:

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOi…",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOi…",
  "token_type": "bearer"
}
```

Errors:

```text
401  {"detail": "Incorrect email or password"}
422  {"detail": [{"type": "missing", "loc": ["body", "password"], "msg": "Field required", "input": null}]}
429  {"error": "Rate limit exceeded: 10 per 1 minute"}
```

The token is a JWT whose payload is `{"sub": user id, "role": "landlord", "type": "access", "exp": ...}`. PMDesk treats it as an opaque string and asks `/v1/auth/me` for the role.

#### 3. `GET /v1/auth/me`: who am I?

Auth: Bearer.

```json
{
  "id": "9b2f…",
  "email": "demo.landlord@example.com",
  "full_name": "Demo Landlord",
  "role": "landlord",
  "phone": null,
  "created_at": "2026-10-20T09:14:03.512345Z",
  "has_password": true,
  "signs_in_with_apple": false
}
```

#### 4. `POST /v1/auth/refresh`: a new token pair (stretch goal)

No Bearer header. JSON body:

```json
{"refresh_token": "eyJhbGciOi…"}
```

The 200 response has the same shape as login, with both tokens new. A 401 says `"Invalid refresh token"` or `"This session has been signed out"`; either way, sign in again.

#### 5. `GET /v1/properties`: my properties

Auth: Bearer, landlord only. Optional query parameters: `limit` (up to 200), `cursor`, `q` (searches name and address), `status` (`under_construction` or `ready`), `property_type`. Newest first.

`GET /v1/properties?limit=200`

```json
{
  "items": [
    {
      "id": "1c9e…",
      "landlord_id": "9b2f…",
      "name": "Garden Court",
      "address": "12 Corniche St, Alexandria",
      "status": "ready",
      "delivery_date": null,
      "property_type": "building",
      "apartment_count": 3,
      "created_at": "2026-10-20T09:20:11.002311Z",
      "archived_at": null,
      "viewer_is_owner": true,
      "co_owner_count": 0
    },
    {
      "id": "5a47…",
      "landlord_id": "9b2f…",
      "name": "Palm Villa",
      "address": "New Capital, Plot 88",
      "status": "under_construction",
      "delivery_date": "2027-06-30",
      "property_type": "villa",
      "apartment_count": null,
      "created_at": "2026-10-20T09:22:40.551820Z",
      "archived_at": null,
      "viewer_is_owner": true,
      "co_owner_count": 0
    }
  ],
  "total": 2,
  "next_cursor": null,
  "status_counts": null,
  "amount_totals": null
}
```

#### 6. `GET /v1/units?property_id=…`

Units are sorted by `unit_number` **as text**, so `"10"` comes before `"2"`. `bathrooms` is a JSON number, not money, so `Double` is fine for it.

```json
{
  "items": [
    {"id": "e01d…", "property_id": "1c9e…", "unit_number": "1A", "bedrooms": 3, "bathrooms": 2.0, "currency": "EGP", "is_occupied": true},
    {"id": "e02d…", "property_id": "1c9e…", "unit_number": "1B", "bedrooms": 2, "bathrooms": 1.5, "currency": "EGP", "is_occupied": true},
    {"id": "e03d…", "property_id": "1c9e…", "unit_number": "2A", "bedrooms": 2, "bathrooms": 1.0, "currency": "EGP", "is_occupied": false}
  ],
  "total": 3,
  "next_cursor": null,
  "status_counts": null,
  "amount_totals": null
}
```

#### 7. `GET /v1/leases?unit_id=…`

Optional `status`: `active`, `ended` or `terminated`. Newest start date first. `status_counts` counts every status. An `end_date` of null means the lease is open-ended. A lease only carries `tenant_id`; the tenant's name comes from call 8.

```json
{
  "items": [
    {
      "id": "a7b3…",
      "unit_id": "e01d…",
      "tenant_id": "44c1…",
      "start_date": "2026-05-01",
      "end_date": "2027-04-30",
      "rent_amount": "18000.00",
      "currency": "EGP",
      "first_due_date": "2026-05-01",
      "status": "active"
    }
  ],
  "total": 1,
  "next_cursor": null,
  "status_counts": {"active": 1},
  "amount_totals": null
}
```

#### 8. `GET /v1/users/lookup?user_id=…`: a tenant's name

Landlord only, and it only returns tenant accounts. PMDesk makes one call per lease, which is fine at demo size; section h proposes a better way. A 404 says `"No tenant with that email"`, even when looking up by id.

```json
{"id": "44c1…", "email": "demo.tenant@example.com", "full_name": "Demo Tenant", "role": "tenant", "phone": null, "created_at": "2026-10-20T09:16:55.118001Z"}
```

#### 9. `GET /v1/payments?lease_id=…`

Optional `status`: `pending`, `paid` or `late`. Oldest due date first. `status_counts` and `amount_totals` cover **every** matching row, not just this page, so use them for the totals line instead of adding up the grid. The example shows 3 of 12 items.

```json
{
  "items": [
    {"id": "p001…", "lease_id": "a7b3…", "amount": "18000.00", "due_date": "2026-09-01", "paid_date": "2026-09-03", "status": "paid", "method": "manual"},
    {"id": "p002…", "lease_id": "a7b3…", "amount": "18000.00", "due_date": "2026-10-01", "paid_date": null, "status": "late", "method": "stub_button"},
    {"id": "p003…", "lease_id": "a7b3…", "amount": "18000.00", "due_date": "2026-11-01", "paid_date": null, "status": "pending", "method": "stub_button"}
  ],
  "total": 12,
  "next_cursor": null,
  "status_counts": {"paid": 5, "late": 1, "pending": 6},
  "amount_totals": {"collected": "90000.00", "outstanding": "126000.00"}
}
```

Generated payments have `method` set to `stub_button`, a placeholder. PMDesk sends `manual` when it records a payment.

#### 10. `PATCH /v1/payments/{id}`: record a payment (PMDesk's one write)

Landlord, and the **main owner** only. JSON body; only the fields you send change.

Mark paid:

```json
{"status": "paid", "paid_date": "2026-10-23", "method": "manual"}
```

Undo it (useful for resetting the demo):

```json
{"status": "pending", "paid_date": null}
```

The 200 response is the updated payment, shaped like an item in call 9. If you undo a payment whose due date has passed, it comes back as `"late"`.

- Unlike loan instalments, payments **don't** get a `paid_date` filled in by the server. Send it yourself.
- Errors: `403 "Not allowed"` (co-owner), `409` (archived property), `404`, and `422` (for example, a malformed date).
- Don't use `POST /v1/payments/{id}/pay`. It's tenant-only and a stub that changes nothing.

#### 11. `GET /v1/loans?property_id=…`

`principal` is the **full price**, not the amount borrowed. The amount borrowed is `principal` minus `down_payment`.

```json
{
  "items": [
    {
      "id": "l9d2…",
      "property_id": "5a47…",
      "lender": "Developer plan",
      "principal": "15000000.00",
      "down_payment": "750000.00",
      "interest_rate_pct": "0.000",
      "start_date": "2026-03-31",
      "frequency": "quarterly",
      "currency": "EGP",
      "status": "active",
      "notes": null,
      "created_at": "2026-10-20T09:25:02.771093Z"
    }
  ],
  "total": 1,
  "next_cursor": null,
  "status_counts": {"active": 1},
  "amount_totals": null
}
```

#### 12. `GET /v1/loans/{id}/schedule`: the amortization timeline

The server works this out on every request from the stored instalments. The example is EGP 15,000,000 with 5% down on 31 Mar 2026, 40 quarterly periods and no interest, the same numbers `tests/test_loans.py` checks. Periods 3–39 are left out.

```json
{
  "loan": {"…": "the same object as in call 11"},
  "periods": [
    {
      "period": 1, "due_date": "2026-03-31",
      "beginning_balance": "15000000.00", "amount": "750000.00", "ending_balance": "14250000.00",
      "pct_of_principal": "5.0000", "status": "paid", "paid_date": "2026-03-31",
      "is_down_payment": true, "installment_id": "i001…",
      "interest_amount": "0", "principal_amount": "750000.00"
    },
    {
      "period": 2, "due_date": "2026-06-30",
      "beginning_balance": "14250000.00", "amount": "365384.62", "ending_balance": "13884615.38",
      "pct_of_principal": "2.4359", "status": "late", "paid_date": null,
      "is_down_payment": false, "installment_id": "i002…",
      "interest_amount": "0", "principal_amount": "365384.62"
    },
    {
      "period": 40, "due_date": "2035-12-31",
      "beginning_balance": "365384.44", "amount": "365384.44", "ending_balance": "0.00",
      "pct_of_principal": "2.4359", "status": "pending", "paid_date": null,
      "is_down_payment": false, "installment_id": "i040…",
      "interest_amount": "0", "principal_amount": "365384.44"
    }
  ],
  "allocated": "15000000.00",
  "allocated_pct": "100.0000",
  "paid_to_date": "750000.00",
  "remaining": "14250000.00",
  "total_interest": "0",
  "drifted": false,
  "on_grid": true
}
```

How to read it:
- The last row absorbs the rounding (365,384.44 instead of 365,384.62), so the rows add up exactly to the price.
- With interest (`interest_rate_pct` above 0), each row splits into `interest_amount` and `principal_amount`. Only the principal part reduces the balance.
- `drifted` means the rows no longer add up to the principal, because someone edited them without rebalancing.
- `on_grid` means the due dates still follow the loan's frequency.
- Show both flags; don't recompute them.

#### 13. `GET /v1/cashflow/forecast?frequency=quarterly`

This is per landlord, not per property. `frequency` is `monthly`, `quarterly` (the default) or `yearly`. A 404 saying `"Cashflow forecasting is not configured"` means the landlord never set up a profile. Show "Not set up", not an error.

Example inputs: starting balance 500,000.00, income 90,000.00 per quarter, 0% growth, one lease at 18,000.00 a month, and one instalment of 360,000.00 due on 15 Jan 2027.

```json
{
  "currency": "EGP",
  "frequency": "quarterly",
  "start_date": "2026-10-01",
  "first_negative_date": null,
  "final_balance": "428000.00",
  "periods": [
    {"period": 1, "date": "2026-10-01", "beginning_balance": "500000.00", "income": "90000.00", "rent_income": "54000.00", "payments": "0", "maintenance": "0", "ending_balance": "644000.00"},
    {"period": 2, "date": "2027-01-01", "beginning_balance": "644000.00", "income": "90000.00", "rent_income": "54000.00", "payments": "360000.00", "maintenance": "0", "ending_balance": "428000.00"}
  ]
}
```

Notice the `"0"` values: a sum with nothing in it has no decimals. The parser must accept `"0"`, `"54000.00"` and `"-1500.50"` alike.

#### Not needed for the MVP, but good to know

- `GET /v1/dashboard`: everything the first screen needs in one answer (occupancy, what's due this month, a cashflow sparkline). A stretch goal.
- `GET /v1/loans/summary`: loan totals per currency.
- `GET /v1/enums`: every value list. `GET /v1/app-config`: the minimum app version and feature flags, no auth needed.
- `https://YOUR-API-HOST/docs`: FastAPI's interactive documentation for every endpoint. Open it in a browser and try calls by hand.

---

## b) Reachability

### b.1 What the repo says about hosting

- **API:** a Render web service with `plan: free` (`render.yaml`). It runs uvicorn behind Render's HTTPS proxy.
- **Database:** Neon Postgres. **Web app:** Vercel.
- **No custom domain**, and no Cloudflare configuration in the repo. The Cloudflare tunnels used until 23 Aug 2026 were retired. The only Cloudflare product still in use is R2 file storage, which PMDesk never touches.
- So "behind Cloudflare" can only mean Render's own network edge. That edge may run on Cloudflare, and the response headers in b.5 will show it (`server: cloudflare`, `cf-ray`). Either way it's Render's Cloudflare account, so there are **no bot-protection or firewall settings of yours** to check.

### b.2 What could block a desktop client (checked in the code)

- **User-Agent or Origin checks:** none. Nothing in the backend reads either header. CORS only affects browsers: a desktop app sends no `Origin` header, and CORS never blocks it.
- **API keys:** none. A Bearer token is all it takes.
- **Rate limits:** login allows 10 per minute and 100 per hour per client IP; register allows 20 per hour (`app/config.py`). Going over returns `429 {"error": ...}`.
- **Unverified:** uvicorn is started without `--forwarded-allow-ips`, so the IP the rate limiter sees may be Render's proxy rather than yours. If so, other people's logins count toward the same limit. In practice: never retry login in a loop.
- **Evidence that non-browser clients already work:** the iOS app uses this API daily, and on 16 Oct 2026 a Python script created the App Review demo data through it.

### b.3 Cold starts and timeouts

- Render's free tier puts the API to sleep after about 15 minutes without traffic, and the first request after that takes about 50 seconds. October's dashboard shows only ~16 of 750 free hours used, so production does sleep when idle; the uptime monitor isn't keeping it awake. Section h covers waking it before the demo.
- The free tier also has a monthly limit on server hours, shared with the staging server. If it runs out, Render suspends the API until the 1st of the next month. Section h covers what that means for interview day.
- THTTPClient's default timeouts are 60 seconds to connect and 60 seconds for the response, which a cold start can approach. So PMDesk reads its timeouts from the ini file: `ConnectTimeoutMs=15000` and `ResponseTimeoutMs=90000`. A sleeping server usually shows up as a slow response rather than a refused connection, so the response timeout is the one that needs to be long.

### b.4 TLS (HTTPS)

- On Windows, THTTPClient uses the operating system's own HTTPS support (WinHTTP + Schannel), so there are **no OpenSSL DLLs** to ship. Indy's `TIdHTTP`, the older Delphi HTTP component, needs OpenSSL DLLs beside the exe for HTTPS. That's one reason to choose THTTPClient.
- Windows' built-in `curl.exe` uses Schannel too. If `curl.exe` works from the laptop, THTTPClient will connect the same way.
- The laptop's clock must be roughly right, or certificate checks fail.

### b.5 Test from the Windows laptop before writing any Delphi

Use **Command Prompt (cmd.exe)**, not PowerShell. In Windows PowerShell 5.1, `curl` is an alias for `Invoke-WebRequest`, and PowerShell saves your command history to disk, password included. Always type `curl.exe`.

**1. Is the server up, and what's in front of it?**

```text
curl.exe -i https://YOUR-API-HOST/health
```

Expect status 200 (`HTTP/1.1 200 OK` or `HTTP/2 200`) and `{"status":"ok"}`. Then read the headers: `server: cloudflare` and a `cf-ray` header mean Cloudflare is in front.

**2. The same request with PMDesk's User-Agent, and with none at all:**

```text
curl.exe -i -A "PMDesk/0.1 (Windows; Delphi)" https://YOUR-API-HOST/health
curl.exe -i -A "" https://YOUR-API-HOST/health
```

Both should return 200. If either returns 403, or an HTML "checking your browser" page, something in front of the server is filtering bots. Stop there and investigate before writing Delphi.

**3. How long a request takes.** Run it now, and again after the laptop has been idle for a while; this shows whether you hit a cold start.

```text
curl.exe -s -o NUL -w "%{http_code} in %{time_total}s\n" https://YOUR-API-HOST/health
```

**4. Login: wrong password first, then the right one.**

```text
curl.exe -i https://YOUR-API-HOST/v1/auth/login --data-urlencode "username=YOUR-DEMO-EMAIL" --data-urlencode "password=wrong"
```

Expect 401 with `{"detail":"Incorrect email or password"}`. Then repeat with the real password and copy `access_token` from the answer. `--data-urlencode` makes curl send a POST with `Content-Type: application/x-www-form-urlencoded`, exactly what PMDesk will send. In cmd, a `"` or `%` inside the password can get mangled, so pick a demo password without them.

**5. Use the token:**

```text
set TOKEN=paste-the-access-token-here
curl.exe -s https://YOUR-API-HOST/v1/auth/me -H "Authorization: Bearer %TOKEN%"
curl.exe -s "https://YOUR-API-HOST/v1/properties?limit=200" -H "Authorization: Bearer %TOKEN%"
curl.exe -i https://YOUR-API-HOST/v1/properties -H "Authorization: Bearer nonsense"
```

The last command must return 401 with `{"detail":"Could not validate credentials"}`. That's what PMDesk will see when a token expires. Put quotes around any URL containing `?` or `&`, because cmd treats `&` as "run another command". Close the window afterwards; `set` only lasts as long as that window.

**Pass condition:** if steps 1–5 work, the network path is proven. Any later failure is in the Delphi code, not the network.

---

## c) Demo data

### c.1 What exists today

- **No seed script or fixture files in the repo.** `scripts/` holds only `export_openapi.py`.
- The tests create their own data in a throwaway SQLite database on every run (`tests/conftest.py` has a `portfolio` fixture; `tests/test_loans.py` has `SHEET_LOAN`). They're good templates for request bodies, but they can't be used against a real server.
- Production has an App Review demo account, made on 16 Oct with a one-off script that isn't in the repo. **Don't use it for PMDesk:**
  - Apple's reviewer signs in with it.
  - PMDesk's "Mark paid" would change what the reviewer sees.
  - Its password shouldn't travel to another laptop or repo.

### c.2 Proposal: a separate demo landlord for PMDesk

**Accounts:** a demo landlord, which PMDesk signs in with, and a demo tenant. A lease needs a tenant account; nobody ever signs in as it.

**Data**, enough to make every screen worth showing:

| Property | Type and status | Units | Leases and payments | Loan |
|---|---|---|---|---|
| Garden Court | building, ready, 3 apartments | 1A, 1B, 2A | 1A: 18,000 a month, May 2026 – Apr 2027; May–Sep paid, Oct late, the rest pending. 1B: 12,500 a month from Aug 2026, open-ended. 2A: vacant. | none |
| Palm Villa | villa, under construction, delivery 30 Jun 2027 | 1 (the villa itself) | none: it can't be leased until it's delivered | developer plan: 15,000,000.00, 5% down, 40 quarterly periods, no interest |
| Marina Studio | studio, ready | 1 | none | bank loan: 2,400,000.00, 20% down, 15% a year, quarterly over 3 years (13 rows). Shows the interest/principal split. |

Plus a **cashflow profile**: starting balance 500,000.00, income 90,000.00 per quarter, 0% growth, starting 1 Oct 2026, in EGP.

Each lease gets 12 payments from `POST /v1/leases/{id}/generate-payments`. That way there are always unpaid rows to mark paid during a demo, and "Mark unpaid" resets them.

**Two ways to create it:**

- **C1: by hand, no code.** Register both accounts on the web app, then enter the data in the web or iOS app. About 30 minutes. Nothing to review or maintain, but no quick reset.
- **C2: a seed script that only uses the public API.** About 150 lines of Python, standard library only.
  - It asks for the password when it runs and never stores it.
  - It refuses to run if the demo account already exists, and prints what it created.
  - It makes the same requests the web app makes, so the backend doesn't change.
  - It would live in the **new PMDesk repo** (`tools/seed_demo.py`), not in the backend repo.
  - Test it against a local backend first.

**Where:** I recommend **production**, using the demo landlord's own account. It's the server the interview demo will hit (wake it before the demo: see h). Staging has a separate database, which is safer, but it sleeps, so the first request on interview day would take about 50 seconds unless you wake it first.

> **Decided:** C2, on production, with its own demo account. The script is in step g.1.

---

## d) App design

### d.1 Two-tier vs three-tier

```text
Two-tier (the camp app)          Three-tier (PMDesk)

+-------------+                  +------------+  HTTPS + JSON  +-------------+  SQL  +------------+
| VCL app     |                  | PMDesk.exe | -------------> | FastAPI     | ----> | PostgreSQL |
| + FireDAC   |                  | (VCL)      | <------------- | on Render   | <---- | on Neon    |
+------+------+                  +------------+  bearer token  +-------------+       +------------+
       | SQL                      presentation                   rules + auth          data
+------v------+
| database    |
+-------------+
```

**Why three-tier here:**
- **No database password on the desktop.** PMDesk can only do what the API allows.
- **The rules already exist once, on the server, for the web and iOS apps:** who may see or change what, when a payment is late, how a loan plan rounds. PMDesk becomes a third client of those rules, not a third copy of them.
- **It works over the internet through HTTPS.** A two-tier app wants a LAN or VPN connection to the database.
- **The database can change behind a stable contract:** the `/v1` paths, money as strings and dates as `YYYY-MM-DD`, all enforced by tests.

**What it costs:**
- Every action is a network round trip, so requests need background threads.
- More things can fail: the network, an expired token, a sleeping server.
- You can't bind a grid straight to a table.

**When two-tier is still the right choice:** one site on a LAN with trusted users, heavy data entry where every millisecond counts, or offline work against a local database, like your camp app with SQLite.

### d.2 Units, and the one rule between them

```text
 uMain (TfrmMain)        uLogin (TfrmLogin)       forms: controls, grids, datasets
          \                   /                    -> never use System.Net.* or System.JSON
           \                 /
          uAsync (TAsync.Run<T>)                   worker thread -> result back on UI thread
                   |
          uPropertyApi (TPropertyApi)              HTTP + JSON + status codes -> records or EApiError
                   |                               -> never uses Vcl.* units
   uApiTypes (records)   uApiErrors (errors)   uConfig (ini)
```

| Unit | Contains | Uses |
|---|---|---|
| `uApiTypes.pas` | Records: `TPropertyRec`, `TUnitRec`, `TLeaseRec`, `TPaymentRec`, `TLoanRec`, `TSchedulePeriodRec`, `TForecastPeriodRec`, plus array types such as `TPropertyArray` | System units only |
| `uApiErrors.pas` | `TApiErrorKind`, `EApiError`, `TApiErrorInfo` (complete code in f.3) | `System.SysUtils` |
| `uConfig.pas` | `TAppConfig`: reads and writes `PMDesk.ini` | `System.IniFiles` |
| `uPropertyApi.pas` | `TPropertyApi`: one method per endpoint. Its JSON helpers sit in its implementation section. | `System.Net.HttpClient`, `System.JSON`, the three units above |
| `uAsync.pas` | `TAsync.Run<T>` (complete code in e.3) | `System.Threading`, `uApiErrors` |
| `uDataSets.pas` | Creates the memtables' fields in code (and the bonus CSV export) | `Data.DB`, `FireDAC.Comp.Client` |
| `uLogin.pas` | `TfrmLogin` | `uPropertyApi`, `uAsync`, `uApiErrors`, `uConfig` |
| `uMain.pas` | `TfrmMain` | everything above except the `System.Net` and `System.JSON` units |

**The rule:** forms never see HTTP or JSON, and `TPropertyApi` never sees a control. That's why the API class can be reused unchanged by a console tool, a Windows service or a test project, and why the UI can be replaced without touching it.

**Naming**, following your IDE gotchas:
- Unit `uMain`, form `frmMain`, class `TfrmMain`.
- Components get a type prefix: `edtEmail`, `btnSignIn`, `grdPayments`, `mtPayments` (a `TFDMemTable`), `dsPayments` (a `TDataSource`).

### d.3 Screens

**Login:** a modal dialog shown before the main window.

```text
+-------------------------------------------+
| PMDesk - Sign in                          |
|                                           |
|  Server   https://YOUR-API-HOST           |
|  Email    [________________________]      |
|  Password [************************]      |
|                                           |
|  <status or error text>     [ Sign in ]   |
+-------------------------------------------+
```

**Main window:**

```text
+------------------------------------------------------------------------------------+
| Demo Landlord (landlord)                      [Refresh] [Export CSV] [Sign out]    |
+-------------------------+----------------------------------------------------------+
| Properties              | [ Units & leases ] [ Loans ] [ Cashflow ]                |
| Name          Type      | Units     1A   3 bd  2 ba    occupied                    |
| Garden Court  building  |           1B   2 bd  1.5 ba  occupied                    |
| Palm Villa    villa     | Leases    Demo Tenant  18,000.00 EGP  May 26 - Apr 27    |
| Marina Studio studio    | Payments  01.09.2026  18,000.00  paid                    |
|                         |           01.10.2026  18,000.00  late    [Mark paid]     |
|                         |           ...                            [Mark unpaid]   |
|                         | Collected 90,000.00 - Outstanding 126,000.00             |
+-------------------------+----------------------------------------------------------+
| Ready - refreshed 14:32                                                            |
+------------------------------------------------------------------------------------+
```

- **Units & leases tab:** click a property to load its units, a unit to load its leases, and a lease to load its payments. Each click is one background request.
- **Loans tab:** the selected property's loans. Click a loan to see its schedule, with paid to date, remaining, total interest, and the `drifted` / `on_grid` flags.
- **Cashflow tab:** the landlord's forecast across all properties, a monthly / quarterly / yearly switch, the first negative date and the final balance. It shows "Not set up" when the server returns 404.
- **Write buttons are disabled** when the property isn't yours (`viewer_is_owner = false`) or is archived. The server would refuse anyway, but the UI shouldn't offer it.
- **One main form with tabs, not one form per screen.** Fewer forms means fewer chances for a reply to arrive after its form was freed (see e.5).

### d.4 MVP and stretch goals

**MVP, over two days** (the build guide in section g follows this order):
1. **Saturday:** demo data and curl tests; project setup; `uConfig`, `uApiErrors`, `uApiTypes`, `uAsync` and `uDataSets`; `uPropertyApi` (login, me, properties); the login form; the properties grid, loaded in the background.
2. **Sunday:** the units → leases (with tenant names) → payments drill-down; error handling (an expired session signs you in again; network errors); Mark paid / Mark unpaid; the loan schedule tab; a README, a screenshot and a demo recording.

**Bonus steps** (skippable, g.B1–g.B8): the Cashflow tab, CSV export, silent token refresh, request tickets, device headers, pointing PMDesk at a local backend, DUnitX tests and a Win64 build.

**Further ideas, not in the guide:**
- Recompute the interest-free plan in Delphi with `Currency` and compare it with the server's rows: a rounding story for the interview.
- A Dashboard tab (`/v1/dashboard`).
- Filters (late only) and a search box (`q`).

### d.5 Data: records, not classes, for what the API returns

```pascal
type
  TPaymentRec = record
    Id: string;
    LeaseId: string;
    Amount: Currency;
    DueDate: TDate;
    PaidDate: TDate;    // 0 = not paid (JSON null)
    Status: string;     // 'pending' | 'paid' | 'late' | anything new
    Method: string;
  end;
  TPaymentArray = TArray<TPaymentRec>;
```

**Why records:**
- **They're values.** Assigning or returning one copies it. There's nothing to `Free`, so nothing to leak.
- **They're safe to hand between threads.** `string` fields and dynamic arrays are reference-counted by the compiler. An array built on a worker thread can be handed to the UI thread as it is, because once it's handed over the worker never touches it again.
- **Classes would need an owner**, such as a `TObjectList<T>` with `OwnsObjects`, plus a rule for who frees them across two threads. That's where leaks and access violations come from.
- **Classes are the right tool** for things with behaviour and a lifetime: `TPropertyApi`, `TAppConfig`, the forms.

**Nulls:** Delphi has no built-in nullable type.
- A null date becomes `0` (30 Dec 1899, never a real lease date).
- A null string becomes `''`.
- If you ever need to tell "no amount" apart from zero money, add a `HasX: Boolean` field. The MVP doesn't need one.

### d.6 Display: TFDMemTable + TDataSource + TDBGrid

Each grid gets a `TFDMemTable` (FireDAC's in-memory dataset; you already know FireDAC) and a `TDataSource`. The records from the API are copied into the memtable on the UI thread.

**Why:**
- **Typed fields.** Money is an exact decimal field with a display format, and dates are dates, so the grid formats and sorts them correctly.
- **Built-in features:** sorting (`IndexFieldNames`), filtering, `Locate` (keep the selected row after a refresh) and `DisableControls` / `EnableControls`.
- **One CSV export routine** works for every grid, because every grid sits on a dataset.
- **It's how dataset-centric Delphi business apps (ERP) are written,** so the code will look familiar to the people interviewing you.
- **Grids are read-only** (`ReadOnly = True`, `dgRowSelect`). A change goes through an API call followed by a reload, never by typing into the grid.

**Alternatives considered:**

| Option | Verdict |
|---|---|
| `TStringGrid` | Everything is text, so you format, sort and export by hand. Fine for a tiny fixed table. |
| `TListView` (vsReport) | Native look, but you get no types, sorting or export for free. |
| `TRESTClient` + `TRESTResponseDataSetAdapter` (Delphi's built-in REST library) | Fills a dataset from JSON with almost no code, which is great for a quick prototype. But money strings arrive as string fields, field types are guessed, and the threading and errors are hidden inside components. The point here is to show you understand each layer. Mention it in the interview as the fast path. |

**A real trap with money fields:** use **`ftBCD`**, which gives a `TBCDField` holding an exact `Currency`. **Don't use `ftCurrency`:** a `TCurrencyField` is a `TFloatField` underneath, so it's a `Double` with a money display format. Set `Precision = 18`, `Size = 2` (for BCD fields, `Size` is the number of decimals) and `DisplayFormat = '#,##0.00'`.

### d.7 Money: `Currency`, never `Double`

- **What `Currency` is:** a 64-bit integer that counts ten-thousandths. You get 4 exact decimals and a range of about ±922 trillion, and `0.1 + 0.2 = 0.3` exactly. `Double` is binary floating point: 0.1 has no exact value, sums drift, and equality tests fail.
- **Money never touches floating point.** Every amount from the API is a JSON string. PMDesk reads the string and converts it with `StrToCurr(S, ApiFormat)`, where `ApiFormat` is a `TFormatSettings` with `DecimalSeparator = '.'`.
- **Why the fixed format matters at an Austrian company:** on Windows set to German (Austria), the decimal separator is `,`, so a plain `StrToCurr('18000.00')` raises `EConvertError`.
- **Parse with fixed settings, display with the user's settings.** `FormatCurr('#,##0.00', V)` shows `18.000,00` on a German (Austria) Windows and `18,000.00` on an English one.
- **Sending money back:** as a string, with `FormatCurr('0.00', V, ApiFormat)`.
- **No money arithmetic in PMDesk's MVP.** The server owns every figure; its own rule is written down in `app/routers/dashboard.py`. The payments list already returns totals. Fewer places to round means fewer places to be wrong.
- **For the stretch recompute only:** Delphi's `Round` rounds half to even (banker's rounding), while the server rounds half up (`ROUND_HALF_UP`). Matching the server would need your own half-up rounding.
- `pct_of_principal` (4 decimals) and `interest_rate_pct` (3 decimals) also fit `Currency` exactly.

### d.8 Dates

- **Parsing:** by hand, so there's no time zone and no locale involved:
  `EncodeDate(StrToInt(Copy(S, 1, 4)), StrToInt(Copy(S, 6, 2)), StrToInt(Copy(S, 9, 2)))`
- **Sending:** `FormatDateTime('yyyy-mm-dd', D)`. In format strings, `/` would be replaced by the Windows date separator (`.` in Austria), and `mm` means month while `nn` means minutes.
- **Displaying:** a date field formats itself with the Windows short date format, for example `01.10.2026` in Austria.

### d.9 Configuration: `PMDesk.ini` next to the exe

```ini
[Server]
BaseUrl=https://YOUR-API-HOST
ConnectTimeoutMs=15000
ResponseTimeoutMs=90000

[Client]
; generated on first run; names this installation in the server's session list
DeviceId=
; convenience only: pre-fills the email box
LastEmail=
```

- **Location:** `ChangeFileExt(ParamStr(0), '.ini')`, next to the exe. While you develop, that's the `Win32\Debug` folder.
- **No secrets in it:** no password, no token. The device id is not a secret.
- **Git:** the build output folders (`Win32/`) are ignored, so the real ini is never committed. The repo gets a `PMDesk.example.ini` with the placeholder address instead.
- **First run:** if the ini is missing, PMDesk writes one with the example values and asks you to set `BaseUrl`.

### d.10 Tokens, device headers, User-Agent

- **Tokens:** the access and refresh tokens are two string fields of `TPropertyApi`. They're set on the UI thread after login and cleared on sign-out. They're never written to the ini, the registry, a log or an error message. Closing the app forgets them, so you sign in each time; that trade-off is deliberate.
- **Device headers** (bonus step B5): at login, PMDesk sends `X-Device-Id` (the GUID from the ini), `X-Device-Name` (the computer name), `X-Device-Platform: windows` and `X-App-Version: 0.1.0`. The server then keeps one session for this installation (`GET /v1/devices` lists them). Without these headers, every sign-in creates a new "Unnamed device" session.
- **User-Agent:** every request sends `User-Agent: PMDesk/0.1 (Windows; Delphi)`. It's polite, and it makes PMDesk's traffic easy to spot in logs.

---

## e) Threading

### e.1 The rules

1. **Only the main thread touches the VCL:** controls, forms, and datasets connected to grids.
2. **Read what you need from controls before starting the work**, into local variables. The worker uses those copies, never the controls.
3. **The worker only does HTTP and JSON → records**, all of it inside `TPropertyApi`. Then it hands the result back.
4. **Results come back through `TThread.Queue`.** `Synchronize` would make the worker wait while the UI runs the code; nothing here needs the worker to wait, so `Queue` is the better fit.
5. **Errors are caught on the worker and copied into a `TApiErrorInfo` record.** Never use the exception object `E` inside the queued code: Delphi frees it at the end of the `except` block, long before the queued code runs, and the result is an access violation.
6. **While a request runs:** disable the button that started it, show a status, and refuse to close the window (`OnCloseQuery`).
7. **Each API call creates and frees its own `THTTPClient`,** so no HTTP object is shared between threads.
8. **The token is written only on the main thread** (after login, before any other request starts) and only read by workers.
9. **Drop stale replies.** Suppose the user clicks property A, then property B before A's units arrive. A's answer must not overwrite B's. Each drill-down keeps a request number, and any reply that isn't from the latest request is dropped.

### e.2 TTask or TThread?

| | `TTask.Run` (`System.Threading`) | A `TThread` subclass |
|---|---|---|
| Thread | taken from a shared pool and reused | its own OS thread |
| Code | an anonymous method, written where it's used | a class that overrides `Execute` |
| Good for | short jobs, such as one HTTP request | long-running workers, loops, queues |

PMDesk uses `TTask` through one small helper, so every call looks the same. `TThread.CreateAnonymousThread` sits in between.

Calling `Application.ProcessMessages` in a loop is not a substitute. The UI still freezes for the length of each request, and it invites re-entrancy bugs: a second click starts a second request while the first one is still running.

### e.3 The reusable helper: `uAsync.pas` (complete unit)

```pascal
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
```

### e.4 How a form uses it

```pascal
procedure TfrmMain.LoadProperties;
begin
  SetBusy(True, 'Loading properties...');
  TAsync.Run<TPropertyArray>(
    function: TPropertyArray
    begin
      Result := FApi.GetProperties;        // worker thread: no controls here
    end,
    procedure(Items: TPropertyArray)
    begin
      SetBusy(False, Format('%d properties', [Length(Items)]));
      FillProperties(Items);               // main thread: safe to touch the grid
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, 'Could not load properties');
      HandleApiError(Err);                 // main thread
    end);
end;
```

`LoadProperties` returns immediately and the window stays responsive. Later, exactly one of the two callbacks runs on the main thread.

The stale-reply guard from rule 9:

```pascal
procedure TfrmMain.LoadUnits(const PropertyId: string);
var
  Ticket: Integer;
begin
  Inc(FUnitsTicket);
  Ticket := FUnitsTicket;                  // this request's number
  TAsync.Run<TUnitArray>(
    function: TUnitArray
    begin
      Result := FApi.GetUnits(PropertyId);
    end,
    procedure(Items: TUnitArray)
    begin
      if Ticket <> FUnitsTicket then
        Exit;                              // a newer request was started: drop this one
      FillUnits(Items);
    end,
    procedure(Err: TApiErrorInfo)
    begin
      if Ticket = FUnitsTicket then
        HandleApiError(Err);
    end);
end;
```

Each call to `LoadUnits` gets its own `Ticket` variable, which its callbacks capture. `FUnitsTicket` is only read and written on the main thread, so the comparison is safe.

### e.5 What can still go wrong

- **Closing the main window while a request runs.** The reply would arrive at a form that no longer exists. Rule 6 prevents this: the window refuses to close while requests are pending. The longest possible wait is the response timeout.
- **A `ShowMessage` dialog inside a callback.** It blocks the UI, and other replies queue up behind it until it closes. That's acceptable; use the status bar for routine messages.
- **Double-clicking "Mark paid".** That would send two requests. Disable the button until the reply arrives.

---

## f) Error handling

### f.1 Where each failure is caught

```text
THTTPClient raises ENetException --+
HTTP status is not 2xx ------------+--> TPropertyApi raises EApiError(Kind, StatusCode, server's text)
                                            |
Bad or unexpected JSON (EJSONException, EConvertError) --+
                                            |            |
                                            v            v
                  TAsync: except on E: Exception -> TApiErrorInfo (a copy)
                                            |
                                            |  TThread.Queue
                                            v
                  Form: HandleApiError(Err) -> a message, the login form again, or a quiet status
```

Every error reaches the form in the same shape. The form decides what the user sees.

### f.2 What the user sees

| Kind | Comes from | The user sees | PMDesk then |
|---|---|---|---|
| `aekNetwork` | `ENetException`: no internet, DNS, TLS, timeout | "Cannot reach the server…" plus the technical reason | does nothing automatically; the user presses Refresh |
| `aekUnauthorized` | 401 | At login: the server's text ("Incorrect email or password"). Anywhere else: "Your session has expired" | shows the login form again, then reloads |
| `aekForbidden` | 403 | the server's text | rarely happens: write buttons are already disabled for co-owners |
| `aekNotFound` | 404 | the server's text | for cashflow, 404 means "Not set up" and is shown in the tab, not as an error |
| `aekConflict` | 409 | the server's text, which is written for people ("Palm Villa is still under construction…") | reloads the view |
| `aekValidation` | 422 | each problem on its own line, e.g. `paid_date: Input should be a valid date` | |
| `aekRateLimited` | 429 | "Too many attempts. Wait a minute." | |
| `aekServer` | 5xx | "The server had a problem (HTTP 503)…" | |
| `aekUnexpected` | anything else: bad JSON, a bug | the exception's class name and message | worth investigating |

**Check input before sending it.** For example, an empty email shows a message and no request goes out. The server still has the final say: its 422 answer is handled anyway.

**Retries:** the MVP never retries on its own. If it ever does:
- GETs and the `PATCH` are safe to repeat. The PATCH sets a state, so sending it twice changes nothing more.
- A `POST` that creates something is not safe to repeat.

### f.3 `uApiErrors.pas` (complete unit)

```pascal
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
```

The login form doesn't use `UserText` for a 401. At login, a 401 means a wrong password, not an expired session, so it shows `Message`, the server's own sentence.

### f.4 Turning a response into data, or into an EApiError

These two routines go in the implementation section of `uPropertyApi`. Step g.5 gives the complete unit; they're shown here so you can review them now.

```pascal
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
    Exit;                                   // not JSON: e.g. a proxy's HTML error page
  try
    if not (Root is TJSONObject) then
      Exit;                                 // finally still runs: Root is freed
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
    else if not Root.TryGetValue<string>('error', Result) then   // 429 from the rate limiter
      Result := '';
  finally
    Root.Free;                              // frees Detail, Item, Loc too: the root owns them
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
```

### f.5 try..finally and try..except: the patterns used throughout

**1. Create, then `try`, then use, then free in `finally`:**

```pascal
Root := TJSONObject.ParseJSONValue(Body);   // create BEFORE the try
try
  // ... use Root ...
finally
  Root.Free;                                 // always runs: on success, on Exit, on an exception
end;
```

If the creation were inside the `try` and failed, the `finally` would free a variable that was never assigned.

**2. Several objects: set them all to `nil` first.** `Free` on `nil` does nothing.

```pascal
Http := nil;
Body := nil;
try
  Http := THTTPClient.Create;
  Body := TStringStream.Create(Json, TEncoding.UTF8);
  // ...
finally
  Body.Free;
  Http.Free;
end;
```

**3. JSON ownership.** Free only what you created, or what `ParseJSONValue` returned. Values you get out of it (`GetValue`, `Items[I]`) belong to the root; freeing them as well is a double free. A `TJSONObject` you build owns every pair you `AddPair` to it.

**4. Translate errors, don't swallow them.** `except on E: ENetException do raise EApiError.Create(aekNetwork, 0, E.Message); end;` turns a network error into the app's own error type. Never write `except end;` with nothing inside: the error vanishes and the bug hides. To pass the same exception on unchanged, use a bare `raise;`.

**5. Interfaces free themselves.** `IHTTPResponse` is reference-counted and disappears when the last variable pointing to it goes away. Never call `Free` on it.

**6. Leak check while developing.** Put `ReportMemoryLeaksOnShutdown := True;` in the `.dpr` (step g.2). When you close the app, it lists every object you forgot to free.

---

## g) Build guide

### g.0 How to use this guide

**Schedule**

| Day | Step | What you build | Time |
|---|---|---|---|
| Sat | g.1 | Demo data (seed script) + curl tests | 45 min |
| Sat | g.2 | Empty project, git, leak check | 20 min |
| Sat | g.3 | `uConfig`: the ini file | 20 min |
| Sat | g.4 | Shared units: errors, records, async helper, table helper | 20 min |
| Sat | g.5 | `uPropertyApi` (health, login, me, properties) + a smoke test | 45 min |
| Sat | g.6 | Login form | 45 min |
| Sat | g.7 | Properties grid, loaded in the background | 45 min |
| Sun | g.8–g.15 | Tabs, units → leases → payments, errors, Mark paid, loan schedule, README, recording | about 4.5 h |
| Bonus | g.B1–g.B8 | Cashflow, CSV, token refresh, request tickets, device headers, local backend, DUnitX, Win64 | skippable |

**How the steps are written**
- Each step has five parts: *what and why*, *IDE actions*, *code*, *what to understand*, *how to test*.
- Don't start the next step until the test passes. Commit after each step: `git add -A` then `git commit -m "g.N ..."`.
- Every code block says where it goes. When a procedure changes, the step shows the **whole** procedure to replace it with.

**Who owns which part of a form unit**

| Part of the unit | Owner | What you do |
|---|---|---|
| The `published` part of the class (the components and event handlers listed right after `class(TForm)`) | the IDE | Never type in it. Drop components and double-click events instead, and the IDE writes it. |
| `private` and `public` sections | you | This guide gives you the complete text for these. |
| The implementation of each procedure | you | Paste the complete procedure. |

**Your IDE gotchas, built into the steps**
- Unit name ≠ form name: unit `uMain`, form `frmMain`, class `TfrmMain`.
- **Set a component's `Name` before you double-click its event.** The handler name comes from the component name (`btnSignIn` → `btnSignInClick`).
- **Never copy and paste a button.** The copy shares the original's click handler. Drop every button fresh from the Tool Palette.
- `end;` closes a block. `end.` (with a full stop) appears once, as the last line of a unit.

**Keys:** `Ctrl+F9` compiles, `F9` runs with the debugger, `Shift+Ctrl+S` saves all, `F1` opens help for the word under the cursor.

**If something doesn't compile**

| Message | Likely cause and fix |
|---|---|
| `E2003 Undeclared identifier: 'TFDMemTable'` (or another component type) | The unit is missing from `uses`. Dropping that component on the form adds it, or add it by hand (for this one, `FireDAC.Comp.Client`). |
| `E2003 Undeclared identifier: 'ENetException'` or `'TNetHeader'` | `System.Net.URLClient` is missing from `uPropertyApi`'s interface `uses`. |
| `E2003 Undeclared identifier: 'Patch'` | Tell me. It would mean THTTPClient in Delphi 13 has no `Patch` method, and I'd give you the alternative. |
| `EConvertError: '18000.00' is not a valid floating point value` | Something called `StrToCurr` without `ApiFormat`. Only `JCurr` should convert money. |
| `Field 'Id' not found` | The table's `Define…Table` procedure wasn't called in `FormCreate`, or a field name has a typo. |
| `Cannot perform this operation on a closed dataset` | `CreateDataSet` never ran for that memtable (it's at the end of every `Define…Table`). |
| Login returns 422 with `Field required` | The form body isn't being sent as a form. Check that `Login` passes `'application/x-www-form-urlencoded'` as the content type. |

None of this code has been compiled yet. When a message isn't in the table, copy it exactly, with the unit name and line number.

---

### g.1 Demo data and API tests (Saturday, first thing)

**What and why.** Create the demo landlord and data from section c.2 through the public API. The seed script makes the same requests the web app makes, so the server checks everything exactly as it would for a real user: validation, ownership, the delivery-date rule. It needs no database password. Then prove the network path from the Windows laptop with `curl.exe` before writing any Delphi.

**Actions**

1. Create the repo folder on the laptop, e.g. `C:\Dev\PMDesk`, and a `tools` folder inside it.
2. Save the script below as `tools\seed_demo.py`.
3. Choose the two demo emails. `@example.com` addresses are fine, because the app never sends mail (e.g. `pmdesk.demo@example.com` and `pmdesk.tenant@example.com`). Choose the landlord's password: at least 12 characters, and **without `"` or `%`**, so the curl tests in cmd.exe don't mangle it. Keep it in your password manager, never in the repo.
4. *Recommended:* run the script against a local backend first (below), then against production.
5. Run it against production.
6. Run the curl tests from section b.5, signing in as the new demo landlord.

**The script: `tools/seed_demo.py`**

```python
#!/usr/bin/env python3
"""Create PMDesk's demo data through the PM API's public endpoints.

What it creates (PLAN.md, section c.2):
  * a demo landlord (you sign in to PMDesk with it) and a demo tenant
  * Garden Court: a building with apartments 1A, 1B, 2A; two leases with
    12 monthly payments each, the past months marked paid except one
  * Palm Villa: a villa under construction with an interest-free developer plan
  * Marina Studio: a studio with a 15% bank loan
  * a cashflow profile

It only calls endpoints the web app calls: no database access, no admin route.
You type the landlord's password when it runs; it is never printed or saved.
The tenant gets a random password nobody needs: no one signs in as the tenant.
If the landlord email is already registered, it stops before creating anything.

Usage:
  python seed_demo.py --base-url http://127.0.0.1:8000 \
      --landlord-email demo.landlord@example.com \
      --tenant-email demo.tenant@example.com

Python 3.9+, standard library only.
"""

import argparse
import getpass
import json
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "PMDesk-seed/0.1"
TIMEOUT_S = 120  # a sleeping Render free instance needs ~50 s to answer


class ApiError(Exception):
    def __init__(self, method, path, status, body):
        super().__init__(f"{method} {path} -> HTTP {status}: {body[:500]}")
        self.status = status


class Api:
    """Just enough HTTP client: JSON in and out, one bearer token."""

    def __init__(self, base_url):
        self.base_url = base_url.rstrip("/")
        self.token = None

    def call(self, method, path, body=None, form=None, headers=None):
        all_headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
        data = None
        if form is not None:
            data = urllib.parse.urlencode(form).encode("utf-8")
            all_headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif body is not None:
            data = json.dumps(body).encode("utf-8")
            all_headers["Content-Type"] = "application/json"
        if self.token:
            all_headers["Authorization"] = "Bearer " + self.token
        all_headers.update(headers or {})

        request = urllib.request.Request(
            self.base_url + path, data=data, headers=all_headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as err:
            raise ApiError(
                method, path, err.code, err.read().decode("utf-8", "replace")
            ) from None
        return json.loads(raw) if raw else None


def mark_installments_paid(api, loan_id, until):
    """Mark every instalment due on or before `until` (YYYY-MM-DD) as paid."""
    count = 0
    for row in api.call("GET", f"/v1/loans/{loan_id}/installments"):
        if row["due_date"] <= until:
            api.call(
                "PATCH",
                f"/v1/installments/{row['id']}",
                body={"status": "paid", "paid_date": row["due_date"]},
            )
            count += 1
    return count


def main():
    parser = argparse.ArgumentParser(description="Create PMDesk's demo data.")
    parser.add_argument("--base-url", required=True, help="e.g. https://YOUR-API-HOST")
    parser.add_argument("--landlord-email", required=True)
    parser.add_argument("--tenant-email", required=True)
    args = parser.parse_args()

    api = Api(args.base_url)
    print(f"Server: {api.base_url}")
    print("Waking it up (a sleeping server can take about a minute)...")
    print("  /health says:", api.call("GET", "/health"))

    password = getpass.getpass(f"Choose a password for {args.landlord_email}: ")
    if len(password) < 12:
        print("Use at least 12 characters. Nothing was sent.")
        return 1
    answer = input(
        f"Create the demo landlord, tenant and data on {api.base_url}? Type YES: "
    )
    if answer != "YES":
        print("Nothing was sent.")
        return 1

    # --- accounts ---
    try:
        api.call("POST", "/v1/auth/register", body={
            "email": args.landlord_email, "password": password,
            "full_name": "Demo Landlord", "role": "landlord",
        })
    except ApiError as err:
        if err.status == 409:
            print(f"{args.landlord_email} is already registered. Nothing was created.")
            return 1
        raise
    print("Created landlord", args.landlord_email)

    tenant_id = None
    try:
        tenant = api.call("POST", "/v1/auth/register", body={
            "email": args.tenant_email, "password": secrets.token_urlsafe(24),
            "full_name": "Demo Tenant", "role": "tenant",
        })
        tenant_id = tenant["id"]
        print("Created tenant", args.tenant_email)
    except ApiError as err:
        if err.status != 409:
            raise
        # it exists already: looked up below, once signed in

    tokens = api.call(
        "POST", "/v1/auth/login",
        form={"username": args.landlord_email, "password": password},
        headers={
            "X-Device-Id": "pmdesk-seed-script",
            "X-Device-Name": "PMDesk seed script",
            "X-Device-Platform": "script",
        },
    )
    api.token = tokens["access_token"]
    print("Signed in as the landlord")

    if tenant_id is None:
        query = urllib.parse.urlencode({"email": args.tenant_email})
        tenant_id = api.call("GET", f"/v1/users/lookup?{query}")["id"]
        print("Reusing the existing tenant", args.tenant_email)

    # --- Garden Court: a building, three apartments, two leases ---
    garden = api.call("POST", "/v1/properties", body={
        "name": "Garden Court", "address": "12 Corniche St, Alexandria",
        "status": "ready", "property_type": "building", "apartment_count": 3,
    })
    print("Created property Garden Court")
    units = {}
    for number, bedrooms, bathrooms in (("1A", 3, 2), ("1B", 2, 1.5), ("2A", 2, 1)):
        units[number] = api.call("POST", "/v1/units", body={
            "property_id": garden["id"], "unit_number": number,
            "bedrooms": bedrooms, "bathrooms": bathrooms,
        })
    print("  units 1A, 1B, 2A")

    leases = {
        "1A": api.call("POST", "/v1/leases", body={
            "unit_id": units["1A"]["id"], "tenant_id": tenant_id,
            "start_date": "2026-05-01", "end_date": "2027-04-30",
            "rent_amount": "18000.00", "currency": "EGP",
            "first_due_date": "2026-05-01",
        }),
        "1B": api.call("POST", "/v1/leases", body={
            "unit_id": units["1B"]["id"], "tenant_id": tenant_id,
            "start_date": "2026-08-01", "end_date": None,
            "rent_amount": "12500.00", "currency": "EGP",
            "first_due_date": "2026-08-01",
        }),
    }
    # 1A: May-Sep paid, so October shows as late; 1B: Aug-Oct paid
    paid_until = {"1A": "2026-09-30", "1B": "2026-10-31"}
    for label, lease in leases.items():
        payments = api.call(
            "POST", f"/v1/leases/{lease['id']}/generate-payments", body={"months": 12}
        )
        paid = 0
        for payment in payments:
            if payment["due_date"] <= paid_until[label]:
                api.call("PATCH", f"/v1/payments/{payment['id']}", body={
                    "status": "paid", "paid_date": payment["due_date"],
                    "method": "manual",
                })
                paid += 1
        print(f"  lease {label}: {len(payments)} payments, {paid} marked paid")

    # --- Palm Villa: under construction, interest-free developer plan ---
    villa = api.call("POST", "/v1/properties", body={
        "name": "Palm Villa", "address": "New Capital, Plot 88",
        "status": "under_construction", "delivery_date": "2027-06-30",
        "property_type": "villa", "unit": {"bedrooms": 4, "bathrooms": 3},
    })
    villa_loan = api.call("POST", "/v1/loans", body={
        "property_id": villa["id"], "lender": "Developer plan",
        "total_price": "15000000.00", "down_payment_pct": "5",
        "purchase_date": "2026-03-31", "period_count": 40,
        "frequency": "quarterly", "currency": "EGP",
    })
    paid = mark_installments_paid(api, villa_loan["id"], until="2026-09-30")
    print(f"Created property Palm Villa, developer plan, {paid} instalments paid")

    # --- Marina Studio: a bank loan with interest ---
    studio = api.call("POST", "/v1/properties", body={
        "name": "Marina Studio", "address": "Marina 5, North Coast",
        "status": "ready", "property_type": "studio",
        "unit": {"bedrooms": 0, "bathrooms": 1},
    })
    bank_loan = api.call("POST", "/v1/loans", body={
        "property_id": studio["id"], "lender": "Demo Bank",
        "total_price": "2400000.00", "down_payment_pct": "20",
        "purchase_date": "2026-01-15", "period_count": 13,
        "frequency": "quarterly", "interest_rate_pct": "15", "currency": "EGP",
    })
    paid = mark_installments_paid(api, bank_loan["id"], until="2026-10-15")
    print(f"Created property Marina Studio, bank loan at 15%, {paid} instalments paid")

    # --- cashflow profile (the bonus Cashflow tab reads it) ---
    api.call("PUT", "/v1/cashflow/profile", body={
        "starting_balance": "500000.00", "income_per_period": "90000.00",
        "annual_growth_pct": "0", "start_date": "2026-10-01", "currency": "EGP",
    })
    print("Created the cashflow profile")

    print(f"\nDone. Sign in to PMDesk as {args.landlord_email}.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ApiError as err:
        sys.exit(f"\nStopped: {err}\nEverything printed above was created; nothing after it.")
    except urllib.error.URLError as err:
        sys.exit(f"\nCould not reach the server: {err.reason}")
```

**Recommended: a test run against a local backend first (on the Mac, in the PM repo).** It uses a throwaway local database; Neon is never touched. In the connection string, use the same user and password as your `.env`'s `DATABASE_URL`, with the database name changed to `pm_seed_test`:

```text
cd ~/PM
source .venv/bin/activate
createdb pm_seed_test
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/pm_seed_test alembic upgrade head
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/pm_seed_test fastapi dev app/main.py
```

Then, in a second terminal:

```text
python3 tools/seed_demo.py --base-url http://127.0.0.1:8000 --landlord-email pmdesk.demo@example.com --tenant-email pmdesk.tenant@example.com
```

Afterwards: stop the server (`Ctrl+C`) and drop the test database (`dropdb pm_seed_test`).

**Production run.** Run it on whichever machine has Python 3: on Windows `py tools\seed_demo.py ...`, on the Mac `python3 tools/seed_demo.py ...`.

```text
py tools\seed_demo.py --base-url https://YOUR-API-HOST --landlord-email pmdesk.demo@example.com --tenant-email pmdesk.tenant@example.com
```

Expected output:

```text
Server: https://YOUR-API-HOST
Waking it up (a sleeping server can take about a minute)...
  /health says: {'status': 'ok'}
Choose a password for pmdesk.demo@example.com:
Create the demo landlord, tenant and data on https://YOUR-API-HOST? Type YES: YES
Created landlord pmdesk.demo@example.com
Created tenant pmdesk.tenant@example.com
Signed in as the landlord
Created property Garden Court
  units 1A, 1B, 2A
  lease 1A: 12 payments, 5 marked paid
  lease 1B: 12 payments, 3 marked paid
Created property Palm Villa, developer plan, 3 instalments paid
Created property Marina Studio, bank loan at 15%, 4 instalments paid
Created the cashflow profile

Done. Sign in to PMDesk as pmdesk.demo@example.com.
```

If you see `CERTIFICATE_VERIFY_FAILED` on the Mac, the python.org build is missing its certificates. Either run `/Applications/Python 3.x/Install Certificates.command` once, or point Python at the certificates in the PM repo's virtual environment:

```text
SSL_CERT_FILE=$(~/PM/.venv/bin/python -m certifi) python3 tools/seed_demo.py ...
```

**What to understand**
- **Why seed through the API and not straight into the database:** the same validation, the same ownership rules, no database credentials, and it works against any copy of the server.
- **Why it refuses to run twice:** a seed that runs twice and creates duplicates is worse than one that stops. Registering the landlord is the guard: a `409` means the data already exists.
- **Interest-loan instalments can only change status.** That's why the script only marks them paid. The server refuses any other edit on a loan with interest (section a.2, 400).

**How to test**
- Sign in to the web app as the demo landlord. You should see Garden Court, Palm Villa and Marina Studio. In Garden Court, unit 1A's lease should have October marked late.
- Then run the curl tests in section b.5. All 5 should pass.

---

### g.2 Create the project

**What and why.** An empty VCL application, saved under the right names, in git, with the memory-leak report switched on from the first run.

**IDE actions**
1. **File > New > Windows VCL Application - Delphi.**
2. In the Object Inspector, with the form selected: **Name** = `frmMain`, **Caption** = `PMDesk`, **Position** = `poScreenCenter`, **Width** = `1200`, **Height** = `760`.
3. **File > Save All** (`Shift+Ctrl+S`):
   - The first dialog saves the unit: folder `C:\Dev\PMDesk`, file name `uMain.pas`.
   - The second saves the project: `PMDesk.dproj`.
4. In the **Projects** window, expand **Target Platforms**. **Windows 32-bit** must be the active one (shown in bold). If it isn't, right-click it and choose **Activate**.
5. **Project > View Source** opens `PMDesk.dpr`. Add the 4 lines marked below, directly after `begin`. Leave every other line the IDE wrote as it is.

```pascal
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
```

6. In `C:\Dev\PMDesk`, create **`.gitignore`** (in Notepad, save with the file type "All files"):

```text
Win32/
Win64/
__history/
__recovery/
*.local
*.identcache
*.dsk
*.stat
*.ini
!PMDesk.example.ini
```

7. In the same folder, create **`PMDesk.example.ini`**:

```ini
[Server]
BaseUrl=https://YOUR-API-HOST
ConnectTimeoutMs=15000
ResponseTimeoutMs=90000

[Client]
DeviceId=
LastEmail=
```

8. In a terminal in `C:\Dev\PMDesk`: `git init`, then `git add -A`, then `git commit -m "g.2 empty VCL project"`.

**What to understand**

| File | What it is |
|---|---|
| `.dpr` | The program itself: its `begin…end.` is what runs first. |
| `.dproj` | The build settings (an MSBuild file). |
| `.pas` | Your code. |
| `.dfm` | The form's layout, as text: every property you set in the Object Inspector. |
| `.res` | The app icon and version information. |
| `Win32\Debug\` | The build output, where `PMDesk.exe` appears. |

- `ReportMemoryLeaksOnShutdown` is a switch in Delphi's memory manager (FastMM). If anything you created is still allocated when the app exits, you get a dialog listing it.
- `{$IFDEF DEBUG}` keeps the leak report out of release builds.

**How to test:** press `F9`. An empty window titled PMDesk opens. Close it: no leak dialog appears.

---

### g.3 Configuration: `uConfig`

**What and why.** The server address and timeouts belong in an ini file, not in the code. Then the same exe can point at production, staging or `localhost` without being recompiled, and no address ends up in git.

**IDE actions**
1. **File > New > Unit - Delphi**, then **File > Save As** → `uConfig.pas`.
2. Replace **everything** in the new unit with the code below.
3. Switch to `uMain` (tab at the top of the editor). In the **interface** `uses` clause (the first `uses`, near the top), add `, uConfig` just before the `;` that ends it.
4. Replace the `private` section of `TfrmMain` (the lines between `private` and `public`) with the private section below.
5. Select the form: click an empty spot on it, or choose `frmMain` in the Object Inspector's dropdown. In the Object Inspector's **Events** tab, double-click **OnCreate**, then **OnDestroy**. The IDE creates two empty procedures; replace each with the complete version below.

**`uConfig.pas` (complete unit)**

```pascal
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
```

**`uMain`: the private section (replace it whole)**

```pascal
  private
    FConfig: TAppConfig;
```

**`uMain`: the two event procedures (complete)**

```pascal
procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FConfig := TAppConfig.Create;
  FConfig.Load;
  Caption := 'PMDesk - ' + FConfig.BaseUrl;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FConfig.Free;
end;
```

**What to understand**
- **`ParamStr(0)`** is the full path of the running exe, so `ChangeFileExt` turns `...\PMDesk.exe` into `...\PMDesk.ini`.
- **`TIniFile` works directly on the file.** Every read and write goes straight to disk, and the file is only created on the first write. That's why `FirstRun` is checked before anything is written.
- **The `try..finally` pattern:** `Ini` is created **before** `try`, and freed in `finally`, so it's freed even if a read raises an exception.
- **The form owns `FConfig`.** It creates it in `OnCreate` and frees it in `OnDestroy`: one owner, one place to free.

**How to test**
1. Press `F9`. The caption reads `PMDesk - https://YOUR-API-HOST`, and `Win32\Debug\PMDesk.ini` now exists with a `DeviceId`.
2. Close the app, set `BaseUrl` in that ini to the real server address, and press `F9` again. The caption shows the real address.
3. No leak dialog when you close.

---

### g.4 Shared units: errors, records, the async helper, the table helper

**What and why.** Four small units that everything else uses:

| Unit | What it holds | Code |
|---|---|---|
| `uApiErrors` | one error type for the whole app | section f.3 |
| `uAsync` | the background-thread helper | section e.3 |
| `uApiTypes` | the records the API returns | below |
| `uDataSets` | builds memtable fields in code | below |

**IDE actions.** For each of the four units, in this order:
1. **File > New > Unit - Delphi**.
2. **File > Save As** with the unit's name (`uApiErrors.pas`, `uAsync.pas`, `uApiTypes.pas`, `uDataSets.pas`).
3. Replace everything in the new unit with its code.

**`uApiTypes.pas` (complete unit)**

```pascal
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
```

**`uDataSets.pas` (complete unit)**

```pascal
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
```

**What to understand**
- **`uApiTypes` has no `uses` clause at all.** `string`, `Currency`, `TDate` and `TArray<T>` are all built into the language. A unit that depends on nothing can be used by any layer.
- **`TAsync.Run<T>` is generic.** One method works for any result type: `TPropertyArray`, `TUserRec`, `TLoanSchedule`… The compiler generates a version for each type you use it with.
- **Two field-type traps for an interview:**
  - `TWideStringField` vs `TStringField`: Unicode vs 8-bit text.
  - `TBCDField` vs `TCurrencyField`: exact decimal vs `Double`.
- **The memtable owns its fields** (`Create(DS)` makes it the owner), so you never free a field yourself.

**How to test:** **Project > Compile PMDesk** (`Ctrl+F9`) finishes with no errors. **Project > View Source** shows all four new units in the `.dpr`'s `uses` list (the IDE adds them for you).

---

### g.5 The API unit (health, login, me, properties) + a smoke test

**What and why.** `TPropertyApi` is the only place that knows about HTTP and JSON (section d.2). Today it gets the plumbing (sending a request, checking the answer, following pages), the first four endpoints, and the JSON helpers. A temporary button proves it works. It runs **on the UI thread on purpose**, so you can feel the freeze that g.7 removes.

**IDE actions**
1. **File > New > Unit - Delphi**, then **File > Save As** → `uPropertyApi.pas`, and replace everything with the code below.
2. In `uMain`'s **interface** `uses` clause, add `, uApiTypes, uApiErrors, uPropertyApi` just before the `;` (after the `uConfig` you added in g.3).
3. Replace `TfrmMain`'s `private` section, `FormCreate` and `FormDestroy` with the versions below.
4. From the Tool Palette (**Standard** category), drop a **TButton** on the form. Set **Name** = `btnTest`, **Caption** = `Test API`, **Left** = `8`, **Top** = `8`. Then double-click it and replace the empty `btnTestClick` with the version below.

**`uPropertyApi.pas` (complete unit, Saturday version)**

```pascal
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
```

**`uMain`: the private section (replace it whole)**

```pascal
  private
    FConfig: TAppConfig;
    FApi: TPropertyApi;
```

**`uMain`: `FormCreate`, `FormDestroy`, `btnTestClick` (complete)**

```pascal
procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FConfig := TAppConfig.Create;
  FConfig.Load;
  FApi := TPropertyApi.Create(FConfig.BaseUrl, FConfig.ConnectTimeoutMs,
    FConfig.ResponseTimeoutMs);
  Caption := 'PMDesk - ' + FConfig.BaseUrl;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FApi.Free;
  FConfig.Free;
end;

procedure TfrmMain.btnTestClick(Sender: TObject);
begin
  // TEMPORARY: removed in g.7. It runs on the UI thread on purpose: while it
  // waits, try to drag the window. You can't. TAsync fixes that in g.7.
  try
    FApi.CheckHealth;
    ShowMessage('Server is up: ' + FConfig.BaseUrl);
    FApi.GetProperties;                // not signed in yet: must fail with 401
    ShowMessage('Unexpected: properties loaded without signing in');
  except
    on E: EApiError do
      ShowMessage(Format('EApiError, HTTP %d: %s', [E.StatusCode, E.Message]));
  end;
end;
```

**What to understand**
- **`Send` is the single exit to the network.** Headers, UTF-8, error mapping and status checks are written once. Every endpoint is a few lines on top of it.
- **One `THTTPClient` per call**, created and freed inside `Send`. Nothing is shared between threads, so there's nothing to lock (section e.1, rule 7).
- **`ENetException` is not `EApiError`.** It means no HTTP answer arrived at all, so it's mapped to `aekNetwork`. A 4xx or 5xx *is* an answer: THTTPClient doesn't raise for it, and `CheckResponse` decides.
- **`ContentAsString(TEncoding.UTF8)`:** without the explicit encoding, the body could be decoded as ANSI, because the server's `Content-Type` names no charset.
- **The login form is encoded by hand (`FormEncode`)**, so a password containing `&`, `+` or `=` can't break the form body.
- **`ForEachItem` hides paging.** Forms always get the full list, however many pages the server needed.
- **Captured variables:** `GetProperties` collects into a local `Items`, not into `Result`. Delphi doesn't allow an anonymous method to capture `Result`.

**How to test**
1. Press `F9` and click **Test API**. You should see "Server is up", then `EApiError, HTTP 401: Not authenticated` (FastAPI's answer when no token is sent). This proves the request, the error parsing and the error mapping all work.
2. Click it again after the server has been idle for a while: the window freezes until the answer comes. Remember that feeling.
3. Set `BaseUrl=https://localhost:1` in the ini and press `F9`: you get `HTTP 0` with a connection error. That's the network path. Set the real address back afterwards.

---

### g.6 Login form

**What and why.** A modal dialog that signs in **in the background** and refuses accounts that aren't landlords. It makes two requests in a chain: login, then "who am I?". It stores the token on the main thread between them (section e.1, rule 8).

**IDE actions**
1. **File > New > VCL Form - Delphi**. In the Object Inspector: **Name** = `frmLogin`. Then **File > Save As** → `uLogin.pas`.
2. Set the form's properties: **Caption** = `PMDesk - Sign in`, **BorderStyle** = `bsDialog`, **Position** = `poMainFormCenter`, **ClientWidth** = `420`, **ClientHeight** = `210`.
3. Drop these components from the **Standard** category. Drop each one fresh; never copy and paste. Set **Name** first.

| Type | Name | Properties |
|---|---|---|
| TLabel | `lblServerCaption` | Caption `Server`, Left 16, Top 20 |
| TLabel | `lblServer` | Caption `-`, Left 96, Top 20 |
| TLabel | `lblEmail` | Caption `Email`, Left 16, Top 56 |
| TEdit | `edtEmail` | Left 96, Top 52, Width 300, Text *(empty it)* |
| TLabel | `lblPassword` | Caption `Password`, Left 16, Top 92 |
| TEdit | `edtPassword` | Left 96, Top 88, Width 300, Text *(empty)*, **PasswordChar** `*` |
| TLabel | `lblStatus` | Caption *(empty)*, Left 16, Top 124, **AutoSize** False, Width 388, Height 36, **WordWrap** True |
| TButton | `btnSignIn` | Caption `Sign in`, Left 232, Top 168, Width 80, **Default** True |
| TButton | `btnCancel` | Caption `Cancel`, Left 320, Top 168, Width 80, **Cancel** True, **ModalResult** `mrCancel` |

4. **Events:** double-click `btnSignIn` (this creates `btnSignInClick`). Then select the form, open the **Events** tab, and double-click **OnCloseQuery**.
5. **Stop the IDE from auto-creating this form.** **Project > View Source**, then delete the line `Application.CreateForm(TfrmLogin, frmLogin);`. `TfrmLogin.Execute` creates the dialog when it's needed and frees it afterwards.
6. In `uLogin`, add `, uApiTypes, uApiErrors, uConfig, uPropertyApi` before the `;` of the **interface** `uses` clause.
7. With `uLogin` open, choose **File > Use Unit…** (`Alt+F11`), pick `uAsync`, and choose **Implementation**. The IDE adds `uses uAsync;` right after `{$R *.dfm}`.
8. Replace the `private` and `public` sections of `TfrmLogin` with the ones below, then replace or add the procedures.
9. In `uMain`, also with **File > Use Unit…** → `uLogin` → **Implementation**. Then replace the `private` section, and add a **FormShow** event (form, **Events** tab, double-click **OnShow**) and the `SignIn` procedure below.

**`uLogin`: the private and public sections (replace both)**

```pascal
  private
    FApi: TPropertyApi;
    FConfig: TAppConfig;
    FUser: TUserRec;
    FBusy: Boolean;
    procedure SetBusy(Busy: Boolean);
    procedure ShowError(const Err: TApiErrorInfo);
    procedure LoadAccount;
  public
    // Shows the dialog. True = signed in as a landlord; User says who.
    class function Execute(AApi: TPropertyApi; AConfig: TAppConfig;
      out User: TUserRec): Boolean;
```

**`uLogin`: procedures.** These go in the implementation section, after the `uses uAsync;` line. Two of them are the empty handlers the IDE created (`btnSignInClick`, `FormCloseQuery`): replace those. Add the rest anywhere between `implementation` and the final `end.`.

```pascal
class function TfrmLogin.Execute(AApi: TPropertyApi; AConfig: TAppConfig;
  out User: TUserRec): Boolean;
var
  Form: TfrmLogin;
begin
  Form := TfrmLogin.Create(nil);       // we own it: no auto-create, no owner
  try
    Form.FApi := AApi;
    Form.FConfig := AConfig;
    Form.lblServer.Caption := AConfig.BaseUrl;
    Form.edtEmail.Text := AConfig.LastEmail;
    if Form.edtEmail.Text <> '' then
      Form.ActiveControl := Form.edtPassword;
    Result := Form.ShowModal = mrOk;
    if Result then
      User := Form.FUser;
  finally
    Form.Free;
  end;
end;

procedure TfrmLogin.SetBusy(Busy: Boolean);
begin
  FBusy := Busy;
  edtEmail.Enabled := not Busy;
  edtPassword.Enabled := not Busy;
  btnSignIn.Enabled := not Busy;
  btnCancel.Enabled := not Busy;
end;

procedure TfrmLogin.ShowError(const Err: TApiErrorInfo);
begin
  if Err.Kind = aekUnauthorized then
    lblStatus.Caption := Err.Message   // at login, 401 = wrong email or password
  else
    lblStatus.Caption := Err.UserText;
end;

procedure TfrmLogin.btnSignInClick(Sender: TObject);
var
  Email, Password: string;
begin
  // read the controls here, on the UI thread; the worker gets copies (rule 2)
  Email := Trim(edtEmail.Text);
  Password := edtPassword.Text;
  if (Email = '') or (Password = '') then
  begin
    lblStatus.Caption := 'Enter your email and password.';
    Exit;
  end;

  FApi.ClearTokens;
  SetBusy(True);
  lblStatus.Caption := 'Signing in... (a sleeping server can take up to a minute)';
  TAsync.Run<TTokenPair>(
    function: TTokenPair
    begin
      Result := FApi.Login(Email, Password);   // worker thread
    end,
    procedure(Pair: TTokenPair)
    begin
      FApi.SetTokens(Pair);                    // main thread only (rule 8)
      LoadAccount;                             // second request: who am I?
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False);
      ShowError(Err);
    end);
end;

procedure TfrmLogin.LoadAccount;
begin
  TAsync.Run<TUserRec>(
    function: TUserRec
    begin
      Result := FApi.GetMe;
    end,
    procedure(User: TUserRec)
    begin
      SetBusy(False);
      if User.Role <> 'landlord' then
      begin
        FApi.ClearTokens;
        lblStatus.Caption := 'PMDesk is for landlord accounts. This one is a '
          + User.Role + ' account.';
        Exit;
      end;
      FUser := User;
      FConfig.LastEmail := User.Email;
      FConfig.SaveLastEmail;
      ModalResult := mrOk;                     // closes the dialog
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False);
      FApi.ClearTokens;
      ShowError(Err);
    end);
end;

procedure TfrmLogin.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Closing while a request runs would free this form before its reply
  // arrives, and the reply would then write to a dead form (PLAN e.5).
  CanClose := not FBusy;
end;
```

**`uMain`: the private section (replace it whole)**

```pascal
  private
    FConfig: TAppConfig;
    FApi: TPropertyApi;
    FUser: TUserRec;
    procedure SignIn;
```

**`uMain`: `FormShow` (the handler the IDE created) and `SignIn` (new, add it after `FormShow`)**

```pascal
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
    Caption := 'PMDesk - ' + FUser.FullName
  else
    Close;
end;
```

**What to understand**
- **`Execute` is a class function.** It creates the dialog, shows it, reads the result and frees it, all in one place. Callers can't forget to free the form.
- **Two requests in a chain.** The first callback stores the tokens on the main thread, then starts the second request. It's async without blocking and without a shared variable.
- **`ModalResult := mrOk` closes a modal form.** `ShowModal` then returns `mrOk`.
- **`OnCloseQuery` stops the window closing while a request is running.** Otherwise the form could be freed before its reply arrives.
- **The landlord check here is only for the user's benefit; security lives on the server.** A tenant who skipped this check would still get `403` on every call.

**How to test**
1. Press `F9`. The main window appears, then the login dialog on top of it.
2. Click **Sign in** with empty boxes: "Enter your email and password."
3. Try a wrong password: "Incorrect email or password", in the server's words.
4. Sign in with the right password: the dialog closes and the caption shows "PMDesk - Demo Landlord". Close the app and restart: the email is filled in already.
5. Click **Cancel**: the app closes, with no leak dialog.
6. Optional: try to close the dialog while "Signing in…" is showing. It refuses.

---

### g.7 Properties grid, loaded in the background

**What and why.** The first real screen: the landlord's properties in a grid, loaded by `TAsync` so the window stays responsive. The temporary test button from g.5 goes away.

**IDE actions**
1. **Remove `btnTest`.** Select it and press `Delete`. The IDE deletes the button, but **not** its handler, because the handler contains code. Delete the procedure `TfrmMain.btnTestClick` from the implementation section yourself. (The private section you paste in step 5 below doesn't mention it.)
2. Drop these components, **Name first**:

| Type (Tool Palette category) | Name | Properties |
|---|---|---|
| TPanel (Standard) | `pnlTop` | **Align** alTop, Height 41, BevelOuter bvNone, Caption *(empty it)* |
| TButton, dropped **onto** `pnlTop` | `btnRefresh` | Caption `Refresh`, Left 8, Top 8 |
| TButton, onto `pnlTop` | `btnSignOut` | Caption `Sign out`, Left 96, Top 8 |
| TLabel, onto `pnlTop` | `lblUser` | Caption `Not signed in`, Left 190, Top 12 |
| TStatusBar (Win32) | `StatusBar1` | **SimplePanel** True (it docks to the bottom by itself) |
| TPanel (Standard) | `pnlProperties` | **Align** alLeft, Width 420, BevelOuter bvNone, Caption *(empty)* |
| TDBGrid (Data Controls), dropped **onto** `pnlProperties` | `grdProperties` | **Align** alClient, **ReadOnly** True. Under **Options**, expand with `+` and set `dgRowSelect` True and `dgAlwaysShowSelection` True |
| TFDMemTable (FireDAC) | `mtProperties` | nothing to set: its fields are created in code |
| TDataSource (Data Access) | `dsProperties` | **DataSet** `mtProperties` |

   Then set `grdProperties.DataSource` to `dsProperties`.
3. **Events:** double-click `btnRefresh` and `btnSignOut`. On the form's **Events** tab, double-click **OnCloseQuery**.
4. **File > Use Unit…** → add `uAsync` and `uDataSets` to the **Implementation** uses. `uLogin` is already there.
5. Replace the `private` section, `FormCreate` and `SignIn` with the versions below, and add the other procedures.

**`uMain`: the private section (replace it whole)**

```pascal
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
```

**`uMain`: a small helper function.** Paste it in the implementation section, directly below the `uses …;` line that follows `{$R *.dfm}`, and above the first procedure:

```pascal
// 'under_construction' -> 'under construction', for display only
function Pretty(const S: string): string;
begin
  Result := StringReplace(S, '_', ' ', [rfReplaceAll]);
end;
```

**`uMain`: procedures (complete).** `FormCreate` and `SignIn` replace the existing ones. `btnRefreshClick`, `btnSignOutClick` and `FormCloseQuery` replace the empty handlers. The rest are new.

```pascal
procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FConfig := TAppConfig.Create;
  FConfig.Load;
  FApi := TPropertyApi.Create(FConfig.BaseUrl, FConfig.ConnectTimeoutMs,
    FConfig.ResponseTimeoutMs);
  Caption := 'PMDesk - ' + FConfig.BaseUrl;
  DefinePropertiesTable;
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
  mtProperties.DisableControls;            // one repaint at the end, not one per row
  try
    mtProperties.EmptyDataSet;
    for P in Items do
    begin
      mtProperties.Append;
      mtProperties.FieldByName('Id').AsString := P.Id;
      mtProperties.FieldByName('Name').AsString := P.Name;
      mtProperties.FieldByName('PropType').AsString := Pretty(P.PropertyType);
      mtProperties.FieldByName('Status').AsString := Pretty(P.Status);
      if P.DeliveryDate <> 0 then          // left alone = NULL = empty cell
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
end;

procedure TfrmMain.btnRefreshClick(Sender: TObject);
begin
  LoadProperties;
end;

procedure TfrmMain.btnSignOutClick(Sender: TObject);
begin
  FApi.ClearTokens;                         // forgotten: nothing was ever saved
  mtProperties.EmptyDataSet;
  lblUser.Caption := 'Not signed in';
  SignIn;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FPending = 0;                 // PLAN e.1, rule 6
  if not CanClose then
    StatusBar1.SimpleText := 'Still waiting for the server - try again in a moment.';
end;
```

**What to understand**
- **The pattern from section e:** `LoadProperties` returns at once. The worker only calls `FApi`. The grid is filled in the success callback, on the main thread.
- **`FPending` counts running requests.** It drives the status text, disables Refresh and Sign out, and blocks closing.
- **`DisableControls` / `EnableControls`** stop the grid repainting on every `Append` and `Post`. `try..finally` makes sure the controls are switched back on even if filling fails.
- **NULL vs 0:** a field you don't assign after `Append` stays NULL, so the grid shows an empty cell instead of 30.12.1899.
- **Hidden fields** (`Id`, `IsOwner`, `IsArchived`) travel with each row for the code, and the grid doesn't show them. Sunday uses them.

**How to test**
1. Press `F9` and sign in: "Loading properties…", then 3 properties. Palm Villa shows "under construction" with its delivery date in your Windows date format.
2. **The responsiveness test:** after the server has been idle, sign in and drag the window around while it's loading. It moves. In g.5 it froze.
3. Click **Refresh**: it reloads, and the button is disabled while it does.
4. Click **Sign out**: the grid empties and the login dialog appears again.
5. **Error path:** set `ResponseTimeoutMs=1` in the ini and restart. Loading fails at once with the "Cannot reach the server" message. Set it back to `90000`.
6. Close the app: no leak dialog. Commit: `git commit -am "g.7 properties grid"`.

---

### g.8 Sunday layout: tabs and grids (no code)

**What and why.** The right-hand side of the window: a tab for the units → leases → payments drill-down and a tab for loans, with an empty grid for each. Building the layout first means each later step only adds behaviour.

**IDE actions.** Name every component first, drop every component fresh (never copy and paste), and give **every TDBGrid** these settings: **Align** alClient, **ReadOnly** True, **Options** `dgRowSelect` and `dgAlwaysShowSelection` set to True.

1. **TSplitter** (Additional category) `splLeft`: **Align** alLeft. It must sit to the *right* of `pnlProperties`. If it lands at the far left edge of the form, set its **Left** to `430`.
2. **TPageControl** (Win32) `pgcMain`: **Align** alClient.
3. Right-click `pgcMain` and choose **New Page**. Click inside the new page and set **Name** `tsUnits`, **Caption** `Units and leases`. Repeat **New Page** for **Name** `tsLoans`, **Caption** `Loans`.
4. Click the **Units and leases** tab, then drop onto that page:

| Component | Name | Properties |
|---|---|---|
| TGroupBox | `gbUnits` | **Align** alTop, Height 170, Caption `Units` |
| TDBGrid, **inside** `gbUnits` | `grdUnits` | grid settings |
| TGroupBox | `gbLeases` | **Align** alTop, Height 140, Caption `Leases`. If it lands above Units, set **Top** to `300`. |
| TDBGrid, inside `gbLeases` | `grdLeases` | grid settings |
| TGroupBox | `gbPayments` | **Align** alClient, Caption `Payments` |
| TPanel, inside `gbPayments` | `pnlPaymentActions` | **Align** alBottom, Height 41, BevelOuter bvNone, Caption *(empty)* |
| TButton, on that panel | `btnMarkPaid` | Caption `Mark paid`, Left 8, Top 8, Width 100, **Enabled** False |
| TButton, on that panel (a fresh one) | `btnMarkUnpaid` | Caption `Mark unpaid`, Left 116, Top 8, Width 100, **Enabled** False |
| TLabel, on that panel | `lblTotals` | Caption *(empty)*, Left 232, Top 12 |
| TDBGrid, inside `gbPayments` (click the empty area above the panel) | `grdPayments` | grid settings |

5. Click the **Loans** tab, then drop onto it:

| Component | Name | Properties |
|---|---|---|
| TGroupBox | `gbLoans` | **Align** alTop, Height 150, Caption `Loans` |
| TDBGrid, inside `gbLoans` | `grdLoans` | grid settings |
| TGroupBox | `gbSchedule` | **Align** alClient, Caption `Schedule` |
| TPanel, inside `gbSchedule` | `pnlScheduleSummary` | **Align** alBottom, Height 33, BevelOuter bvNone, Caption *(empty)* |
| TLabel, on that panel | `lblSchedule` | Caption *(empty)*, Left 8, Top 8 |
| TDBGrid, inside `gbSchedule` | `grdSchedule` | grid settings |

6. Drop five **TFDMemTable** + **TDataSource** pairs anywhere on the form: `mtUnits`/`dsUnits`, `mtLeases`/`dsLeases`, `mtPayments`/`dsPayments`, `mtLoans`/`dsLoans`, `mtSchedule`/`dsSchedule`. Set each TDataSource's **DataSet** to its memtable, then each grid's **DataSource**: `grdUnits` → `dsUnits`, `grdLeases` → `dsLeases`, and so on.
7. Set `pgcMain.ActivePage` to `tsUnits`.

**What to understand**
- **`Align` does the layout.** Controls with alTop stack from the top, in the order they were aligned, and alClient takes whatever space is left. Resizing the window moves nothing by hand.
- **A TSplitter resizes the control it sits next to**, which is why its position relative to `pnlProperties` matters.
- **Grids are views, datasets hold the data:** grid → data source → memtable. Swapping the dataset behind a grid needs no grid code.

**How to test:** press `F9` and sign in. Properties load as before, the right side shows empty group boxes, the splitter drags, and the tabs switch. Commit.

---

### g.9 Units: the first drill-down

**What and why.** Clicking a property, or moving to it with the arrow keys, loads its units in the background. Every detail table also gets its fields now, so `FormCreate` doesn't need to change again. A "Changed" procedure clears everything below a level before it loads; that pattern repeats at every level.

**`uPropertyApi`: three additions.** Each goes at one of the `>>> Sunday` marker lines you pasted on Saturday.

*Declaration.* Above `// >>> Sunday: new endpoint declarations go above this line`:

```pascal
    function GetUnits(const PropertyId: string): TUnitArray;
```

*Parser.* Above `// >>> Sunday: new parser functions go above the TPropertyApi line below`:

```pascal
function ParseUnit(O: TJSONObject): TUnitRec;
begin
  Result.Id := JStr(O, 'id');
  Result.UnitNumber := JStr(O, 'unit_number');
  Result.Bedrooms := JInt(O, 'bedrooms');
  Result.Bathrooms := JFloat(O, 'bathrooms');
  Result.IsOccupied := JBool(O, 'is_occupied');
end;
```

*Method.* Above `// >>> Sunday: new endpoint methods go above "initialization"`:

```pascal
function TPropertyApi.GetUnits(const PropertyId: string): TUnitArray;
var
  Items: TUnitArray;
begin
  Items := nil;
  ForEachItem('/v1/units?property_id=' + PropertyId,
    procedure(O: TJSONObject)
    begin
      Items := Items + [ParseUnit(O)];
    end);
  Result := Items;
end;
```

**`uMain`: IDE actions**
1. Add these lines at the end of the `private` section, just above the line `public`:

```pascal
    procedure DefineDetailTables;
    function SelectedId(DS: TFDMemTable): string;
    procedure ClearTable(DS: TFDMemTable);
    procedure PropertyChanged;
    procedure LoadUnits(const PropertyId: string);
    procedure FillUnits(const Items: TUnitArray);
    procedure UnitChanged;
```

2. **Events on datasets:** select `mtProperties` (click its icon on the form), open the **Events** tab and double-click **AfterScroll**. Do the same for `mtUnits`.
3. Replace `FormCreate`, `FillProperties` and `btnSignOutClick` with the versions below, fill the two AfterScroll handlers, and add the new procedures.

**`uMain`: procedures (complete)**

```pascal
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

procedure TfrmMain.mtPropertiesAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
    PropertyChanged;
end;

procedure TfrmMain.PropertyChanged;
var
  PropertyId: string;
begin
  ClearTable(mtUnits);
  UnitChanged;                       // empties everything below units too
  PropertyId := SelectedId(mtProperties);
  if PropertyId <> '' then
    LoadUnits(PropertyId);
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

procedure TfrmMain.mtUnitsAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
    UnitChanged;
end;

procedure TfrmMain.UnitChanged;
begin
  ClearTable(mtLeases);
  ClearTable(mtPayments);
  // g.10 loads the selected unit's leases here
end;

procedure TfrmMain.btnSignOutClick(Sender: TObject);
begin
  FApi.ClearTokens;
  ClearTable(mtProperties);
  PropertyChanged;                   // empties every detail table
  lblUser.Caption := 'Not signed in';
  SignIn;
end;
```

**What to understand**
- **`AfterScroll` fires whenever the current row changes:** a click, an arrow key, but also every `Append`, `Post` and `EmptyDataSet`. `DisableControls` stops the grid repainting; it does **not** stop dataset events. Hence `FFilling`, and `ClearTable` remembering its previous value.
- **A cascade of "Changed" procedures:** `PropertyChanged` clears units and calls `UnitChanged`, which will clear leases and call `LeaseChanged`, and so on. Each level only knows the level below it.
- **The stale-reply guard** (`SelectedId(mtProperties) = PropertyId`) is rule 9 from section e, in its simplest form: the answer is only used if it's still about the row the user is on.

**How to test**
- Click Garden Court: 1A, 1B, 2A. Palm Villa and Marina Studio: one unit each, numbered `1`.
- Use the arrow keys in the properties grid: the units follow.
- Click quickly across all three properties: the units always match the property finally selected.
- Commit.

---

### g.10 Leases, with tenant names

**What and why.** Clicking a unit loads its leases. A lease only carries `tenant_id`, so the API unit looks up each tenant's name and returns finished records. The form never knows two calls were made.

**`uPropertyApi`: three additions, at the same markers as before**

*Declarations:*

```pascal
    function GetTenantName(const TenantId: string): string;
    function GetLeases(const UnitId: string): TLeaseArray;
```

*Parser:*

```pascal
function ParseLease(O: TJSONObject): TLeaseRec;
begin
  Result.Id := JStr(O, 'id');
  Result.TenantId := JStr(O, 'tenant_id');
  Result.TenantName := '';           // filled in by GetLeases
  Result.StartDate := JDate(O, 'start_date');
  Result.EndDate := JDate(O, 'end_date');
  Result.RentAmount := JCurr(O, 'rent_amount');
  Result.CurrencyCode := JStr(O, 'currency');
  Result.Status := JStr(O, 'status');
end;
```

*Methods:*

```pascal
function TPropertyApi.GetTenantName(const TenantId: string): string;
var
  Root: TJSONObject;
begin
  Root := nil;
  try
    Root := ParseObject(Send('GET', '/v1/users/lookup?user_id=' + TenantId));
  except
    on E: EApiError do
      if E.Kind = aekNotFound then
        Exit('(unknown tenant)')      // a name we cannot show is not an error
      else
        raise;                        // anything else: pass it on unchanged
  end;
  try
    Result := JStr(Root, 'full_name');
  finally
    Root.Free;
  end;
end;

// A unit's leases, each with its tenant's name: one extra call per lease,
// composed here so the form gets finished records (PLAN a.4, call 8).
function TPropertyApi.GetLeases(const UnitId: string): TLeaseArray;
var
  Items: TLeaseArray;
  I: Integer;
begin
  Items := nil;
  ForEachItem('/v1/leases?unit_id=' + UnitId,
    procedure(O: TJSONObject)
    begin
      Items := Items + [ParseLease(O)];
    end);
  for I := 0 to High(Items) do
    Items[I].TenantName := GetTenantName(Items[I].TenantId);
  Result := Items;
end;
```

**`uMain`: IDE actions**
1. Add these lines just above `public`:

```pascal
    procedure LoadLeases(const UnitId: string);
    procedure FillLeases(const Items: TLeaseArray);
    procedure LeaseChanged;
```

2. Select `mtLeases`, open **Events**, and double-click **AfterScroll**.
3. Replace `UnitChanged`, and add the rest.

**`uMain`: procedures (complete)**

```pascal
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

procedure TfrmMain.mtLeasesAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
    LeaseChanged;
end;

procedure TfrmMain.LeaseChanged;
begin
  ClearTable(mtPayments);
  // g.11 loads the selected lease's payments here
end;
```

**What to understand**
- **Where to combine calls:** in the API layer. The form asked for "leases", and composing two endpoints into one answer belongs below the line where HTTP lives.
- **Translating one error into a value:** a 404 on the name lookup becomes `'(unknown tenant)'`. Every other error is re-raised with a bare `raise;`, unchanged.
- **The N+1 trade-off:** one lookup per lease is fine for 2 leases and bad for 2,000. Section h proposes a backend change for later.

**How to test**
- Garden Court, unit 1A: one lease, **Demo Tenant**, From 01.05.2026, To 30.04.2027, Rent 18.000,00 (on a German-format Windows: separators follow your Windows region), EGP, active.
- 1B: open-ended (the To cell is empty), 12.500,00.
- 2A, and Palm Villa's unit: no leases.
- Commit.

---

### g.11 Payments and totals

**What and why.** Clicking a lease loads its payments, plus the server's totals (collected and outstanding) taken from `amount_totals`. The client doesn't add up the grid, because the server's totals cover every row (section a.4, call 9).

**`uPropertyApi`: three additions**

*Declaration:*

```pascal
    function GetPayments(const LeaseId: string): TPaymentList;
```

*Parser:*

```pascal
function ParsePayment(O: TJSONObject): TPaymentRec;
begin
  Result.Id := JStr(O, 'id');
  Result.Amount := JCurr(O, 'amount');
  Result.DueDate := JDate(O, 'due_date');
  Result.PaidDate := JDate(O, 'paid_date');
  Result.Status := JStr(O, 'status');
  Result.Method := JStr(O, 'method');
end;
```

*Method:*

```pascal
function TPropertyApi.GetPayments(const LeaseId: string): TPaymentList;
var
  List: TPaymentList;
begin
  List.Items := nil;
  List.Collected := 0;
  List.Outstanding := 0;
  ForEachItem('/v1/payments?lease_id=' + LeaseId,
    procedure(O: TJSONObject)
    begin
      List.Items := List.Items + [ParsePayment(O)];
    end,
    procedure(Page: TJSONObject)
    var
      Totals: TJSONValue;
    begin
      // the server's totals cover every matching row, not just this page
      Totals := JValue(Page, 'amount_totals');
      if Totals is TJSONObject then
      begin
        List.Collected := JCurr(TJSONObject(Totals), 'collected');
        List.Outstanding := JCurr(TJSONObject(Totals), 'outstanding');
      end;
    end);
  Result := List;
end;
```

**`uMain`: IDE actions**
1. Add these lines just above `public`:

```pascal
    procedure LoadPayments(const LeaseId: string; const SelectId: string = '');
    procedure FillPayments(const List: TPaymentList; const SelectId: string);
    procedure UpdatePaymentButtons;
```

2. Select `mtPayments`, open **Events**, and double-click **AfterScroll**.
3. Replace `LeaseChanged`, and add the rest.

**`uMain`: procedures (complete)**

```pascal
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

procedure TfrmMain.mtPaymentsAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
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
```

**What to understand**
- **Two callbacks on one request:** `Each` gets every item, and `OnPage` gets each page's top-level object, which is where the totals are.
- **`FormatCurr` with no settings argument uses Windows' region:** `90.000,00` in Austria. Parsing used `ApiFormat`; displaying uses the user's settings (section d.7).
- **`Locate`** finds a row by field value. After a reload it puts the cursor back where the user was.
- **The buttons light up now but do nothing until g.13.** That's expected.

**How to test**
- Lease 1A: 12 payments, May–Sep **paid**, October **late**, the rest pending. The totals read Collected 90.000,00, Outstanding 126.000,00.
- Lease 1B: Collected 37.500,00, Outstanding 112.500,00.
- Moving between paid and unpaid rows flips which button is enabled.
- Commit.

---

### g.12 Error handling: expired token → sign in again; network errors

**What and why.** A 401 in the middle of a session means the token expired (60 minutes, section a.1). PMDesk then signs in again and reloads, instead of failing. Several requests often fail at the same moment (for example units and loans together), so only one dialog may open at a time.

**IDE actions**
1. In `uMain`'s private section, add this field directly **below the line `FFilling: Boolean;`**. Fields must come before the method declarations; Delphi refuses a field after a method in the same section.

```pascal
    FShowingError: Boolean; // a dialog is open: later errors only reach the status bar
```

2. Replace `HandleApiError` with the version below.
3. **Temporary test tools:**
   - In `uPropertyApi`, add `procedure BreakTokenForTesting;` at the declaration marker, and the method below at the method marker.
   - In `uMain`, drop a fresh TButton onto `pnlTop`: **Name** `btnBreakToken`, Caption `Break token`, Left 700, Top 8. Double-click it.

**`uMain`: `HandleApiError` (complete, replaces Saturday's)**

```pascal
procedure TfrmMain.HandleApiError(const Err: TApiErrorInfo);
begin
  StatusBar1.SimpleText := Err.UserText.Replace(sLineBreak, ' ');
  // Several requests can fail at once (units and loans, say). One dialog is
  // enough: while it is open, later errors only update the status bar.
  if FShowingError then
    Exit;
  FShowingError := True;
  try
    if Err.Kind = aekUnauthorized then
    begin
      FApi.ClearTokens;
      MessageDlg(Err.UserText, mtInformation, [mbOK], 0);
      SignIn;                        // the login dialog again; success reloads all
    end
    else
      MessageDlg(Err.UserText, mtError, [mbOK], 0);
  finally
    FShowingError := False;
  end;
end;
```

**Temporary: `uPropertyApi` method and `uMain` handler (both removed after testing)**

```pascal
procedure TPropertyApi.BreakTokenForTesting;
begin
  FAccessToken := 'expired-on-purpose';   // the next request will get 401
end;
```

```pascal
procedure TfrmMain.btnBreakTokenClick(Sender: TObject);
begin
  FApi.BreakTokenForTesting;              // TEMPORARY (g.12)
  StatusBar1.SimpleText := 'Token broken: click any property';
end;
```

**What to understand**
- **One place decides what errors look like.** Every callback passes errors to `HandleApiError`, which owns the dialogs, the re-login and the status bar.
- **Dialogs and queued replies:** a modal dialog still processes queued replies while it's open (`ShowModal` runs a message loop). That's why the `FShowingError` guard is needed: without it, a second 401 arriving during the first dialog would open a second login.
- **The web and iOS clients go further:** they refresh the token silently and retry the request. Bonus B3 adds the silent refresh to PMDesk.

**How to test**
1. **Expired token:** click **Break token**, then click another property. You get "Your session has expired", then the login dialog. Sign in and everything reloads.
2. **Offline:** turn Wi-Fi off and click **Refresh**. You get "Cannot reach the server…" with Windows' reason underneath. Turn Wi-Fi on, click Refresh, and it works.
3. **Several failures at once:** with Wi-Fi off, click a property. You get one dialog, and the status bar shows the rest.
4. Remove the test tools: delete `btnBreakToken` (and its handler procedure and declaration, as in g.7). In `uPropertyApi`, delete `BreakTokenForTesting`, both its declaration and its method. Then commit.

---

### g.13 Mark paid / Mark unpaid

**What and why.** PMDesk's one write: it records a payment as received today, or undoes that. It asks before writing money, disables the buttons while saving, and reloads from the server afterwards, so the "late" rule and the totals stay the server's.

**`uPropertyApi`: two additions**

*Declaration:*

```pascal
    function SetPaymentPaid(const PaymentId: string; Paid: Boolean;
      PaidOn: TDate): TPaymentRec;
```

*Method:*

```pascal
function TPropertyApi.SetPaymentPaid(const PaymentId: string; Paid: Boolean;
  PaidOn: TDate): TPaymentRec;
var
  Body, Root: TJSONObject;
  Json: string;
begin
  // build JSON with TJSONObject, never by gluing strings: it escapes for us
  Body := TJSONObject.Create;
  try
    if Paid then
    begin
      Body.AddPair('status', 'paid');
      // the server does not fill paid_date for payments: send it (PLAN a.4, call 10)
      Body.AddPair('paid_date', FormatDateTime('yyyy-mm-dd', PaidOn));
      Body.AddPair('method', 'manual');
    end
    else
    begin
      Body.AddPair('status', 'pending');
      Body.AddPair('paid_date', TJSONNull.Create);   // Body owns it and frees it
    end;
    Json := Body.ToJSON;
  finally
    Body.Free;
  end;

  Root := ParseObject(Send('PATCH', '/v1/payments/' + PaymentId,
    'application/json', Json));
  try
    Result := ParsePayment(Root);
  finally
    Root.Free;
  end;
end;
```

**`uMain`: IDE actions**
1. Add `procedure ChangePayment(Paid: Boolean);` just above `public`.
2. Double-click `btnMarkPaid`, then `btnMarkUnpaid`. Each is its own button, dropped fresh in g.8, so each gets its own handler.

**`uMain`: procedures (complete)**

```pascal
procedure TfrmMain.btnMarkPaidClick(Sender: TObject);
begin
  ChangePayment(True);
end;

procedure TfrmMain.btnMarkUnpaidClick(Sender: TObject);
begin
  ChangePayment(False);
end;

procedure TfrmMain.ChangePayment(Paid: Boolean);
var
  PaymentId, LeaseId, Question: string;
  PaidOn: TDate;
begin
  PaymentId := SelectedId(mtPayments);
  LeaseId := SelectedId(mtLeases);
  if (PaymentId = '') or (LeaseId = '') then
    Exit;

  if Paid then
    Question := 'Record the payment due %s (%s) as paid today?'
  else
    Question := 'Mark the payment due %s (%s) as not paid?';
  if MessageDlg(Format(Question, [mtPayments.FieldByName('DueDate').AsString,
    mtPayments.FieldByName('Amount').DisplayText]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  PaidOn := Date;                          // today, on this PC
  btnMarkPaid.Enabled := False;            // no double clicks while it saves
  btnMarkUnpaid.Enabled := False;
  SetBusy(True, 'Saving...');
  TAsync.Run<TPaymentRec>(
    function: TPaymentRec
    begin
      Result := FApi.SetPaymentPaid(PaymentId, Paid, PaidOn);
    end,
    procedure(Saved: TPaymentRec)
    begin
      SetBusy(False, Format('Payment due %s is now %s',
        [DateToStr(Saved.DueDate), Saved.Status]));
      // reload from the server: its totals and its "late" rule, not ours
      if SelectedId(mtLeases) = LeaseId then
        LoadPayments(LeaseId, Saved.Id);
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, 'Not saved');
      UpdatePaymentButtons;
      HandleApiError(Err);
    end);
end;
```

**What to understand**
- **`TJSONNull.Create` is how you send `null`.** Leaving the key out would mean "don't change it" (section a.4, call 10). `AddPair` hands ownership to `Body`, so freeing `Body` frees everything in it.
- **Read, confirm, write, reload.** The client never edits its own copy of the row. After the write it shows what the server now says: "pending" comes back as "late" if the date has passed.
- **The PATCH is idempotent** (repeating it changes nothing more), which makes it safe if the network fails and the user tries again. Disabling the buttons still stops accidental double requests.
- **`DisplayText`** returns the field as the grid shows it (`18.000,00`), which is right for a sentence shown to the user.

**How to test**
1. Lease 1A, select October (late), click **Mark paid**, then **Yes**. The row shows paid with today's date and Method "manual", and the totals become Collected 108.000,00, Outstanding 108.000,00.
2. Open the web app or the iOS app: the same payment is paid there too. *That's the demo moment.*
3. Click **Mark unpaid**: it's back to late, with the totals as before.
4. Click **No** in the dialog: nothing is sent.
5. Commit.

---

### g.14 Loan schedule tab

**What and why.** The amortization view: a property's loans, and for the selected loan, every period with opening balance, payment, interest, principal and closing balance. All numbers come from the server; PMDesk displays them (section d.7).

**`uPropertyApi`: additions**

*Declarations:*

```pascal
    function GetLoans(const PropertyId: string): TLoanArray;
    function GetSchedule(const LoanId: string): TLoanSchedule;
```

*Parsers:*

```pascal
function ParseLoan(O: TJSONObject): TLoanRec;
begin
  Result.Id := JStr(O, 'id');
  Result.Lender := JStr(O, 'lender');
  Result.Principal := JCurr(O, 'principal');
  Result.DownPayment := JCurr(O, 'down_payment');
  Result.InterestRatePct := JCurr(O, 'interest_rate_pct');
  Result.StartDate := JDate(O, 'start_date');
  Result.Frequency := JStr(O, 'frequency');
  Result.CurrencyCode := JStr(O, 'currency');
  Result.Status := JStr(O, 'status');
end;

function ParseSchedulePeriod(O: TJSONObject): TSchedulePeriodRec;
begin
  Result.Period := JInt(O, 'period');
  Result.DueDate := JDate(O, 'due_date');
  Result.BeginningBalance := JCurr(O, 'beginning_balance');
  Result.Amount := JCurr(O, 'amount');
  Result.InterestAmount := JCurr(O, 'interest_amount');
  Result.PrincipalAmount := JCurr(O, 'principal_amount');
  Result.EndingBalance := JCurr(O, 'ending_balance');
  Result.PctOfPrincipal := JCurr(O, 'pct_of_principal');
  Result.Status := JStr(O, 'status');
  Result.PaidDate := JDate(O, 'paid_date');
  Result.IsDownPayment := JBool(O, 'is_down_payment');
end;
```

*Methods:*

```pascal
function TPropertyApi.GetLoans(const PropertyId: string): TLoanArray;
var
  Items: TLoanArray;
begin
  Items := nil;
  ForEachItem('/v1/loans?property_id=' + PropertyId,
    procedure(O: TJSONObject)
    begin
      Items := Items + [ParseLoan(O)];
    end);
  Result := Items;
end;

// Not a paged list: one object with a "periods" array and summary figures.
function TPropertyApi.GetSchedule(const LoanId: string): TLoanSchedule;
var
  Root: TJSONObject;
  Periods: TJSONValue;
  I: Integer;
begin
  Root := ParseObject(Send('GET', '/v1/loans/' + LoanId + '/schedule'));
  try
    Periods := Root.GetValue('periods');
    if not (Periods is TJSONArray) then
      raise EApiError.Create(aekUnexpected, 0, 'The schedule has no periods.');
    SetLength(Result.Periods, TJSONArray(Periods).Count);
    for I := 0 to TJSONArray(Periods).Count - 1 do
      Result.Periods[I] := ParseSchedulePeriod(
        TJSONArray(Periods).Items[I] as TJSONObject);
    Result.PaidToDate := JCurr(Root, 'paid_to_date');
    Result.Remaining := JCurr(Root, 'remaining');
    Result.TotalInterest := JCurr(Root, 'total_interest');
    Result.Drifted := JBool(Root, 'drifted');
    Result.OnGrid := JBool(Root, 'on_grid');
  finally
    Root.Free;
  end;
end;
```

**`uMain`: IDE actions**
1. Add these lines just above `public`:

```pascal
    procedure LoadLoans(const PropertyId: string);
    procedure FillLoans(const Items: TLoanArray);
    procedure LoanChanged;
    procedure LoadSchedule(const LoanId: string);
    procedure FillSchedule(const S: TLoanSchedule);
```

2. Select `mtLoans`, open **Events**, and double-click **AfterScroll**.
3. Replace `PropertyChanged`, and add the rest.

**`uMain`: procedures (complete)**

```pascal
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

procedure TfrmMain.mtLoansAfterScroll(DataSet: TDataSet);
begin
  if not FFilling then
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
```

**What to understand**
- **Two requests at once:** `PropertyChanged` starts the units and loans requests together. Both run in parallel on pool threads, and each reply checks it's still wanted.
- **`SetLength` then fill:** when the count is known up front (one JSON array), size the array once instead of growing it.
- **Amortization in one sentence:** each payment pays interest on the balance owed going into the period, and the rest reduces the balance. The last row absorbs rounding, so the balance ends at exactly 0. *The server computes it; PMDesk shows it.*
- **No Currency arithmetic was needed.** Every figure, including the totals, is the server's.

**How to test.** Expected values, checked against the local test run:
- **Palm Villa → Loans tab:** "Developer plan", Price 15.000.000,00, Down payment 750.000,00, Rate 0.000, quarterly. The schedule has 40 rows; rows 1–3 are paid (row 1 "paid (down)"), and row 40 closes at 0,00. Summary: Paid to date 1.480.769,24, Remaining 13.519.230,76, Interest 0,00.
- **Marina Studio:** "Demo Bank", 15.000 %, 13 rows. Row 2: payment 201.623,62 = interest 72.000,00 + principal 129.623,62. Interest total 499.483,41.
- **Garden Court:** no loans; the grid stays empty.

Commit.

---

### g.15 README, screenshot, GitHub

**What and why.** The repo is part of the interview story: a README that explains the design in one screen, a screenshot, and a check that nothing private gets pushed. The recording checklist is in h.3.

**Actions**
1. **Screenshot:** run PMDesk on Garden Court → 1A with payments visible. Press `Win+Shift+S`, then select the window. Open Paint, paste, and save as `docs\screenshot.png` (create the `docs` folder).
2. **README:** create `README.md` in the repo root with the template below, and adjust anything you like.
3. **Leak check:** run, click through every tab, sign out, close. There should be no leak dialog.
4. **Before pushing, check that nothing private is in git:**
   - `git status --ignored`: `PMDesk.ini` must appear under *Ignored files*.
   - `git grep -n -i "PART-OF-YOUR-REAL-HOST"` (type a piece of the real address): it must find nothing.
   - The password appears nowhere, because you never typed it into a file.
5. **GitHub:** on github.com, **New repository** → name `PMDesk`, Public, *without* a README. Then:

```text
git add -A
git commit -m "g.15 README and screenshot"
git branch -M main
git remote add origin https://github.com/YOUR-USER/PMDesk.git
git push -u origin main
git tag demo-ready
git push origin demo-ready
```

**`README.md` template**

````markdown
# PMDesk

A Windows desktop client, written in Delphi (VCL), for Property Manager: a
FastAPI + PostgreSQL backend I built, which also serves a React web app and a
native iOS app.

![PMDesk](docs/screenshot.png)

## Why

Many Delphi business applications talk straight to their database (two-tier).
PMDesk is the other shape: a native client of a REST API (three-tier). It
reuses the server's rules (who may see what, when a payment is late, how a
loan plan rounds) instead of copying them, and it holds no database password.

## What it does

- Sign in (OAuth2 password form; the token is kept in memory only)
- Properties → units → leases (with tenant names) → rent payments, with the server's totals
- Record a payment as paid, or undo it
- Loan amortization schedules, including the interest/principal split
- Every request runs in the background, so the window never freezes
- Errors in plain words: offline, session expired (sign in again), validation, server

## How it is built

```text
Forms (VCL) -> TAsync (TTask + TThread.Queue) -> TPropertyApi (THTTPClient + System.JSON) -> REST API
                                                 returns records, or raises EApiError
```

- Built-in libraries only: System.Net.HttpClient, System.JSON, System.Threading, FireDAC TFDMemTable.
- No HTTP or JSON code in any form; the API unit uses no VCL unit.
- Money is `Currency`, parsed from the API's decimal strings with fixed format
  settings and shown with the user's (`18.000,00` in Austria). Grid fields are
  `TBCDField`, never `TCurrencyField` (which is a Double underneath).
- Records, not classes, for API data: nothing to free, safe to pass between threads.

## Run it

1. Delphi 13 (Community Edition is enough): open `PMDesk.dproj`, build for Windows 32-bit.
2. Run once. It creates `PMDesk.ini` next to the exe. Set `BaseUrl` there (see `PMDesk.example.ini`).
3. Sign in with a landlord account.

## Next steps

Silent token refresh, DUnitX tests for the JSON layer, a cashflow tab and CSV export.
````

**What to understand:** the README is your pitch in writing. It states the problem (two-tier vs three-tier), the layers and the money rule. Section i turns it into talking points.

**How to test:** open the repo on github.com in a private browser window. The README renders, the screenshot shows, and there's no `.ini` and no real host.

---

### Bonus steps (each one optional and independent)

> Do them in any order once g.15 is pushed. Each is one feature with its own test. Where a step replaces a procedure, the complete version is shown.

#### B1. Cashflow tab

**What and why.** The landlord's forecast (section a.4, call 13), with a monthly / quarterly / yearly switch, the first negative date and the final balance. A 404 from the server means "not set up"; that's an answer, not an error.

**IDE actions**
1. Right-click `pgcMain` → **New Page**: Name `tsCashflow`, Caption `Cashflow`.
2. On it, add:
   - a TPanel `pnlForecastTop`: Align alTop, Height 41, BevelOuter bvNone, Caption empty.
   - on that panel, a TComboBox `cbFrequency`: Left 8, Top 9, **Style** `csDropDownList`. In **Items**, enter `monthly`, `quarterly`, `yearly` one per line. **ItemIndex** `1`.
   - also on that panel, a TLabel `lblForecast`: Left 160, Top 12, Caption empty.
   - a TDBGrid `grdForecast` on the page (grid settings).
   - `mtForecast` / `dsForecast` on the form, linked to each other and to the grid.
3. Events: `cbFrequency` **OnChange**; `pgcMain` **OnChange**.
4. Add these lines just above `public`: `procedure DefineForecastTable;`, `procedure LoadForecast;`, `procedure FillForecast(const F: TForecast);`
5. In `FormCreate`, add the line `DefineForecastTable;` after `DefineDetailTables;`.

**`uPropertyApi`**

*Declaration:*

```pascal
    function GetForecast(const Frequency: string): TForecast;
```

*Parser:*

```pascal
function ParseForecastPeriod(O: TJSONObject): TForecastPeriodRec;
begin
  Result.Period := JInt(O, 'period');
  Result.StartDate := JDate(O, 'date');
  Result.BeginningBalance := JCurr(O, 'beginning_balance');
  Result.Income := JCurr(O, 'income');
  Result.RentIncome := JCurr(O, 'rent_income');
  Result.Payments := JCurr(O, 'payments');
  Result.Maintenance := JCurr(O, 'maintenance');
  Result.EndingBalance := JCurr(O, 'ending_balance');
end;
```

*Method:*

```pascal
function TPropertyApi.GetForecast(const Frequency: string): TForecast;
var
  Root: TJSONObject;
  Periods: TJSONValue;
  I: Integer;
begin
  Result.Configured := False;
  Result.CurrencyCode := '';
  Result.FirstNegativeDate := 0;
  Result.FinalBalance := 0;
  Result.Periods := nil;
  Root := nil;
  try
    Root := ParseObject(Send('GET', '/v1/cashflow/forecast?frequency=' + Frequency));
  except
    on E: EApiError do
      if E.Kind = aekNotFound then
        Exit                          // never set up: an answer, not an error
      else
        raise;
  end;
  try
    Result.Configured := True;
    Result.CurrencyCode := JStr(Root, 'currency');
    Result.FirstNegativeDate := JDate(Root, 'first_negative_date');
    Result.FinalBalance := JCurr(Root, 'final_balance');
    Periods := Root.GetValue('periods');
    if Periods is TJSONArray then
    begin
      SetLength(Result.Periods, TJSONArray(Periods).Count);
      for I := 0 to TJSONArray(Periods).Count - 1 do
        Result.Periods[I] := ParseForecastPeriod(
          TJSONArray(Periods).Items[I] as TJSONObject);
    end;
  finally
    Root.Free;
  end;
end;
```

**`uMain`: procedures (complete)**

```pascal
procedure TfrmMain.DefineForecastTable;
begin
  AddInt(mtForecast, 'Period', '#');
  AddDate(mtForecast, 'StartDate', 'From');
  AddMoney(mtForecast, 'Opening', 'Opening');
  AddMoney(mtForecast, 'Income', 'Income');
  AddMoney(mtForecast, 'Rent', 'Rent');
  AddMoney(mtForecast, 'Payments', 'Loan payments');
  AddMoney(mtForecast, 'Maintenance', 'Maintenance');
  AddMoney(mtForecast, 'Closing', 'Closing');
  mtForecast.CreateDataSet;
end;

procedure TfrmMain.pgcMainChange(Sender: TObject);
begin
  if pgcMain.ActivePage = tsCashflow then
    LoadForecast;
end;

procedure TfrmMain.cbFrequencyChange(Sender: TObject);
begin
  LoadForecast;
end;

procedure TfrmMain.LoadForecast;
var
  Frequency: string;
begin
  Frequency := cbFrequency.Text;           // read on the UI thread (rule 2)
  SetBusy(True, 'Loading forecast...');
  TAsync.Run<TForecast>(
    function: TForecast
    begin
      Result := FApi.GetForecast(Frequency);
    end,
    procedure(F: TForecast)
    begin
      SetBusy(False, '');
      FillForecast(F);
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, '');
      HandleApiError(Err);
    end);
end;

procedure TfrmMain.FillForecast(const F: TForecast);
var
  P: TForecastPeriodRec;
begin
  mtForecast.DisableControls;
  try
    mtForecast.EmptyDataSet;
    for P in F.Periods do
    begin
      mtForecast.Append;
      mtForecast.FieldByName('Period').AsInteger := P.Period;
      mtForecast.FieldByName('StartDate').AsDateTime := P.StartDate;
      mtForecast.FieldByName('Opening').AsCurrency := P.BeginningBalance;
      mtForecast.FieldByName('Income').AsCurrency := P.Income;
      mtForecast.FieldByName('Rent').AsCurrency := P.RentIncome;
      mtForecast.FieldByName('Payments').AsCurrency := P.Payments;
      mtForecast.FieldByName('Maintenance').AsCurrency := P.Maintenance;
      mtForecast.FieldByName('Closing').AsCurrency := P.EndingBalance;
      mtForecast.Post;
    end;
    mtForecast.First;
  finally
    mtForecast.EnableControls;
  end;

  if not F.Configured then
    lblForecast.Caption := 'Cashflow forecasting is not set up for this account.'
  else if F.FirstNegativeDate <> 0 then
    lblForecast.Caption := Format('Goes negative from %s. Final balance %s %s.',
      [DateToStr(F.FirstNegativeDate), FormatCurr('#,##0.00', F.FinalBalance), F.CurrencyCode])
  else
    lblForecast.Caption := Format('Never goes negative. Final balance %s %s.',
      [FormatCurr('#,##0.00', F.FinalBalance), F.CurrencyCode]);
end;
```

**How to test:** open the Cashflow tab. With the seeded profile, quarterly shows 37 periods, "Goes negative from 01.01.2027", and a final balance of −10.191.966,93 EGP. Switch to monthly: more rows, the same obligations, and a slightly different final balance (the README explains why).

#### B2. CSV export

**What and why.** Export the grid on the current tab (payments, schedule or forecast) for Excel. Two Austrian details matter here:
- Use the Windows **list separator** (`;` when the decimal separator is `,`).
- Write a **UTF-8 byte-order mark**, so Excel reads names and the `€` sign correctly.

**IDE actions**
1. Set `lblUser.Left` to `290`. Drop a fresh TButton onto `pnlTop`: **Name** `btnExport`, Caption `Export CSV`, Left 184, Top 8. Double-click it.
2. Drop a **TSaveDialog** (Dialogs category) `dlgExport`: **DefaultExt** `csv`, **Filter** `CSV files (*.csv)|*.csv`. Under **Options**, set `ofOverwritePrompt` True.
3. In `uDataSets`:
   - add `procedure ExportCsv(DS: TDataSet; const FileName: string);` to the interface section, after the last declaration;
   - add `uses System.SysUtils, System.Classes;` right after `implementation`;
   - add the two routines below, just above the final `end.`.
4. In `uMain`, add `function ExportTable: TFDMemTable;` just above `public`.

**`uDataSets`: routines (complete)**

```pascal
function CsvQuote(const S: string; Sep: Char): string;
begin
  if (Pos(Sep, S) > 0) or (Pos('"', S) > 0) or (Pos(#13, S) > 0) or (Pos(#10, S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

procedure ExportCsv(DS: TDataSet; const FileName: string);
var
  Writer: TStreamWriter;
  Sep: Char;
  Mark: TBookmark;
  Line: string;
  I: Integer;
  First: Boolean;
begin
  // the Windows list separator: ';' in Austria (where ',' is the decimal
  // comma), ',' in English locales. It is what Excel expects on this PC.
  Sep := FormatSettings.ListSeparator;
  // TEncoding.UTF8 writes a byte-order mark first: Excel needs it for UTF-8
  Writer := TStreamWriter.Create(FileName, False, TEncoding.UTF8);
  try
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

    Mark := DS.Bookmark;
    DS.DisableControls;
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
```

**`uMain`: procedures (complete)**

```pascal
function TfrmMain.ExportTable: TFDMemTable;
begin
  if pgcMain.ActivePage = tsLoans then
    Result := mtSchedule
  // if you did B1, add:  else if pgcMain.ActivePage = tsCashflow then Result := mtForecast
  else
    Result := mtPayments;
end;

procedure TfrmMain.btnExportClick(Sender: TObject);
var
  DS: TFDMemTable;
begin
  DS := ExportTable;
  if DS.IsEmpty then
  begin
    StatusBar1.SimpleText := 'Nothing to export on this tab.';
    Exit;
  end;
  dlgExport.FileName := 'pmdesk-export.csv';
  if dlgExport.Execute then
  begin
    ExportCsv(DS, dlgExport.FileName);
    StatusBar1.SimpleText := 'Exported to ' + dlgExport.FileName;
  end;
end;
```

**How to test:**
- Export lease 1A's payments and open the file in Excel. The columns should be split correctly, the amounts should be numbers, and "Demo Tenant" and the dates should be readable.
- Open the same file in Notepad: the bottom right should say **UTF-8 with BOM**. If it says plain *UTF-8*, add `Writer.Write(#$FEFF);` as the first line inside the outer `try`.
- Optional: switch Windows to German (Austria) (h.6) and export again: the separator becomes `;`.

#### B3. Silent token refresh

**What and why.** On a 401, PMDesk first tries `POST /v1/auth/refresh` in the background (section a.4, call 4). The login dialog appears only if that fails. One renewal serves every 401 that arrives meanwhile, the same idea as the web client's single shared refresh and the iOS client's `refreshTask`.

**`uPropertyApi`**

*Declaration:*

```pascal
    function RefreshSession: TTokenPair;     // worker thread; reads the refresh token
```

*Method:*

```pascal
function TPropertyApi.RefreshSession: TTokenPair;
var
  Body, Root: TJSONObject;
  Json: string;
begin
  Body := TJSONObject.Create;
  try
    Body.AddPair('refresh_token', FRefreshToken);
    Json := Body.ToJSON;
  finally
    Body.Free;
  end;
  Root := ParseObject(Send('POST', '/v1/auth/refresh', 'application/json', Json));
  try
    Result.AccessToken := JStr(Root, 'access_token');
    Result.RefreshToken := JStr(Root, 'refresh_token');
  finally
    Root.Free;
  end;
end;
```

**`uMain`**
1. Add the field `FRenewing: Boolean;` directly below `FShowingError: Boolean;`.
2. Add `procedure RenewSession;` just above `public`.
3. Replace `HandleApiError`, and add `RenewSession`.

```pascal
procedure TfrmMain.HandleApiError(const Err: TApiErrorInfo);
begin
  if Err.Kind = aekUnauthorized then
  begin
    RenewSession;                    // try the refresh token before bothering anyone
    Exit;
  end;
  StatusBar1.SimpleText := Err.UserText.Replace(sLineBreak, ' ');
  if FShowingError then
    Exit;
  FShowingError := True;
  try
    MessageDlg(Err.UserText, mtError, [mbOK], 0);
  finally
    FShowingError := False;
  end;
end;

procedure TfrmMain.RenewSession;
begin
  if FRenewing or FShowingError then
    Exit;                            // one renewal serves every 401 meanwhile
  FRenewing := True;
  SetBusy(True, 'Session expired - renewing...');
  TAsync.Run<TTokenPair>(
    function: TTokenPair
    begin
      Result := FApi.RefreshSession;
    end,
    procedure(Pair: TTokenPair)
    begin
      FRenewing := False;
      FApi.SetTokens(Pair);          // main thread (rule 8)
      SetBusy(False, 'Session renewed');
      LoadProperties;                // reload what failed
    end,
    procedure(Err: TApiErrorInfo)
    begin
      FRenewing := False;
      SetBusy(False, '');
      FApi.ClearTokens;
      FShowingError := True;
      try
        MessageDlg('Your session has ended. Please sign in again.',
          mtInformation, [mbOK], 0);
        SignIn;
      finally
        FShowingError := False;
      end;
    end);
end;
```

**How to test:** put the temporary **Break token** tools from g.12 back for a moment. Break the token, click a property: the status bar briefly shows "renewing", then "Session renewed", and **no dialog appears**. The test only breaks the access token; the refresh token still works. Remove the tools again.

#### B4. Request tickets (for the frequency switch)

**What and why.** The stale-reply check in g.9–g.14 compares the reply's id with the selected row's id. The forecast has no id: switching monthly → yearly → quarterly quickly sends three requests, and their replies can arrive in any order. A ticket number keeps only the latest (section e.4).

**IDE actions:** add the field `FForecastTicket: Integer;` directly below `FFilling: Boolean;`. Then replace `LoadForecast` (from B1):

```pascal
procedure TfrmMain.LoadForecast;
var
  Frequency: string;
  Ticket: Integer;
begin
  Frequency := cbFrequency.Text;
  Inc(FForecastTicket);
  Ticket := FForecastTicket;               // this request's number
  SetBusy(True, 'Loading forecast...');
  TAsync.Run<TForecast>(
    function: TForecast
    begin
      Result := FApi.GetForecast(Frequency);
    end,
    procedure(F: TForecast)
    begin
      SetBusy(False, '');
      if Ticket = FForecastTicket then     // only the latest request may fill the grid
        FillForecast(F);
    end,
    procedure(Err: TApiErrorInfo)
    begin
      SetBusy(False, '');
      if Ticket = FForecastTicket then
        HandleApiError(Err);
    end);
end;
```

**How to test:** turn on Windows' network throttling (or test right after an idle period), then switch the frequency quickly three times. The grid always ends up matching the frequency finally selected.

#### B5. Device headers

**What and why.** Name this installation at login (section d.10). The server then keeps one session for this PC instead of a new "Unnamed device" session at every sign-in.

**`uPropertyApi`**
1. Add these fields directly below `FRefreshToken: string;`:

```pascal
    FDeviceId: string;
    FDeviceName: string;
```

2. Declaration:

```pascal
    procedure SetDevice(const ADeviceId, ADeviceName: string);   // main thread, before Login
```

3. Add the method `SetDevice`, and replace `Login`:

```pascal
procedure TPropertyApi.SetDevice(const ADeviceId, ADeviceName: string);
begin
  FDeviceId := ADeviceId;
  FDeviceName := ADeviceName;
end;

function TPropertyApi.Login(const Email, Password: string): TTokenPair;
var
  Root: TJSONObject;
  Device: TNetHeaders;
begin
  Device := nil;
  if FDeviceId <> '' then
    Device := [TNetHeader.Create('X-Device-Id', FDeviceId),
               TNetHeader.Create('X-Device-Name', FDeviceName),
               TNetHeader.Create('X-Device-Platform', 'windows'),
               TNetHeader.Create('X-App-Version', '0.1.0')];
  // a form, not JSON: OAuth2PasswordRequestForm (PLAN a.4, call 2)
  Root := ParseObject(Send('POST', '/v1/auth/login',
    'application/x-www-form-urlencoded',
    'username=' + FormEncode(Email) + '&password=' + FormEncode(Password), Device));
  try
    Result.AccessToken := JStr(Root, 'access_token');
    Result.RefreshToken := JStr(Root, 'refresh_token');
  finally
    Root.Free;
  end;
end;
```

**`uMain`:** replace `FormCreate`. If you did B1, keep its `DefineForecastTable;` line.

```pascal
procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FConfig := TAppConfig.Create;
  FConfig.Load;
  FApi := TPropertyApi.Create(FConfig.BaseUrl, FConfig.ConnectTimeoutMs,
    FConfig.ResponseTimeoutMs);
  FApi.SetDevice(FConfig.DeviceId, GetEnvironmentVariable('COMPUTERNAME'));
  Caption := 'PMDesk - ' + FConfig.BaseUrl;
  DefinePropertiesTable;
  DefineDetailTables;
end;
```

**How to test:** sign in, sign out, and sign in again. Then, with a token in cmd (b.5, step 5):
`curl.exe -s https://YOUR-API-HOST/v1/devices -H "Authorization: Bearer %TOKEN%"`
It should list **one** session named after your PC, platform `windows`, app version `0.1.0`. The earlier unnamed sessions from before this step are still listed too.

#### B6. Pointing PMDesk at a local backend

**What and why.** The fallback from section h.2: if Render is down, run the API on the Mac and point PMDesk at it. No code changes: that's what the ini file is for.

**Actions**
1. Start the API on the Mac as described in h.2 (it listens on `0.0.0.0:8000`).
2. Find the Mac's address: `ipconfig getifaddr en0` (e.g. `192.168.1.23`).
3. On the laptop, test it: `curl.exe http://192.168.1.23:8000/health`
4. In `PMDesk.ini`, set `BaseUrl=http://192.168.1.23:8000` and restart PMDesk. Plain `http` is fine on a home network; THTTPClient handles both.
5. Afterwards, set `BaseUrl` back to the real server.

**How to test:** the caption shows the local address, sign-in works, and the Mac's terminal logs each request.

#### B7. DUnitX tests for the parsing

**What and why.** Unit tests for the parts that are easy to get wrong:
- money parsing when Windows uses a comma;
- dates and nulls;
- the login form encoding;
- the three error shapes.

DUnitX ships with the IDE.

**Actions**
1. **Expose four helpers for the tests.** In `uPropertyApi`'s **interface** section, after the `end;` of `TPropertyApi` and before `implementation`, add the four declarations below. Their bodies already exist in the implementation section.

```pascal
// Exposed for the unit tests (bonus B7); the app itself only uses TPropertyApi.
function JCurr(O: TJSONObject; const Name: string): Currency;
function JDate(O: TJSONObject; const Name: string): TDate;
function FormEncode(const S: string): string;
function ExtractDetail(const Body: string): string;
```

2. **File > New > Other… > Delphi > DUnitX > DUnitX Project.** Tick "Create Test Unit", class name `TApiParsingTests`, and save it in `C:\Dev\PMDesk\tests` as `PMDeskTests.dproj`.
3. **Project > Add to Project…**: add `..\uPropertyApi.pas`, `..\uApiTypes.pas` and `..\uApiErrors.pas`.
4. Replace the generated test unit's content with the code below (keep its unit name on the first line).
5. Press `F9`: a console window lists the results.

```pascal
unit TestApiParsing;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TApiParsingTests = class
  public
    [Test] procedure MoneyIsReadWithADotWhateverTheLocale;
    [Test] procedure ZeroAndNegativeMoney;
    [Test] procedure DatesAndNulls;
    [Test] procedure LoginFormEncoding;
    [Test] procedure ErrorBodiesBecomeReadableText;
  end;

implementation

uses
  System.SysUtils, System.JSON, uPropertyApi;

function Obj(const Json: string): TJSONObject;   // the caller frees it
begin
  Result := TJSONObject.ParseJSONValue(Json) as TJSONObject;
end;

procedure TApiParsingTests.MoneyIsReadWithADotWhateverTheLocale;
var
  O: TJSONObject;
  Saved: Char;
begin
  Saved := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := ',';         // as on a German (Austria) Windows
  O := Obj('{"amount": "18000.50"}');
  try
    Assert.IsTrue(JCurr(O, 'amount') = 18000.50, 'should read 18000.50');
  finally
    O.Free;
    FormatSettings.DecimalSeparator := Saved;
  end;
end;

procedure TApiParsingTests.ZeroAndNegativeMoney;
var
  O: TJSONObject;
begin
  O := Obj('{"a": "0", "b": "-1500.50", "c": null}');
  try
    Assert.IsTrue(JCurr(O, 'a') = 0);
    Assert.IsTrue(JCurr(O, 'b') = -1500.50);
    Assert.IsTrue(JCurr(O, 'c') = 0, 'null reads as 0');
  finally
    O.Free;
  end;
end;

procedure TApiParsingTests.DatesAndNulls;
var
  O: TJSONObject;
begin
  O := Obj('{"d": "2026-10-01", "n": null}');
  try
    Assert.AreEqual(EncodeDate(2026, 10, 1), JDate(O, 'd'));
    Assert.IsTrue(JDate(O, 'n') = 0, 'null reads as 0');
    Assert.IsTrue(JDate(O, 'missing') = 0, 'a missing key reads as 0');
  finally
    O.Free;
  end;
end;

procedure TApiParsingTests.LoginFormEncoding;
begin
  // & = + and space would break a form body; e-acute is two UTF-8 bytes
  Assert.AreEqual('a%26b%3Dc%2Bd%20%C3%A9', FormEncode('a&b=c+d ' + #$00E9));
  Assert.AreEqual('demo.landlord%40example.com', FormEncode('demo.landlord@example.com'));
end;

procedure TApiParsingTests.ErrorBodiesBecomeReadableText;
begin
  Assert.AreEqual('Not allowed', ExtractDetail('{"detail": "Not allowed"}'));
  Assert.AreEqual('paid_date: Input should be a valid date',
    ExtractDetail('{"detail": [{"loc": ["body", "paid_date"], "msg": "Input should be a valid date"}]}'));
  Assert.AreEqual('Rate limit exceeded: 10 per 1 minute',
    ExtractDetail('{"error": "Rate limit exceeded: 10 per 1 minute"}'));
  Assert.AreEqual('', ExtractDetail('<html>502 Bad Gateway</html>'));
end;

initialization
  TDUnitX.RegisterTestFixture(TApiParsingTests);

end.
```

**How to test:** all 5 tests pass. Then break one on purpose, for example by changing `ApiFormat.DecimalSeparator := '.'` to `','` in `uPropertyApi`. The money test fails, which proves it guards that line. Change it back.

#### B8. A Win64 build

**What and why.** Most new Delphi deployments are 64-bit. For this app, it's a platform switch, not a code change.

**Actions:** in the **Projects** window, right-click **Target Platforms** → **Add Platform…** → **Windows 64-bit**. Right-click it → **Activate**, then **Project > Build PMDesk**. The exe appears in `Win64\Debug`, and it creates its own `PMDesk.ini` there.

**What to understand:** the code has no pointer-to-Integer casts and no inline assembler, and `Currency`, `string` and THTTPClient behave the same on both platforms. That's why the switch is free here. In a large legacy codebase, those casts are where 64-bit migrations hurt.

**How to test:** run it. In Task Manager, the process shows **no** "(32 bit)" after its name. Sign in and click through every tab.

---

## h) Recommendations

### h.1 Make sure the API is awake before the demo

**The facts:**
- Render's free tier sleeps after about 15 minutes without traffic, and waking takes about 50 seconds.
- Your dashboard shows ~16 of 750 free hours used in October. A service kept awake all month would be at roughly 550 hours by now, so production **is** sleeping when idle.
- The uptime monitor that was meant to keep it awake isn't doing so.
- The database (Neon) also scales to zero when quiet, so the first database query after a lull takes a few extra seconds. The backend's connection pool handles that (`pool_pre_ping`, in `app/database.py`).

**Check what the uptime monitor actually does.** In UptimeRobot:
1. **Dashboard → Monitors.** Find the Property Manager monitor.
2. **Status:** green *Up* is good. *Paused* means it never runs: resume it.
3. **URL:** it must be exactly `https://YOUR-API-HOST/health`. Not the staging API, and not the Vercel web app. Pinging the web app keeps Vercel busy and Render asleep.
4. **Interval:** 5 minutes. Anything above 15 minutes lets the server fall asleep between pings.
5. **Response-time graph:** a row of ~50-second responses means each ping is waking a sleeping server, so the interval is too long or the monitor was paused.
6. **Cross-check on Render:** open `pm-api` → **Logs**. You should see `GET /health` every 5 minutes. No such lines means the monitor isn't hitting production.

**Cost:** about 8 days of October are left. Even awake around the clock until the 31st, that's roughly 200 more hours, about 216 of 750 in total, so it's safe this month. From 1 November, a full month awake is about 720 hours plus staging's hours, which is close to the cap. Decide that after the interview; it doesn't need to change now.

**Interview-day routine (Windows laptop, cmd.exe):**
1. **T−20 minutes:** wake the server and repeat until it answers in under a second. The first try may take about 50 s.

```text
curl.exe -s -o NUL -w "%{http_code} in %{time_total}s\n" https://YOUR-API-HOST/health
```

2. **T−15 minutes:** start PMDesk, sign in, and click Garden Court → 1A → payments, then the Loans tab. This also wakes the database.
3. **During the interview hour:** keep both awake from a second cmd window, every 4 minutes. `/health/db` touches the database too; that's fine for one hour, but don't leave it running for days.

```text
for /L %i in (1,0,2) do @(curl.exe -s -o NUL https://YOUR-API-HOST/health/db & timeout /t 240 /nobreak >NUL)
```

   `for /L %i in (1,0,2)` counts from 1 to 2 in steps of 0, so it runs until you press `Ctrl+C`.

### h.2 Fallback: run the API on the Mac, against Neon

**When to use it:** Render is down or suspended, but Neon is fine. PMDesk then talks to the same production data through an API running on your Mac.

**One-time check:** the Mac's backend code must match what Render runs. In `~/PM`, `git status` and `git log -1` should show `docs/ios-plan`, up to date. Your only uncommitted files are iOS ones, so the backend is identical.

**Start it (Mac, terminal):**

```text
cd ~/PM
source .venv/bin/activate
read -s "DATABASE_URL?Neon production URL (scheme edited): "; export DATABASE_URL
export JWT_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
export ENVIRONMENT=local-fallback
export SENTRY_DSN=
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

- **Where the database URL comes from:** the Neon dashboard → project `pm` → production branch → **Connection details**. Change its scheme from `postgresql://` to `postgresql+psycopg://`, otherwise SQLAlchemy picks the wrong driver. Keep `?sslmode=require` at the end.
- **`read -s`** hides what you paste and keeps the password out of your shell history. `export DATABASE_URL=...` typed directly would be saved in `~/.zsh_history`.
- **A fresh `JWT_SECRET`:** tokens issued by Render don't work here, and the reverse. You simply sign in again. The secret lives only in this terminal.
- **`SENTRY_DSN=`** stops errors from this laptop being reported to production's Sentry.
- **Never run `alembic upgrade` against Neon from the laptop.** Render's builds already did; the schema is current.
- `--host 0.0.0.0` lets the Windows laptop reach the API. When macOS asks whether Python may accept incoming connections, choose **Allow**.

**Point PMDesk at it:** follow bonus step B6. Get the Mac's address with `ipconfig getifaddr en0`, test with `curl.exe http://<that address>:8000/health`, then set `BaseUrl` in the ini. Both machines must be on the same Wi-Fi, so if the interview is in person, bring the Mac.

**Afterwards:** stop the server (`Ctrl+C`) and close the terminal (that forgets the exported values). Set `BaseUrl` back.

**Fallback 2, fully offline (no Render, no Neon):** use the local Postgres recipe from g.1 (a test database, `fastapi dev`, the seed script), then run the API with `--host 0.0.0.0` as above and point PMDesk at the Mac. The data has the same shape; only the ids differ.

**Rehearse it once before Tuesday.** It takes about 10 minutes. A fallback you've never run isn't a fallback.

### h.3 Backup recording: checklist

**Before recording**
- [ ] Server warm (h.1). Demo data reset: lease 1A's October is *late* again (Mark unpaid if you marked it).
- [ ] Do Not Disturb on. Close mail, chat, and any browser tabs with private data.
- [ ] Display scaling at 100–125%, with PMDesk at its normal size (1200 × 760).
- [ ] Recorder ready. On Windows 11: **Snipping Tool → Record**, then select the PMDesk window area. On Windows 10: **Xbox Game Bar** (`Win+G`; `Win+Alt+R` starts and stops; it records the active app).
- [ ] Microphone checked: record 10 seconds and play it back.
- [ ] The real server address appears in the title bar and the login dialog. That's fine for a private backup; blur it before posting the video anywhere public.
- [ ] Never show the ini file, a cmd window with `%TOKEN%`, or the Neon dashboard on screen.

**Script (about 3 minutes; the same order as the live demo in i.4)**
1. Start PMDesk. Wrong password: show the server's own message. Right password: "Loading…", and **drag the window while it loads**.
2. Garden Court → 1A → lease → payments: October *late*, plus the totals.
3. **Mark paid** → confirm: the totals change. Optionally show the same payment paid on your phone. Then **Mark unpaid**.
4. **Loans tab:** Palm Villa (40 rows, closing at 0,00), then Marina Studio (interest + principal split).
5. **Errors:** Wi-Fi off → Refresh → the message. Wi-Fi on → Refresh.
6. If you did B1/B2: the Cashflow tab, then Export CSV → open it in Excel.
7. Sign out, then close: no leak dialog.

**After recording**
- [ ] Watch it all the way through: sound, readability (zoom in if the text is small), dead time to trim.
- [ ] Keep two copies, on the laptop and on a USB stick or cloud drive, with the date in the file name.
- [ ] Take 5 screenshots of the key screens as the backup's backup.

### h.4 What the repo suggests (approaches it confirms or improves)

1. **The server owns every figure.** `app/routers/dashboard.py` says so in its docstring. PMDesk keeps that rule: it displays numbers and never computes them. That's also why there's no rounding risk in the client.
2. **There's a contract, and CI enforces it.** `/v1` paths, money as strings and plain dates are enforced by `tests/test_contract.py`. CI regenerates the OpenAPI spec and blocks breaking changes (`.github/workflows/ci.yml`). A third client can trust the shape; say this in the interview.
3. **`frontend/openapi.json` is the machine-readable contract.** A next step for PMDesk would be checking its records against it. Delphi has no built-in generator for this.
4. **The existing clients refresh tokens with a single in-flight refresh** (`frontend/src/api/client.ts` → `refreshInFlight`; the iOS `APIClient` actor → `refreshTask`). Bonus B3 is the Delphi version of the same idea.
5. **The iOS app names its installation at login** (`DeviceIdentity.swift`). Bonus B5 does the same.
6. **`/v1/dashboard` is screen-shaped:** one request per screen, because a cold server should cost one wait, not five. A Delphi dashboard tab would use it as it is.
7. **`/v1/app-config` is a kill switch** that a shipped client checks at startup. PMDesk doesn't need it, but would if it were ever distributed.

### h.5 Backend changes worth proposing (after the interview; each needs your OK)

All of these are additive or docs-only first (expand, then contract).

| # | Change | Why | Kind |
|---|---|---|---|
| 1 | Add `tenant_name` to `LeaseRead` | Removes PMDesk's one-lookup-per-lease (N+1). Web and iOS would benefit too. | additive field |
| 2 | Fix the README's auth section | It says `POST /auth/login`; the real path is `/v1/auth/login` (same for register, refresh, me). | docs only |
| 3 | Check the rate limiter's client IP on Render | uvicorn starts without `--forwarded-allow-ips`, so the limiter may count Render's proxy IP instead of the user's. Verify first (log `request.client.host`), then set `FORWARDED_ALLOW_IPS`. | config |
| 4 | Case-insensitive login email | Login compares the email exactly, while Apple sign-in lowercases it. Check for accounts that differ only by case first. | behaviour change |
| 5 | Default `paid_date` to today on `PATCH /payments` | Loan instalments already do this; payments leave it empty unless sent. | small behaviour change |
| 6 | Decide on the uptime monitor and the free-hours cap | Keeping production awake uses most of the 750 hours per month. A choice, not code. | decision |

### h.6 Risks and what to do about them

| Risk | What you'd see | Mitigation |
|---|---|---|
| API asleep at the start | First sign-in takes ~50 s | h.1 warm-up. The login text already says a sleeping server can take a minute. |
| Render down or suspended | Network errors or 5xx | h.2 fallback (rehearsed), then the recording (h.3). |
| The interview network blocks or proxies traffic | curl and PMDesk fail | Phone hotspot, then the recording. |
| Demo data changed while rehearsing | October already paid | **Mark unpaid** resets it. If it's badly off, run the seed with a second email and sign in with that. |
| Token expires mid-demo (60 min) | The login dialog appears | That's a feature: say so. Or do B3. |
| Rate limit after many rehearsal logins | "Too many attempts" | Wait a minute (10 logins per minute). |
| A broken build on Monday night | It won't compile | Work on a branch after the `demo-ready` tag. `git checkout demo-ready` rebuilds the known-good version. |
| A question about Austrian settings | | **Test it beforehand:** Settings → Time & language → Language & region → Regional format **German (Austria)**. Restart PMDesk: dates read 24.10.2026, money 18.000,00, CSV uses `;`, and everything still loads (that proves `ApiFormat` works). Switch back afterwards. |
| A leak dialog at the end of the demo | FastMM's report | Fix any leak you find while testing, or demo the Release build: Projects → Build Configurations → **Release** → Activate → Build. It has no leak report. |
| A projector or a high-DPI screen | The layout looks off | Test once at 150% scaling. |
| A secret on screen | | Passwords are masked. Never show the ini, a token in cmd, or the Neon dashboard while sharing. |

---

## i) Interview prep

### i.1 The 60-second pitch

> "I built PMDesk, a Delphi VCL desktop client for a property-management backend I wrote in FastAPI and PostgreSQL, which also serves a React web app and an iOS app. It's the modernization case: instead of a desktop app talking straight to its database, it's a native client of a versioned REST API.
>
> The interesting parts were Delphi-specific. Every request runs on a TTask and comes back through TThread.Queue, so the window never freezes. No form contains HTTP or JSON: one API class returns records or raises one error type. Money is Currency, parsed from decimal strings with fixed format settings and shown in the user's locale, in BCD fields rather than TCurrencyField. And an expired session brings back the login instead of an error.
>
> I came to Delphi from Python and TypeScript and built this in a weekend. That's the other thing I wanted to show: I learn a stack quickly, and I still make deliberate design decisions."

### i.2 Talking points

1. **The modernization story.** Same business data, but the desktop client holds no database password and reuses the server's rules, the ones the web and iOS apps already use.
2. **Layers with one rule each:** forms → `TAsync` → `TPropertyApi` → records. No HTTP or JSON in forms, and no VCL in the API unit. The API class could run unchanged in a console tool, a service or a test.
3. **Responsiveness:**
   - Every request runs on a pool thread, and results return via `TThread.Queue`.
   - Errors are copied into a record before crossing threads.
   - A busy counter disables buttons and blocks closing, and stale replies are dropped.
4. **Money correctness:**
   - Values come as JSON strings and go into `Currency`, with fixed parse settings and the user's display settings.
   - Fields are `TBCDField`, not `TCurrencyField`.
   - Tested under German (Austria) regional settings.
5. **Errors in one place:** a single `EApiError` with kinds. A 401 means sign in again (or a silent refresh). A 422 becomes one line per field. "No answer at all" (network) is kept apart from "an answer that says no" (HTTP 4xx/5xx).
6. **Memory discipline:** create → `try` → `finally Free`. JSON values belong to their root. Records and interfaces need no `Free`. The FastMM leak report stays clean.
7. **Security:** no database credentials in the client. Tokens are in memory only, and the ini file holds no secrets. The server enforces roles; the client's check only spares the user an error.
8. **Your camp app and PMDesk, side by side:**
   - Camp app (two-tier, FireDAC + SQLite): the overlap check runs in a transaction, and `ekUKViolated` is caught.
   - PMDesk (three-tier): that check would move to the server, inside one transaction backed by a database constraint. The client just shows the 409. *Directly relevant to campsite booking software.*

### i.3 Likely questions, with short answers

**When would you add an API layer to a Delphi app?**
When clients leave the LAN (remote sites, internet, mobile); when more than one kind of client needs the same rules; when you can't hand out database credentials; or when the database must change without redeploying every desktop. Not for a single-site app with trusted users on a LAN: there, two-tier is simpler and faster.

**How would you migrate an existing two-tier app?**
Step by step, never as one big rewrite.
- Pick one module and put its rules behind endpoints.
- Switch that module's screens from `TFDQuery` to API calls that fill `TFDMemTable`s. Grids and reports barely change, because they're bound to datasets either way.
- Version the API, add contract tests, move to token auth, and repeat module by module.

**How do you keep the UI responsive?**
- Network work runs on worker threads (`TTask`).
- Results go to the main thread with `TThread.Queue`.
- Controls are disabled while busy, and the window refuses to close while requests run.
- Stale replies are dropped.
- No `ProcessMessages` loops.

**`TThread.Queue` or `Synchronize`?**
`Synchronize` blocks the worker until the main thread has run the code. That risks a deadlock if the main thread is waiting for the worker. `Queue` posts the code and returns at once. Use `Synchronize` only when the worker needs a value back from the UI.

**Why can't a worker thread touch a control?**
The VCL isn't thread-safe. Controls wrap Windows handles that belong to the main thread's message loop, and touching them from two threads corrupts their state, unpredictably.

**Anonymous method pitfalls?**
- They capture *variables*, not values: a closure inside a loop sees the loop variable's last value.
- You can't capture `Result` or `var` parameters.
- An exception object used in queued code has already been freed, so copy what you need first.

**How do you avoid memory leaks?**
- Ownership is explicit: create, `try`, use, `finally Free`.
- Components are freed by their `Owner`, and JSON values by their root.
- Records and interfaces free themselves.
- `ReportMemoryLeaksOnShutdown` is on in debug builds.

**Why `Currency` and not `Double`?**
`Double` is binary floating point: 0.1 isn't exact, sums drift, and equality checks fail. `Currency` is a 64-bit integer counting ten-thousandths, so it's exact to 4 decimals. In datasets, use `TBCDField`; `TCurrencyField` is a `Double` underneath. Beyond 4 decimals, use `TBcd` / `TFMTBCDField`.

**What about rounding?**
Delphi's `Round` rounds half to even (banker's rounding). Commercial rules usually round half up, and tax rules may say per line or per total. Decide *where* rounding happens. In PMDesk, the server does all of it, so there's exactly one rule.

**What breaks on an Austrian Windows?**
- `StrToCurr('18000.00')`, because the decimal separator is `,`. Parse machine data with fixed settings and display with the user's.
- Dates: parse ISO dates by position. In `FormatDateTime`, `/` means the local date separator.
- CSV for Excel: use the list separator (`;`) and a UTF-8 BOM.

**Why THTTPClient and not Indy or TRESTClient?**
THTTPClient is part of the RTL and uses Windows' own TLS (WinHTTP/Schannel), so there are no OpenSSL DLLs to ship and patch. Indy needs them. `TRESTClient` with its dataset adapter is faster for a prototype, but it hides threading and error handling, and it turns money into strings.

**How does the auth work, and where's the token?**
- Login is an OAuth2 password form. It returns a 60-minute JWT access token and a 30-day refresh token, tied to a device session that can be revoked.
- The access token is sent as `Bearer` and kept in memory only.
- A 401 leads to a refresh or a new sign-in.
- The server checks every request.

**How would you test it?**
- DUnitX for the parsing: money under a German locale, dates, nulls, error shapes.
- Integration runs against a throwaway local backend with seed data.
- The backend already has pytest and a contract test.
- Forms are kept thin, so little UI logic needs testing.

**What about working offline?**
Today: a clear error and a retry. Next: cache what was loaded in FireDAC + SQLite (as in the camp app), queue writes with an idempotency key, and sync later, resolving conflicts with server-side versions.

**Records or classes?**
Records for data: values, nothing to free, safe to hand between threads. Classes for things with identity, behaviour and a lifetime: the API client, the config, the forms.

**Is THTTPClient thread-safe?**
PMDesk sidesteps the question: one instance per request, so nothing is shared and nothing needs a lock. Alternatives are one client per thread or a pool. Never share one instance between threads without checking.

**What was hardest, or most surprising?**
- `AfterScroll` fires on `Append` and `Post` too, which is why the `FFilling` guard exists.
- Two field-type traps: `TCurrencyField` is a `Double`, and `TStringField` is 8-bit.
- The threading discipline.

Coming from Python, Delphi's explicit ownership felt like a feature, not a burden.

**What would you do next?**
Silent refresh that retries the failed request; DUnitX in CI; the tenant name in the lease response; a dashboard tab using the screen-shaped endpoint; an installer with code signing; Win64 as the default.

**How would you prevent double bookings in a three-tier version?**
On the server, in one transaction, backed by a database constraint. In Postgres, that's an exclusion constraint on a date range per pitch. The API answers 409, and the client shows the message, exactly as PMDesk handles 409 today. A client-side check alone can never guarantee it, because two clients can check at the same moment.

### i.4 Live demo (5 minutes): what to show, what to say

1. **Login, with a wrong password first.** *"The text is the server's own; the client maps errors in one place."* Then sign in and drag the window. *"Every request runs on a thread-pool task."*
2. **Properties → Garden Court → 1A → payments.** *"Three requests, each in the background; a stale reply is dropped. The tenant's name is a second call, combined in the API layer."*
3. **Mark paid.** *"Confirm, PATCH, reload from the server: its 'late' rule, its totals."* Show the phone app if it's at hand. Then Mark unpaid.
4. **Loans.** *"The server computes the amortization; the client shows it. Money is Currency end to end, never Double."*
5. **Wi-Fi off → Refresh.** *"No answer at all is a different error from an HTTP error."* Wi-Fi back on.
6. **Code, briefly:** `uPropertyApi.Send` (one way out to the network), `TAsync.Run` (16 lines), `AddMoney` (`TBCDField`, not `TCurrencyField`).

**If the server is slow:** *"That's a free-tier cold start. It's why the client has a 90-second response timeout and says so on screen."* Show the code while it wakes. **If it's down:** switch to the h.2 fallback, or play the recording.

### i.5 Questions to ask them

- Which Delphi versions and platforms are you on: VCL or FireMonkey, 32- or 64-bit? How far along is the move to newer versions?
- How do your clients reach their data today: directly (FireDAC or similar), DataSnap, RAD Server, or your own REST services? Is an API layer for web or mobile planned?
- How do you test Delphi code: DUnitX, CI builds, code review?
- What do a new developer's first three months look like?
