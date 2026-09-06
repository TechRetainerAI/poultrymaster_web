-- =============================================================================
-- Migration 235: Hotel Guest Request Types Lookup Table  (PostgreSQL)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.hotelrequesttypes (
    hotelrequesttypeid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.hotelrequesttypes (code, description, sortorder) VALUES
    ('WKC',  'Wake-Up Call',          1),
    ('TWL',  'Extra Towels',          2),
    ('PIL',  'Extra Pillows',         3),
    ('RSV',  'Room Service',          4),
    ('CLN',  'Room Cleaning',         5),
    ('MTN',  'Maintenance',           6),
    ('TRN',  'Transport / Taxi',      7),
    ('LND',  'Laundry',              8),
    ('MNB',  'Minibar Restock',       9),
    ('LCO',  'Late Check-out',       10),
    ('ECO',  'Early Check-in',       11),
    ('BED',  'Extra Bed / Cot',      12),
    ('SPR',  'Spa / Wellness',       13),
    ('TUR',  'Tour / Activity',      14),
    ('FNB',  'Food & Beverage',      15),
    ('OTH',  'Other',                16)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.sphotel_requesttype_list()
 RETURNS SETOF hotelrequesttypes
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM hotelrequesttypes
    WHERE isactive = true
    ORDER BY sortorder, description;
END;
$function$;
