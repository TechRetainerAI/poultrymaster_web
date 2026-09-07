-- =============================================================================
-- Migration 237: Hotel Restaurant Table Locations Lookup  (PostgreSQL)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.hoteltablelocations (
    hoteltablelocationid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.hoteltablelocations (code, description, sortorder) VALUES
    ('IND',  'Indoor',            1),
    ('OUT',  'Outdoor',           2),
    ('PAT',  'Patio',             3),
    ('TER',  'Terrace',           4),
    ('BAR',  'Bar Area',          5),
    ('PLR',  'Poolside',          6),
    ('LOB',  'Lobby Lounge',      7),
    ('ROF',  'Rooftop',           8),
    ('GAR',  'Garden',            9),
    ('VIP',  'VIP / Private',    10),
    ('BQT',  'Banquet Hall',     11),
    ('OTH',  'Other',            12)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.sphotel_tablelocation_list()
 RETURNS SETOF hoteltablelocations
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM hoteltablelocations
    WHERE isactive = true
    ORDER BY sortorder, description;
END;
$function$;
