-- Migration 366: Classes and Academic Terms for school businesses.
--
-- GenericClasses: "Primary 1", "JSS 2", "Kindergarten" etc.
-- GenericAcademicTerms: "Term 1 2026", "Semester 2 2026" etc.
--
-- Both are FarmId-scoped and only used by school businesses, but stored in the
-- same database as all Generic companies (no separate schema).
--
-- Idempotent: safe to run multiple times.

DO $$
BEGIN
    -- =========================================================================
    -- Classes
    -- =========================================================================
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'genericclasses') THEN
        CREATE TABLE genericclasses (
            genericclassid SERIAL PRIMARY KEY,
            farmid VARCHAR(450) NOT NULL,
            classname VARCHAR(100) NOT NULL,
            classlevel INT NULL,                  -- sortable numeric level (1, 2, 3…)
            classteacher VARCHAR(200) NULL,
            capacity INT NULL,
            description VARCHAR(500) NULL,
            isactive BOOLEAN NOT NULL DEFAULT TRUE,
            createdat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updatedat TIMESTAMPTZ NOT NULL DEFAULT NOW(),

            CONSTRAINT uq_genericclasses_name UNIQUE (farmid, classname)
        );

        CREATE INDEX ix_genericclasses_farmid ON genericclasses (farmid);
    END IF;

    -- =========================================================================
    -- Academic Terms
    -- =========================================================================
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'genericacademicterms') THEN
        CREATE TABLE genericacademicterms (
            genericacademictermid SERIAL PRIMARY KEY,
            farmid VARCHAR(450) NOT NULL,
            termname VARCHAR(100) NOT NULL,
            startdate DATE NOT NULL,
            enddate DATE NOT NULL,
            iscurrent BOOLEAN NOT NULL DEFAULT FALSE,
            isactive BOOLEAN NOT NULL DEFAULT TRUE,
            createdat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updatedat TIMESTAMPTZ NOT NULL DEFAULT NOW(),

            CONSTRAINT uq_genericacademicterms_name UNIQUE (farmid, termname),
            CONSTRAINT chk_genericacademicterms_dates CHECK (enddate > startdate)
        );

        CREATE INDEX ix_genericacademicterms_farmid ON genericacademicterms (farmid);
    END IF;
END $$;

-- =========================================================================
-- CRUD stored procedures
-- =========================================================================

-- Classes
CREATE OR REPLACE FUNCTION spgenericclass_list(p_farmid VARCHAR(450))
RETURNS TABLE(genericclassid INT, farmid VARCHAR(450), classname VARCHAR(100), classlevel INT,
              classteacher VARCHAR(200), capacity INT, description VARCHAR(500), isactive BOOLEAN,
              studentcount BIGINT)
LANGUAGE sql STABLE AS $$
    SELECT c.genericclassid, c.farmid, c.classname, c.classlevel,
           c.classteacher, c.capacity, c.description, c.isactive,
           (SELECT COUNT(*) FROM genericcustomers s
            WHERE s.farmid = c.farmid AND s.classorgrade = c.classname AND s.isdeleted = FALSE) AS studentcount
    FROM genericclasses c
    WHERE c.farmid = p_farmid
    ORDER BY c.classlevel NULLS LAST, c.classname;
$$;

CREATE OR REPLACE FUNCTION spgenericclass_upsert(
    p_farmid VARCHAR(450), p_id INT, p_classname VARCHAR(100), p_classlevel INT,
    p_classteacher VARCHAR(200), p_capacity INT, p_description VARCHAR(500), p_isactive BOOLEAN
)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_id INT;
BEGIN
    IF p_id IS NOT NULL AND p_id > 0 THEN
        UPDATE genericclasses SET classname = p_classname, classlevel = p_classlevel,
            classteacher = p_classteacher, capacity = p_capacity, description = p_description,
            isactive = p_isactive, updatedat = NOW()
        WHERE genericclassid = p_id AND farmid = p_farmid
        RETURNING genericclassid INTO v_id;
    ELSE
        INSERT INTO genericclasses (farmid, classname, classlevel, classteacher, capacity, description, isactive)
        VALUES (p_farmid, p_classname, p_classlevel, p_classteacher, p_capacity, p_description, p_isactive)
        RETURNING genericclassid INTO v_id;
    END IF;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION spgenericclass_delete(p_id INT, p_farmid VARCHAR(450))
RETURNS VOID LANGUAGE sql AS $$
    DELETE FROM genericclasses WHERE genericclassid = p_id AND farmid = p_farmid;
$$;

-- Academic Terms
CREATE OR REPLACE FUNCTION spgenericacademicterm_list(p_farmid VARCHAR(450))
RETURNS TABLE(genericacademictermid INT, farmid VARCHAR(450), termname VARCHAR(100),
              startdate DATE, enddate DATE, iscurrent BOOLEAN, isactive BOOLEAN)
LANGUAGE sql STABLE AS $$
    SELECT t.genericacademictermid, t.farmid, t.termname, t.startdate, t.enddate,
           t.iscurrent, t.isactive
    FROM genericacademicterms t
    WHERE t.farmid = p_farmid
    ORDER BY t.startdate DESC;
$$;

CREATE OR REPLACE FUNCTION spgenericacademicterm_upsert(
    p_farmid VARCHAR(450), p_id INT, p_termname VARCHAR(100),
    p_startdate DATE, p_enddate DATE, p_iscurrent BOOLEAN, p_isactive BOOLEAN
)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_id INT;
BEGIN
    -- If setting as current, unset any other current term
    IF p_iscurrent THEN
        UPDATE genericacademicterms SET iscurrent = FALSE WHERE farmid = p_farmid AND iscurrent = TRUE;
    END IF;

    IF p_id IS NOT NULL AND p_id > 0 THEN
        UPDATE genericacademicterms SET termname = p_termname, startdate = p_startdate,
            enddate = p_enddate, iscurrent = p_iscurrent, isactive = p_isactive, updatedat = NOW()
        WHERE genericacademictermid = p_id AND farmid = p_farmid
        RETURNING genericacademictermid INTO v_id;
    ELSE
        INSERT INTO genericacademicterms (farmid, termname, startdate, enddate, iscurrent, isactive)
        VALUES (p_farmid, p_termname, p_startdate, p_enddate, p_iscurrent, p_isactive)
        RETURNING genericacademictermid INTO v_id;
    END IF;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION spgenericacademicterm_delete(p_id INT, p_farmid VARCHAR(450))
RETURNS VOID LANGUAGE sql AS $$
    DELETE FROM genericacademicterms WHERE genericacademictermid = p_id AND farmid = p_farmid;
$$;
