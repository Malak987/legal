-- ARCHIVED CANDIDATE — do not apply or restore to supabase/migrations/.
-- A read-only live catalog check on 2026-10-24 found the equivalent index
-- cases_lawyer_category_idx on (lawyer_id, category_id). This candidate uses a
-- different name and would create a redundant index if run with IF NOT EXISTS.
CREATE INDEX IF NOT EXISTS idx_cases_lawyer_category
  ON public.cases (lawyer_id, category_id);
