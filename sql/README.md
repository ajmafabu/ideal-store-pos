# Database — how to apply the October 2026 audit fixes

The 47 historical SQL files now live in `sql/legacy/` for reference only.
**Do not run them again.** The database is brought to one known state by a
single, re-runnable script.

| File | What it does | Changes data? |
|---|---|---|
| `verify_schema.sql` | Health check: every row should say **OK** | No (read-only) |
| `2026_10_audit_fixes.sql` | The migration (schema, money posting, stock/FIFO, GST, reports, security, backup/restore) | Yes — in **one transaction** |
| `data_cleanup_2026_10.sql` | Product data clean-up: reports (part A), helper functions (part B), commented apply steps (part C) | Only part C, line by line |
| `tests/` | Local/CI tests: a fresh database with every business scenario, and an upgrade from the 47 legacy files | Test databases only |

## Apply (about 15 minutes)

1. **Back up first.** Supabase Dashboard → Database → Backups (or `supabase db dump`).
   Also make an in-app backup if the app is running.
2. **Check the current state.** Open the SQL editor, paste `verify_schema.sql`, run it.
   Several rows will say MISSING. That is expected before the migration.
3. **Run the migration.** Paste the whole of `2026_10_audit_fixes.sql` and run it.
   It runs in one transaction: if anything fails, nothing is changed. It is safe
   to run again later.
4. **Verify.** Run `verify_schema.sql` again. Every row must say **OK**.
   `cash book: balance vs journal` may say INFO: that is your opening balance
   or old drift, shown so you can record an opening-balance entry.
5. **Turn off public sign-ups** (recommended): Authentication → Providers → Email →
   *Allow new users to sign up* = off. Staff are created from the app's Staff
   screen, which does not need public sign-up to be open.
   The migration already ignores any role a sign-up tries to claim, so this is a second lock.
6. **Release app 1.1.0 and update every till on the same day:**
   `.\release.ps1 1.1.0` builds the Windows zip and its `.sha256` file through GitHub Actions.
   From 1.1.0 on, money is booked to cash/bank by the database. Old app versions can
   keep billing safely, because the database ignores their duplicate cash entries.
   They should still be updated quickly.
7. **Clean the product data** (`data_cleanup_2026_10.sql`): run part A, fix what it lists,
   then use part C one line at a time.

## What changed for the app

* Sales, purchases, payments, expenses and returns post to cash/bank **inside the
  database** from what is stored on the document. The app no longer writes cash-book
  entries for them.
* Product stock can only change through documents (sale, purchase, return, damaged),
  **Stock In/Out** (`adjust_stock`) or a physical count (`reconcile_stock_with_batches`).
  A plain product update keeps every other change but leaves stock alone.
* Every money- or stock-changing function checks the caller is an **active admin**
  (sales and returns: an active member).
* `restore_backup` and `factory_reset` each run in one transaction.

## Running the tests locally

Requires PostgreSQL 16 on a local socket. Defaults are `/tmp/pg`, port 5433, user postgres.
Override them with `PGHOST`/`PGPORT`/`PGUSER`.

```bash
bash sql/tests/run_local.sh      # fresh DB + scenario tests  → ALL SCENARIO TESTS PASSED
bash sql/tests/run_upgrade.sh    # legacy DB + old data + upgrade → ALL UPGRADE TESTS PASSED
```

CI runs both on every push (`.github/workflows/test.yml`, job *database*).
