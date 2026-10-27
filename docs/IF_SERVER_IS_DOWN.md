# If the server is down — what to do

Ideal Store POS keeps its data on Supabase (the "server"). This page says what
to do when it cannot be reached. Keep a printed copy at the counter.

## At the counter (staff) — சர்வர் வேலை செய்யவில்லை என்றால்

**English**
1. Keep billing as usual. Bills are saved on this PC / phone and print normally.
2. The bar at the bottom says *"Server problem — N saved on this device"* or
   *"Offline — N items pending"*. That is fine.
3. Do **not** uninstall the app, clear its data, or sign out — the saved
   bills are inside it.
4. If possible bill from **one** device (the PC): while cut off, the PC and
   the phone cannot see each other's stock.
5. Wait with: new products, customer credit payments, purchase entries.
6. When the server is back, the bills go by themselves (the number goes to 0).

**தமிழ்**
1. வழக்கம் போல பில் போடுங்கள். பில் இந்த கணினி / போனில் சேமிக்கப்படும், பிரிண்ட் ஆகும்.
2. கீழே *"Server problem — N saved on this device"* என்று வரும். பரவாயில்லை.
3. ஆப்பை **அன்இன்ஸ்டால் செய்யவோ, டேட்டாவை அழிக்கவோ, லாக் அவுட் செய்யவோ கூடாது** — சேமித்த பில்கள் அதில் உள்ளன.
4. முடிந்தால் **ஒரே** சாதனத்தில் (கணினியில்) பில் போடுங்கள்.
5. புதிய பொருள், கடன் வசூல், கொள்முதல் பதிவு — சர்வர் வந்த பிறகு செய்யுங்கள்.
6. சர்வர் வந்ததும் பில்கள் தானாக போகும் (எண் 0 ஆகும்).

## The owner — if it lasts more than a day

1. Check https://status.supabase.com — is Supabase itself down?
2. Check the internet provider: open the app on mobile data and on Wi-Fi.
   (In 2025 some Indian providers blocked `supabase.co` for a while.)
3. Your data is safe: the shop PC makes a backup every day
   (**Backup & Restore** shows the last one) and copies it to Google Drive.

## Moving to a new server (only if Supabase is gone for good)

Tested on 27 Oct 2026: a backup restored into a database built from the SQL
files in git matched in every table (stock, batches, sales, cash book, dues).

1. Create a new Supabase project (supabase.com → New project). Note its
   **Project URL** and **anon / publishable key** (Settings → API).
   Never use the *secret* / *service_role* key in the app.
2. In its **SQL Editor**, run every `sql/2026_*.sql` file from the GitHub
   repository, oldest first (`2026_10_audit_fixes.sql` first). Then run
   `sql/verify_schema.sql`.
3. Storage should now show a private bucket named `backups` (step 2 makes
   it). If it does not, create it there: private, name `backups`.
4. **On the shop PC:** app → login screen → **Server settings** (or More →
   Server Settings) → paste the new URL and key → **Test connection** →
   **Use this server** → type SERVER → close and open the app.
5. **Sign up FIRST, as the owner.** The first account on a new server
   becomes the admin. Do this before any staff signs up.
6. **Backup & Restore → Restore** the newest backup file (from the PC's
   backup folder or Google Drive). Type RESTORE.
7. Check: Home figures, Stock, a few customers' credit, supplier dues.
8. Re-create staff logins (Staff screen) and set their PINs.
9. On every phone: **Server settings** → same URL and key → restart →
   sign in. Bills that waited on a phone are sent to the new server.

Time needed: about half a day. Data lost: nothing before the last backup;
bills made offline meanwhile are sent to the new server.
