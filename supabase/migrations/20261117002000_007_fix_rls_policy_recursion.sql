CREATE OR REPLACE FUNCTION public.is_pharmacy_owner(p_pharmacy_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pharmacies p
    WHERE p.id = p_pharmacy_id
      AND p.owner_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_pharmacy_owner(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_pharmacy_owner(uuid) TO authenticated;

DROP POLICY IF EXISTS pharmacies_read ON public.pharmacies;
CREATE POLICY pharmacies_read
  ON public.pharmacies FOR SELECT TO authenticated
  USING (
    owner_id = auth.uid()
    OR public.is_pharmacy_member(id)
    OR EXISTS (
      SELECT 1
      FROM public.app_users u
      WHERE u.id = auth.uid()
        AND u.is_super_admin = true
    )
  );

DROP POLICY IF EXISTS members_read ON public.pharmacy_members;
CREATE POLICY members_read
  ON public.pharmacy_members FOR SELECT TO authenticated
  USING (
    public.is_pharmacy_owner(pharmacy_id)
    OR public.is_pharmacy_member(pharmacy_id)
    OR EXISTS (
      SELECT 1
      FROM public.app_users u
      WHERE u.id = auth.uid()
        AND u.is_super_admin = true
    )
  );

DROP POLICY IF EXISTS members_insert ON public.pharmacy_members;
CREATE POLICY members_insert
  ON public.pharmacy_members FOR INSERT TO authenticated
  WITH CHECK (
    public.is_pharmacy_owner(pharmacy_id)
    OR EXISTS (
      SELECT 1
      FROM public.app_users u
      WHERE u.id = auth.uid()
        AND u.is_super_admin = true
    )
  );

DROP POLICY IF EXISTS members_update ON public.pharmacy_members;
CREATE POLICY members_update
  ON public.pharmacy_members FOR UPDATE TO authenticated
  USING (
    public.is_pharmacy_owner(pharmacy_id)
    OR EXISTS (
      SELECT 1
      FROM public.app_users u
      WHERE u.id = auth.uid()
        AND u.is_super_admin = true
    )
  )
  WITH CHECK (
    public.is_pharmacy_owner(pharmacy_id)
    OR EXISTS (
      SELECT 1
      FROM public.app_users u
      WHERE u.id = auth.uid()
        AND u.is_super_admin = true
    )
  );

DROP POLICY IF EXISTS members_delete ON public.pharmacy_members;
CREATE POLICY members_delete
  ON public.pharmacy_members FOR DELETE TO authenticated
  USING (
    public.is_pharmacy_owner(pharmacy_id)
    OR user_id = auth.uid()
  );
