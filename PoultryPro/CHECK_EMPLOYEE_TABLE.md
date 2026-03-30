# ✅ Employee Table Verification Guide

## **IMPORTANT: NO NEW TABLE NEEDED!**

Employees use the **existing `AspNetUsers` table** created by Identity.

---

## 🔍 How to Verify the Table Exists

### **Option 1: SQL Server Management Studio (SSMS)**

1. Open **SQL Server Management Studio**
2. Connect to your database server
3. Navigate to your database (the one in your connection string)
4. Expand **Tables**
5. Look for: **`AspNetUsers`**

You should see these columns:
```
AspNetUsers
├── Id (nvarchar)
├── UserName (nvarchar)
├── NormalizedUserName (nvarchar)
├── Email (nvarchar)
├── NormalizedEmail (nvarchar)
├── EmailConfirmed (bit)
├── PasswordHash (nvarchar)
├── SecurityStamp (nvarchar)
├── ConcurrencyStamp (nvarchar)
├── PhoneNumber (nvarchar)
├── PhoneNumberConfirmed (bit)
├── TwoFactorEnabled (bit)
├── LockoutEnd (datetimeoffset)
├── LockoutEnabled (bit)
├── AccessFailedCount (int)
├── FarmId (nvarchar) ← Custom column
├── FarmName (nvarchar) ← Custom column
├── IsStaff (bit) ← Custom column (KEY FOR EMPLOYEES!)
├── IsSubscriber (bit) ← Custom column
├── RefreshToken (nvarchar) ← Custom column
├── RefreshTokenExpiry (datetime2) ← Custom column
├── FirstName (nvarchar) ← Custom column
├── LastName (nvarchar) ← Custom column
└── CustomerId (nvarchar) ← Custom column
```

---

### **Option 2: Query the Database**

Run this SQL query in SSMS:

```sql
-- Check if table exists
SELECT TABLE_NAME 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_NAME = 'AspNetUsers'

-- View table structure
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'AspNetUsers'
ORDER BY ORDINAL_POSITION

-- Check existing users
SELECT 
    Id,
    UserName,
    Email,
    FirstName,
    LastName,
    FarmId,
    FarmName,
    IsStaff,
    EmailConfirmed
FROM AspNetUsers
```

---

### **Option 3: Check in Visual Studio**

1. Open **Server Explorer** in Visual Studio
2. Add a connection to your database
3. Expand **Tables**
4. Find **`AspNetUsers`**
5. Right-click → **Show Table Data**

---

## 🔍 What You Should See

### **Admin Record (IsStaff = 0)**
```
Id: some-guid
UserName: admin
Email: admin@farm.com
FirstName: John
LastName: Admin
FarmId: abc-123-farm-guid
FarmName: Sunny Farm
IsStaff: 0 (FALSE) ← This is an ADMIN
EmailConfirmed: 1
```

### **Employee Record (IsStaff = 1)**
```
Id: another-guid
UserName: johndoe
Email: john@farm.com
FirstName: John
LastName: Doe
FarmId: abc-123-farm-guid (SAME as admin!)
FarmName: Sunny Farm
IsStaff: 1 (TRUE) ← This is an EMPLOYEE
EmailConfirmed: 1
```

---

## 📋 Summary of Tables Used

| Table Name | Purpose |
|------------|---------|
| **AspNetUsers** | Stores ALL users (Admin & Employees) |
| AspNetRoles | Stores roles (Admin, Staff, User) |
| AspNetUserRoles | Maps users to roles |
| AspNetUserClaims | Stores user claims |
| AspNetUserLogins | External login providers |
| AspNetUserTokens | User tokens |

**You ONLY need to use `AspNetUsers`** - the other tables are managed by Identity automatically.

---

## ❓ FAQ

### Q: Do I need to create a separate `Employees` table?
**A:** ❌ **NO!** Use the existing `AspNetUsers` table with `IsStaff = true`

### Q: How does the system know who is an employee?
**A:** ✅ By checking the `IsStaff` column:
- `IsStaff = false` (or 0) → Admin
- `IsStaff = true` (or 1) → Employee

### Q: Can Admin and Employee have the same FarmId?
**A:** ✅ **YES!** This is how they share farm data:
```
Admin:     FarmId = "abc-123"
Employee1: FarmId = "abc-123" (same farm!)
Employee2: FarmId = "abc-123" (same farm!)
```

### Q: What if the table doesn't exist?
**A:** It was created when you ran migrations. If it doesn't exist:
1. Check your connection string in `appsettings.json`
2. Run migrations: `dotnet ef database update`

### Q: How do I add the `IsStaff` column if it's missing?
**A:** It should already be there from the `ApplicationUser` model. If not:
```bash
cd LoginAPI/User.Management.API
dotnet ef migrations add AddIsStaffColumn
dotnet ef database update
```

---

## 🎯 Code That Uses This Table

### When Admin Creates Employee

```csharp
// AdminService.cs
public async Task<ApplicationUser> CreateEmployeeAsync(ApplicationUser employee, string password)
{
    employee.IsStaff = true; ← Sets to TRUE for employees
    employee.SecurityStamp = Guid.NewGuid().ToString();
    employee.EmailConfirmed = true;
    
    var result = await _userManager.CreateAsync(employee, password);
    // Saves to AspNetUsers table!
}
```

### When Employee Logs In

```csharp
// AccountController.cs
var role = loginResponse.Response.IsStaff ? "Staff" : "Admin";
jwtClaims.Add(new Claim(ClaimTypes.Role, role));
```

### Query to Get Employees

```csharp
// AdminService.cs
var employees = await _userManager.Users
    .Where(u => u.IsStaff && u.FarmId == farmId)
    .ToListAsync();
// Queries AspNetUsers WHERE IsStaff = 1 AND FarmId = @farmId
```

---

## ✅ Conclusion

**You don't need to create any new tables!**

The employee management system uses:
- ✅ Existing `AspNetUsers` table
- ✅ `IsStaff` column to differentiate Admin vs Employee
- ✅ `FarmId` column to link them to the same farm
- ✅ Identity's built-in password hashing and authentication

**Everything is already set up!** Just create employees through the UI and they'll be stored in `AspNetUsers` with `IsStaff = true`.

---

## 🧪 Test It!

1. **Create an employee** through `/Employee/Index`
2. **Open SSMS** and run:
   ```sql
   SELECT UserName, Email, IsStaff, FarmId 
   FROM AspNetUsers 
   WHERE IsStaff = 1
   ```
3. You'll see your employee! ✅

---

**No database changes needed - the system is ready to use!** 🚀

