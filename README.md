# PharmOS

PharmOS is a Next.js application using Supabase Auth and PostgreSQL for a
multi-tenant pharmacy management system.

## Local setup

1. Copy `.env.example` to `.env.local`.
2. Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` from the
   Supabase project settings. Never put a service-role key in a `NEXT_PUBLIC_`
   variable or browser code.
3. For a new database, apply migrations in filename order. For an existing
   database, compare its migration history and apply only reviewed migrations
   that are not already present. Registration, tenant permissions, and
   inventory operations depend on their corresponding migrations.
4. Install dependencies with `npm ci`.
5. Start the app with `npm run dev`.

The database schema is maintained as SQL migrations. Applying them to a remote
project is a separate deployment step; configuring the project URL and key does
not apply migrations automatically.

## Super Admin access

The current profile schema uses `app_users.is_super_admin` (a protected
database flag), not a `role` text column. Only trusted database administrators
should grant this flag; authenticated users can update their own profile name
and phone but cannot update the flag. The `/admin` pharmacy-management screen
is additionally protected by PostgreSQL RLS and the pharmacy status guard.

## Pharmacy registration

Public signup creates a normal user account only. Signed-in account owners can
submit a pharmacy application from `/dashboard/profile`; applications remain
pending until a Super Admin reviews them at `/admin`. Rejected owners can update
and resubmit the same application. Database access is enforced by RLS and the
`submit_pharmacy_registration` function. Apply migration
`20261117004000_009_owner_pharmacy_registration.sql` and the follow-up
`20261117005000_010_pharmacy_rejection_reason_guard.sql` before deploying this UI.
Optional logos are stored in the public `pharmacy-logos` bucket (upload is
restricted to the authenticated owner's registration path).

## Medicines and inventory

Approved pharmacy users with the relevant role permissions can manage the
medicine catalog and categories from the dashboard. Inventory is tracked by
expiry-dated batch. Opening stock and adjustments are recorded through the
`create_inventory_batch` and `adjust_inventory_batch` database functions; the
inventory movement ledger is read-only to browser clients. Migration
`20261117008000_013_remove_legacy_inventory_policies.sql` removes legacy
member-wide inventory policies and direct movement-write privileges.

The ERP is being delivered in phases. Sales/POS, purchasing, finance,
employees, reporting, and other not-yet-built modules are not available yet.
