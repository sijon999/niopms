/*
# Tenant / Organization Foundation and Access Control

## Purpose
Multi-tenant foundation: organizations (pharmacies), user profiles, roles,
permissions, member relationships, and subscription management.

## New Tables
- app_users: readable mirror of auth.users with display info + super_admin flag
- pharmacies: the tenant entity, with status workflow and settings jsonb
- roles: role definitions, scoped per pharmacy (null pharmacy_id = platform template)
- permissions: granular permission keys (module + action)
- role_permissions: many-to-many roles <-> permissions
- pharmacy_members: membership of a user in a pharmacy with a role
- subscription_plans: platform plans managed by super admin
- subscriptions: a pharmacy's active subscription

## Security
- RLS enabled on every table
- pharmacies visible to owner, members, and super admins
- app_users self-readable + super admin reads all
- pharmacy_members readable by the pharmacy's members
- roles/role_permissions readable by pharmacy members
- permissions and subscription_plans world-readable to authenticated
- subscriptions visible to owner and members
- Policies created AFTER all tables exist so cross-table references resolve
*/

-- ============ Tables (no policies yet) ============

CREATE TABLE IF NOT EXISTS app_users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  full_name text,
  phone text,
  is_super_admin boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pharmacies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL,
  phone text,
  address_line1 text,
  address_line2 text,
  city text,
  state text,
  postal_code text,
  country text NOT NULL DEFAULT 'United States',
  drug_license_number text,
  tax_id text,
  owner_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','suspended','deactivated')),
  approved_at timestamptz,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  suspended_at timestamptz,
  deactivated_at timestamptz,
  settings jsonb NOT NULL DEFAULT '{"expiry_alert_days":[30,60,90],"tax_rate":0,"currency":"USD","invoice_prefix":"INV"}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  is_system boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, name)
);

CREATE TABLE IF NOT EXISTS permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  module text NOT NULL,
  action text NOT NULL,
  description text
);

CREATE TABLE IF NOT EXISTS role_permissions (
  role_id uuid REFERENCES roles(id) ON DELETE CASCADE,
  permission_id uuid REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS pharmacy_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  invited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  invited_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, user_id)
);

CREATE TABLE IF NOT EXISTS subscription_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text,
  price_monthly numeric(10,2) NOT NULL DEFAULT 0,
  price_yearly numeric(10,2) NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'USD',
  max_users int,
  max_products int,
  features jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  trial_days int NOT NULL DEFAULT 14,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  plan_id uuid NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'trialing'
    CHECK (status IN ('trialing','active','past_due','canceled','expired')),
  billing_cycle text NOT NULL DEFAULT 'monthly'
    CHECK (billing_cycle IN ('monthly','yearly')),
  current_period_start timestamptz NOT NULL DEFAULT now(),
  current_period_end timestamptz,
  trial_ends_at timestamptz,
  canceled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ============ Enable RLS ============
ALTER TABLE app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacies ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

-- ============ Grants ============
GRANT SELECT, UPDATE ON app_users TO authenticated;
GRANT SELECT, INSERT, UPDATE ON pharmacies TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON roles TO authenticated;
GRANT SELECT ON permissions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON role_permissions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON pharmacy_members TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON subscription_plans TO authenticated;
GRANT SELECT, INSERT, UPDATE ON subscriptions TO authenticated;

-- ============ Policies ============

-- app_users
DROP POLICY IF EXISTS "app_users_self_read" ON app_users;
CREATE POLICY "app_users_self_read"
  ON app_users FOR SELECT TO authenticated
  USING (auth.uid() = id OR is_super_admin = true);

DROP POLICY IF EXISTS "app_users_self_update" ON app_users;
CREATE POLICY "app_users_self_update"
  ON app_users FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- pharmacies
