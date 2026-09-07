-- =============================================================================
-- Migration 243: Restaurant Menu Item Names Lookup  (PostgreSQL)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.restaurantmenuitemnames (
    restaurantmenuitemnameid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(150) NOT NULL,
    category    character varying(100),
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.restaurantmenuitemnames (code, description, category, sortorder) VALUES
    -- Appetizers
    ('SPR',  'Spring Rolls',         'Appetizers',   1),
    ('SAM',  'Samosa',               'Appetizers',   2),
    ('KEB',  'Kebab',                'Appetizers',   3),
    ('WNG',  'Chicken Wings',        'Appetizers',   4),
    ('BRS',  'Bruschetta',           'Appetizers',   5),
    ('SOP',  'Soup of the Day',      'Soups',        6),
    -- Main Course
    ('GCK',  'Grilled Chicken',      'Main Course',  10),
    ('FCK',  'Fried Chicken',        'Main Course',  11),
    ('FRC',  'Fried Rice',           'Main Course',  12),
    ('JLF',  'Jollof Rice',          'Main Course',  13),
    ('BNK',  'Banku & Tilapia',      'Main Course',  14),
    ('FUF',  'Fufu & Soup',          'Main Course',  15),
    ('WCH',  'Waakye',               'Main Course',  16),
    ('BRG',  'Burger',               'Burgers',      17),
    ('CHB',  'Cheeseburger',         'Burgers',      18),
    ('PST',  'Pasta',                'Pasta',        19),
    ('PZZ',  'Pizza',                'Pizza',        20),
    ('STK',  'Steak',                'Main Course',  21),
    ('FSH',  'Grilled Fish',         'Seafood',      22),
    ('SHR',  'Shrimp / Prawns',      'Seafood',      23),
    ('LMB',  'Lamb Chops',           'Main Course',  24),
    ('WRP',  'Wrap / Burrito',       'Sandwiches',   25),
    ('SND',  'Sandwich',             'Sandwiches',   26),
    ('SLD',  'Salad',                'Salads',       27),
    -- Sides
    ('FRS',  'French Fries',         'Sides',        30),
    ('CLS',  'Coleslaw',             'Sides',        31),
    ('PLN',  'Plantain (Fried)',     'Sides',        32),
    ('YAM',  'Yam (Fried/Boiled)',   'Sides',        33),
    ('RCE',  'Plain Rice',           'Sides',        34),
    -- Desserts
    ('ICR',  'Ice Cream',            'Desserts',     40),
    ('CKE',  'Cake',                 'Desserts',     41),
    ('PNC',  'Pancakes',             'Desserts',     42),
    ('FRS',  'Fruit Salad',          'Desserts',     43),
    -- Beverages
    ('SFD',  'Soft Drink',           'Beverages',    50),
    ('JCE',  'Fresh Juice',          'Beverages',    51),
    ('SMT',  'Smoothie',             'Beverages',    52),
    ('WTR',  'Water',                'Beverages',    53),
    ('BER',  'Beer',                 'Beverages',    54),
    ('WNE',  'Wine',                 'Beverages',    55),
    ('CKT',  'Cocktail',             'Beverages',    56),
    ('CFE',  'Coffee',               'Hot Beverages',57),
    ('TEA',  'Tea',                  'Hot Beverages',58),
    ('MLT',  'Malt Drink',           'Beverages',    59),
    -- Other
    ('OTH',  'Other',                'Other',        99)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.sprestaurant_menuitemname_list()
 RETURNS SETOF restaurantmenuitemnames
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM restaurantmenuitemnames WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;
