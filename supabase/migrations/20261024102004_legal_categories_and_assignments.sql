-- Migration: 20261024102004_legal_categories_and_assignments.sql
-- Source: applied live migration recorded at version 20261024102004; contents
-- were reconciled read-only against supabase_migrations.schema_migrations.
-- Purpose: add the category catalogue and normalized lawyer/case assignments
-- after inspection confirmed that the live public schema had no
-- legal_categories table, lawyers.category_id, cases.category_id, or
-- cases.lawyer_id. Existing text labels and case rows are preserved.
--
-- Forward-only and additive: existing assignments remain NULL until an
-- administrator explicitly links a lawyer or case. No rows are rewritten.

BEGIN;

CREATE TABLE public.legal_categories (
  id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name text NOT NULL,
  slug text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT legal_categories_name_check
    CHECK (char_length(btrim(name)) BETWEEN 2 AND 120),
  CONSTRAINT legal_categories_slug_check
    CHECK (char_length(btrim(slug)) BETWEEN 1 AND 160),
  CONSTRAINT legal_categories_slug_key UNIQUE (slug)
);

-- Avoid visually duplicate category names even when case or Unicode
-- normalization differs. Slugs are separately unique for API/UI stability.
CREATE UNIQUE INDEX legal_categories_name_lower_key
  ON public.legal_categories (lower(name));

-- `experience` is already part of the lawyer API contract but was absent from
-- the inspected live relation. Its empty-string default keeps old rows and
-- public projections usable without requiring a backfill.
ALTER TABLE public.lawyers
  ADD COLUMN IF NOT EXISTS experience text NOT NULL DEFAULT '';
ALTER TABLE public.lawyers
  ADD COLUMN category_id text;
ALTER TABLE public.cases
  ADD COLUMN lawyer_id text,
  ADD COLUMN category_id text;

ALTER TABLE public.lawyers
  ADD CONSTRAINT lawyers_category_id_fkey
  FOREIGN KEY (category_id)
  REFERENCES public.legal_categories(id)
  ON DELETE RESTRICT;

ALTER TABLE public.cases
  ADD CONSTRAINT cases_lawyer_id_fkey
  FOREIGN KEY (lawyer_id)
  REFERENCES public.lawyers(id)
  ON DELETE RESTRICT,
  ADD CONSTRAINT cases_category_id_fkey
  FOREIGN KEY (category_id)
  REFERENCES public.legal_categories(id)
  ON DELETE RESTRICT,
  ADD CONSTRAINT cases_assignment_pair_check
  CHECK ((lawyer_id IS NULL) = (category_id IS NULL));

-- When both case assignment fields are set, the selected lawyer must be
-- assigned to the same category. Separate FKs above retain explicit category
-- and lawyer relationships for catalog discovery and referential integrity.
ALTER TABLE public.lawyers
  ADD CONSTRAINT lawyers_id_category_id_key UNIQUE (id, category_id);
ALTER TABLE public.cases
  ADD CONSTRAINT cases_lawyer_category_fkey
  FOREIGN KEY (lawyer_id, category_id)
  REFERENCES public.lawyers(id, category_id)
  ON DELETE RESTRICT;

CREATE INDEX lawyers_category_id_idx ON public.lawyers (category_id);
CREATE INDEX cases_category_id_idx ON public.cases (category_id);
CREATE INDEX cases_lawyer_id_idx ON public.cases (lawyer_id);

-- Keep legacy display/search columns aligned when an administrator renames a
-- category. IDs remain stable and no unrelated rows are touched.
CREATE OR REPLACE FUNCTION public.sync_legal_category_labels()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.name IS DISTINCT FROM OLD.name THEN
    UPDATE public.lawyers
       SET specialty = NEW.name
     WHERE category_id = NEW.id;
    UPDATE public.cases
       SET case_type = NEW.name
     WHERE category_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_legal_categories_updated_at
  BEFORE UPDATE ON public.legal_categories
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_legal_categories_sync_labels
  AFTER UPDATE OF name ON public.legal_categories
  FOR EACH ROW EXECUTE FUNCTION public.sync_legal_category_labels();

-- Categories are public catalogue data. Writes are authenticated and then
-- limited to existing administrators by RLS; no service-role key is needed by
-- the API or clients.
ALTER TABLE public.legal_categories ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.legal_categories FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.legal_categories TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.legal_categories TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.legal_categories TO service_role;

CREATE POLICY legal_categories_select_public ON public.legal_categories
  FOR SELECT TO anon, authenticated
  USING (true);
CREATE POLICY legal_categories_insert_admin_only ON public.legal_categories
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());
CREATE POLICY legal_categories_update_admin_only ON public.legal_categories
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
CREATE POLICY legal_categories_delete_admin_only ON public.legal_categories
  FOR DELETE TO authenticated
  USING (public.is_admin());

-- The connected project already has table-level SELECT/DML grants on lawyers
-- and cases. These narrow column grants support relation writes and the label
-- sync trigger in the reviewed least-privilege baseline without broadening
-- unrelated column access.
GRANT SELECT (category_id) ON public.lawyers TO anon, authenticated;
GRANT INSERT (category_id) ON public.lawyers TO authenticated;
GRANT UPDATE (category_id, specialty) ON public.lawyers TO authenticated;
GRANT SELECT (lawyer_id, category_id) ON public.cases TO authenticated;
GRANT INSERT (lawyer_id, category_id) ON public.cases TO authenticated;
GRANT UPDATE (lawyer_id, category_id, user_id, case_type) ON public.cases TO authenticated;

COMMIT;
