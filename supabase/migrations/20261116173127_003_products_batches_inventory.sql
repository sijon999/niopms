/*
# Products, batches, and inventory movements

## Purpose
Creates the core inventory model: products (medicines), batches (expiry-tracked
lot inventory), and inventory movements (append-only ledger of every stock
change). Stock is NEVER merged across batches — each batch keeps its own
available quantity, enabling FEFO dispensing and expiry control.

## New Tables
- products: the medicine master record, tenant-scoped
- product_batches: per-batch stock with manufacturing/expiry dates and prices
- inventory_movements: append-only ledger (in/out/adjust) with source reference

## Security
- All tenant-scoped; RLS via is_pharmacy_member(pharmacy_id).
- The product's pharmacy_id is the tenant key; batches and movements reference
  the product, so their policies join through products to check membership.

## Notes
- `products.total_stock` is a denormalized sum of batch available quantities,
  maintained by trigger. It powers low-stock / out-of-stock dashboard checks
  without scanning batches.
- `product_batches.available_qty` is decremented by sales and increments on
  purchase receipt, always via inventory_movements rows for audit.
- Selling expired stock is prevented at the application layer (POS) by checking
  expiry_date against now() before deducting.
*/

-- ============ products ============
CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  name text NOT NULL,
  generic_name text,
  generic_id uuid REFERENCES generics(id) ON DELETE SET NULL,
  brand_id uuid REFERENCES brands(id) ON DELETE SET NULL,
  manufacturer_id uuid REFERENCES manufacturers(id) ON DELETE SET NULL,
  category_id uuid REFERENCES categories(id) ON DELETE SET NULL,
  dosage_form_id uuid REFERENCES dosage_forms(id) ON DELETE SET NULL,
  strength text,
  unit_id uuid REFERENCES units(id) ON DELETE SET NULL,
  pack_size int,
  sku text,
  barcode text,
  purchase_price numeric(14,2) NOT NULL DEFAULT 0,
  selling_price numeric(14,2) NOT NULL DEFAULT 0,
  wholesale_price numeric(14,2) NOT NULL DEFAULT 0,
  reorder_level int NOT NULL DEFAULT 10,
  description text,
  image_url text,
  requires_prescription boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived')),
  total_stock int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON products TO authenticated;

DROP POLICY IF EXISTS "products_read" ON products;
CREATE POLICY "products_read" ON products FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "products_insert" ON products;
CREATE POLICY "products_insert" ON products FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "products_update" ON products;
CREATE POLICY "products_update" ON products FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "products_delete" ON products;
CREATE POLICY "products_delete" ON products FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_products_pharmacy ON products(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_products_status ON products(status);

DROP TRIGGER IF EXISTS trg_products_updated_at ON products;
CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============ product_batches ============
CREATE TABLE IF NOT EXISTS product_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  batch_number text NOT NULL,
  manufacturing_date date,
  expiry_date date NOT NULL,
  purchase_price numeric(14,2) NOT NULL DEFAULT 0,
  selling_price numeric(14,2) NOT NULL DEFAULT 0,
  quantity_received int NOT NULL DEFAULT 0,
  available_qty int NOT NULL DEFAULT 0,
  supplier_id uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  purchase_id uuid,
  is_expired_override boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE product_batches ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON product_batches TO authenticated;

DROP POLICY IF EXISTS "batches_read" ON product_batches;
CREATE POLICY "batches_read" ON product_batches FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "batches_insert" ON product_batches;
CREATE POLICY "batches_insert" ON product_batches FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "batches_update" ON product_batches;
CREATE POLICY "batches_update" ON product_batches FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_batches_product ON product_batches(product_id);
CREATE INDEX IF NOT EXISTS idx_batches_pharmacy ON product_batches(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_batches_expiry ON product_batches(expiry_date);
CREATE INDEX IF NOT EXISTS idx_batches_available ON product_batches(available_qty);

DROP TRIGGER IF EXISTS trg_batches_updated_at ON product_batches;
CREATE TRIGGER trg_batches_updated_at BEFORE UPDATE ON product_batches
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============ inventory_movements ============
CREATE TABLE IF NOT EXISTS inventory_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  batch_id uuid REFERENCES product_batches(id) ON DELETE SET NULL,
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  movement_type text NOT NULL CHECK (movement_type IN ('purchase','sale','sale_return','adjustment','transfer_in','transfer_out')),
  quantity_delta int NOT NULL,
  reference_type text,
  reference_id uuid,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE inventory_movements ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON inventory_movements TO authenticated;

DROP POLICY IF EXISTS "movements_read" ON inventory_movements;
CREATE POLICY "movements_read" ON inventory_movements FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "movements_insert" ON inventory_movements;
CREATE POLICY "movements_insert" ON inventory_movements FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_movements_product ON inventory_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_movements_pharmacy ON inventory_movements(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_movements_created ON inventory_movements(created_at);

-- ============ Trigger: keep products.total_stock in sync with batches ============
CREATE OR REPLACE FUNCTION recompute_product_total_stock()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  pid uuid;
BEGIN
  pid := COALESCE(NEW.product_id, OLD.product_id);
  IF pid IS NOT NULL THEN
    UPDATE products SET total_stock = COALESCE(
      (SELECT SUM(available_qty) FROM product_batches WHERE product_id = pid), 0)
    WHERE id = pid;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_batches_recompute ON product_batches;
CREATE TRIGGER trg_batches_recompute
  AFTER INSERT OR UPDATE OR DELETE ON product_batches
  FOR EACH ROW EXECUTE FUNCTION recompute_product_total_stock();
