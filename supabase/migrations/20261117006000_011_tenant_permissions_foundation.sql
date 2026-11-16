CREATE OR REPLACE FUNCTION private.has_pharmacy_permission(
  p_pharmacy_id uuid,
  p_permission_key text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
  SELECT private.is_pharmacy_member(p_pharmacy_id)
    AND (
      private.is_pharmacy_owner(p_pharmacy_id)
      OR EXISTS (
        SELECT 1
        FROM public.pharmacy_members m
        JOIN public.role_permissions rp ON rp.role_id = m.role_id
        JOIN public.permissions p ON p.id = rp.permission_id
        WHERE m.pharmacy_id = p_pharmacy_id
          AND m.user_id = auth.uid()
          AND m.is_active
          AND p.key = p_permission_key
      )
    );
$$;

CREATE OR REPLACE FUNCTION private.has_any_pharmacy_permission(
  p_pharmacy_id uuid,
  p_permission_keys text[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
  SELECT private.is_pharmacy_member(p_pharmacy_id)
    AND (
      private.is_pharmacy_owner(p_pharmacy_id)
      OR EXISTS (
        SELECT 1
        FROM public.pharmacy_members m
        JOIN public.role_permissions rp ON rp.role_id = m.role_id
        JOIN public.permissions p ON p.id = rp.permission_id
        WHERE m.pharmacy_id = p_pharmacy_id
          AND m.user_id = auth.uid()
          AND m.is_active
          AND p.key = ANY (p_permission_keys)
      )
    );
$$;

REVOKE ALL ON FUNCTION private.has_pharmacy_permission(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.has_any_pharmacy_permission(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.has_pharmacy_permission(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_any_pharmacy_permission(uuid, text[]) TO authenticated;

INSERT INTO public.permissions (key, module, action, description)
VALUES ('audit_logs.view', 'Audit Logs', 'view', 'View pharmacy audit history')
ON CONFLICT (key) DO NOTHING;

DO $$
DECLARE
  pharmacy_record record;
  template_role record;
  pharmacy_role_id uuid;
BEGIN
  FOR pharmacy_record IN
    SELECT id FROM public.pharmacies WHERE status = 'pending'
  LOOP
    FOR template_role IN
      SELECT id, name, description, is_system
      FROM public.roles
      WHERE pharmacy_id IS NULL
      ORDER BY name
    LOOP
      INSERT INTO public.roles (pharmacy_id, name, description, is_system)
      VALUES (pharmacy_record.id, template_role.name, template_role.description, template_role.is_system)
      ON CONFLICT (pharmacy_id, name) DO NOTHING
      RETURNING id INTO pharmacy_role_id;

      IF pharmacy_role_id IS NULL THEN
        SELECT id INTO pharmacy_role_id
        FROM public.roles
        WHERE pharmacy_id = pharmacy_record.id AND name = template_role.name;
      END IF;

      INSERT INTO public.role_permissions (role_id, permission_id)
      SELECT pharmacy_role_id, rp.permission_id
      FROM public.role_permissions rp
      WHERE rp.role_id = template_role.id
      ON CONFLICT DO NOTHING;
    END LOOP;

    INSERT INTO public.dosage_forms (pharmacy_id, name)
    SELECT pharmacy_record.id, source.name
    FROM (VALUES
      ('Tablet'), ('Capsule'), ('Syrup'), ('Suspension'), ('Injection'),
      ('Cream'), ('Ointment'), ('Drops'), ('Inhaler'), ('Powder'), ('Other')
    ) AS source(name)
    ON CONFLICT (pharmacy_id, name) DO NOTHING;

    INSERT INTO public.units (pharmacy_id, name, abbreviation)
    SELECT pharmacy_record.id, source.name, source.abbreviation
    FROM (VALUES ('Strip', 'strip'), ('Box', 'box'), ('Bottle', 'btl'), ('Piece', 'pc'), ('ml', 'ml')) AS source(name, abbreviation)
    ON CONFLICT (pharmacy_id, name) DO NOTHING;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.provision_pharmacy_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  template_role record;
  pharmacy_role_id uuid;
BEGIN
  IF NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  FOR template_role IN
    SELECT id, name, description, is_system
    FROM public.roles
    WHERE pharmacy_id IS NULL
    ORDER BY name
  LOOP
    INSERT INTO public.roles (pharmacy_id, name, description, is_system)
    VALUES (NEW.id, template_role.name, template_role.description, template_role.is_system)
    ON CONFLICT (pharmacy_id, name) DO NOTHING
    RETURNING id INTO pharmacy_role_id;

    IF pharmacy_role_id IS NULL THEN
      SELECT id INTO pharmacy_role_id
      FROM public.roles
      WHERE pharmacy_id = NEW.id AND name = template_role.name;
    END IF;

    INSERT INTO public.role_permissions (role_id, permission_id)
    SELECT pharmacy_role_id, rp.permission_id
    FROM public.role_permissions rp
    WHERE rp.role_id = template_role.id
    ON CONFLICT DO NOTHING;
  END LOOP;

  INSERT INTO public.dosage_forms (pharmacy_id, name)
  SELECT NEW.id, source.name
  FROM (VALUES
    ('Tablet'), ('Capsule'), ('Syrup'), ('Suspension'), ('Injection'),
    ('Cream'), ('Ointment'), ('Drops'), ('Inhaler'), ('Powder'), ('Other')
  ) AS source(name)
  ON CONFLICT (pharmacy_id, name) DO NOTHING;

  INSERT INTO public.units (pharmacy_id, name, abbreviation)
  SELECT NEW.id, source.name, source.abbreviation
  FROM (VALUES ('Strip', 'strip'), ('Box', 'box'), ('Bottle', 'btl'), ('Piece', 'pc'), ('ml', 'ml')) AS source(name, abbreviation)
  ON CONFLICT (pharmacy_id, name) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.provision_pharmacy_defaults() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_provision_pharmacy_defaults ON public.pharmacies;
CREATE TRIGGER trg_provision_pharmacy_defaults
  AFTER INSERT ON public.pharmacies
  FOR EACH ROW EXECUTE FUNCTION public.provision_pharmacy_defaults();

CREATE OR REPLACE FUNCTION public.guard_pharmacy_member_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
DECLARE
  assigned_role record;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'A pharmacy member account cannot be reassigned';
  END IF;

  SELECT r.id, r.pharmacy_id, r.name
  INTO assigned_role
  FROM public.roles r
  WHERE r.id = NEW.role_id;

  IF assigned_role.id IS NULL
    OR assigned_role.pharmacy_id IS DISTINCT FROM NEW.pharmacy_id
    OR lower(assigned_role.name) = 'owner' THEN
    RAISE EXCEPTION 'The employee role must belong to this pharmacy and cannot be Owner';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_pharmacy_member_role() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_guard_pharmacy_member_role ON public.pharmacy_members;
CREATE TRIGGER trg_guard_pharmacy_member_role
  BEFORE INSERT OR UPDATE ON public.pharmacy_members
  FOR EACH ROW EXECUTE FUNCTION public.guard_pharmacy_member_role();

DROP POLICY IF EXISTS roles_read ON public.roles;
DROP POLICY IF EXISTS roles_insert ON public.roles;
DROP POLICY IF EXISTS roles_update ON public.roles;
DROP POLICY IF EXISTS roles_delete ON public.roles;
DROP POLICY IF EXISTS "roles_read" ON public.roles;
DROP POLICY IF EXISTS "roles_insert" ON public.roles;
DROP POLICY IF EXISTS "roles_update" ON public.roles;
DROP POLICY IF EXISTS "roles_delete" ON public.roles;
CREATE POLICY roles_read
  ON public.roles FOR SELECT TO authenticated
  USING (pharmacy_id IS NULL OR private.is_pharmacy_member(pharmacy_id));
CREATE POLICY roles_insert
  ON public.roles FOR INSERT TO authenticated
  WITH CHECK (
    pharmacy_id IS NOT NULL
    AND is_system = false
    AND private.is_pharmacy_owner(pharmacy_id)
  );
CREATE POLICY roles_update
  ON public.roles FOR UPDATE TO authenticated
  USING (pharmacy_id IS NOT NULL AND is_system = false AND private.is_pharmacy_owner(pharmacy_id))
  WITH CHECK (pharmacy_id IS NOT NULL AND is_system = false AND private.is_pharmacy_owner(pharmacy_id));
CREATE POLICY roles_delete
  ON public.roles FOR DELETE TO authenticated
  USING (pharmacy_id IS NOT NULL AND is_system = false AND private.is_pharmacy_owner(pharmacy_id));

DROP POLICY IF EXISTS role_permissions_read ON public.role_permissions;
DROP POLICY IF EXISTS role_permissions_manage ON public.role_permissions;
DROP POLICY IF EXISTS "role_permissions_read" ON public.role_permissions;
DROP POLICY IF EXISTS "role_permissions_manage" ON public.role_permissions;
CREATE POLICY role_permissions_read
  ON public.role_permissions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.roles r
      WHERE r.id = role_id
        AND (r.pharmacy_id IS NULL OR private.is_pharmacy_member(r.pharmacy_id))
    )
  );
CREATE POLICY role_permissions_manage
  ON public.role_permissions FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.roles r
      WHERE r.id = role_id AND r.pharmacy_id IS NOT NULL
        AND private.is_pharmacy_owner(r.pharmacy_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.roles r
      WHERE r.id = role_id AND r.pharmacy_id IS NOT NULL
        AND private.is_pharmacy_owner(r.pharmacy_id)
    )
  );

DROP POLICY IF EXISTS members_read ON public.pharmacy_members;
DROP POLICY IF EXISTS members_insert ON public.pharmacy_members;
DROP POLICY IF EXISTS members_update ON public.pharmacy_members;
DROP POLICY IF EXISTS members_delete ON public.pharmacy_members;
DROP POLICY IF EXISTS "members_read" ON public.pharmacy_members;
DROP POLICY IF EXISTS "members_insert" ON public.pharmacy_members;
DROP POLICY IF EXISTS "members_update" ON public.pharmacy_members;
DROP POLICY IF EXISTS "members_delete" ON public.pharmacy_members;
CREATE POLICY members_read
  ON public.pharmacy_members FOR SELECT TO authenticated
  USING (private.is_pharmacy_owner(pharmacy_id) OR user_id = auth.uid() OR private.is_pharmacy_member(pharmacy_id));
CREATE POLICY members_insert
  ON public.pharmacy_members FOR INSERT TO authenticated
  WITH CHECK (private.is_pharmacy_owner(pharmacy_id));
CREATE POLICY members_update
  ON public.pharmacy_members FOR UPDATE TO authenticated
  USING (private.is_pharmacy_owner(pharmacy_id))
  WITH CHECK (private.is_pharmacy_owner(pharmacy_id));
CREATE POLICY members_delete
  ON public.pharmacy_members FOR DELETE TO authenticated
  USING (private.is_pharmacy_owner(pharmacy_id));

DO $$
DECLARE
  rule record;
  operation text;
BEGIN
  FOR rule IN
    SELECT * FROM (VALUES
      ('categories', 'categories'),
      ('generics', 'products'),
      ('manufacturers', 'products'),
      ('brands', 'products'),
      ('dosage_forms', 'products'),
      ('units', 'products'),
      ('suppliers', 'suppliers'),
      ('customers', 'customers'),
      ('products', 'products'),
      ('product_batches', 'inventory'),
      ('inventory_movements', 'inventory'),
      ('sales', 'sales'),
      ('sale_items', 'sales'),
      ('sale_payments', 'sales'),
      ('sale_returns', 'sales_returns'),
      ('sale_return_items', 'sales_returns'),
      ('purchases', 'purchases'),
      ('purchase_items', 'purchases'),
      ('expenses', 'expenses'),
      ('prescriptions', 'prescriptions')
    ) AS table_rules(table_name, module_key)
  LOOP
    FOR operation IN SELECT unnest(ARRAY['select', 'insert', 'update', 'delete'])
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', rule.table_name || '_' || CASE operation WHEN 'select' THEN 'read' ELSE operation END, rule.table_name);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', rule.table_name || '_' || operation, rule.table_name);
    END LOOP;

    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (private.has_pharmacy_permission(pharmacy_id, %L))',
      rule.table_name || '_read', rule.table_name, rule.module_key || '.view'
    );

    IF rule.table_name <> 'inventory_movements' THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (private.has_any_pharmacy_permission(pharmacy_id, %L::text[]))',
        rule.table_name || '_insert', rule.table_name,
        CASE rule.table_name
          WHEN 'product_batches' THEN ARRAY['inventory.adjust', 'purchases.create']::text[]
          WHEN 'sale_items' THEN ARRAY['sales.create']::text[]
          WHEN 'sale_payments' THEN ARRAY['sales.create']::text[]
          WHEN 'sale_returns' THEN ARRAY['sales_returns.create']::text[]
          WHEN 'sale_return_items' THEN ARRAY['sales_returns.create']::text[]
          WHEN 'purchase_items' THEN ARRAY['purchases.create']::text[]
          WHEN 'prescriptions' THEN ARRAY['prescriptions.create']::text[]
          ELSE ARRAY[rule.module_key || '.create']::text[]
        END
      );
    ELSE
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (private.has_any_pharmacy_permission(pharmacy_id, ARRAY[''inventory.adjust'', ''sales.create'', ''purchases.create'']::text[]))',
        rule.table_name || '_insert', rule.table_name
      );
    END IF;

    IF rule.table_name NOT IN ('inventory_movements') THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (private.has_any_pharmacy_permission(pharmacy_id, %L::text[])) WITH CHECK (private.has_any_pharmacy_permission(pharmacy_id, %L::text[]))',
        rule.table_name || '_update', rule.table_name,
        CASE rule.table_name
          WHEN 'product_batches' THEN ARRAY['inventory.adjust', 'purchases.edit']::text[]
          WHEN 'sale_items' THEN ARRAY['sales.edit']::text[]
          WHEN 'sale_payments' THEN ARRAY['sales.edit']::text[]
          WHEN 'sale_returns' THEN ARRAY['sales_returns.approve']::text[]
          WHEN 'sale_return_items' THEN ARRAY['sales_returns.approve']::text[]
          WHEN 'purchase_items' THEN ARRAY['purchases.edit']::text[]
          ELSE ARRAY[rule.module_key || '.edit']::text[]
        END,
        CASE rule.table_name
          WHEN 'product_batches' THEN ARRAY['inventory.adjust', 'purchases.edit']::text[]
          WHEN 'sale_items' THEN ARRAY['sales.edit']::text[]
          WHEN 'sale_payments' THEN ARRAY['sales.edit']::text[]
          WHEN 'sale_returns' THEN ARRAY['sales_returns.approve']::text[]
          WHEN 'sale_return_items' THEN ARRAY['sales_returns.approve']::text[]
          WHEN 'purchase_items' THEN ARRAY['purchases.edit']::text[]
          ELSE ARRAY[rule.module_key || '.edit']::text[]
        END
      );
    END IF;

    IF rule.table_name NOT IN ('product_batches', 'inventory_movements', 'sale_items', 'sale_payments', 'sale_return_items', 'purchase_items') THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (private.has_pharmacy_permission(pharmacy_id, %L))',
        rule.table_name || '_delete', rule.table_name, rule.module_key || '.delete'
      );
    ELSE
      NULL;
    END IF;
  END LOOP;
END;
$$;

REVOKE UPDATE, DELETE ON public.inventory_movements FROM authenticated;
REVOKE DELETE ON public.product_batches, public.sale_items, public.sale_payments,
  public.sale_return_items, public.purchase_items FROM authenticated;
