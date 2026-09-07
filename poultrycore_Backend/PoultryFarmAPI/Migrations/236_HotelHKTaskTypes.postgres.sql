-- =============================================================================
-- Migration 236: Hotel Housekeeping Task Types Lookup Table  (PostgreSQL)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.hotelhktasktypes (
    hotelhktasktypeid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.hotelhktasktypes (code, description, sortorder) VALUES
    ('DLY',  'Daily Cleaning',        1),
    ('DPC',  'Deep Clean',            2),
    ('TND',  'Turndown Service',      3),
    ('CKO',  'Checkout Clean',        4),
    ('STA',  'Stayover Clean',        5),
    ('INS',  'Inspection',            6),
    ('LND',  'Linen Change',          7),
    ('MNB',  'Minibar Restock',       8),
    ('PUB',  'Public Area Clean',     9),
    ('LDR',  'Laundry Collection',   10),
    ('MTN',  'Maintenance Check',    11),
    ('OTH',  'Other',                12)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.sphotel_hktasktype_list()
 RETURNS SETOF hotelhktasktypes
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM hotelhktasktypes
    WHERE isactive = true
    ORDER BY sortorder, description;
END;
$function$;
