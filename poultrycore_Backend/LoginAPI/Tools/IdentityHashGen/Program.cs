using Microsoft.AspNetCore.Identity;
using User.Management.Data.Models;

// Usage: dotnet run -- "YourPlainTextPassword"
// Prints ASP.NET Core Identity v3 password hash for AspNetUsers.PasswordHash (SQL Server).
var pwd = args.Length > 0 ? args[0] : "DevSystemAdmin!23";
var hasher = new PasswordHasher<ApplicationUser>();
var hash = hasher.HashPassword(new ApplicationUser(), pwd);
Console.WriteLine(hash);
