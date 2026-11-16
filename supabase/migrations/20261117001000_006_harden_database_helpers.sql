ALTER FUNCTION public.set_updated_at()
  SET search_path = public, pg_temp;
ALTER FUNCTION public.recompute_product_total_stock()
  SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.set_updated_at()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.recompute_product_total_stock()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_pharmacy_status_changes()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rls_auto_enable()
  FROM PUBLIC, anon, authenticated;
