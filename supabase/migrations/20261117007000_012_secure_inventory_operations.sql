ALTER TABLE public.product_batches
  ADD COLUMN IF NOT EXISTS mrp numeric(14,2) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.recompute_product_total_stock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  product_uuid uuid;
BEGIN
  product_uuid := COALESCE(NEW.product_id, OLD.product_id);
  IF product_uuid IS NOT NULL THEN
    UPDATE public.products
    SET total_stock = COALESCE(
      (SELECT SUM(available_qty) FROM public.product_batches WHERE product_id = product_uuid),
      0
    )
    WHERE id = product_uuid;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_product_tenant_references()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (NEW.generic_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.generics WHERE id = NEW.generic_id AND pharmacy_id = NEW.pharmacy_id
  )) OR (NEW.brand_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.brands WHERE id = NEW.brand_id AND pharmacy_id = NEW.pharmacy_id
  )) OR (NEW.manufacturer_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.manufacturers WHERE id = NEW.manufacturer_id AND pharmacy_id = NEW.pharmacy_id
  )) OR (NEW.category_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.categories WHERE id = NEW.category_id AND pharmacy_id = NEW.pharmacy_id
  )) OR (NEW.dosage_form_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.dosage_forms WHERE id = NEW.dosage_form_id AND pharmacy_id = NEW.pharmacy_id
  )) OR (NEW.unit_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.units WHERE id = NEW.unit_id AND pharmacy_id = NEW.pharmacy_id
  )) THEN
    RAISE EXCEPTION 'Product catalog references must belong to the same pharmacy';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_product_tenant_references() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_guard_product_tenant_references ON public.products;
CREATE TRIGGER trg_guard_product_tenant_references
  BEFORE INSERT OR UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.guard_product_tenant_references();

CREATE OR REPLACE FUNCTION public.prevent_product_history_deletion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.inventory_movements WHERE product_id = OLD.id)
    OR EXISTS (SELECT 1 FROM public.product_batches WHERE product_id = OLD.id AND available_qty > 0) THEN
    RAISE EXCEPTION 'A medicine with stock or movement history cannot be deleted; archive it instead';
  END IF;
  RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION public.prevent_product_history_deletion() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_prevent_product_history_deletion ON public.products;
CREATE TRIGGER trg_prevent_product_history_deletion
  BEFORE DELETE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.prevent_product_history_deletion();

CREATE OR REPLACE FUNCTION public.guard_batch_tenant_references()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.products
    WHERE id = NEW.product_id AND pharmacy_id = NEW.pharmacy_id
  ) OR (NEW.supplier_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.suppliers
    WHERE id = NEW.supplier_id AND pharmacy_id = NEW.pharmacy_id
  )) THEN
    RAISE EXCEPTION 'Batch product and supplier must belong to the same pharmacy';
  END IF;

  IF NEW.expiry_date <= CURRENT_DATE
    OR (NEW.manufacturing_date IS NOT NULL AND NEW.manufacturing_date > NEW.expiry_date)
    OR NEW.purchase_price < 0
    OR NEW.selling_price < 0
    OR NEW.mrp < 0
    OR NEW.quantity_received < 0
    OR NEW.available_qty < 0 THEN
    RAISE EXCEPTION 'Batch dates, prices, and quantities are invalid';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_batch_tenant_references() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_guard_batch_tenant_references ON public.product_batches;
CREATE TRIGGER trg_guard_batch_tenant_references
  BEFORE INSERT OR UPDATE ON public.product_batches
  FOR EACH ROW EXECUTE FUNCTION public.guard_batch_tenant_references();

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_batches_product_number
  ON public.product_batches(product_id, batch_number);

REVOKE INSERT, UPDATE, DELETE ON public.product_batches FROM authenticated;

