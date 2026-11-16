ALTER TABLE public.pharmacies
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS logo_path text,
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.pharmacies
  DROP CONSTRAINT IF EXISTS pharmacies_status_check;
ALTER TABLE public.pharmacies
  ADD CONSTRAINT pharmacies_status_check
  CHECK (status IN ('pending', 'approved', 'rejected', 'suspended', 'deactivated'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_pharmacies_owner_unique
  ON public.pharmacies(owner_id)
  WHERE owner_id IS NOT NULL;

CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_users u
    WHERE u.id = auth.uid()
      AND u.is_super_admin = true
  );
$$;

CREATE OR REPLACE FUNCTION private.can_register_pharmacy()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.app_users u
      WHERE u.id = auth.uid()
        AND u.is_super_admin = false
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.pharmacy_members m
      WHERE m.user_id = auth.uid()
        AND m.is_active = true
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.pharmacies p
      WHERE p.owner_id = auth.uid()
        AND p.status <> 'rejected'
    );
$$;

REVOKE ALL ON FUNCTION private.is_super_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.can_register_pharmacy() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_register_pharmacy() TO authenticated;

DROP POLICY IF EXISTS app_users_self_read ON public.app_users;
CREATE POLICY app_users_self_read
  ON public.app_users FOR SELECT TO authenticated
  USING (id = auth.uid() OR private.is_super_admin());

DROP POLICY IF EXISTS pharmacies_insert ON public.pharmacies;
CREATE POLICY pharmacies_insert
  ON public.pharmacies FOR INSERT TO authenticated
  WITH CHECK (private.is_super_admin());

DROP POLICY IF EXISTS pharmacies_update ON public.pharmacies;
CREATE POLICY pharmacies_update
  ON public.pharmacies FOR UPDATE TO authenticated
  USING (private.is_super_admin())
  WITH CHECK (private.is_super_admin());

