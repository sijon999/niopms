DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.pharmacies'::regclass
      AND conname = 'pharmacies_rejected_reason_check'
  ) THEN
    ALTER TABLE public.pharmacies
      ADD CONSTRAINT pharmacies_rejected_reason_check
      CHECK (
        status <> 'rejected'
        OR length(btrim(COALESCE(rejection_reason, ''))) >= 5
      );
  END IF;
END;
$$;
