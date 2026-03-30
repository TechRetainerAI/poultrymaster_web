-- Chat tables for staff ↔ admin/farm owner messaging

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = 'ChatThreads' AND type = 'U')
BEGIN
  CREATE TABLE [dbo].[ChatThreads] (
    [ThreadId] UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    [FarmId] NVARCHAR(100) NOT NULL,
    [CreatedBy] NVARCHAR(100) NOT NULL,
    [CreatedAt] DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_ChatThreads PRIMARY KEY ([ThreadId])
  );
END

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = 'ChatParticipants' AND type = 'U')
BEGIN
  CREATE TABLE [dbo].[ChatParticipants] (
    [ThreadId] UNIQUEIDENTIFIER NOT NULL,
    [UserId] NVARCHAR(100) NOT NULL,
    [Role] NVARCHAR(50) NULL,
    [LastReadAt] DATETIME2 NULL,
    CONSTRAINT PK_ChatParticipants PRIMARY KEY ([ThreadId],[UserId]),
    CONSTRAINT FK_ChatParticipants_Threads FOREIGN KEY ([ThreadId]) REFERENCES [dbo].[ChatThreads]([ThreadId]) ON DELETE CASCADE
  );
END

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = 'ChatMessages' AND type = 'U')
BEGIN
  CREATE TABLE [dbo].[ChatMessages] (
    [MessageId] UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    [ThreadId] UNIQUEIDENTIFIER NOT NULL,
    [UserId] NVARCHAR(100) NOT NULL,
    [Content] NVARCHAR(MAX) NOT NULL,
    [CreatedAt] DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    [IsRead] BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_ChatMessages PRIMARY KEY ([MessageId]),
    CONSTRAINT FK_ChatMessages_Threads FOREIGN KEY ([ThreadId]) REFERENCES [dbo].[ChatThreads]([ThreadId]) ON DELETE CASCADE
  );
END

-- Helpful indexes
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ChatMessages_ThreadId_CreatedAt')
BEGIN
  CREATE INDEX IX_ChatMessages_ThreadId_CreatedAt ON [dbo].[ChatMessages]([ThreadId],[CreatedAt] DESC);
END


