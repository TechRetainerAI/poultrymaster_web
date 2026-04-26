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

### 003_AddEggGradeToProductionRecords.sql
**Purpose:** Store egg quality grade (P1, P2, etc.) on each production record.

**What it does:**
1. Adds nullable `EggGrade` column (`NVARCHAR(50)`) to `ProductionRecords`
2. Updates `spProductionRecord_Insert`, `spProductionRecord_Update`, `spProductionRecord_GetById`, and `spProductionRecord_GetAll` to read/write `EggGrade`

**Result:** Farmers can select a grade when logging production; it appears in the list and exports.

## How to Run

### Option 1: SQL Server Management Studio (SSMS)
1. Open SSMS and connect to your database
2. Open each migration file in order (001 first, then 002, then 003)
3. Execute each script

### Option 2: Command Line (sqlcmd)

From the folder that contains the `.sql` files (`PoultryFarmAPI\Migrations`):

```powershell
cd path\to\PoultryFarmAPI\Migrations

# TrustServerCertificate=True  →  add -C
# Prefer not putting the password in shell history: set env var, then omit -P
$env:SQLCMDPASSWORD = "your-password-here"
sqlcmd -S YOUR_SERVER -d YOUR_DATABASE -U YOUR_LOGIN -C -b -i "001_UnifyProductionTables.sql"
sqlcmd -S YOUR_SERVER -d YOUR_DATABASE -U YOUR_LOGIN -C -b -i "002_SyncFeedUsageWithProductionRecord.sql"
sqlcmd -S YOUR_SERVER -d YOUR_DATABASE -U YOUR_LOGIN -C -b -i "003_AddEggGradeToProductionRecords.sql"
Remove-Item Env:SQLCMDPASSWORD
```

`-b` makes `sqlcmd` exit with a non-zero code if a batch fails (easier to spot errors).

#### Who can run these scripts?

Migrations **drop and recreate** stored procedures and may **alter tables**. The SQL login must be allowed to do that on `PoultryMaster`, for example:

- a member of **`db_owner`** on that database, or  
- **`db_ddladmin`**, or  
- the server/database administrator account you use for schema changes.

An application login that only has `SELECT`/`INSERT`/`UPDATE`/`EXEC` on procedures will often get:

`Msg 3701 ... Cannot drop the procedure ... because it does not exist or you do not have permission.`

In that case, run the same `sqlcmd` lines while connected as an **admin** login (or ask your DBA to run the scripts / grant temporary DDL rights).

**Security:** Do not paste production passwords or full connection strings into chat, tickets, or git. If a password was exposed, **rotate it** in SQL Server and update Cloud Run / app settings.

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
   SELECT TOP 1 * FROM dbo.ProductionRecords;
   -- After 001: BrokenEggs, Notes, EggCount. After 003: also EggGrade.
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
