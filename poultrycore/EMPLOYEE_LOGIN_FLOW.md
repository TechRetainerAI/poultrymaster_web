# 🔐 Employee Login Flow - Complete Guide

## Overview
This document explains how the **Admin → Employee → Login** workflow works in PoultryPro.

---

## 📋 The Flow

### 1️⃣ **Admin Registers**
- Admin creates an account at `/Account/Register`
- System creates:
  - User account with `IsStaff = false`
  - Unique `FarmId` (GUID)
  - Role: `Admin` or `FarmAdmin`

### 2️⃣ **Admin Creates Employee**
- Admin logs in and navigates to **Employee Management** (`/Employee/Index`)
- Admin clicks "Add New Employee"
- Admin fills in employee details:
  - First Name
  - Last Name
  - Email
  - Phone Number
  - **Username** (for employee login)
  - **Password** (for employee login)
- System creates employee with:
  - `IsStaff = true`
  - Same `FarmId` as admin
  - `EmailConfirmed = true` (auto-confirmed)
  - Role: `Staff` or `User`

### 3️⃣ **Employee Logs In**
- Employee goes to `/Account/Login`
- Employee enters:
  - **Username** (created by admin)
  - **Password** (created by admin)
- System validates credentials
- Login adds these claims:
  ```csharp
  IsStaff = "true"
  FarmId = "admin's-farm-id"
  FarmName = "Farm Name"
  Role = "Staff"
  ```

### 4️⃣ **Dashboard Redirect**
After successful login, the system checks the role:

**If Admin** (`IsStaff = false`):
- Redirects to → `/Home/AdminDashboard`
- Shows full access with Employee Management

**If Employee** (`IsStaff = true`):
- Redirects to → `/Home/EmployeeDashboard`  
- Shows limited access (no delete/edit permissions)

---

## 🔍 Code Flow

### Login Process (`AccountController.cs`)

```csharp
[HttpPost]
public async Task<IActionResult> Login(LoginModel loginModel)
{
    var loginResponse = await _authenticationService.LoginAsync(loginModel);
    
    if (loginResponse.IsSuccess)
    {
        // Add claims including IsStaff
        jwtClaims.Add(new Claim("IsStaff", loginResponse.Response.IsStaff.ToString()));
        
        // Set role based on IsStaff
        var role = loginResponse.Response.IsStaff ? "Staff" : "Admin";
        jwtClaims.Add(new Claim(ClaimTypes.Role, role));
        
        // Add FarmId and FarmName
        jwtClaims.Add(new Claim("FarmId", loginResponse.Response.FarmId));
        jwtClaims.Add(new Claim("FarmName", loginResponse.Response.FarmName));
        
        // Sign in user
        await HttpContext.SignInAsync("PoultryFarmSoftwareCookieScheme", claimsPrincipal);
        
        // Redirect to Home/Index (which then redirects based on role)
        return RedirectToAction("Index", "Home");
    }
}
```

### Dashboard Redirect (`HomeController.cs`)

```csharp
public IActionResult Index()
{
    var isStaff = User.FindFirst("IsStaff")?.Value;
    var role = User.FindFirst(ClaimTypes.Role)?.Value;
    
    if (isStaff == "true" || role == "Staff")
    {
        // Employee Dashboard
        return RedirectToAction("EmployeeDashboard");
    }
    else
    {
        // Admin Dashboard
        return RedirectToAction("AdminDashboard");
    }
}
```

---

## 🎨 Dashboard Differences

### Admin Dashboard (`/Home/AdminDashboard`)
✅ Full access to all features  
✅ **Employee Management** (highlighted in green)  
✅ Can create, edit, delete all records  
✅ Can view reports and analytics  
✅ Manage farm settings

### Employee Dashboard (`/Home/EmployeeDashboard`)
✅ View all farm data  
✅ Add new records (production, feed usage, etc.)  
❌ **Cannot** create other employees  
❌ Limited edit/delete permissions  
❌ Cannot access admin-only features  
ℹ️ Info box showing employee access level

---

## 🔐 Security & Permissions

### Role-Based Access Control

**Admin Roles:**
- `Admin`
- `FarmAdmin`

**Employee Roles:**
- `Staff`
- `User`

### Authorization Examples

```csharp
// Controller level - Admin only
[Authorize(Roles = "Admin,FarmAdmin")]
public IActionResult AdminDashboard() { ... }

// Controller level - Employee only
[Authorize(Roles = "Staff,User")]
public IActionResult EmployeeDashboard() { ... }

// View level - Conditional display
@if (User.IsInRole("Admin") || User.IsInRole("FarmAdmin"))
{
    <a href="/Employee">👥 Employee Management</a>
}
```

