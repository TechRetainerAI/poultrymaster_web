-- 446_FixGenericProductionStockMovementStatus.postgres.sql
-- Recording (or reversing) a Generic production record failed with
--   column "status" of relation "genericstockmovements" does not exist
-- spgenericproductionrecord_insert (442) and spgenericproductionrecord_reverse (439)
-- wrote a "status" column that genericstockmovements has never had. Every other
-- writer of that table (e.g. the opening-stock insert in 441) leaves it out.
-- Re-create both functions unchanged except that the movement is marked approved
-- through the existing approvedat column instead of the missing status column.
-- Idempotent (CREATE OR REPLACE, same signatures).

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
  v_productcost NUMERIC;
BEGIN
  v_totalcost := p_quantityproduced * COALESCE(p_unitcost, 0);

  -- Get the product's current cost price for material cost tracking
  SELECT costprice INTO v_productcost
  FROM genericproducts
  WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

  INSERT INTO genericproductionrecords (
    "FarmId", "GenericProductId", "QuantityProduced", "ProductionDate",
    "UnitCost", "TotalCost", "BatchNumber", "MaterialsUsed", "Notes",
    "Status", "CreatedBy", "CreatedAt",
    "MaterialCostPerUnit", "TotalMaterialCost", "CostTransferMethod"
  ) VALUES (
    p_farmid, p_genericproductid, p_quantityproduced, p_productiondate,
    p_unitcost, v_totalcost, p_batchnumber, p_materialsused, p_notes,
    'Posted', p_createdby, NOW(),
    COALESCE(p_unitcost, v_productcost, 0),
    COALESCE(p_unitcost, v_productcost, 0) * p_quantityproduced,
    'Exact'
  ) RETURNING "GenericProductionRecordId" INTO v_id;

  -- Stock movement (production increases stock)
  INSERT INTO genericstockmovements (
    farmid, genericproductid, movementdate, movementtype,
    quantity, unitcost, totalcostvalue, reason, notes,
    approvedat, createdat
  ) VALUES (
    p_farmid, p_genericproductid, p_productiondate, 'Production',
    p_quantityproduced, p_unitcost, v_totalcost,
    'Production record #' || v_id,
    COALESCE(p_batchnumber, '') || CASE WHEN p_notes IS NOT NULL THEN ' - ' || p_notes ELSE '' END,
    NOW(), NOW()
  );

  -- Update product current stock
  UPDATE genericproducts
  SET currentstock = currentstock + p_quantityproduced
  WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

  RETURN v_id;
END;
$fn$;

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

  -- Reverse stock movement (lowercase columns)
  INSERT INTO genericstockmovements (
    farmid, genericproductid, movementdate, movementtype,
    quantity, unitcost, totalcostvalue, reason, notes,
    approvedat, createdat
  ) VALUES (
    p_farmid, v_productid, NOW(), 'Reversal',
    -v_qty, v_unitcost, -v_totalcost,
    'Reversal of production #' || p_id, p_reason,
    NOW(), NOW()
  );

  -- Reduce product stock (lowercase columns)
  UPDATE genericproducts
  SET currentstock = currentstock - v_qty
  WHERE genericproductid = v_productid AND farmid = p_farmid;
END;
$fn$;
