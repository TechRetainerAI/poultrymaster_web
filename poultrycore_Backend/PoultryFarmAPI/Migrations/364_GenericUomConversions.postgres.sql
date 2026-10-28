-- Migration 364: Unit-of-measure conversion table for Generic products.
--
-- Allows businesses like yam sellers to define conversions between units:
-- e.g., 1 basket = 20 tubers, 1 crate = 50 tubers.
--
-- The conversion is per-product (yam baskets differ from tomato baskets) and
-- per-farm (every seller defines their own ratios).
--
-- Idempotent: safe to run multiple times.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'genericuomconversions') THEN
        CREATE TABLE genericuomconversions (
            genericuomconversionid SERIAL PRIMARY KEY,
            farmid VARCHAR(450) NOT NULL,
            genericproductid INT NULL,  -- NULL = farm-wide conversion
            fromunit VARCHAR(50) NOT NULL,
            tounit VARCHAR(50) NOT NULL,
            conversionfactor NUMERIC(14, 4) NOT NULL CHECK (conversionfactor > 0),
            isactive BOOLEAN NOT NULL DEFAULT TRUE,
            createdat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updatedat TIMESTAMPTZ NOT NULL DEFAULT NOW(),

            CONSTRAINT uq_genericuomconversions_product UNIQUE (farmid, genericproductid, fromunit, tounit)
        );

        CREATE INDEX ix_genericuomconversions_farmid ON genericuomconversions (farmid);
        CREATE INDEX ix_genericuomconversions_product ON genericuomconversions (genericproductid) WHERE genericproductid IS NOT NULL;

        COMMENT ON TABLE genericuomconversions IS
            '364. Unit-of-measure conversions. NULL genericproductid = farm-wide default. Non-null = product-specific override.';
        COMMENT ON COLUMN genericuomconversions.conversionfactor IS
            'How many tounit make one fromunit. E.g., 1 basket = 20 tubers → fromunit=basket, tounit=tuber, factor=20.';
    END IF;
END $$;

-- CRUD stored procedures
CREATE OR REPLACE FUNCTION spgenericuomconversion_list(p_farmid VARCHAR(450), p_productid INT DEFAULT NULL)
RETURNS TABLE(
    genericuomconversionid INT,
    farmid VARCHAR(450),
    genericproductid INT,
    fromunit VARCHAR(50),
    tounit VARCHAR(50),
    conversionfactor NUMERIC,
    isactive BOOLEAN
)
LANGUAGE sql STABLE AS $$
    SELECT c.genericuomconversionid, c.farmid, c.genericproductid,
           c.fromunit, c.tounit, c.conversionfactor, c.isactive
    FROM genericuomconversions c
    WHERE c.farmid = p_farmid
      AND (p_productid IS NULL OR c.genericproductid IS NULL OR c.genericproductid = p_productid)
      AND c.isactive = TRUE
    ORDER BY c.genericproductid NULLS FIRST, c.fromunit;
$$;

CREATE OR REPLACE FUNCTION spgenericuomconversion_upsert(
    p_farmid VARCHAR(450),
    p_productid INT,
    p_fromunit VARCHAR(50),
    p_tounit VARCHAR(50),
    p_factor NUMERIC
)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO genericuomconversions (farmid, genericproductid, fromunit, tounit, conversionfactor)
    VALUES (p_farmid, p_productid, p_fromunit, p_tounit, p_factor)
    ON CONFLICT (farmid, genericproductid, fromunit, tounit)
    DO UPDATE SET conversionfactor = EXCLUDED.conversionfactor, updatedat = NOW()
    RETURNING genericuomconversionid INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION spgenericuomconversion_delete(p_id INT, p_farmid VARCHAR(450))
RETURNS VOID
LANGUAGE sql AS $$
    DELETE FROM genericuomconversions WHERE genericuomconversionid = p_id AND farmid = p_farmid;
$$;