DROP POLICY IF EXISTS "pharmacies_read" ON pharmacies;
CREATE POLICY "pharmacies_read"
  ON pharmacies FOR SELECT TO authenticated
  USING (
    owner_id = auth.uid()
    OR EXISTS (SELECT 1 FROM pharmacy_members m WHERE m.pharmacy_id = pharmacies.id AND m.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

DROP POLICY IF EXISTS "pharmacies_insert" ON pharmacies;
CREATE POLICY "pharmacies_insert"
  ON pharmacies FOR INSERT TO authenticated
  WITH CHECK (
    owner_id = auth.uid()
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

DROP POLICY IF EXISTS "pharmacies_update" ON pharmacies;
CREATE POLICY "pharmacies_update"
  ON pharmacies FOR UPDATE TO authenticated
  USING (
    owner_id = auth.uid()
    OR EXISTS (SELECT 1 FROM pharmacy_members m WHERE m.pharmacy_id = pharmacies.id AND m.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  )
  WITH CHECK (
    owner_id = auth.uid()
    OR EXISTS (SELECT 1 FROM pharmacy_members m WHERE m.pharmacy_id = pharmacies.id AND m.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

-- roles
DROP POLICY IF EXISTS "roles_read" ON roles;
CREATE POLICY "roles_read"
  ON roles FOR SELECT TO authenticated
  USING (
    pharmacy_id IS NULL
    OR EXISTS (SELECT 1 FROM pharmacy_members m WHERE m.pharmacy_id = roles.pharmacy_id AND m.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

DROP POLICY IF EXISTS "roles_insert" ON roles;
CREATE POLICY "roles_insert"
  ON roles FOR INSERT TO authenticated
  WITH CHECK (
    pharmacy_id IS NULL
    OR EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = roles.pharmacy_id AND p.owner_id = auth.uid())
  );

DROP POLICY IF EXISTS "roles_update" ON roles;
CREATE POLICY "roles_update"
  ON roles FOR UPDATE TO authenticated
  USING (
    pharmacy_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = roles.pharmacy_id AND p.owner_id = auth.uid())
  )
  WITH CHECK (
    pharmacy_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = roles.pharmacy_id AND p.owner_id = auth.uid())
  );

DROP POLICY IF EXISTS "roles_delete" ON roles;
CREATE POLICY "roles_delete"
  ON roles FOR DELETE TO authenticated
  USING (
    pharmacy_id IS NOT NULL
    AND is_system = false
    AND EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = roles.pharmacy_id AND p.owner_id = auth.uid())
  );

-- permissions (catalog)
DROP POLICY IF EXISTS "permissions_read" ON permissions;
CREATE POLICY "permissions_read"
  ON permissions FOR SELECT TO authenticated USING (true);

-- role_permissions
DROP POLICY IF EXISTS "role_permissions_read" ON role_permissions;
CREATE POLICY "role_permissions_read"
  ON role_permissions FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM roles r WHERE r.id = role_id AND (
      r.pharmacy_id IS NULL
      OR EXISTS (SELECT 1 FROM pharmacy_members m WHERE m.pharmacy_id = r.pharmacy_id AND m.user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
    ))
  );

DROP POLICY IF EXISTS "role_permissions_manage" ON role_permissions;
CREATE POLICY "role_permissions_manage"
  ON role_permissions FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM roles r WHERE r.id = role_id AND r.pharmacy_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = r.pharmacy_id AND p.owner_id = auth.uid()))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM roles r WHERE r.id = role_id AND r.pharmacy_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = r.pharmacy_id AND p.owner_id = auth.uid()))
  );

-- pharmacy_members
DROP POLICY IF EXISTS "members_read" ON pharmacy_members;
CREATE POLICY "members_read"
  ON pharmacy_members FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = pharmacy_members.pharmacy_id AND p.owner_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM pharmacy_members m2
      WHERE m2.pharmacy_id = pharmacy_members.pharmacy_id AND m2.user_id = auth.uid()
    )
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

