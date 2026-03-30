using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using User.Management.Data.Models;
using User.Management.Data;
using System;
using IdentityRole = Microsoft.AspNetCore.Identity.IdentityRole;

namespace User.Management.Service.Services
{
    public class AdminService : IAdminService
    {
        private readonly UserManager<ApplicationUser> _userManager;
        private readonly RoleManager<IdentityRole> _roleManager;
        private readonly IUserProfileDAL _userProfileDAL;
        private readonly ISubscriptionDAL _subscriptionDal;

        public AdminService(UserManager<ApplicationUser> userManager, RoleManager<IdentityRole> roleManager, IUserProfileDAL userProfileDAL, ISubscriptionDAL subscriptionDal)
        {
            _userManager = userManager;
            _roleManager = roleManager;
            _userProfileDAL = userProfileDAL;
            _subscriptionDal = subscriptionDal;
        }

        public async Task<List<ApplicationUser>> GetEmployeesByFarmIdAsync(string farmId)
        {
            try
            {
                Console.WriteLine($"[AdminService] GetEmployeesByFarmIdAsync called with FarmId: {farmId}");
                
                // Get all users where IsStaff = true and FarmId matches
                var allStaffUsers = await _userManager.Users
                    .Where(u => u.IsStaff == true)
                    .ToListAsync();
                
                Console.WriteLine($"[AdminService] Total staff users in database: {allStaffUsers.Count}");
                foreach (var user in allStaffUsers)
                {
                    Console.WriteLine($"[AdminService] Staff user found - UserName: {user.UserName}, FarmId: {user.FarmId}, IsStaff: {user.IsStaff}");
                }
                
                var employees = allStaffUsers
                    .Where(u => u.FarmId == farmId)
                    .OrderBy(u => u.FirstName)
                    .ThenBy(u => u.LastName)
                    .ToList();

                Console.WriteLine($"[AdminService] Employees matching FarmId {farmId}: {employees.Count}");
                foreach (var emp in employees)
                {
                    Console.WriteLine($"[AdminService] Matching employee - UserName: {emp.UserName}, FarmId: {emp.FarmId}");
                }

                return employees;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[AdminService] Error fetching employees: {ex.Message}");
                Console.WriteLine($"[AdminService] Stack trace: {ex.StackTrace}");
                throw new Exception($"Error fetching employees for farm {farmId}: {ex.Message}", ex);
            }
        }

        public async Task<ApplicationUser> GetEmployeeByIdAsync(string employeeId, string farmId)
        {
            try
            {
                var employee = await _userManager.Users
                    .FirstOrDefaultAsync(u => u.Id == employeeId && u.FarmId == farmId && u.IsStaff);

                return employee;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error fetching employee {employeeId}: {ex.Message}", ex);
            }
        }

