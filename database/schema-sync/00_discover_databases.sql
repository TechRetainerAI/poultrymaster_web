-- ============================================================
-- STEP 0: Discover databases on the server
-- Run this connected to [master] on 34.39.109.13.
-- Paste the full result back to Claude so we can confirm which
-- database is DEV and which is PROD before doing anything else.
-- ============================================================

SELECT
    d.name                                AS DatabaseName,
    d.state_desc                          AS State,
    d.create_date                         AS Created,
    d.compatibility_level                 AS CompatLevel,
    SUSER_SNAME(d.owner_sid)              AS Owner,
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB
FROM sys.databases d
JOIN sys.master_files mf ON mf.database_id = d.database_id
WHERE d.database_id > 4                   -- exclude system DBs
GROUP BY d.name, d.state_desc, d.create_date, d.compatibility_level, d.owner_sid
ORDER BY d.name;
