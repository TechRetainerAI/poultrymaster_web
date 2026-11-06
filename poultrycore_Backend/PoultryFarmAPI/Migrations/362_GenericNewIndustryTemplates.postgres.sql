-- Migration 362: Add ProduceSeller, Grocery, Barbershop, Salon, HardwareShop,
-- ElectronicsShop, Wholesaler, Bakery, CarDealership, AutoRepair, Tailor,
-- Laundry, Pharmacy, Freelancer industry templates.
--
-- Creates spgenericbusinesstemplate_apply_extended which wraps the original
-- spgenericbusinesstemplate_apply, maps new industry names to known base
-- templates, then adds industry-specific seeding.
--
-- Idempotent: safe to run multiple times.

DROP FUNCTION IF EXISTS spgenericbusinesstemplate_apply_extended(VARCHAR, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION spgenericbusinesstemplate_apply_extended(
    p_farmid        VARCHAR(450),
    p_businesstemplate TEXT,
    p_industrytemplate TEXT,
    p_createdby     TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql AS $fn$
DECLARE
    v_base_industry TEXT;
    v_row RECORD;
BEGIN
    -- Map new industry templates to existing base templates
    v_base_industry := CASE p_industrytemplate
        WHEN 'ProduceSeller'   THEN 'Retail'
        WHEN 'Grocery'         THEN 'Retail'
        WHEN 'HardwareShop'    THEN 'Retail'
        WHEN 'ElectronicsShop' THEN 'Retail'
        WHEN 'Wholesaler'      THEN 'Retail'
        WHEN 'Bakery'          THEN 'Retail'
        WHEN 'CarDealership'   THEN 'Retail'
        WHEN 'Pharmacy'        THEN 'Retail'
        WHEN 'Barbershop'      THEN 'Other'
        WHEN 'Salon'           THEN 'Other'
        WHEN 'AutoRepair'      THEN 'Other'
        WHEN 'Tailor'          THEN 'Other'
        WHEN 'Laundry'         THEN 'Other'
        WHEN 'Freelancer'      THEN 'RetainerBusiness'
        ELSE p_industrytemplate
    END;

    -- Call the original SP with the mapped base industry
    PERFORM spgenericbusinesstemplate_apply(p_farmid, p_businesstemplate, v_base_industry, p_createdby);

    -- Update the actual industry template to the new one (the original set the base)
    UPDATE genericcompanyprofiles
    SET genericindustrytemplate = p_industrytemplate
    WHERE genericcompanyprofiles.farmid = p_farmid;

    -- Industry-specific INCOME categories
    IF p_industrytemplate = 'ProduceSeller' THEN
        FOR v_row IN SELECT unnest(ARRAY['Produce Sales','Yam Sales','Vegetable Sales','Fruit Sales']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Grocery' THEN
        FOR v_row IN SELECT unnest(ARRAY['Grocery Sales','Provisions Sales','Beverage Sales','Household Items Sales']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Barbershop' THEN
        FOR v_row IN SELECT unnest(ARRAY['Haircut Services','Beard & Shave Services','Product Sales']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Salon' THEN
        FOR v_row IN SELECT unnest(ARRAY['Hair Services','Nail Services','Skincare Services','Beauty Product Sales']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Pharmacy' THEN
        FOR v_row IN SELECT unnest(ARRAY['Prescription Medicine Sales','Over-the-Counter Sales','Health Products Sales','Medical Supplies Sales']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'HardwareShop' THEN
        FOR v_row IN SELECT unnest(ARRAY['Building Materials Sales','Electrical Supplies Sales','Plumbing Supplies Sales','Paint & Finishes Sales','Tools & Equipment Sales']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'ElectronicsShop' THEN
        FOR v_row IN SELECT unnest(ARRAY['Phone Sales','Accessories Sales','Gadget Sales','Repair Services Income']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Wholesaler' THEN
        FOR v_row IN SELECT unnest(ARRAY['Wholesale Sales','Bulk Order Sales','Distribution Income','Retail Markup Sales']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Bakery' THEN
        FOR v_row IN SELECT unnest(ARRAY['Bread Sales','Pastry Sales','Cake & Custom Orders','Wholesale Bakery Sales']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'CarDealership' THEN
        FOR v_row IN SELECT unnest(ARRAY['Vehicle Sales','Parts & Accessories Sales','Service & Repair Income','Finance & Insurance Income']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'AutoRepair' THEN
        FOR v_row IN SELECT unnest(ARRAY['Repair & Labour Income','Parts Sales','Diagnostic Services','Bodywork & Painting Income']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Tailor' THEN
        FOR v_row IN SELECT unnest(ARRAY['Custom Clothing Income','Alterations Income','Fabric Sales','Uniform Orders Income']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Laundry' THEN
        FOR v_row IN SELECT unnest(ARRAY['Washing Services','Dry Cleaning Services','Ironing Services','Special Items / Bulk Cleaning']) AS name
        LOOP
            INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericservicecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    END IF;

    -- Industry-specific EXPENSE categories
    IF p_industrytemplate = 'ProduceSeller' THEN
        FOR v_row IN SELECT unnest(ARRAY['Spoilage & Waste','Transport to Market','Market Stall / Space Rent','Loading & Offloading']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Grocery' THEN
        FOR v_row IN SELECT unnest(ARRAY['Expired / Damaged Stock','Shop Rent','Shop Maintenance','Display & Shelving']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate IN ('Barbershop', 'Salon') THEN
        FOR v_row IN SELECT unnest(ARRAY['Shop Rent','Equipment & Tools','Supplies & Consumables','Shop Maintenance']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Pharmacy' THEN
        FOR v_row IN SELECT unnest(ARRAY['Shop Rent','Expired Medicine Disposal','Regulatory Fees & Licences','Cold Storage & Equipment']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'HardwareShop' THEN
        FOR v_row IN SELECT unnest(ARRAY['Shop Rent','Warehouse Rent','Delivery & Transport','Breakage & Damage','Heavy Equipment Hire']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'ElectronicsShop' THEN
        FOR v_row IN SELECT unnest(ARRAY['Shop Rent','Warranty Claims & Returns','Display & Demo Units','Repair Parts & Tools','Shop Security']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Wholesaler' THEN
        FOR v_row IN SELECT unnest(ARRAY['Warehouse Rent','Delivery & Distribution','Loading & Offloading','Packaging Materials','Vehicle Maintenance']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Bakery' THEN
        FOR v_row IN SELECT unnest(ARRAY['Bakery Rent','Raw Ingredients','Packaging','Oven & Equipment Maintenance','Expired / Unsold Stock']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'CarDealership' THEN
        FOR v_row IN SELECT unnest(ARRAY['Showroom Rent','Vehicle Preparation & Cleaning','Vehicle Registration & Paperwork','Advertising & Marketing','Transport & Towing']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'AutoRepair' THEN
        FOR v_row IN SELECT unnest(ARRAY['Workshop Rent','Tools & Equipment','Spare Parts Purchases','Vehicle Towing','Waste Disposal (Oil, Tyres)']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Tailor' THEN
        FOR v_row IN SELECT unnest(ARRAY['Workshop Rent','Fabric & Materials','Thread & Accessories','Sewing Machine Maintenance','Pattern & Design Supplies']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    ELSIF p_industrytemplate = 'Laundry' THEN
        FOR v_row IN SELECT unnest(ARRAY['Shop Rent','Detergents & Chemicals','Water & Utilities','Machine Maintenance','Packaging & Hangers']) AS name
        LOOP
            INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat, updatedat)
            SELECT p_farmid, v_row.name, TRUE, FALSE, NOW(), NOW()
            WHERE NOT EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = p_farmid AND c.name = v_row.name);
        END LOOP;
    END IF;

    -- =====================================================================
    -- School: seed default classes (Ghanaian education system)
    -- =====================================================================
    IF p_industrytemplate = 'School' THEN
        FOR v_row IN
            SELECT * FROM (VALUES
                ('Creche / Nursery', 0),
                ('Kindergarten 1 (KG1)', 1),
                ('Kindergarten 2 (KG2)', 2),
                ('Primary 1', 3),
                ('Primary 2', 4),
                ('Primary 3', 5),
                ('Primary 4', 6),
                ('Primary 5', 7),
                ('Primary 6', 8),
                ('JHS 1', 9),
                ('JHS 2', 10),
                ('JHS 3', 11),
                ('SHS 1', 12),
                ('SHS 2', 13),
                ('SHS 3', 14)
            ) AS t(classname, classlevel)
        LOOP
            INSERT INTO genericclasses (farmid, classname, classlevel, isactive)
            SELECT p_farmid, v_row.classname, v_row.classlevel, TRUE
            WHERE NOT EXISTS (
                SELECT 1 FROM genericclasses c WHERE c.farmid = p_farmid AND c.classname = v_row.classname
            );
        END LOOP;
    END IF;
END;
$fn$;