DROP POLICY IF EXISTS "members_insert" ON pharmacy_members;
CREATE POLICY "members_insert"
  ON pharmacy_members FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = pharmacy_members.pharmacy_id AND p.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

DROP POLICY IF EXISTS "members_update" ON pharmacy_members;
CREATE POLICY "members_update"
  ON pharmacy_members FOR UPDATE TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = pharmacy_members.pharmacy_id AND p.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  )
  WITH CHECK (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = pharmacy_members.pharmacy_id AND p.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

DROP POLICY IF EXISTS "members_delete" ON pharmacy_members;
CREATE POLICY "members_delete"
  ON pharmacy_members FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = pharmacy_members.pharmacy_id AND p.owner_id = auth.uid())
    OR user_id = auth.uid()
  );

-- subscription_plans
DROP POLICY IF EXISTS "plans_read" ON subscription_plans;
CREATE POLICY "plans_read"
  ON subscription_plans FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "plans_write" ON subscription_plans;
CREATE POLICY "plans_write"
  ON subscription_plans FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true));

-- subscriptions
DROP POLICY IF EXISTS "subs_read" ON subscriptions;
CREATE POLICY "subs_read"
  ON subscriptions FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = subscriptions.pharmacy_id AND p.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM pharmacy_members m WHERE m.pharmacy_id = subscriptions.pharmacy_id AND m.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

DROP POLICY IF EXISTS "subs_owner_write" ON subscriptions;
CREATE POLICY "subs_owner_write"
  ON subscriptions FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = subscriptions.pharmacy_id AND p.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM pharmacies p WHERE p.id = subscriptions.pharmacy_id AND p.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

