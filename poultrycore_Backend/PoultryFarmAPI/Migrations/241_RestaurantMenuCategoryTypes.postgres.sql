-- =============================================================================
-- Migration 241: Restaurant Menu Category Types Lookup  (PostgreSQL)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.restaurantmenucategorytypes (
    restaurantmenucategorytypeid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.restaurantmenucategorytypes (code, description, sortorder) VALUES
    ('APP',  'Appetizers & Starters',   1),
    ('SOP',  'Soups',                   2),
    ('SAL',  'Salads',                  3),
    ('MNC',  'Main Course',             4),
    ('SDS',  'Sides',                   5),
    ('GRL',  'Grills & BBQ',            6),
    ('SEA',  'Seafood',                 7),
    ('PST',  'Pasta & Noodles',         8),
    ('PIZ',  'Pizza',                   9),
    ('SND',  'Sandwiches & Wraps',     10),
    ('BRG',  'Burgers',               11),
    ('RCE',  'Rice Dishes',            12),
    ('BKF',  'Breakfast',              13),
    ('DST',  'Desserts',               14),
    ('BVG',  'Beverages',              15),
    ('HBV',  'Hot Beverages',          16),
    ('CKT',  'Cocktails',             17),
    ('WIN',  'Wine & Spirits',         18),
    ('SNK',  'Snacks',                19),
    ('KDS',  'Kids Menu',             20),
    ('CMB',  'Combos & Meal Deals',    21),
    ('SPL',  'Specials / Seasonal',    22),
    ('OTH',  'Other',                  23)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.sprestaurant_menucategorytype_list()
 RETURNS SETOF restaurantmenucategorytypes
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM restaurantmenucategorytypes WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;
