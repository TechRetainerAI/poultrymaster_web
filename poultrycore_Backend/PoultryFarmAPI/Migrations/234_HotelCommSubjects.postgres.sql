-- =============================================================================
-- Migration 234: Hotel Communication Subjects Lookup Table  (PostgreSQL)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.hotelcommsubjects (
    hotelcommsubjectid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.hotelcommsubjects (code, description, sortorder) VALUES
    ('WLC',  'Welcome / Pre-arrival',      1),
    ('CHK',  'Check-in / Check-out',        2),
    ('REQ',  'Guest Request',               3),
    ('CMP',  'Complaint',                   4),
    ('FBK',  'Feedback / Review',           5),
    ('BIL',  'Billing Inquiry',             6),
    ('RES',  'Reservation Change',          7),
    ('MTN',  'Maintenance Issue',           8),
    ('LST',  'Lost & Found',               9),
    ('SPC',  'Special Occasion',            10),
    ('VIP',  'VIP / Loyalty',               11),
    ('EMR',  'Emergency',                   12),
    ('GEN',  'General Inquiry',             13),
    ('OTH',  'Other',                       14)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.sphotel_commsubject_list()
 RETURNS SETOF hotelcommsubjects
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM hotelcommsubjects
    WHERE isactive = true
    ORDER BY sortorder, description;
END;
$function$;
