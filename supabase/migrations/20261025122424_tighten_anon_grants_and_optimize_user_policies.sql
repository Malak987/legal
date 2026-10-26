-- Migration: 20261025122424_tighten_anon_grants_and_optimize_user_policies.sql
--
-- RECONCILIATION FILE — ALREADY APPLIED TO THE LIVE PROJECT.
-- This migration was applied directly to Supabase project qqfzbecwhewswkyxgebu
-- (it is recorded in supabase_migrations.schema_migrations) but was never
-- committed to Git. The SQL below is copied verbatim from the statement that
-- Supabase recorded for version 20261025122424. It is committed only so that
-- local migration history matches remote history; `supabase db push` refuses to
-- run while the remote has a version the local directory does not contain.
-- Do NOT re-run it manually against the live project.

-- Least-privilege Data API access: anonymous visitors can only read intentionally public catalog data.
REVOKE ALL PRIVILEGES ON TABLE
  public.users,
  public.cases,
  public.bookings,
  public.booking_slots,
  public.tasks,
  public.chats,
  public.chat_messages,
  public.earnings,
  public.favorites,
  public.notifications,
  public.subscriptions,
  public.wallet_idempotency,
  public.wallet_transactions,
  public.wallets
FROM anon;

-- Explicitly preserve anonymous read access only for public-facing data.
GRANT SELECT ON TABLE
  public.lawyers,
  public.legal_categories,
  public.plans,
  public.reviews,
  public.availability
TO anon;

-- Cache auth.uid() per statement in user policies to avoid per-row re-evaluation.
DROP POLICY IF EXISTS users_select_self_or_admin ON public.users;
CREATE POLICY users_select_self_or_admin
ON public.users
FOR SELECT
TO authenticated
USING (
  (id = current_app_user_id())
  OR (auth_user_id = (SELECT auth.uid()))
  OR is_admin()
);

DROP POLICY IF EXISTS users_insert_self_client_or_admin ON public.users;
CREATE POLICY users_insert_self_client_or_admin
ON public.users
FOR INSERT
TO authenticated
WITH CHECK (
  is_admin()
  OR (
    id = ((SELECT auth.uid())::text)
    AND uid = ((SELECT auth.uid())::text)
    AND (auth_user_id IS NULL OR auth_user_id = (SELECT auth.uid()))
    AND role = 'client'
  )
);

DROP POLICY IF EXISTS users_update_self_or_admin ON public.users;
CREATE POLICY users_update_self_or_admin
ON public.users
FOR UPDATE
TO authenticated
USING (
  (id = current_app_user_id())
  OR (auth_user_id = (SELECT auth.uid()))
  OR is_admin()
)
WITH CHECK (
  is_admin()
  OR (
    ((id = current_app_user_id()) OR (auth_user_id = (SELECT auth.uid())))
    AND role = (SELECT u.role FROM public.users AS u WHERE u.id = users.id)
    AND lower(email) = (SELECT lower(u.email) FROM public.users AS u WHERE u.id = users.id)
  )
);
