# Check Employee Storage in Database

## ⚠️ IMPORTANT: Employees ARE Stored in AspNetUsers Table

Employees are stored in the **AspNetUsers** table via ASP.NET Identity. The `sp_CreateUser` stored procedure is **OPTIONAL** and only for a separate profile table.

## Verify Employees Are Stored

Run these SQL queries to check if employees are being stored:

### 1. Check All Employees (Staff) - PRIMARY QUERY
```sql
-- This is the main query - employees are stored here
SELECT 
    Id,
    UserName,
    Email,
    FirstName,
    LastName,
    PhoneNumber,
    FarmId,
    FarmName,
    IsStaff,
    EmailConfirmed,
    LockoutEnabled,
    AccessFailedCount,
    PasswordHash,  -- Should not be null if employee was created
    SecurityStamp  -- Should not be null if employee was created
FROM AspNetUsers
WHERE IsStaff = 1
ORDER BY UserName;
```

### 1b. Check if IsStaff Column Exists
```sql
-- If the above query fails, check if IsStaff column exists
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'AspNetUsers' 
    AND COLUMN_NAME LIKE '%Staff%' OR COLUMN_NAME LIKE '%Farm%';
```

### 2. Check All Users (Admin + Employees)
```sql
SELECT 
    Id,
    UserName,
    Email,
    FirstName,
    LastName,
    IsStaff,
    EmailConfirmed,
    FarmId,
    FarmName
FROM AspNetUsers
ORDER BY IsStaff, UserName;
```

### 3. Check Recent Employee Creations
```sql
SELECT TOP 10
    Id,
    UserName,
    Email,
    FirstName,
    LastName,
    IsStaff,
    EmailConfirmed,
    FarmId,
    FarmName
FROM AspNetUsers
WHERE IsStaff = 1
ORDER BY Id DESC;
```

### 4. Check if Stored Procedure Exists
```sql
SELECT 
    name,
    type_desc,
    create_date,
    modify_date
FROM sys.objects
WHERE name = 'sp_CreateUser'
    AND type = 'P';
```

## Note About Stored Procedure

The `sp_CreateUser` stored procedure is **OPTIONAL**. Employees are stored in the `AspNetUsers` table via ASP.NET Identity's `UserManager.CreateAsync()`. 

The stored procedure `sp_CreateUser` is only used for a separate user profile table and is not required for employee creation. If it doesn't exist, employees will still be created successfully in `AspNetUsers`.

## Troubleshooting

If employees aren't appearing in database:

### Step 1: Verify Employee Creation
Check backend logs when creating employee. You should see:
```
[AdminService] Employee '{UserName}' (ID: {Id}) created successfully in AspNetUsers table
```

### Step 2: Check Database Connection
Verify you're checking the **correct database**. Check `appsettings.json`:
```json
{
  "ConnectionStrings": {
    "ConnStr": "Your_Database_Connection_String"
  }
}
```

### Step 3: Check FarmId Match
Employees are filtered by FarmId. Make sure you're querying with the correct FarmId:
```sql
-- First, get your FarmId from your admin account
SELECT Id, UserName, FarmId, IsStaff 
FROM AspNetUsers 
WHERE IsStaff = 0;  -- Your admin account

-- Then check employees with the same FarmId
SELECT Id, UserName, FarmId, IsStaff 
FROM AspNetUsers 
WHERE IsStaff = 1 
    AND FarmId = 'YOUR_FARM_ID_HERE';  -- Use FarmId from above query
```

### Step 4: Check All Users (No Filter)
If employees still don't appear, check ALL users:
```sql
SELECT Id, UserName, Email, FarmId, IsStaff, EmailConfirmed
FROM AspNetUsers
ORDER BY IsStaff, UserName;
```

### Step 5: Verify Database Schema
Check if IsStaff and FarmId columns exist:
```sql
SELECT COLUMN_NAME, DATA_TYPE 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'AspNetUsers' 
    AND (COLUMN_NAME = 'IsStaff' OR COLUMN_NAME = 'FarmId');
```

### Step 6: Check for Transaction Issues
If using transactions, ensure they're committed:
- ASP.NET Identity's `UserManager.CreateAsync()` automatically commits
- No manual transaction needed

### Common Issues:

1. **Wrong Database**: You might be checking a different database than the one the API uses
2. **FarmId Mismatch**: Employee created with different FarmId than admin
3. **Column Missing**: IsStaff or FarmId columns don't exist (run migrations)
4. **Connection String**: API using different database than you're checking

