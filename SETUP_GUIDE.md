# Wholesale Market App - Setup Guide

## Step 1: Create Supabase Project

1. Go to https://supabase.com and sign up
2. Click "New Project"
3. Enter project name: `wholesale-market`
4. Set database password (save it!)
5. Choose region closest to you
6. Click "Create new project"

## Step 2: Run SQL Setup

1. In Supabase dashboard, go to **SQL Editor**
2. Copy the entire content from `sql/setup.sql`
3. Paste and click **Run**
4. All tables, indexes, and RLS policies will be created

## Step 3: Get API Keys

1. Go to **Settings** → **API**
2. Copy these two values:
   - **Project URL** (looks like: `https://xxxx.supabase.co`)
   - **Anon/Public Key** (long string starting with `eyJ...`)

## Step 4: Update Flutter Config

Open `lib/config/supabase_config.dart` and replace:

```dart
static const String supabaseUrl = 'YOUR_SUPABASE_URL';      // ← Paste Project URL
static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';  // ← Paste Anon Key
```

## Step 5: Create First Admin User

1. Run the app on your device/emulator
2. Sign up with your email
3. Go to Supabase Dashboard → **Table Editor** → **profiles**
4. Find your row and change `role` from `staff` to `admin`
5. Refresh the app - you should now see the Admin dashboard

## Step 6: Add Staff

As admin, you can now:
1. Sign up new users with their email
2. Change their role to `staff` in the profiles table
3. Or use the app's staff management (coming in Phase 6)

## Folder Structure

```
wholesale_market/
├── lib/
│   ├── config/          → Supabase credentials
│   ├── models/          → Data models (Profile, etc.)
│   ├── router/          → GoRouter setup + auth routing
│   ├── screens/
│   │   ├── auth/        → Login screen
│   │   ├── admin/       → Admin bottom nav shell
│   │   ├── staff/       → Staff bottom nav shell
│   │   └── shared/      → Dashboard, Inventory, Sales
│   ├── services/        → AuthService, SupabaseService
│   ├── widgets/         → Reusable widgets
│   └── utils/           → Helpers
├── sql/
│   └── setup.sql        → Database setup script
└── pubspec.yaml         → Dependencies
```

## Commands

```bash
# Run app
flutter run

# Build APK
flutter build apk

# Build iOS
flutter build ios
```
