# CLAUDE.md — Ideal Store POS

Point-of-sale and accounts app for a wholesale/retail grocery shop in Tamil Nadu.
Flutter (Windows desktop is the main target; Android also builds) + Supabase (Postgres).
Bills print in English or Tamil on thermal printers. Repo: `ajmafabu/ideal-store-pos` (public).

The owner is not a full-time developer. Explain changes in plain words, give
copy-paste steps, and ask before anything that changes or deletes shop data.

## Commands (Windows, project root)

```bat
flutter pub get
flutter analyze --no-fatal-infos lib test   :: must report "No issues found"
flutter test                                :: all tests must pass
flutter build windows --release             :: output: build\windows\x64\runner\Release
```

- Analyze only `lib test`. Root scripts (`translate_tamil*.dart`, `clear_tamil.dart`,
  `tool/`) are one-off helpers and are excluded in `analysis_options.yaml`.
- Any analyzer **warning** fails the release; fix it, do not suppress it.
- Supabase URL/key: `lib/config/supabase_config.dart` reads `--dart-define=SUPABASE_URL` /
  `SUPABASE_ANON_KEY` and falls back to the built-in values. The anon key is a JWT
  (`eyJ…`, 3 dot-separated parts); a test guards this. Never put the service-role key in the app.

SQL tests (need PostgreSQL 16 and bash, e.g. WSL or CI; defaults `/tmp/pg`, port 5433,
override with `PGHOST`/`PGPORT`/`PGUSER`):
```bash
bash sql/tests/run_local.sh     # fresh DB + every business scenario → ALL SCENARIO TESTS PASSED
bash sql/tests/run_upgrade.sh   # 47 legacy files + old data + migration → ALL UPGRADE TESTS PASSED
```
Call helper scripts with `bash script.sh`: files committed from Windows have no execute bit.

## Layout

```
lib/
  main.dart                 startup, Hive, periodic sync, startup update check + _UpdateDialog
  config/                   Supabase config, theme, Hive adapter, billing providers
  config/providers/         Riverpod providers by area (sales, dashboard, accounts, sync…)
  models/                   Sale/CartItem, Purchase/PurchaseItem, Product, Customer…
  services/                 all Supabase access (sale_, purchase_, product_, customer_…),
                            offline_service (queue + dead-letter), update_service, backup…
  screens/admin|staff|desktop|shared|customer|auth|splash
  screens/admin/admin_shell.dart   sidebar, routes, "Check for Updates"
  screens/desktop/desktop_billing_screen.dart   main till screen (keyboard shortcuts, F1 help)
  utils/                    validators, payment_methods, network_errors, error_messages,
                            invoice_generator (PDF), thermal_invoice, logger
sql/
  2026_10_audit_fixes.sql   THE schema: one idempotent migration, one transaction
  verify_schema.sql         read-only health check; every row should say OK
  data_cleanup_2026_10.sql  product data reports + helpers (merge_products, normalize categories)
  cleanup_report.sql / cleanup_check.sql   read-only product clean-up reports
  legacy/                   47 historical files: reference only, NEVER run again
  tests/                    scenario + upgrade tests (run in CI job "database")
test/                       Flutter tests (audit_fixes_test, services_test, models_test…)
.github/workflows/          test.yml (analyze, tests, SQL tests), build-windows.yml (release zip)
release.ps1                 local release script (gitignored, *.ps1)
_claude/                    local helper .bat files (git-excluded); not part of the app
```

## Rules the code depends on (do not break)

**Money is posted by the database.**
- Sales, purchases, payments, expenses and returns write cash/bank entries through
  Postgres triggers (`reconcile_postings`, `money_split`), based on what is stored
  on the document.
- The app must **never** insert `account_transactions` for these.
- `customer_service.recordPayment` / `supplier_service.recordPayment` call the server
  and queue offline **only** on network errors.

**Stock changes only through:**
- documents (sale, purchase, return, damaged);
- `adjust_stock(product, delta)` (Stock In/Out);
- a physical count (`reconcile_stock_with_batches` / `ProductService.setPhysicalStock`).

The `guard_products_stock` trigger keeps the old `stock` on any plain product update
made by `authenticated`/`anon`. Batches are consumed FIFO.

**Stock units.** `CartItem.stockFactor` is how many product stock units one sold line
unit uses. Example: a box of 12 of a piece-counted product = 12. Keep it through
`copyWith`, held bills, `toJson`/`fromJson` and edits.

**Idempotent saves.**
- New sales and purchases get a client UUID from `newDocumentId()` before saving.
- A retried save is recognised by that id, so never let the server generate it.
- `isUuid()` separates real ids from old `local-…` ids.

**Offline.** Queue only when `isNetworkError(e)` is true. A server rejection goes to the
dead-letter box, shown on the **Sync Issues** screen (`needsReview` provider), and must not
be retried forever.

**Payment methods.**
- Always go through `PaymentMethods.normalize`. The values are `cash | upi | bank | credit | split`.
- `PaymentMethods.accountType` maps `upi`/`bank` to the bank account and the rest to cash.

**GST and invoice numbers.**
- The DB computes the CGST/SGST/IGST split; the app does not send it.
- `sales.invoice_no` is the bill number; use `Sale.invoiceLabel`.

