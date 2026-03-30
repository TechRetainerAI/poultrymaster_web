# Stored Procedure: spFlock_GetTotalQuantityForBatch

## 📋 Overview
This stored procedure calculates the total quantity of birds across all flocks for a specific batch. It's used to validate that the total quantity of flocks doesn't exceed the available birds in a batch.

## 🚀 Installation

### Step 1: Run the SQL Script
Execute the SQL script in your database:

```sql
-- Open SQL Server Management Studio (SSMS) or your preferred SQL client
-- Connect to your database: poultry2_Prod
-- Open and execute: spFlock_GetTotalQuantityForBatch.sql
```

### Step 2: Verify the Stored Procedure
After running the script, verify it was created:

```sql
-- Check if the stored procedure exists
SELECT * FROM sys.procedures 
WHERE name = 'spFlock_GetTotalQuantityForBatch';

-- Or test it directly
EXEC [dbo].[spFlock_GetTotalQuantityForBatch]
    @BatchId = 1,
    @UserId = 'your-user-guid',
    @FarmId = 'your-farm-guid',
    @FlockIdToExclude = NULL;
```

## 📝 Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `@BatchId` | INT | Yes | The batch ID to calculate total quantity for |
| `@UserId` | NVARCHAR(450) | Yes | The user ID (for filtering) |
| `@FarmId` | NVARCHAR(450) | Yes | The farm ID (for filtering) |
| `@FlockIdToExclude` | INT | No | Flock ID to exclude from calculation (useful when updating a flock) |

## 📤 Returns

Returns a single integer value: `TotalQuantity` - The sum of all `Quantity` values from flocks matching the criteria.

## 🔧 Usage Example

```sql
-- Get total quantity for a batch (excluding a specific flock during update)
EXEC [dbo].[spFlock_GetTotalQuantityForBatch]
    @BatchId = 1,
    @UserId = '3eae0c3a-d8c1-484a-9bcc-744ebe0b5dea',
    @FarmId = 'f4d89880-d5df-4d54-b744-c09cb0f278e2',
    @FlockIdToExclude = 123;  -- Exclude flock ID 123 from calculation

-- Get total quantity for a batch (all flocks)
EXEC [dbo].[spFlock_GetTotalQuantityForBatch]
    @BatchId = 1,
    @UserId = '3eae0c3a-d8c1-484a-9bcc-744ebe0b5dea',
    @FarmId = 'f4d89880-d5df-4d54-b744-c09cb0f278e2',
    @FlockIdToExclude = NULL;
```

## ⚠️ Important Notes

1. **Database**: Make sure you're connected to the correct database (`poultry2_Prod`)
2. **Permissions**: Ensure the application user has EXECUTE permissions on this stored procedure
3. **Backend Code**: The C# backend code (`BirdFlockService.cs`) is already updated to use this stored procedure
4. **Deployment**: After creating the stored procedure, deploy the updated backend code

## 🔄 After Installation

1. ✅ Run the SQL script to create the stored procedure
2. ✅ Deploy the updated backend from `PoultryPro\publish\PoultryFarmAPI\`
3. ✅ Restart the API service
4. ✅ Test flock creation to verify it works

## 🐛 Troubleshooting

### Error: "Could not find stored procedure"
- Make sure you ran the SQL script in the correct database
- Verify the stored procedure exists: `SELECT * FROM sys.procedures WHERE name = 'spFlock_GetTotalQuantityForBatch'`

### Error: "Permission denied"
- Grant EXECUTE permission to your application user:
  ```sql
  GRANT EXECUTE ON [dbo].[spFlock_GetTotalQuantityForBatch] TO [YourAppUser];
  ```

### Error: "Invalid object name 'Flock'"
- Verify the `Flock` table exists in your database
- Check that you're connected to the correct database