        public async Task<ApplicationUser> CreateEmployeeAsync(ApplicationUser employee, string password)
        {
            try
            {
                // Ensure IsStaff is set to true
                employee.IsStaff = true;
                employee.SecurityStamp = Guid.NewGuid().ToString();
                employee.TwoFactorEnabled = false;
                employee.EmailConfirmed = true; // Auto-confirm staff emails

                var result = await _userManager.CreateAsync(employee, password);

                if (!result.Succeeded)
                {
                    var errors = string.Join(", ", result.Errors.Select(e => e.Description));
                    throw new Exception($"Failed to create employee: {errors}");
                }

                // Explicitly ensure EmailConfirmed and IsStaff are set and persisted
                // Sometimes Identity doesn't persist properties set before CreateAsync
                employee.EmailConfirmed = true;
                employee.IsStaff = true; // Ensure IsStaff is explicitly set again
                var updateResult = await _userManager.UpdateAsync(employee);
                
                if (!updateResult.Succeeded)
                {
                    var errors = string.Join(", ", updateResult.Errors.Select(e => e.Description));
                    throw new Exception($"Failed to update employee properties: {errors}");
                }

                // Assign Staff role (if the role exists)
                if (await _roleManager.RoleExistsAsync("Staff"))
                {
                    await _userManager.AddToRoleAsync(employee, "Staff");
                }
                // Also assign User role as fallback
                else if (await _roleManager.RoleExistsAsync("User"))
                {
                    await _userManager.AddToRoleAsync(employee, "User");
                }

                // Create user profile for the employee (optional - stored procedure may not exist)
                // This is a separate profile table, but employee is already created in AspNetUsers via Identity
                try
                {
                    var profileCreated = await _userProfileDAL.CreateUserAsync(employee);
                    if (!profileCreated)
                    {
                        Console.WriteLine($"Warning: User profile stored procedure (sp_CreateUser) may not exist or failed, but employee is still created in AspNetUsers table");
                    }
                }
                catch (Exception profileEx)
                {
                    // Log but don't fail employee creation if profile creation fails
                    // Employee is already successfully created in AspNetUsers table via Identity
                    // The stored procedure sp_CreateUser is optional and may not exist
                    Console.WriteLine($"Warning: Failed to create user profile via stored procedure: {profileEx.Message}");
                    Console.WriteLine($"Info: Employee '{employee.UserName}' is still successfully created in AspNetUsers table");
                }

                // Verify employee was created successfully in AspNetUsers with correct properties
                var verifyEmployee = await _userManager.FindByIdAsync(employee.Id);
                if (verifyEmployee == null)
                {
                    throw new Exception("Employee creation failed - user not found in database after creation");
                }

                // Verify IsStaff is actually true in the database
                if (!verifyEmployee.IsStaff)
                {
                    Console.WriteLine($"Warning: Employee '{employee.UserName}' was created but IsStaff is false. Attempting to fix...");
                    verifyEmployee.IsStaff = true;
                    var fixResult = await _userManager.UpdateAsync(verifyEmployee);
                    if (!fixResult.Succeeded)
                    {
                        var errors = string.Join(", ", fixResult.Errors.Select(e => e.Description));
                        throw new Exception($"Employee created but IsStaff could not be set to true: {errors}");
                    }
                    Console.WriteLine($"Fixed: Employee '{employee.UserName}' IsStaff is now set to true");
                }

                // Verify EmailConfirmed is actually true in the database
                if (!verifyEmployee.EmailConfirmed)
                {
                    Console.WriteLine($"Warning: Employee '{employee.UserName}' was created but EmailConfirmed is false. Attempting to fix...");
                    verifyEmployee.EmailConfirmed = true;
                    var fixResult = await _userManager.UpdateAsync(verifyEmployee);
                    if (!fixResult.Succeeded)
                    {
                        var errors = string.Join(", ", fixResult.Errors.Select(e => e.Description));
                        throw new Exception($"Employee created but EmailConfirmed could not be set to true: {errors}");
                    }
                    Console.WriteLine($"Fixed: Employee '{employee.UserName}' EmailConfirmed is now set to true");
                }

                // Verify NormalizedUserName and NormalizedEmail are set (critical for login lookups)
                // ASP.NET Identity should set these automatically, but verify they exist
                if (string.IsNullOrEmpty(verifyEmployee.NormalizedUserName))
                {
                    Console.WriteLine($"Warning: Employee '{employee.UserName}' has NULL or empty NormalizedUserName. This will prevent login by username.");
                    Console.WriteLine($"Info: NormalizedUserName should be set automatically by UserManager. Checking if UserName is set...");
                    if (!string.IsNullOrEmpty(verifyEmployee.UserName))
                    {
                        // UserManager should handle this, but log for debugging
                        Console.WriteLine($"Info: UserName is '{verifyEmployee.UserName}' but NormalizedUserName is missing. This may indicate an Identity configuration issue.");
                    }
                }
                else
                {
                    Console.WriteLine($"Info: NormalizedUserName is set to '{verifyEmployee.NormalizedUserName}' for employee '{employee.UserName}'");
                }

                if (string.IsNullOrEmpty(verifyEmployee.NormalizedEmail))
                {
                    Console.WriteLine($"Warning: Employee '{employee.Email}' has NULL or empty NormalizedEmail. This will prevent login by email.");
                    Console.WriteLine($"Info: NormalizedEmail should be set automatically by UserManager. Checking if Email is set...");
                    if (!string.IsNullOrEmpty(verifyEmployee.Email))
                    {
                        // UserManager should handle this, but log for debugging
                        Console.WriteLine($"Info: Email is '{verifyEmployee.Email}' but NormalizedEmail is missing. This may indicate an Identity configuration issue.");
                    }
                }
                else
                {
                    Console.WriteLine($"Info: NormalizedEmail is set to '{verifyEmployee.NormalizedEmail}' for employee '{employee.Email}'");
                }

                Console.WriteLine($"Success: Employee '{employee.UserName}' (ID: {employee.Id}) created successfully in AspNetUsers table with IsStaff=true and EmailConfirmed=true");
                Console.WriteLine($"Login Info - UserName: '{verifyEmployee.UserName}', NormalizedUserName: '{verifyEmployee.NormalizedUserName}', Email: '{verifyEmployee.Email}', NormalizedEmail: '{verifyEmployee.NormalizedEmail}'");
                return verifyEmployee; // Return the verified employee from database
            }
            catch (Exception ex)
            {
                throw new Exception($"Error creating employee: {ex.Message}", ex);
            }
        }

