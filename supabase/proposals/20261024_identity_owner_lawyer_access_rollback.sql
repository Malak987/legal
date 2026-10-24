-- ROLLBACK PROPOSAL ONLY — do not run without separate explicit approval.
-- This restores the exact relevant live helper/trigger definitions observed on
-- 2026-10-24. It intentionally aborts if an owner profile already exists; no
-- owner is silently demoted or deleted.

BEGIN;

DO $preflight$
BEGIN
  IF EXISTS (SELECT 1 FROM public.users WHERE role = 'owner') THEN
    RAISE EXCEPTION 'Rollback refused: owner profiles exist; prepare an explicit owner-role transition first';
  END IF;
END;
$preflight$;

DROP POLICY IF EXISTS cases_select_assigned_lawyer ON public.cases;
DROP POLICY IF EXISTS bookings_select_assigned_lawyer ON public.bookings;
DROP FUNCTION IF EXISTS private.is_current_user_lawyer_for(text);

DROP TRIGGER IF EXISTS guard_owner_profile_delete_trigger ON public.users;
DROP FUNCTION IF EXISTS public.guard_owner_profile_delete();
DROP TRIGGER IF EXISTS guard_owner_profile_insert_trigger ON public.users;
DROP FUNCTION IF EXISTS public.guard_owner_profile_insert();

DROP TRIGGER IF EXISTS trg_auth_users_link_migrated ON auth.users;

CREATE OR REPLACE FUNCTION public.link_migrated_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NEW.email IS NOT NULL THEN
    UPDATE public.users
       SET auth_user_id = NEW.id,
           updated_at = now()
     WHERE lower(email) = lower(NEW.email)
       AND auth_user_id IS NULL;
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER trg_auth_users_link_migrated
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.link_migrated_auth_user();
REVOKE ALL ON FUNCTION public.link_migrated_auth_user() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.current_app_user_id()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT COALESCE(
    (
      SELECT u.id
      FROM public.users u
      WHERE u.auth_user_id = auth.uid()
         OR u.id = auth.uid()::text
      LIMIT 1
    ),
    auth.uid()::text
  );
$function$;

CREATE OR REPLACE FUNCTION private.current_app_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT u.role
  FROM public.users u
  WHERE u.auth_user_id = auth.uid()
     OR u.id = auth.uid()::text
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT COALESCE(
    private.current_app_user_role() = 'admin',
    false
  );
$function$;

CREATE OR REPLACE FUNCTION private.is_lawyer_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT COALESCE(
    private.current_app_user_role() IN ('lawyer', 'admin'),
    false
  );
$function$;

REVOKE ALL ON FUNCTION private.current_app_user_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.current_app_user_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_lawyer_or_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_app_user_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.current_app_user_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_lawyer_or_admin() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_user_identity_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF (
    NEW.id IS DISTINCT FROM OLD.id
    OR NEW.uid IS DISTINCT FROM OLD.uid
    OR NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id
    OR NEW.role IS DISTINCT FROM OLD.role
  ) AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Identity and role fields can only be changed by an administrator'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.guard_user_identity_fields() FROM PUBLIC, anon, authenticated;

-- Restore the baseline owner/client policies exactly. The helper calls are the
-- public invoker wrappers that remain installed by the active migration chain.
DROP POLICY IF EXISTS cases_select_owner_or_admin ON public.cases;
CREATE POLICY cases_select_owner_or_admin ON public.cases
  FOR SELECT TO authenticated
  USING (
    user_id = public.current_app_user_id()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS cases_insert_owner_or_admin ON public.cases;
CREATE POLICY cases_insert_owner_or_admin ON public.cases
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = public.current_app_user_id()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS cases_update_owner_or_admin ON public.cases;
CREATE POLICY cases_update_owner_or_admin ON public.cases
  FOR UPDATE TO authenticated
  USING (
    user_id = public.current_app_user_id()
    OR public.is_admin()
  )
  WITH CHECK (
    user_id = public.current_app_user_id()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS cases_delete_owner_or_admin ON public.cases;
CREATE POLICY cases_delete_owner_or_admin ON public.cases
  FOR DELETE TO authenticated
  USING (
    user_id = public.current_app_user_id()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS bookings_select_owner_or_admin ON public.bookings;
CREATE POLICY bookings_select_owner_or_admin ON public.bookings
  FOR SELECT TO authenticated
  USING (
    user_id = public.current_app_user_id()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS booking_slots_select_owner_or_admin ON public.booking_slots;
CREATE POLICY booking_slots_select_owner_or_admin ON public.booking_slots
  FOR SELECT TO authenticated
  USING (
    user_id = public.current_app_user_id()
    OR public.is_admin()
  );

DROP INDEX IF EXISTS public.users_single_owner_key;
ALTER TABLE public.users DROP CONSTRAINT users_role_check;
ALTER TABLE public.users
  ADD CONSTRAINT users_role_check
  CHECK (role IN ('client', 'lawyer', 'admin')) NOT VALID;
ALTER TABLE public.users VALIDATE CONSTRAINT users_role_check;

COMMIT;
