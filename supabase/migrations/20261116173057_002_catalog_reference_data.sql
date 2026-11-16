/*
# Catalog: tenant-scoped reference data

## Purpose
Creates the reference entities a pharmacy manages before/alongside products:
categories, generic names, manufacturers, brands, dosage forms, units,
suppliers, and customers. All are scoped to a single pharmacy via pharmacy_id
and isolated by RLS through pharmacy_members.

## New Tables
- categories, generics, manufacturers, brands, dosage_forms, units
- suppliers: supplier accounts with outstanding balance tracking
- customers: customer accounts with outstanding balance tracking

## Security
- RLS on all tables; pharmacy members (or owner) can access. Access is gated
  by is_pharmacy_member(pharmacy_id), a SECURITY DEFINER helper.
*/

-- ============ Helper function ============
CREATE OR REPLACE FUNCTION is_pharmacy_member(p_pharmacy_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM pharmacies p WHERE p.id = p_pharmacy_id AND p.owner_id = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM pharmacy_members m
    WHERE m.pharmacy_id = p_pharmacy_id AND m.user_id = auth.uid() AND m.is_active = true
  );
$$;

REVOKE EXECUTE ON FUNCTION is_pharmacy_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_pharmacy_member(uuid) TO authenticated;

-- ============ Tables ============

CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, name)
);

CREATE TABLE IF NOT EXISTS generics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, name)
);

CREATE TABLE IF NOT EXISTS manufacturers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  contact_person text,
  phone text,
  email text,
  address text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, name)
);

CREATE TABLE IF NOT EXISTS brands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  manufacturer_id uuid REFERENCES manufacturers(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, name)
);

CREATE TABLE IF NOT EXISTS dosage_forms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, name)
);

CREATE TABLE IF NOT EXISTS units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  abbreviation text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, name)
);

CREATE TABLE IF NOT EXISTS suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  contact_person text,
  phone text,
  email text,
  address text,
  tax_id text,
  opening_balance numeric(14,2) NOT NULL DEFAULT 0,
  current_balance numeric(14,2) NOT NULL DEFAULT 0,
  notes text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  phone text,
  email text,
  address text,
  date_of_birth date,
  gender text CHECK (gender IN ('male','female','other')),
  opening_balance numeric(14,2) NOT NULL DEFAULT 0,
  current_balance numeric(14,2) NOT NULL DEFAULT 0,
  notes text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ============ Enable RLS ============
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE generics ENABLE ROW LEVEL SECURITY;
ALTER TABLE manufacturers ENABLE ROW LEVEL SECURITY;
ALTER TABLE brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE dosage_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE units ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

-- ============ Grants ============
GRANT SELECT, INSERT, UPDATE, DELETE ON categories TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON generics TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON manufacturers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON brands TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON dosage_forms TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON units TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON suppliers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON customers TO authenticated;

-- ============ Policies ============
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['categories','generics','manufacturers','brands','dosage_forms','units','suppliers','customers'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_read', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO authenticated USING (is_pharmacy_member(pharmacy_id));', t || '_read', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_insert', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR INSERT TO authenticated WITH CHECK (is_pharmacy_member(pharmacy_id));', t || '_insert', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_update', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR UPDATE TO authenticated USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));', t || '_update', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_delete', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR DELETE TO authenticated USING (is_pharmacy_member(pharmacy_id));', t || '_delete', t);
  END LOOP;
END $$;

-- ============ Indexes ============
CREATE INDEX IF NOT EXISTS idx_categories_pharmacy ON categories(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_generics_pharmacy ON generics(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_manufacturers_pharmacy ON manufacturers(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_brands_pharmacy ON brands(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_dosage_forms_pharmacy ON dosage_forms(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_units_pharmacy ON units(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_pharmacy ON suppliers(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_customers_pharmacy ON customers(pharmacy_id);

-- ============ Triggers ============
DROP TRIGGER IF EXISTS trg_categories_updated_at ON categories;
CREATE TRIGGER trg_categories_updated_at BEFORE UPDATE ON categories
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_generics_updated_at ON generics;
CREATE TRIGGER trg_generics_updated_at BEFORE UPDATE ON generics
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_manufacturers_updated_at ON manufacturers;
CREATE TRIGGER trg_manufacturers_updated_at BEFORE UPDATE ON manufacturers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_brands_updated_at ON brands;
CREATE TRIGGER trg_brands_updated_at BEFORE UPDATE ON brands
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_dosage_forms_updated_at ON dosage_forms;
CREATE TRIGGER trg_dosage_forms_updated_at BEFORE UPDATE ON dosage_forms
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_units_updated_at ON units;
CREATE TRIGGER trg_units_updated_at BEFORE UPDATE ON units
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_suppliers_updated_at ON suppliers;
CREATE TRIGGER trg_suppliers_updated_at BEFORE UPDATE ON suppliers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_customers_updated_at ON customers;
CREATE TRIGGER trg_customers_updated_at BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
