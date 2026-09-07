-- =============================================================================
-- Migration 240: Hotel Supply Items & Categories Lookup Tables  (PostgreSQL)
-- =============================================================================

-- Supply Categories
CREATE TABLE IF NOT EXISTS public.hotelsupplycategories (
    hotelsupplycategoryid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.hotelsupplycategories (code, description, sortorder) VALUES
    ('LIN',  'Linen & Bedding',      1),
    ('TOI',  'Toiletries',           2),
    ('MNB',  'Minibar Items',         3),
    ('KIT',  'Kitchen Supplies',      4),
    ('CLN',  'Cleaning Supplies',     5),
    ('STN',  'Stationery',           6),
    ('UNI',  'Uniforms',             7),
    ('AMN',  'Guest Amenities',       8),
    ('EQP',  'Equipment',            9),
    ('FNB',  'Food & Beverage',      10),
    ('LAU',  'Laundry Supplies',     11),
    ('SAF',  'Safety & First Aid',   12),
    ('DEC',  'Decor & Furnishing',   13),
    ('OTH',  'Other',               14)
ON CONFLICT (code) DO NOTHING;

-- Supply Items (common hotel supply names)
CREATE TABLE IF NOT EXISTS public.hotelsupplyitems (
    hotelsupplyitemid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    category    character varying(50),
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.hotelsupplyitems (code, description, category, sortorder) VALUES
    ('BTW',  'Bath Towels',           'Linen & Bedding',    1),
    ('HTW',  'Hand Towels',           'Linen & Bedding',    2),
    ('FTW',  'Face Towels',           'Linen & Bedding',    3),
    ('BDS',  'Bed Sheets',            'Linen & Bedding',    4),
    ('PLW',  'Pillow Cases',          'Linen & Bedding',    5),
    ('DVT',  'Duvet Covers',          'Linen & Bedding',    6),
    ('BLK',  'Blankets',              'Linen & Bedding',    7),
    ('BTR',  'Bathrobes',             'Linen & Bedding',    8),
    ('SLP',  'Slippers',              'Guest Amenities',    9),
    ('SHP',  'Shampoo',               'Toiletries',        10),
    ('CND',  'Conditioner',           'Toiletries',        11),
    ('BWH',  'Body Wash',             'Toiletries',        12),
    ('SOP',  'Bar Soap',              'Toiletries',        13),
    ('LTN',  'Body Lotion',           'Toiletries',        14),
    ('TBR',  'Toothbrush',            'Toiletries',        15),
    ('TPT',  'Toothpaste',            'Toiletries',        16),
    ('RZR',  'Razor / Shaving Kit',   'Toiletries',        17),
    ('SWC',  'Shower Cap',            'Toiletries',        18),
    ('TSP',  'Tissue Paper',          'Guest Amenities',   19),
    ('TPR',  'Toilet Paper',          'Guest Amenities',   20),
    ('WBT',  'Water Bottles',         'Minibar Items',     21),
    ('SFD',  'Soft Drinks',           'Minibar Items',     22),
    ('SNK',  'Snacks',                'Minibar Items',     23),
    ('CFE',  'Coffee Sachets',        'Guest Amenities',   24),
    ('TEA',  'Tea Bags',              'Guest Amenities',   25),
    ('SGR',  'Sugar Sachets',         'Guest Amenities',   26),
    ('CRM',  'Creamer',               'Guest Amenities',   27),
    ('DSH',  'Dish Soap',             'Cleaning Supplies', 28),
    ('FLC',  'Floor Cleaner',         'Cleaning Supplies', 29),
    ('GLC',  'Glass Cleaner',         'Cleaning Supplies', 30),
    ('DSF',  'Disinfectant',          'Cleaning Supplies', 31),
    ('TRB',  'Trash Bags',            'Cleaning Supplies', 32),
    ('GLV',  'Disposable Gloves',     'Cleaning Supplies', 33),
    ('NPK',  'Napkins',               'Kitchen Supplies',  34),
    ('CUT',  'Cutlery (Disposable)',  'Kitchen Supplies',  35),
    ('PEN',  'Pens',                  'Stationery',        36),
    ('NTP',  'Notepad',               'Stationery',        37),
    ('ENV',  'Envelopes',             'Stationery',        38),
    ('LDP',  'Laundry Detergent',     'Laundry Supplies',  39),
    ('FBR',  'Fabric Softener',       'Laundry Supplies',  40),
    ('FAK',  'First Aid Kit',         'Safety & First Aid',41),
    ('FEX',  'Fire Extinguisher',     'Safety & First Aid',42),
    ('OTH',  'Other',                 'Other',             43)
ON CONFLICT (code) DO NOTHING;

-- Stored procedures
CREATE OR REPLACE FUNCTION public.sphotel_supplycategory_list()
 RETURNS SETOF hotelsupplycategories
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hotelsupplycategories WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sphotel_supplyitem_list()
 RETURNS SETOF hotelsupplyitems
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hotelsupplyitems WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;
