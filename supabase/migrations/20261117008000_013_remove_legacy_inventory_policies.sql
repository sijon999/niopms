DROP POLICY IF EXISTS batches_read ON public.product_batches;
DROP POLICY IF EXISTS batches_insert ON public.product_batches;
DROP POLICY IF EXISTS batches_update ON public.product_batches;

DROP POLICY IF EXISTS movements_read ON public.inventory_movements;
DROP POLICY IF EXISTS movements_insert ON public.inventory_movements;

REVOKE INSERT, UPDATE, DELETE ON public.inventory_movements FROM authenticated;
