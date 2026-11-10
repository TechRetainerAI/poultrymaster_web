-- Migration 367: Customer/student attendance for schools and gyms.
--
-- Generalizes attendance tracking to customers (not just staff). A school
-- tracks student attendance; a gym could track member check-ins.
--
-- Idempotent: safe to run multiple times.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'genericcustomerattendance') THEN
        CREATE TABLE genericcustomerattendance (
            genericcustomerattendanceid SERIAL PRIMARY KEY,
            farmid VARCHAR(450) NOT NULL,
            genericcustomerid INT NOT NULL,
            attendancedate DATE NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'Present',  -- Present, Absent, Late, HalfDay, Excused
            genericclassid INT NULL,  -- optional link to class (for schools)
            genericacademictermid INT NULL,  -- optional link to term
            notes VARCHAR(500) NULL,
            createdby VARCHAR(200) NULL,
            createdat TIMESTAMPTZ NOT NULL DEFAULT NOW(),

            CONSTRAINT uq_genericcustomerattendance UNIQUE (farmid, genericcustomerid, attendancedate)
        );

        CREATE INDEX ix_genericcustomerattendance_farmid ON genericcustomerattendance (farmid);
        CREATE INDEX ix_genericcustomerattendance_date ON genericcustomerattendance (farmid, attendancedate);
        CREATE INDEX ix_genericcustomerattendance_class ON genericcustomerattendance (genericclassid) WHERE genericclassid IS NOT NULL;
    END IF;
END $$;

-- CRUD stored procedures
CREATE OR REPLACE FUNCTION spgenericcustomerattendance_list(
    p_farmid VARCHAR(450), p_date DATE DEFAULT NULL, p_classid INT DEFAULT NULL
)
RETURNS TABLE(
    genericcustomerattendanceid INT, farmid VARCHAR(450),
    genericcustomerid INT, customername TEXT, classorgrade TEXT,
    attendancedate DATE, status VARCHAR(20),
    genericclassid INT, genericacademictermid INT,
    notes VARCHAR(500), createdby VARCHAR(200)
)
LANGUAGE sql STABLE AS $$
    SELECT a.genericcustomerattendanceid, a.farmid,
           a.genericcustomerid, c.customername, c.classorgrade,
           a.attendancedate, a.status,
           a.genericclassid, a.genericacademictermid,
           a.notes, a.createdby
    FROM genericcustomerattendance a
    JOIN genericcustomers c ON c.genericcustomerid = a.genericcustomerid AND c.farmid = a.farmid
    WHERE a.farmid = p_farmid
      AND (p_date IS NULL OR a.attendancedate = p_date)
      AND (p_classid IS NULL OR a.genericclassid = p_classid)
    ORDER BY c.customername;
$$;

CREATE OR REPLACE FUNCTION spgenericcustomerattendance_upsert(
    p_farmid VARCHAR(450), p_customerid INT, p_date DATE,
    p_status VARCHAR(20), p_classid INT, p_termid INT,
    p_notes VARCHAR(500), p_createdby VARCHAR(200)
)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO genericcustomerattendance
        (farmid, genericcustomerid, attendancedate, status, genericclassid, genericacademictermid, notes, createdby)
    VALUES (p_farmid, p_customerid, p_date, p_status, p_classid, p_termid, p_notes, p_createdby)
    ON CONFLICT (farmid, genericcustomerid, attendancedate)
    DO UPDATE SET status = EXCLUDED.status, genericclassid = EXCLUDED.genericclassid,
        genericacademictermid = EXCLUDED.genericacademictermid, notes = EXCLUDED.notes
    RETURNING genericcustomerattendanceid INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION spgenericcustomerattendance_delete(p_id INT, p_farmid VARCHAR(450))
RETURNS VOID LANGUAGE sql AS $$
    DELETE FROM genericcustomerattendance WHERE genericcustomerattendanceid = p_id AND farmid = p_farmid;
$$;