CREATE OR REPLACE FUNCTION public.create_inventory_batch(
  p_pharmacy_id uuid,
  p_product_id uuid,
  p_batch_number text,
  p_expiry_date date,
  p_quantity integer,
  p_purchase_price numeric,
  p_selling_price numeric,
  p_mrp numeric DEFAULT NULL,
  p_manufacturing_date date DEFAULT NULL,
  p_supplier_id uuid DEFAULT NULL,
  p_reason text DEFAULT 'Opening stock'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
DECLARE
  new_batch_id uuid;
  stock_reason text := btrim(COALESCE(p_reason, ''));
BEGIN
  IF auth.uid() IS NULL OR NOT private.has_pharmacy_permission(p_pharmacy_id, 'inventory.adjust') THEN
    RAISE EXCEPTION 'Inventory adjustment permission is required';
  END IF;

  IF length(btrim(COALESCE(p_batch_number, ''))) < 1
    OR length(btrim(COALESCE(p_batch_number, ''))) > 120
    OR p_quantity <= 0
    OR p_purchase_price < 0
    OR p_selling_price < 0
    OR COALESCE(p_mrp, p_selling_price) < 0
    OR length(stock_reason) < 5
    OR length(stock_reason) > 500
    OR (p_manufacturing_date IS NOT NULL AND p_manufacturing_date > p_expiry_date) THEN
    RAISE EXCEPTION 'Provide a valid batch number, positive quantity, prices, and reason';
  END IF;

  INSERT INTO public.product_batches (
    product_id, pharmacy_id, batch_number, manufacturing_date, expiry_date,
    purchase_price, selling_price, mrp, quantity_received, available_qty, supplier_id
  )
  SELECT p.id, p_pharmacy_id, btrim(p_batch_number), p_manufacturing_date, p_expiry_date,
         p_purchase_price, p_selling_price, COALESCE(p_mrp, p_selling_price), p_quantity, p_quantity, p_supplier_id
  FROM public.products p
  WHERE p.id = p_product_id
    AND p.pharmacy_id = p_pharmacy_id
    AND p.status = 'active'
  RETURNING id INTO new_batch_id;

  IF new_batch_id IS NULL THEN
    RAISE EXCEPTION 'The product is not active in this pharmacy';
  END IF;

  INSERT INTO public.inventory_movements (
    product_id, batch_id, pharmacy_id, movement_type, quantity_delta,
    reference_type, reference_id, created_by, note
  )
  VALUES (
    p_product_id, new_batch_id, p_pharmacy_id, 'adjustment', p_quantity,
    'opening_stock', new_batch_id, auth.uid(), stock_reason
  );

  RETURN new_batch_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.adjust_inventory_batch(
  p_pharmacy_id uuid,
  p_batch_id uuid,
  p_quantity_delta integer,
  p_reason text,
  p_reference text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
DECLARE
  batch_record public.product_batches%ROWTYPE;
  movement_id uuid;
  adjustment_reason text := btrim(COALESCE(p_reason, ''));
BEGIN
  IF auth.uid() IS NULL OR NOT private.has_pharmacy_permission(p_pharmacy_id, 'inventory.adjust') THEN
    RAISE EXCEPTION 'Inventory adjustment permission is required';
  END IF;

  IF p_quantity_delta = 0
    OR length(adjustment_reason) < 5
    OR length(adjustment_reason) > 500
    OR length(COALESCE(p_reference, '')) > 120 THEN
    RAISE EXCEPTION 'A non-zero adjustment and a reason of 5 to 500 characters are required';
  END IF;

  SELECT b.* INTO batch_record
  FROM public.product_batches b
  WHERE b.id = p_batch_id AND b.pharmacy_id = p_pharmacy_id
  FOR UPDATE;

  IF batch_record.id IS NULL THEN
    RAISE EXCEPTION 'Batch not found in this pharmacy';
  END IF;

  IF batch_record.expiry_date <= CURRENT_DATE AND p_quantity_delta > 0 THEN
    RAISE EXCEPTION 'Expired stock cannot be increased as saleable inventory';
  END IF;
  IF batch_record.available_qty + p_quantity_delta < 0 THEN
    RAISE EXCEPTION 'Adjustment would make batch stock negative';
  END IF;

  UPDATE public.product_batches
  SET available_qty = available_qty + p_quantity_delta
  WHERE id = batch_record.id;

  INSERT INTO public.inventory_movements (
    product_id, batch_id, pharmacy_id, movement_type, quantity_delta,
    reference_type, reference_id, created_by, note
  )
  VALUES (
    batch_record.product_id, batch_record.id, p_pharmacy_id, 'adjustment',
    p_quantity_delta, NULLIF(btrim(COALESCE(p_reference, '')), ''),
    batch_record.id, auth.uid(), adjustment_reason
  )
  RETURNING id INTO movement_id;

  RETURN movement_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_inventory_batch(uuid, uuid, text, date, integer, numeric, numeric, numeric, date, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.adjust_inventory_batch(uuid, uuid, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_inventory_batch(uuid, uuid, text, date, integer, numeric, numeric, numeric, date, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_inventory_batch(uuid, uuid, integer, text, text) TO authenticated;