CREATE OR REPLACE FUNCTION public.guard_pharmacy_status_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
DECLARE
  is_platform_admin boolean;
  is_registration_resubmission boolean;
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
      OR NEW.deactivated_at IS NOT NULL
      OR NEW.rejection_reason IS NOT NULL
      OR NEW.owner_id IS DISTINCT FROM auth.uid()
      OR NOT private.can_register_pharmacy() THEN
      RAISE EXCEPTION 'Only an eligible owner may submit a pending pharmacy registration';
    END IF;
  ELSE
    is_registration_resubmission :=
      COALESCE(current_setting('app.pharmacy_registration_submission', true), '') = 'on'
      AND OLD.status = 'rejected'
      AND NEW.status = 'pending'
      AND NEW.owner_id = auth.uid()
      AND NEW.approved_at IS NULL
      AND NEW.approved_by IS NULL
      AND NEW.suspended_at IS NULL
      AND NEW.deactivated_at IS NULL
      AND NEW.rejection_reason IS NULL;

    IF ROW(
      NEW.status,
      NEW.approved_at,
      NEW.approved_by,
      NEW.suspended_at,
      NEW.deactivated_at,
      NEW.rejection_reason,
      NEW.submitted_at
    ) IS DISTINCT FROM ROW(
      OLD.status,
      OLD.approved_at,
      OLD.approved_by,
      OLD.suspended_at,
      OLD.deactivated_at,
      OLD.rejection_reason,
      OLD.submitted_at
    ) AND NOT COALESCE(is_registration_resubmission, false) THEN
      RAISE EXCEPTION 'Only a Super Admin may change pharmacy registration status or review fields';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_pharmacy_status_changes() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.submit_pharmacy_registration(
  p_owner_name text,
  p_owner_phone text,
  p_name text,
  p_email text,
  p_phone text,
  p_address_line1 text,
  p_address_line2 text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_state text DEFAULT NULL,
  p_postal_code text DEFAULT NULL,
  p_country text DEFAULT 'Bangladesh',
  p_drug_license_number text DEFAULT NULL,
  p_tax_id text DEFAULT NULL,
  p_logo_path text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, storage, auth, pg_temp
AS $$
DECLARE
  requesting_user uuid := auth.uid();
  existing_pharmacy public.pharmacies%ROWTYPE;
  pharmacy_id uuid;
  normalized_email text := lower(btrim(COALESCE(p_email, '')));
BEGIN
  IF requesting_user IS NULL THEN
    RAISE EXCEPTION 'Authentication is required to register a pharmacy';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(requesting_user::text, 0));

  IF NOT private.can_register_pharmacy() THEN
    RAISE EXCEPTION 'This account cannot submit another pharmacy registration';
  END IF;

  IF length(btrim(COALESCE(p_owner_name, ''))) < 2
    OR length(btrim(COALESCE(p_owner_name, ''))) > 120
    OR length(btrim(COALESCE(p_owner_phone, ''))) < 6
    OR length(btrim(COALESCE(p_owner_phone, ''))) > 32
    OR length(btrim(COALESCE(p_name, ''))) < 2
    OR length(btrim(COALESCE(p_name, ''))) > 160
    OR normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    OR length(btrim(COALESCE(p_phone, ''))) < 6
    OR length(btrim(COALESCE(p_phone, ''))) > 32
    OR length(btrim(COALESCE(p_address_line1, ''))) < 4
    OR length(btrim(COALESCE(p_address_line1, ''))) > 240
    OR length(btrim(COALESCE(p_city, ''))) < 2
    OR length(btrim(COALESCE(p_city, ''))) > 120
    OR length(btrim(COALESCE(p_country, ''))) < 2
    OR length(btrim(COALESCE(p_country, ''))) > 120 THEN
    RAISE EXCEPTION 'Please provide valid owner, pharmacy, contact, and address information';
  END IF;

  IF p_logo_path IS NOT NULL AND (
    p_logo_path NOT LIKE (requesting_user::text || '/%')
    OR NOT EXISTS (
      SELECT 1
      FROM storage.objects o
      WHERE o.bucket_id = 'pharmacy-logos'
        AND o.name = p_logo_path
    )
  ) THEN
    RAISE EXCEPTION 'The pharmacy logo must be uploaded to your own pharmacy registration folder';
  END IF;

  SELECT p.*
  INTO existing_pharmacy
  FROM public.pharmacies p
  WHERE p.owner_id = requesting_user
  FOR UPDATE;

  UPDATE public.app_users
  SET full_name = btrim(p_owner_name),
      phone = btrim(p_owner_phone)
  WHERE id = requesting_user;

  IF FOUND IS FALSE THEN
    RAISE EXCEPTION 'The account profile is missing; contact support before submitting';
  END IF;

  IF existing_pharmacy.id IS NOT NULL THEN
    IF existing_pharmacy.status <> 'rejected' THEN
      RAISE EXCEPTION 'A pharmacy registration already exists for this account';
    END IF;

    PERFORM set_config('app.pharmacy_registration_submission', 'on', true);
    UPDATE public.pharmacies
    SET name = btrim(p_name),
        email = normalized_email,
        phone = btrim(p_phone),
        address_line1 = btrim(p_address_line1),
        address_line2 = NULLIF(btrim(COALESCE(p_address_line2, '')), ''),
        city = btrim(p_city),
        state = NULLIF(btrim(COALESCE(p_state, '')), ''),
        postal_code = NULLIF(btrim(COALESCE(p_postal_code, '')), ''),
        country = btrim(p_country),
        drug_license_number = NULLIF(btrim(COALESCE(p_drug_license_number, '')), ''),
        tax_id = NULLIF(btrim(COALESCE(p_tax_id, '')), ''),
        logo_path = p_logo_path,
        status = 'pending',
        rejection_reason = NULL,
        approved_at = NULL,
        approved_by = NULL,
        suspended_at = NULL,
        deactivated_at = NULL,
        submitted_at = now()
    WHERE id = existing_pharmacy.id
    RETURNING id INTO pharmacy_id;
  ELSE
    INSERT INTO public.pharmacies (
      name, email, phone, address_line1, address_line2, city, state, postal_code,
      country, drug_license_number, tax_id, logo_path, owner_id, status,
      rejection_reason, submitted_at
    )
    VALUES (
      btrim(p_name), normalized_email, btrim(p_phone), btrim(p_address_line1),
      NULLIF(btrim(COALESCE(p_address_line2, '')), ''), btrim(p_city),
      NULLIF(btrim(COALESCE(p_state, '')), ''), NULLIF(btrim(COALESCE(p_postal_code, '')), ''),
      btrim(p_country), NULLIF(btrim(COALESCE(p_drug_license_number, '')), ''),
      NULLIF(btrim(COALESCE(p_tax_id, '')), ''), p_logo_path, requesting_user,
      'pending', NULL, now()
    )
    RETURNING id INTO pharmacy_id;
  END IF;

  RETURN pharmacy_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_pharmacy_registration(
  text, text, text, text, text, text, text, text, text, text, text, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_pharmacy_registration(
  text, text, text, text, text, text, text, text, text, text, text, text, text, text
) TO authenticated;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  user_metadata jsonb := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
BEGIN
  INSERT INTO public.app_users (id, email, full_name, phone, is_super_admin)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    NULLIF(user_metadata ->> 'full_name', ''),
    NULLIF(user_metadata ->> 'phone', ''),
    false
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_auth_user() FROM PUBLIC, anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'pharmacy-logos',
  'pharmacy-logos',
  true,
  2097152,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS pharmacy_logos_public_read ON storage.objects;
CREATE POLICY pharmacy_logos_public_read
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'pharmacy-logos');

DROP POLICY IF EXISTS pharmacy_logos_owner_insert ON storage.objects;
CREATE POLICY pharmacy_logos_owner_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'pharmacy-logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND private.can_register_pharmacy()
  );

DROP POLICY IF EXISTS pharmacy_logos_owner_update ON storage.objects;
CREATE POLICY pharmacy_logos_owner_update
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'pharmacy-logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND private.can_register_pharmacy()
  )
  WITH CHECK (
    bucket_id = 'pharmacy-logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND private.can_register_pharmacy()
  );

DROP POLICY IF EXISTS pharmacy_logos_owner_delete ON storage.objects;
CREATE POLICY pharmacy_logos_owner_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'pharmacy-logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND private.can_register_pharmacy()
  );
