/*
# Sales, purchases, expenses, and payments

## Purpose
The financial transaction core: purchase orders (stock-in), sales invoices
(POS output), sale returns, expenses, and payments. Each links back to the
tenant and carries line items. Payments support partial/due settlement for
both customers and suppliers.

## New Tables
- sales: invoice header (customer, totals, discount, tax, paid, due, status)
- sale_items: per-line product/batch/qty/price/discount
- sale_payments: payments against a sale (cash, card, mobile, transfer)
- sale_returns: return header referencing a sale
- sale_return_items: per-line returned qty
- purchases: purchase order header (supplier, totals, status)
- purchase_items: per-line product/batch/qty/cost
- expenses: operating expenses (rent, utilities, salaries, other)
- prescriptions: prescription records optionally linked to a sale

## Security
- All tenant-scoped via is_pharmacy_member(pharmacy_id).
- Insert/update/delete gated by membership.

## Notes
- Sales deduct batch available_qty and write inventory_movements via the
  application layer (edge function or client transaction). The schema itself
  only stores the data; the atomic checkout flow lives in the POS code.
- customer/supplier current_balance is updated by the application after a
  sale/payment/return commits.
- sale number / invoice number is generated per tenant with an invoice prefix
  from pharmacies.settings.
*/

-- ============ sales ============
CREATE TABLE IF NOT EXISTS sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  invoice_number text NOT NULL,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  sold_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  sale_date timestamptz NOT NULL DEFAULT now(),
  subtotal numeric(14,2) NOT NULL DEFAULT 0,
  discount_amount numeric(14,2) NOT NULL DEFAULT 0,
  tax_amount numeric(14,2) NOT NULL DEFAULT 0,
  total numeric(14,2) NOT NULL DEFAULT 0,
  paid_amount numeric(14,2) NOT NULL DEFAULT 0,
  due_amount numeric(14,2) NOT NULL DEFAULT 0,
  change_amount numeric(14,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'completed'
    CHECK (status IN ('held','completed','canceled','refunded')),
  prescription_id uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, invoice_number)
);

ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON sales TO authenticated;

DROP POLICY IF EXISTS "sales_read" ON sales;
CREATE POLICY "sales_read" ON sales FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sales_insert" ON sales;
CREATE POLICY "sales_insert" ON sales FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sales_update" ON sales;
CREATE POLICY "sales_update" ON sales FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sales_delete" ON sales;
CREATE POLICY "sales_delete" ON sales FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_sales_pharmacy ON sales(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(sale_date);
CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id);
CREATE INDEX IF NOT EXISTS idx_sales_status ON sales(status);
CREATE INDEX IF NOT EXISTS idx_sales_invoice ON sales(invoice_number);

DROP TRIGGER IF EXISTS trg_sales_updated_at ON sales;
CREATE TRIGGER trg_sales_updated_at BEFORE UPDATE ON sales
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============ sale_items ============
CREATE TABLE IF NOT EXISTS sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  batch_id uuid REFERENCES product_batches(id) ON DELETE SET NULL,
  quantity int NOT NULL DEFAULT 1,
  unit_price numeric(14,2) NOT NULL DEFAULT 0,
  discount_amount numeric(14,2) NOT NULL DEFAULT 0,
  tax_amount numeric(14,2) NOT NULL DEFAULT 0,
  line_total numeric(14,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON sale_items TO authenticated;

DROP POLICY IF EXISTS "sale_items_read" ON sale_items;
CREATE POLICY "sale_items_read" ON sale_items FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_items_insert" ON sale_items;
CREATE POLICY "sale_items_insert" ON sale_items FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_items_update" ON sale_items;
CREATE POLICY "sale_items_update" ON sale_items FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_items_delete" ON sale_items;
CREATE POLICY "sale_items_delete" ON sale_items FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items(product_id);

-- ============ sale_payments ============
CREATE TABLE IF NOT EXISTS sale_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  amount numeric(14,2) NOT NULL DEFAULT 0,
  method text NOT NULL CHECK (method IN ('cash','card','mobile','bank_transfer','credit')),
  reference text,
  paid_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE sale_payments ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON sale_payments TO authenticated;

DROP POLICY IF EXISTS "sale_payments_read" ON sale_payments;
CREATE POLICY "sale_payments_read" ON sale_payments FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_payments_insert" ON sale_payments;
CREATE POLICY "sale_payments_insert" ON sale_payments FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_payments_update" ON sale_payments;
CREATE POLICY "sale_payments_update" ON sale_payments FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_payments_delete" ON sale_payments;
CREATE POLICY "sale_payments_delete" ON sale_payments FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_sale_payments_sale ON sale_payments(sale_id);

-- ============ sale_returns ============
CREATE TABLE IF NOT EXISTS sale_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  sale_id uuid NOT NULL REFERENCES sales(id) ON DELETE RESTRICT,
  return_number text NOT NULL,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  total numeric(14,2) NOT NULL DEFAULT 0,
  reason text,
  returned_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, return_number)
);

