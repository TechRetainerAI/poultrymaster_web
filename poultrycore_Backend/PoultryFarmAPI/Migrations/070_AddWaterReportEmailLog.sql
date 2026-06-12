/* =============================================================================
   070_AddWaterReportEmailLog.sql

   Prompt 2 Part 3 §3 — backend stub for future "Email this report to the
   owner" functionality. The frontend currently shows a disabled "Email
   report" button (Coming soon). When email infrastructure is added later,
   the API can write into this table and a worker can pick it up.

   No service/controller built yet — schema only so future email work plugs
   in cleanly without breaking what's already deployed.

   Columns:
     ReportType         — slug identifier (sales-report, daily-summary, …)
     FiltersJson        — the exact filter set the user chose, captured at
                          generation time so the email worker can replay the
                          query without trusting client-side selections.
     GeneratedBy        — user id who clicked Email
     GeneratedAt        — when they clicked
     PdfPath            — optional Cloud Storage / blob URL (future)
     EmailTo            — recipient (defaults to farm owner)
     EmailStatus        — Pending | Sending | Sent | Failed | Cancelled
     ScheduledAt        — for later-scheduled sends
     SentAt             — populated on success
     ErrorMessage       — populated on failure

   Idempotent.
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.WaterReportEmailLog', 'U') IS NULL
BEGIN
    PRINT 'Creating dbo.WaterReportEmailLog';
    CREATE TABLE dbo.WaterReportEmailLog (
        WaterReportEmailLogId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                 NVARCHAR(450)  NOT NULL,
        ReportType             NVARCHAR(60)   NOT NULL,
        FiltersJson            NVARCHAR(MAX)  NULL,
        GeneratedBy            NVARCHAR(450)  NULL,
        GeneratedAt            DATETIME2      NOT NULL CONSTRAINT DF_WaterReportEmailLog_GeneratedAt DEFAULT (SYSUTCDATETIME()),
        PdfPath                NVARCHAR(500)  NULL,
        EmailTo                NVARCHAR(200)  NULL,
        EmailStatus            NVARCHAR(20)   NOT NULL CONSTRAINT DF_WaterReportEmailLog_Status DEFAULT ('Pending'),
        ScheduledAt            DATETIME2      NULL,
        SentAt                 DATETIME2      NULL,
        ErrorMessage           NVARCHAR(1000) NULL
    );

    CREATE INDEX IX_WaterReportEmailLog_FarmId   ON dbo.WaterReportEmailLog (FarmId);
    CREATE INDEX IX_WaterReportEmailLog_Status   ON dbo.WaterReportEmailLog (EmailStatus);
    CREATE INDEX IX_WaterReportEmailLog_Sched    ON dbo.WaterReportEmailLog (ScheduledAt) WHERE ScheduledAt IS NOT NULL;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT SELECT, INSERT, UPDATE ON dbo.WaterReportEmailLog TO PoultryAppRole;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Techretainer')
BEGIN
    GRANT SELECT, INSERT, UPDATE ON dbo.WaterReportEmailLog TO Techretainer;
END
GO

PRINT '070_AddWaterReportEmailLog.sql complete.';
GO