### Farm Isolation

All data is filtered by `FarmId`:
- Admin and employees share the same `FarmId`
- Queries filter: `WHERE FarmId = @FarmId`
- Ensures no cross-farm data access

---

## 🧪 Testing the Flow

### Test Case 1: Admin Creates Employee
1. **Register as Admin**
   - Email: `admin@farm.com`
   - Password: `AdminPass123`
   - Farm Name: `Sunny Farm`
   
2. **Login as Admin**
   - Should see **Admin Dashboard**
   - Green "Employee Management" card visible
   
3. **Create Employee**
   - Navigate to `/Employee/Index`
   - Click "Add New Employee"
   - Fill form:
     - Name: `John Doe`
     - Email: `john@farm.com`
     - Username: `johndoe`
     - Password: `Employee123`
   - Click "Create Employee"
   
4. **Logout**

### Test Case 2: Employee Logs In
1. **Login as Employee**
   - Username: `johndoe`
   - Password: `Employee123`
   
2. **Verify**
   - Should redirect to **Employee Dashboard**
   - Blue theme (not green)
   - "STAFF" badge displayed
   - No "Employee Management" in navigation
   - Info box showing limited access
   
3. **Try to Access Admin Feature**
   - Navigate manually to `/Employee/Index`
   - Should get **403 Forbidden** or redirect

---

## 📊 Database Schema

### ApplicationUser Table

| Column | Admin Value | Employee Value |
|--------|-------------|----------------|
| Id | GUID | GUID |
| UserName | admin_username | employee_username |
| Email | admin@farm.com | employee@farm.com |
| FirstName | Admin | John |
| LastName | User | Doe |
| **FarmId** | **farm-guid-123** | **farm-guid-123** (same!) |
| FarmName | Sunny Farm | Sunny Farm |
| **IsStaff** | **false** | **true** |
| EmailConfirmed | true | true |

**Key Point:** Both Admin and Employee have the **same FarmId** to access the same farm data.

---

## 🎯 Navigation Menu

The navigation menu (`_Layout.cshtml`) shows different options based on role:

### Admin Sees:
```
📊 Dashboard
👥 Employees ← ADMIN ONLY (highlighted)
📋 Production Record
🐣 Flocks
🥚 Egg Production
... all other features
```

### Employee Sees:
```
📊 Dashboard
📋 Production Record
🐣 Flocks
🥚 Egg Production
... all other features (NO Employee Management)
```

---

## ⚙️ Configuration

No additional configuration needed! The system automatically:
1. Creates employees with correct `FarmId`
2. Assigns `IsStaff = true`
3. Sets role to "Staff"
4. Redirects to appropriate dashboard on login

---

## 🐛 Troubleshooting

### Issue: Employee sees Admin dashboard
**Solution:** Check that `IsStaff = true` in the database for that user

### Issue: Employee can access `/Employee/Index`
**Solution:** Add `[Authorize(Roles = "Admin,FarmAdmin")]` to EmployeeController

### Issue: Employee created with wrong FarmId
**Solution:** FarmId is taken from admin's claims - ensure admin is logged in

### Issue: Login shows wrong role
**Solution:** Check `AccountController.Login` - ensure role claim is set correctly:
```csharp
var role = loginResponse.Response.IsStaff ? "Staff" : "Admin";
```

---

## ✅ Summary

| Step | Admin | Employee |
|------|-------|----------|
| **Register** | ✅ Self-registers | ❌ Cannot register |
| **Create Employee** | ✅ Can create | ❌ Cannot create |
| **Login** | ✅ With email/username | ✅ With username from admin |
| **Dashboard** | 👨‍💼 Admin Dashboard | 👨‍🌾 Employee Dashboard |
| **Navigation** | All features | Limited features |
| **Employee Mgmt** | ✅ Full access | ❌ No access |
| **FarmId** | Unique GUID | Same as admin |
| **IsStaff** | false | true |
| **Role** | Admin/FarmAdmin | Staff/User |

---

## 🎉 Complete Workflow Example

```
1. Admin registers → Gets FarmId: "abc-123"
2. Admin creates employee:
   - Username: "johndoe"
   - Password: "Pass123"
   - FarmId: "abc-123" (same as admin)
   - IsStaff: true
3. Employee logs in with "johndoe" / "Pass123"
4. System checks IsStaff = true
5. Redirects to Employee Dashboard
6. Employee sees farm data with FarmId = "abc-123"
7. Employee can add records but not delete
```

**Perfect! 🎯**

---

This completes the employee login flow! Admins create employees, employees login with their credentials, and the system automatically shows the appropriate dashboard based on their role.