ALTER TABLE sale_returns ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON sale_returns TO authenticated;

DROP POLICY IF EXISTS "sale_returns_read" ON sale_returns;
CREATE POLICY "sale_returns_read" ON sale_returns FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_returns_insert" ON sale_returns;
CREATE POLICY "sale_returns_insert" ON sale_returns FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_returns_update" ON sale_returns;
CREATE POLICY "sale_returns_update" ON sale_returns FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_returns_delete" ON sale_returns;
CREATE POLICY "sale_returns_delete" ON sale_returns FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_sale_returns_sale ON sale_returns(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_returns_pharmacy ON sale_returns(pharmacy_id);

DROP TRIGGER IF EXISTS trg_sale_returns_updated_at ON sale_returns;
CREATE TRIGGER trg_sale_returns_updated_at BEFORE UPDATE ON sale_returns
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============ sale_return_items ============
CREATE TABLE IF NOT EXISTS sale_return_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_return_id uuid NOT NULL REFERENCES sale_returns(id) ON DELETE CASCADE,
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  sale_item_id uuid REFERENCES sale_items(id) ON DELETE SET NULL,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  batch_id uuid REFERENCES product_batches(id) ON DELETE SET NULL,
  quantity int NOT NULL DEFAULT 1,
  unit_price numeric(14,2) NOT NULL DEFAULT 0,
  line_total numeric(14,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE sale_return_items ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON sale_return_items TO authenticated;

DROP POLICY IF EXISTS "sale_return_items_read" ON sale_return_items;
CREATE POLICY "sale_return_items_read" ON sale_return_items FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_return_items_insert" ON sale_return_items;
CREATE POLICY "sale_return_items_insert" ON sale_return_items FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_return_items_update" ON sale_return_items;
CREATE POLICY "sale_return_items_update" ON sale_return_items FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "sale_return_items_delete" ON sale_return_items;
CREATE POLICY "sale_return_items_delete" ON sale_return_items FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_sale_return_items_return ON sale_return_items(sale_return_id);

-- ============ purchases ============
CREATE TABLE IF NOT EXISTS purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  purchase_number text NOT NULL,
  supplier_id uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  purchased_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  purchase_date timestamptz NOT NULL DEFAULT now(),
  subtotal numeric(14,2) NOT NULL DEFAULT 0,
  discount_amount numeric(14,2) NOT NULL DEFAULT 0,
  tax_amount numeric(14,2) NOT NULL DEFAULT 0,
  total numeric(14,2) NOT NULL DEFAULT 0,
  paid_amount numeric(14,2) NOT NULL DEFAULT 0,
  due_amount numeric(14,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','ordered','received','canceled')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pharmacy_id, purchase_number)
);

ALTER TABLE purchases ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON purchases TO authenticated;

DROP POLICY IF EXISTS "purchases_read" ON purchases;
CREATE POLICY "purchases_read" ON purchases FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "purchases_insert" ON purchases;
CREATE POLICY "purchases_insert" ON purchases FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "purchases_update" ON purchases;
CREATE POLICY "purchases_update" ON purchases FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "purchases_delete" ON purchases;
CREATE POLICY "purchases_delete" ON purchases FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_purchases_pharmacy ON purchases(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON purchases(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchases_date ON purchases(purchase_date);
CREATE INDEX IF NOT EXISTS idx_purchases_status ON purchases(status);

DROP TRIGGER IF EXISTS trg_purchases_updated_at ON purchases;
CREATE TRIGGER trg_purchases_updated_at BEFORE UPDATE ON purchases
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============ purchase_items ============
CREATE TABLE IF NOT EXISTS purchase_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id uuid NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  batch_id uuid REFERENCES product_batches(id) ON DELETE SET NULL,
  batch_number text,
  manufacturing_date date,
  expiry_date date,
  quantity int NOT NULL DEFAULT 1,
  unit_cost numeric(14,2) NOT NULL DEFAULT 0,
  discount_amount numeric(14,2) NOT NULL DEFAULT 0,
  tax_amount numeric(14,2) NOT NULL DEFAULT 0,
  line_total numeric(14,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE purchase_items ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON purchase_items TO authenticated;

DROP POLICY IF EXISTS "purchase_items_read" ON purchase_items;
CREATE POLICY "purchase_items_read" ON purchase_items FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "purchase_items_insert" ON purchase_items;
CREATE POLICY "purchase_items_insert" ON purchase_items FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "purchase_items_update" ON purchase_items;
CREATE POLICY "purchase_items_update" ON purchase_items FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "purchase_items_delete" ON purchase_items;
CREATE POLICY "purchase_items_delete" ON purchase_items FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purchase_items_product ON purchase_items(product_id);

-- ============ expenses ============
CREATE TABLE IF NOT EXISTS expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  category text NOT NULL,
  description text,
  amount numeric(14,2) NOT NULL DEFAULT 0,
  expense_date timestamptz NOT NULL DEFAULT now(),
  paid_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reference text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON expenses TO authenticated;

DROP POLICY IF EXISTS "expenses_read" ON expenses;
CREATE POLICY "expenses_read" ON expenses FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "expenses_insert" ON expenses;
CREATE POLICY "expenses_insert" ON expenses FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "expenses_update" ON expenses;
CREATE POLICY "expenses_update" ON expenses FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "expenses_delete" ON expenses;
CREATE POLICY "expenses_delete" ON expenses FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_expenses_pharmacy ON expenses(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(expense_date);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category);

DROP TRIGGER IF EXISTS trg_expenses_updated_at ON expenses;
CREATE TRIGGER trg_expenses_updated_at BEFORE UPDATE ON expenses
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============ prescriptions ============
CREATE TABLE IF NOT EXISTS prescriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  prescriber_name text,
  prescriber_license text,
  prescription_date date NOT NULL DEFAULT CURRENT_DATE,
  image_url text,
  notes text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','dispensed','expired','canceled')),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON prescriptions TO authenticated;

DROP POLICY IF EXISTS "prescriptions_read" ON prescriptions;
CREATE POLICY "prescriptions_read" ON prescriptions FOR SELECT TO authenticated
  USING (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "prescriptions_insert" ON prescriptions;
CREATE POLICY "prescriptions_insert" ON prescriptions FOR INSERT TO authenticated
  WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "prescriptions_update" ON prescriptions;
CREATE POLICY "prescriptions_update" ON prescriptions FOR UPDATE TO authenticated
  USING (is_pharmacy_member(pharmacy_id)) WITH CHECK (is_pharmacy_member(pharmacy_id));
DROP POLICY IF EXISTS "prescriptions_delete" ON prescriptions;
CREATE POLICY "prescriptions_delete" ON prescriptions FOR DELETE TO authenticated
  USING (is_pharmacy_member(pharmacy_id));

CREATE INDEX IF NOT EXISTS idx_prescriptions_pharmacy ON prescriptions(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_prescriptions_customer ON prescriptions(customer_id);

DROP TRIGGER IF EXISTS trg_prescriptions_updated_at ON prescriptions;
CREATE TRIGGER trg_prescriptions_updated_at BEFORE UPDATE ON prescriptions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Link sales.prescription_id to prescriptions now that the table exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'sales_prescription_id_fkey' AND table_name = 'sales'
  ) THEN
    ALTER TABLE sales ADD CONSTRAINT sales_prescription_id_fkey
      FOREIGN KEY (prescription_id) REFERENCES prescriptions(id) ON DELETE SET NULL;
  END IF;
END $$;
