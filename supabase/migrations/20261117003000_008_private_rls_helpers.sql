CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;

ALTER FUNCTION public.is_pharmacy_member(uuid) SET SCHEMA private;
ALTER FUNCTION public.is_pharmacy_owner(uuid) SET SCHEMA private;

REVOKE ALL ON FUNCTION private.is_pharmacy_member(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_pharmacy_owner(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_pharmacy_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_pharmacy_owner(uuid) TO authenticated;