        public async Task<bool> UpdateEmployeeAsync(ApplicationUser employee)
        {
            try
            {
                // Fetch the existing employee
                var existingEmployee = await _userManager.FindByIdAsync(employee.Id);
                
                if (existingEmployee == null || !existingEmployee.IsStaff)
                {
                    throw new Exception("Employee not found or is not a staff member");
                }

                // Update allowed fields
                existingEmployee.FirstName = employee.FirstName;
                existingEmployee.LastName = employee.LastName;
                existingEmployee.PhoneNumber = employee.PhoneNumber;
                existingEmployee.Email = employee.Email;
                existingEmployee.IsAdmin = employee.IsAdmin;
                existingEmployee.AdminTitle = employee.AdminTitle;
                existingEmployee.Permissions = employee.Permissions;
                existingEmployee.FeaturePermissions = employee.FeaturePermissions;

                var result = await _userManager.UpdateAsync(existingEmployee);

                if (!result.Succeeded)
                {
                    var errors = string.Join(", ", result.Errors.Select(e => e.Description));
                    throw new Exception($"Failed to update employee: {errors}");
                }

                return true;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating employee: {ex.Message}", ex);
            }
        }

        public async Task<bool> DeleteEmployeeAsync(string employeeId, string farmId)
        {
            try
            {
                var employee = await GetEmployeeByIdAsync(employeeId, farmId);
                
                if (employee == null)
                {
                    throw new Exception("Employee not found");
                }

                var result = await _userManager.DeleteAsync(employee);

                if (!result.Succeeded)
                {
                    var errors = string.Join(", ", result.Errors.Select(e => e.Description));
                    throw new Exception($"Failed to delete employee: {errors}");
                }

                return true;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting employee: {ex.Message}", ex);
            }
        }

        public async Task<int> GetEmployeeCountAsync(string farmId)
        {
            try
            {
                var count = await _userManager.Users
                    .CountAsync(u => u.IsStaff && u.FarmId == farmId);

                return count;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error getting employee count for farm {farmId}: {ex.Message}", ex);
            }
        }

        public async Task<List<FarmSummary>> GetFarmsAsync()
        {
            try
            {
                var farms = await _subscriptionDal.GetFarmsAsync();

                // Compute counts per farm from AspNetUsers
                var results = new List<FarmSummary>(farms.Count);
                foreach (var f in farms)
                {
                    var totalUsers = await _userManager.Users.CountAsync(u => u.FarmId == f.FarmId);
                    var staffCount = await _userManager.Users.CountAsync(u => u.FarmId == f.FarmId && u.IsStaff);
                    results.Add(new FarmSummary
                    {
                        FarmId = f.FarmId,
                        FarmName = f.Name,
                        TotalUsers = totalUsers,
                        StaffCount = staffCount
                    });
                }

                return results.OrderBy(r => r.FarmName).ToList();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error listing farms: {ex.Message}", ex);
            }
        }

        public async Task<int> GetFarmCountAsync()
        {
            try
            {
                return await _subscriptionDal.GetFarmCountAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error getting farm count: {ex.Message}", ex);
            }
        }
    }
}

