-- =============================================================================
-- Migration 233: Hotel ID Types Lookup Table  (PostgreSQL)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.hotelidtypes (
    hotelidtypeid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.hotelidtypes (code, description, sortorder) VALUES
    ('PSP',  'Passport',               1),
    ('NID',  'National ID',            2),
    ('DRV',  'Driver''s License',      3),
    ('VOT',  'Voter''s ID',            4),
    ('SSN',  'Social Security Card',   5),
    ('MIL',  'Military ID',            6),
    ('STU',  'Student ID',             7),
    ('RES',  'Residence Permit',       8),
    ('BIR',  'Birth Certificate',      9),
    ('OTH',  'Other',                  10)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.sphotel_idtype_list()
 RETURNS SETOF hotelidtypes
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM hotelidtypes
    WHERE isactive = true
    ORDER BY sortorder, description;
END;
$function$;
