-- 439: Generic Production Records
-- Tracks goods produced by a business (not purchased). Each record increases
-- the product's stock via a stock movement of type 'Production'.

DO $$ BEGIN

-- ============================================================================
-- Table
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'genericproductionrecords') THEN
  CREATE TABLE genericproductionrecords (
    "GenericProductionRecordId" SERIAL PRIMARY KEY,
    "FarmId"                   TEXT NOT NULL,
    "GenericProductId"         INT NOT NULL,
    "QuantityProduced"         NUMERIC(18,4) NOT NULL DEFAULT 0,
    "ProductionDate"           TIMESTAMP NOT NULL DEFAULT NOW(),
    "UnitCost"                 NUMERIC(18,4) DEFAULT 0,
    "TotalCost"                NUMERIC(18,4) DEFAULT 0,
    "BatchNumber"              TEXT,
    "MaterialsUsed"            TEXT,       -- free-text description of inputs
    "Notes"                    TEXT,
    "Status"                   TEXT NOT NULL DEFAULT 'Posted',  -- Posted | Reversed
    "ReversalReason"           TEXT,
    "CreatedBy"                TEXT,
    "ReversedBy"               TEXT,
    "ReversedAt"               TIMESTAMP,
    "CreatedAt"                TIMESTAMP NOT NULL DEFAULT NOW()
  );
  CREATE INDEX idx_genericproductionrecords_farm ON genericproductionrecords ("FarmId");
  CREATE INDEX idx_genericproductionrecords_product ON genericproductionrecords ("GenericProductId");
END IF;

-- ============================================================================
-- List all production records for a farm
-- ============================================================================
CREATE OR REPLACE FUNCTION spgenericproductionrecord_getall(
  p_farmid TEXT,
  p_status TEXT DEFAULT NULL
)
RETURNS TABLE(
  "GenericProductionRecordId" INT,
  "FarmId"                   TEXT,
  "GenericProductId"         INT,
  "ProductName"              TEXT,
  "QuantityProduced"         NUMERIC,
  "ProductionDate"           TIMESTAMP,
  "UnitCost"                 NUMERIC,
  "TotalCost"                NUMERIC,
  "BatchNumber"              TEXT,
  "MaterialsUsed"            TEXT,
  "Notes"                    TEXT,
  "Status"                   TEXT,
  "ReversalReason"           TEXT,
  "CreatedBy"                TEXT,
  "ReversedBy"               TEXT,
  "ReversedAt"               TIMESTAMP,
  "CreatedAt"                TIMESTAMP
) LANGUAGE plpgsql AS $fn$
BEGIN
  RETURN QUERY
  SELECT
    pr."GenericProductionRecordId",
    pr."FarmId",
    pr."GenericProductId",
    p."ProductName",
    pr."QuantityProduced",
    pr."ProductionDate",
    pr."UnitCost",
    pr."TotalCost",
    pr."BatchNumber",
    pr."MaterialsUsed",
    pr."Notes",
    pr."Status",
    pr."ReversalReason",
    pr."CreatedBy",
    pr."ReversedBy",
    pr."ReversedAt",
    pr."CreatedAt"
  FROM genericproductionrecords pr
  LEFT JOIN genericproducts p ON p."GenericProductId" = pr."GenericProductId"
  WHERE pr."FarmId" = p_farmid
    AND (p_status IS NULL OR pr."Status" = p_status)
  ORDER BY pr."ProductionDate" DESC, pr."GenericProductionRecordId" DESC;
END;
$fn$;

-- ============================================================================
-- Insert a production record + create stock movement
-- ============================================================================
CREATE OR REPLACE FUNCTION spgenericproductionrecord_insert(
  p_farmid           TEXT,
  p_genericproductid INT,
  p_quantityproduced NUMERIC,
  p_productiondate   TIMESTAMP,
  p_unitcost         NUMERIC DEFAULT 0,
  p_batchnumber      TEXT DEFAULT NULL,
  p_materialsused    TEXT DEFAULT NULL,
  p_notes            TEXT DEFAULT NULL,
  p_createdby        TEXT DEFAULT NULL
)
RETURNS INT LANGUAGE plpgsql AS $fn$
DECLARE
  v_id INT;
  v_totalcost NUMERIC;
BEGIN
  v_totalcost := p_quantityproduced * COALESCE(p_unitcost, 0);

  INSERT INTO genericproductionrecords (
    "FarmId", "GenericProductId", "QuantityProduced", "ProductionDate",
    "UnitCost", "TotalCost", "BatchNumber", "MaterialsUsed", "Notes",
    "Status", "CreatedBy", "CreatedAt"
  ) VALUES (
    p_farmid, p_genericproductid, p_quantityproduced, p_productiondate,
    p_unitcost, v_totalcost, p_batchnumber, p_materialsused, p_notes,
    'Posted', p_createdby, NOW()
  ) RETURNING "GenericProductionRecordId" INTO v_id;

  -- Create stock movement (increase stock)
  INSERT INTO genericstockmovements (
    "FarmId", "GenericProductId", "MovementDate", "MovementType",
    "Quantity", "UnitCost", "TotalCostValue", "Reason", "Notes",
    "Status", "CreatedAt"
  ) VALUES (
    p_farmid, p_genericproductid, p_productiondate, 'Production',
    p_quantityproduced, p_unitcost, v_totalcost,
    'Production record #' || v_id,
    COALESCE(p_batchnumber, '') || CASE WHEN p_notes IS NOT NULL THEN ' - ' || p_notes ELSE '' END,
    'Approved', NOW()
  );

  -- Update product current stock
  UPDATE genericproducts
  SET "CurrentStock" = "CurrentStock" + p_quantityproduced
  WHERE "GenericProductId" = p_genericproductid AND "FarmId" = p_farmid;

  RETURN v_id;
END;
$fn$;

-- ============================================================================
-- Reverse a production record
-- ============================================================================
CREATE OR REPLACE FUNCTION spgenericproductionrecord_reverse(
  p_id             INT,
  p_farmid         TEXT,
  p_reason         TEXT,
  p_reversedby     TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE
  v_qty NUMERIC;
  v_productid INT;
  v_unitcost NUMERIC;
  v_totalcost NUMERIC;
  v_proddate TIMESTAMP;
BEGIN
  SELECT "QuantityProduced", "GenericProductId", "UnitCost", "TotalCost", "ProductionDate"
  INTO v_qty, v_productid, v_unitcost, v_totalcost, v_proddate
  FROM genericproductionrecords
  WHERE "GenericProductionRecordId" = p_id AND "FarmId" = p_farmid AND "Status" = 'Posted';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Production record not found or already reversed';
  END IF;

  UPDATE genericproductionrecords
  SET "Status" = 'Reversed', "ReversalReason" = p_reason,
      "ReversedBy" = p_reversedby, "ReversedAt" = NOW()
  WHERE "GenericProductionRecordId" = p_id;

  -- Reverse stock movement
  INSERT INTO genericstockmovements (
    "FarmId", "GenericProductId", "MovementDate", "MovementType",
    "Quantity", "UnitCost", "TotalCostValue", "Reason", "Notes",
    "Status", "CreatedAt"
  ) VALUES (
    p_farmid, v_productid, NOW(), 'Reversal',
    -v_qty, v_unitcost, -v_totalcost,
    'Reversal of production #' || p_id, p_reason,
    'Approved', NOW()
  );

  -- Reduce product stock
  UPDATE genericproducts
  SET "CurrentStock" = "CurrentStock" - v_qty
  WHERE "GenericProductId" = v_productid AND "FarmId" = p_farmid;
END;
$fn$;

END $$;
