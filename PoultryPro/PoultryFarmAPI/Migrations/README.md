# Database Migrations

## Overview
These SQL migration scripts update the database schema to unify data tables across the application.

## Migration Scripts

### 001_UnifyProductionTables.sql
**Purpose:** Unifies Production Records and Egg Production pages to use the same database table.

**What it does:**
1. Adds `BrokenEggs`, `Notes`, and `EggCount` columns to the `ProductionRecord` table
2. Updates all `spProductionRecord_*` stored procedures to handle new columns
3. Updates all `spEggProduction_*` stored procedures to read/write from `ProductionRecord` table
4. Migrates existing `EggProduction` data to `ProductionRecord` (if any exists)

**Result:** Both Production Records page and Egg Production page now use the same `ProductionRecord` table.

### 002_SyncFeedUsageWithProductionRecord.sql
**Purpose:** Automatically syncs Feed Usage data when Production Records are created/updated.

**What it does:**
1. Adds `SourceProductionRecordId` column to `FeedUsage` table
2. Creates triggers on `ProductionRecord` table:
   - `trg_ProductionRecord_InsertFeedUsage` - Creates FeedUsage when ProductionRecord is inserted with FeedKg > 0
   - `trg_ProductionRecord_UpdateFeedUsage` - Updates/deletes FeedUsage when ProductionRecord is updated
   - `trg_ProductionRecord_DeleteFeedUsage` - Deletes FeedUsage when ProductionRecord is deleted
3. Migrates existing ProductionRecord feed data to FeedUsage table
4. Updates stored procedures to include source information

**Result:** When you enter FeedKg in Production Records, it automatically appears in Feed Usage page.

## How to Run

### Option 1: SQL Server Management Studio (SSMS)
1. Open SSMS and connect to your database
2. Open each migration file in order (001 first, then 002)
3. Execute each script

### Option 2: Command Line (sqlcmd)
```powershell
# Run migration 001
sqlcmd -S YOUR_SERVER -d YOUR_DATABASE -i "001_UnifyProductionTables.sql"

# Run migration 002
sqlcmd -S YOUR_SERVER -d YOUR_DATABASE -i "002_SyncFeedUsageWithProductionRecord.sql"
```

### Option 3: Azure Data Studio
1. Connect to your database
2. Open each migration file
3. Run each script in order

## Important Notes

1. **Backup First!** Always backup your database before running migrations.
2. **Run in Order:** Migrations must be run in numerical order.
3. **One-Time:** These migrations are designed to be run once. Running them multiple times is safe (they check for existing columns/procedures before creating).
4. **Deploy API After:** After running migrations, rebuild and redeploy the API to use the updated stored procedures.

## Verification

After running migrations, verify:

1. **Production Records Table:**
   ```sql
   SELECT TOP 1 * FROM ProductionRecord;
   -- Should have BrokenEggs, Notes, EggCount columns
   ```

2. **Egg Production reads from same table:**
   ```sql
   EXEC spEggProduction_GetAll @FarmId = 'your-farm-id';
   -- Should return data from ProductionRecord table
   ```

3. **Feed Usage sync:**
   ```sql
   -- Insert a production record with FeedKg > 0
   -- Then check FeedUsage table - should have a new record
   SELECT * FROM FeedUsage WHERE SourceProductionRecordId IS NOT NULL;
   ```

