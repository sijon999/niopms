-- Create application profiles and pending pharmacies atomically with Auth signup.
ALTER TABLE public.pharmacies
  ALTER COLUMN country SET DEFAULT 'Bangladesh',
  ALTER COLUMN settings SET DEFAULT
    '{"expiry_alert_days":[30,60,90],"tax_rate":0,"currency":"BDT","invoice_prefix":"INV"}'::jsonb;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  user_metadata jsonb := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  pharmacy_id uuid;
  template_role record;
  pharmacy_role_id uuid;
BEGIN
  INSERT INTO public.app_users (id, email, full_name, phone, is_super_admin)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    NULLIF(user_metadata ->> 'full_name', ''),
    NULLIF(user_metadata ->> 'phone', ''),
    false
  );

  IF NULLIF(BTRIM(user_metadata ->> 'pharmacy_name'), '') IS NOT NULL THEN
    IF NULLIF(BTRIM(user_metadata ->> 'pharmacy_email'), '') IS NULL THEN
      RAISE EXCEPTION 'Pharmacy email is required for pharmacy registration';
    END IF;

    INSERT INTO public.pharmacies (
      name,
      email,
      phone,
      address_line1,
      city,
      state,
      postal_code,
      country,
      drug_license_number,
      tax_id,
      owner_id,
      status
    )
    VALUES (
      BTRIM(user_metadata ->> 'pharmacy_name'),
      BTRIM(user_metadata ->> 'pharmacy_email'),
      NULLIF(BTRIM(user_metadata ->> 'pharmacy_phone'), ''),
      NULLIF(BTRIM(user_metadata ->> 'address_line1'), ''),
      NULLIF(BTRIM(user_metadata ->> 'city'), ''),
      NULLIF(BTRIM(user_metadata ->> 'state'), ''),
      NULLIF(BTRIM(user_metadata ->> 'postal_code'), ''),
      COALESCE(NULLIF(BTRIM(user_metadata ->> 'country'), ''), 'Bangladesh'),
      NULLIF(BTRIM(user_metadata ->> 'drug_license_number'), ''),
      NULLIF(BTRIM(user_metadata ->> 'tax_id'), ''),
      NEW.id,
      'pending'
    )
    RETURNING id INTO pharmacy_id;

    FOR template_role IN
      SELECT id, name, description, is_system
      FROM public.roles AS template
      WHERE template.pharmacy_id IS NULL
      ORDER BY template.name
    LOOP
      INSERT INTO public.roles (pharmacy_id, name, description, is_system)
      VALUES (pharmacy_id, template_role.name, template_role.description, template_role.is_system)
      RETURNING id INTO pharmacy_role_id;

      INSERT INTO public.role_permissions (role_id, permission_id)
      SELECT pharmacy_role_id, permission_id
      FROM public.role_permissions
      WHERE role_id = template_role.id
      ON CONFLICT DO NOTHING;
    END LOOP;

    INSERT INTO public.dosage_forms (pharmacy_id, name)
    VALUES
      (pharmacy_id, 'Tablet'),
      (pharmacy_id, 'Capsule'),
      (pharmacy_id, 'Syrup'),
      (pharmacy_id, 'Suspension'),
      (pharmacy_id, 'Injection'),
      (pharmacy_id, 'Cream'),
      (pharmacy_id, 'Ointment'),
      (pharmacy_id, 'Drops'),
      (pharmacy_id, 'Inhaler'),
      (pharmacy_id, 'Powder'),
      (pharmacy_id, 'Solution'),
      (pharmacy_id, 'Other')
    ON CONFLICT (pharmacy_id, name) DO NOTHING;

    INSERT INTO public.units (pharmacy_id, name, abbreviation)
    VALUES
      (pharmacy_id, 'Strip', 'strip'),
      (pharmacy_id, 'Box', 'box'),
      (pharmacy_id, 'Bottle', 'btl'),
      (pharmacy_id, 'Piece', 'pc'),
      (pharmacy_id, 'ml', 'ml')
    ON CONFLICT (pharmacy_id, name) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_auth_user() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- A user may update their own profile details, but never their admin flag.
REVOKE UPDATE ON public.app_users FROM authenticated;
GRANT UPDATE (full_name, phone) ON public.app_users TO authenticated;

-- Pharmacy approval and suspension are platform-admin-only state transitions.
CREATE OR REPLACE FUNCTION public.guard_pharmacy_status_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  is_platform_admin boolean;
BEGIN
  SELECT COALESCE(u.is_super_admin, false)
  INTO is_platform_admin
  FROM public.app_users u
  WHERE u.id = auth.uid();

  IF auth.role() = 'service_role' OR COALESCE(is_platform_admin, false) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'pending'
      OR NEW.approved_at IS NOT NULL
      OR NEW.approved_by IS NOT NULL
      OR NEW.suspended_at IS NOT NULL
      OR NEW.deactivated_at IS NOT NULL THEN
      RAISE EXCEPTION 'Only a platform administrator can set pharmacy approval status';
    END IF;
  ELSIF ROW(NEW.status, NEW.approved_at, NEW.approved_by, NEW.suspended_at, NEW.deactivated_at)
    IS DISTINCT FROM ROW(OLD.status, OLD.approved_at, OLD.approved_by, OLD.suspended_at, OLD.deactivated_at) THEN
    RAISE EXCEPTION 'Only a platform administrator can change pharmacy approval status';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_pharmacy_status_changes ON public.pharmacies;
CREATE TRIGGER guard_pharmacy_status_changes
  BEFORE INSERT OR UPDATE ON public.pharmacies
  FOR EACH ROW EXECUTE FUNCTION public.guard_pharmacy_status_changes();

DROP POLICY IF EXISTS "pharmacies_update" ON public.pharmacies;
CREATE POLICY "pharmacies_update"
  ON public.pharmacies FOR UPDATE TO authenticated
  USING (
    owner_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  )
  WITH CHECK (
    owner_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

-- Pending, suspended, and deactivated pharmacies cannot access operational data.
CREATE OR REPLACE FUNCTION public.is_pharmacy_member(p_pharmacy_id uuid)
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
      AND p.status = 'approved'
      AND (
        p.owner_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.pharmacy_members m
          WHERE m.pharmacy_id = p_pharmacy_id
            AND m.user_id = auth.uid()
            AND m.is_active = true
        )
      )
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_pharmacy_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_pharmacy_member(uuid) TO authenticated;

-- Prevent members from granting themselves a different role or reactivating access.
DROP POLICY IF EXISTS "members_update" ON public.pharmacy_members;
CREATE POLICY "members_update"
  ON public.pharmacy_members FOR UPDATE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.pharmacies p WHERE p.id = pharmacy_id AND p.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.pharmacies p WHERE p.id = pharmacy_id AND p.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true)
  );

-- Tenant owners may view subscriptions, but only admins or trusted server code may change them.
DROP POLICY IF EXISTS "subs_owner_write" ON public.subscriptions;
CREATE POLICY "subs_admin_write"
  ON public.subscriptions FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.app_users u WHERE u.id = auth.uid() AND u.is_super_admin = true));