-- ============ Indexes ============
CREATE INDEX IF NOT EXISTS idx_pharmacies_owner ON pharmacies(owner_id);
CREATE INDEX IF NOT EXISTS idx_pharmacies_status ON pharmacies(status);
CREATE INDEX IF NOT EXISTS idx_members_user ON pharmacy_members(user_id);
CREATE INDEX IF NOT EXISTS idx_members_pharmacy ON pharmacy_members(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_roles_pharmacy ON roles(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_pharmacy ON subscriptions(pharmacy_id);

-- ============ Seed permissions ============
DO $$
DECLARE
  perms text[][] := ARRAY[
    ['dashboard.view','Dashboard','view','View the main dashboard'],
    ['pos.view','POS','view','Access the point of sale'],
    ['pos.refund','POS','approve','Process a refund at POS'],
    ['pos.discount','POS','approve','Apply invoice-level discounts above threshold'],
    ['products.view','Products','view','View product list and details'],
    ['products.create','Products','create','Add a new product'],
    ['products.edit','Products','edit','Edit a product'],
    ['products.delete','Products','delete','Delete or archive a product'],
    ['products.export','Products','export','Export product data'],
    ['categories.view','Categories','view','View categories'],
    ['categories.create','Categories','create','Create a category'],
    ['categories.edit','Categories','edit','Edit a category'],
    ['categories.delete','Categories','delete','Delete a category'],
    ['suppliers.view','Suppliers','view','View suppliers'],
    ['suppliers.create','Suppliers','create','Create a supplier'],
    ['suppliers.edit','Suppliers','edit','Edit a supplier'],
    ['suppliers.delete','Suppliers','delete','Delete a supplier'],
    ['customers.view','Customers','view','View customers'],
    ['customers.create','Customers','create','Create a customer'],
    ['customers.edit','Customers','edit','Edit a customer'],
    ['customers.delete','Customers','delete','Delete a customer'],
    ['purchases.view','Purchases','view','View purchase orders'],
    ['purchases.create','Purchases','create','Create a purchase order'],
    ['purchases.edit','Purchases','edit','Edit a purchase order'],
    ['purchases.delete','Purchases','delete','Delete a purchase order'],
    ['purchases.approve','Purchases','approve','Approve a purchase order'],
    ['inventory.view','Inventory','view','View inventory'],
    ['inventory.adjust','Stock Adjustment','edit','Adjust stock levels'],
    ['expiry.view','Expiry Management','view','View expiry information'],
    ['sales.view','Sales','view','View sales'],
    ['sales.create','Sales','create','Create a sale'],
    ['sales.edit','Sales','edit','Edit a sale'],
    ['sales.delete','Sales','delete','Delete or cancel a sale'],
    ['sales.export','Sales','export','Export sales data'],
    ['sales.print','Sales','print','Print or reprint invoices'],
    ['sales_returns.view','Sales Returns','view','View sales returns'],
    ['sales_returns.create','Sales Returns','create','Create a sales return'],
    ['sales_returns.approve','Sales Returns','approve','Approve a sales return'],
    ['prescriptions.view','Prescriptions','view','View prescriptions'],
    ['prescriptions.create','Prescriptions','create','Create a prescription record'],
    ['prescriptions.edit','Prescriptions','edit','Edit a prescription record'],
    ['expenses.view','Expenses','view','View expenses'],
    ['expenses.create','Expenses','create','Create an expense'],
    ['expenses.edit','Expenses','edit','Edit an expense'],
    ['expenses.delete','Expenses','delete','Delete an expense'],
    ['reports.view','Reports','view','View reports'],
    ['reports.export','Reports','export','Export reports'],
    ['employees.view','Employees','view','View employees'],
    ['employees.create','Employees','create','Invite an employee'],
    ['employees.edit','Employees','edit','Edit an employee role'],
    ['employees.delete','Employees','delete','Remove an employee'],
    ['settings.view','Settings','view','View settings'],
    ['settings.edit','Settings','edit','Edit pharmacy settings']
  ];
  p text[];
BEGIN
  FOREACH p SLICE 1 IN ARRAY perms LOOP
    INSERT INTO permissions (key, module, action, description)
    VALUES (p[1], p[2], p[3], p[4])
    ON CONFLICT (key) DO NOTHING;
  END LOOP;
END $$;

-- ============ Seed platform-default role templates ============
DO $$
DECLARE
  owner_role_id uuid;
  manager_role_id uuid;
  pharmacist_role_id uuid;
  sales_role_id uuid;
  inventory_role_id uuid;
  accountant_role_id uuid;
BEGIN
  INSERT INTO roles (pharmacy_id, name, description, is_system)
  VALUES (NULL, 'Owner', 'Full access — pharmacy owner', true)
  ON CONFLICT (pharmacy_id, name) DO NOTHING;

  SELECT id INTO owner_role_id FROM roles WHERE pharmacy_id IS NULL AND name = 'Owner';

  INSERT INTO role_permissions (role_id, permission_id)
  SELECT owner_role_id, id FROM permissions
  ON CONFLICT DO NOTHING;

  INSERT INTO roles (pharmacy_id, name, description, is_system)
  VALUES
    (NULL, 'Manager', 'Manage most operations except billing/owner settings', true),
    (NULL, 'Pharmacist', 'POS, prescriptions, inventory view', true),
    (NULL, 'Salesperson', 'POS and customer management', true),
    (NULL, 'Inventory Manager', 'Inventory, purchases, stock adjustments', true),
    (NULL, 'Accountant', 'Expenses, reports, accounting view', true)
  ON CONFLICT (pharmacy_id, name) DO NOTHING;

  SELECT id INTO manager_role_id FROM roles WHERE pharmacy_id IS NULL AND name = 'Manager';
  SELECT id INTO pharmacist_role_id FROM roles WHERE pharmacy_id IS NULL AND name = 'Pharmacist';
  SELECT id INTO sales_role_id FROM roles WHERE pharmacy_id IS NULL AND name = 'Salesperson';
  SELECT id INTO inventory_role_id FROM roles WHERE pharmacy_id IS NULL AND name = 'Inventory Manager';
  SELECT id INTO accountant_role_id FROM roles WHERE pharmacy_id IS NULL AND name = 'Accountant';

  INSERT INTO role_permissions (role_id, permission_id)
  SELECT manager_role_id, id FROM permissions
  WHERE key NOT IN ('settings.edit','employees.delete')
  ON CONFLICT DO NOTHING;

  INSERT INTO role_permissions (role_id, permission_id)
  SELECT pharmacist_role_id, id FROM permissions
  WHERE key IN (
    'dashboard.view','pos.view','pos.discount','pos.refund',
    'products.view','customers.view','customers.create','customers.edit',
    'prescriptions.view','prescriptions.create','prescriptions.edit',
    'sales.view','sales.create','sales.print',
    'sales_returns.view','sales_returns.create','sales_returns.approve',
    'inventory.view','expiry.view','reports.view'
  )
  ON CONFLICT DO NOTHING;

  INSERT INTO role_permissions (role_id, permission_id)
  SELECT sales_role_id, id FROM permissions
  WHERE key IN (
    'dashboard.view','pos.view','pos.discount',
    'products.view','customers.view','customers.create','customers.edit',
    'sales.view','sales.create','sales.print',
    'prescriptions.view'
  )
  ON CONFLICT DO NOTHING;

  INSERT INTO role_permissions (role_id, permission_id)
  SELECT inventory_role_id, id FROM permissions
  WHERE key IN (
    'dashboard.view',
    'products.view','products.create','products.edit','products.export',
    'categories.view','categories.create','categories.edit',
    'suppliers.view','suppliers.create','suppliers.edit',
    'purchases.view','purchases.create','purchases.edit','purchases.approve',
    'inventory.view','inventory.adjust','expiry.view',
    'reports.view','reports.export'
  )
  ON CONFLICT DO NOTHING;

  INSERT INTO role_permissions (role_id, permission_id)
  SELECT accountant_role_id, id FROM permissions
  WHERE key IN (
    'dashboard.view',
    'sales.view','sales.export','sales_returns.view',
    'purchases.view','expenses.view','expenses.create','expenses.edit','expenses.delete',
    'reports.view','reports.export','customers.view'
  )
  ON CONFLICT DO NOTHING;
END $$;

-- ============ Seed default subscription plans ============
DO $$
BEGIN
  INSERT INTO subscription_plans (name, description, price_monthly, price_yearly, max_users, max_products, features, trial_days)
  VALUES
    ('Starter', 'Single location, up to 3 staff', 29.00, 290.00, 3, 2000, '{"pos":true,"inventory":true,"reports":false,"accounting":false}'::jsonb, 14),
    ('Pro', 'Most pharmacies — full reporting + accounting', 79.00, 790.00, 15, 20000, '{"pos":true,"inventory":true,"reports":true,"accounting":true}'::jsonb, 14),
    ('Enterprise', 'Multiple locations, unlimited', 199.00, 1990.00, NULL, NULL, '{"pos":true,"inventory":true,"reports":true,"accounting":true,"multi_location":true}'::jsonb, 30)
  ON CONFLICT (name) DO NOTHING;
END $$;

-- ============ updated_at trigger ============
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pharmacies_updated_at ON pharmacies;
CREATE TRIGGER trg_pharmacies_updated_at BEFORE UPDATE ON pharmacies
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_app_users_updated_at ON app_users;
CREATE TRIGGER trg_app_users_updated_at BEFORE UPDATE ON app_users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_roles_updated_at ON roles;
CREATE TRIGGER trg_roles_updated_at BEFORE UPDATE ON roles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_members_updated_at ON pharmacy_members;
CREATE TRIGGER trg_members_updated_at BEFORE UPDATE ON pharmacy_members
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_subscriptions_updated_at ON subscriptions;
CREATE TRIGGER trg_subscriptions_updated_at BEFORE UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_plans_updated_at ON subscription_plans;
CREATE TRIGGER trg_plans_updated_at BEFORE UPDATE ON subscription_plans
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