**Permissions.**
- Money- and stock-changing RPCs call `assert_admin()`, or `assert_member()` (active staff) for
  sales and returns.
- The router blocks inactive users and wrong roles.
- Cost price and profit are admin-only in the UI.

**UI conventions.**
- Show users `ErrorMessages.parse(e)`, not raw exceptions. Exception: updater errors show
  the real reason.
- Use `Logger`, never `print`.
- Validate forms with `utils/validators.dart` (amount, GSTIN, phone, quantity, HSN).

**Tests.** Hive is encrypted. Tests call `HiveAdapter.useCipherForTests(...)` in `setUpAll`.

## Changing the database

1. Never edit or re-run `sql/legacy/*`.
2. Write a new file, `sql/YYYY_MM_<what>.sql`:
   - idempotent (`CREATE OR REPLACE`, `IF NOT EXISTS`, guarded `ALTER`s);
   - inside `BEGIN … COMMIT`;
   - `REVOKE … FROM PUBLIC, anon` and `GRANT … TO authenticated` for every new function;
   - `SECURITY DEFINER SET search_path = public` where needed.
3. Add checks to `verify_schema.sql`. Add scenario tests to `sql/tests/scenario_test.sql`,
   and to `upgrade_test.sql` if old data is affected.
4. The owner applies it by hand in **Supabase → SQL Editor**: back up first, run
   `verify_schema.sql`, run the migration, run `verify_schema.sql` again.
5. Supabase SQL Editor quirks:
   - temp tables do not survive between statements, so use one statement with CTEs
     to apply data and report counts;
   - the editor shows only the last result set.
6. Data fixes:
   - first give a **read-only** report;
   - make updates conditional on the old value (`WHERE col = old_value`) so re-runs
     are no-ops;
   - **never delete or merge products without the owner's explicit OK.**
     `merge_products` deletes the duplicate, and its barcode stops scanning.

## Releasing (Windows auto-update)

1. On `master`, with a clean tree, run `flutter analyze` and `flutter test`, then
   `.\release.ps1 1.2.3` (plain `x.y.z`). It bumps `pubspec.yaml` to `x.y.z+(build+1)`,
   commits only `pubspec.yaml`, tags `vX.Y.Z` and pushes.
2. `build-windows.yml` builds `ideal-store-pos-X.Y.Z-windows.zip` plus `.zip.sha256` and
   publishes the GitHub release (about 10 minutes).
3. The installed app checks `releases/latest` about 35 s after start. It shows a pop-up,
   downloads the zip, **verifies the SHA-256** (no checksum, no install), and unpacks to
   `<app folder>\_update`.
4. A detached `.bat` then:
   - keeps the old exe as `.old`;
   - copies the new files over and restarts;
   - if the copy fails, restores the old exe.
5. Logs: `%TEMP%\update_debug.log` (check) and `%TEMP%\update_install.log` (install).
6. The admin sidebar's **Check for Updates** calls `checkForUpdate(manual: true)`: it shows
   errors and ignores "Skip this version".

Field issues on shop PCs:
- **Windows Defender false positive.** The unsigned exe is flagged as
  `Trojan:Win32/Sabsik.EN.A!ml` (an ML heuristic).
  - Install the app to `%LocalAppData%\Programs\IdealStorePOS`.
  - Add exclusions: that folder, the process `ideal_store_pos.exe`, and
    `%TEMP%\update_extract` (used by the 1.1.0 updater).
  - Long term: submit each new exe to Microsoft as a false positive, or code-sign it.
    `signing_cert.pfx` is gitignored; never commit it.
- **`CERTIFICATE_VERIFY_FAILED` on fresh Windows.**
  - Dart's `HttpClient` cannot make Windows download missing root CAs.
  - Workaround: run `Invoke-WebRequest https://api.github.com` (and
    `https://release-assets.githubusercontent.com`) once in PowerShell.
  - Planned fix: bundle a CA list (`SecurityContext.setTrustedCertificatesBytes`).
  - Never re-add `badCertificateCallback`.
- **New PCs need the VC++ 2015-2022 x64 runtime.** It is not bundled yet.

## Repo hygiene

- The Windows checkout has `core.autocrlf`, and git stores LF. Diffs that only change line
  endings are noise; check with `git diff --ignore-cr-at-eol`.
- Do not commit:
  - `build/`, `windows_release/`, `*.zip`, `*.ps1` (gitignored);
  - screenshots, `app_*.txt`, Tamil one-off JSON/PS1 scripts in the root.
- Commit only what you changed. `release.ps1` refuses to run when tracked files are dirty.

## Open items (as of v1.1.1, Oct 2026)

- 1.1.2:
  - bundle trusted CA roots for the updater (fresh-laptop TLS failure);
  - optionally bundle the VC++ runtime DLLs in the zip.
- CI "Test & Analyze" fails at the Analyze step only. Locally it is clean; CI uses the latest
  stable Flutter. Fix one of two ways:
  - pin `flutter-version` in both workflows to the local version (`flutter --version`);
  - or use `--no-fatal-warnings` in CI.
- Product data:
  - 38 products are in category "Other";
  - all products have empty HSN and 0% GST (needed only for GST billing);
  - 5 same-name pairs were kept on purpose (different pack sizes or barcodes).
