# 🚀 Deploying User Management API to Plesk

This guide will help you deploy your .NET 8.0 User Management API to Plesk hosting.

---

## 📋 Prerequisites

1. ✅ **Plesk Access** - Admin or domain owner access
2. ✅ **.NET 8.0 Runtime** - Installed on Plesk server (or use self-contained deployment)
3. ✅ **Published Files** - Located in `publish\LoginAPI` folder
4. ✅ **Database** - SQL Server database configured
5. ✅ **Domain/Subdomain** - Pointing to your Plesk server (e.g., `api.poultrycore.com`)

---

## 🔧 Step 1: Prepare Files for Upload

### Option A: Framework-Dependent (Requires .NET 8.0 on Server)

Your current publish is framework-dependent. You need:
- ✅ .NET 8.0 Runtime installed on Plesk server
- ✅ Smaller file size
- ✅ Faster updates

### Option B: Self-Contained (No .NET Required on Server)

If .NET 8.0 is not installed on Plesk, republish as self-contained:

```powershell
cd "C:\Users\user\Downloads\Telegram Desktop\inventory-login (3)\backend\PoultryPro"
dotnet publish "LoginAPI\User.Management.API\User.Management.API.csproj" `
    --configuration Release `
    --output ".\publish\LoginAPI-SelfContained" `
    --self-contained true `
    --runtime win-x64
```

**Note:** Self-contained is larger (~100MB+) but includes everything needed.

---

## 📤 Step 2: Upload Files to Plesk

### Method 1: Using Plesk File Manager

1. **Login to Plesk**
   - Go to your Plesk control panel
   - Login with your credentials

2. **Navigate to Domain**
   - Click on your domain (e.g., `poultrycore.com`)
   - Or create a subdomain (e.g., `api.poultrycore.com`)

3. **Open File Manager**
   - Go to **Files** → **File Manager**
   - Navigate to `httpdocs` or `httpsdocs` folder

4. **Create API Folder**
   - Create a new folder: `api` or `UserManagementAPI`
   - Or upload directly to root if using subdomain

5. **Upload Files**
   - Upload ALL files from `publish\LoginAPI` folder
   - Include:
     - ✅ `User.Management.API.exe`
     - ✅ `User.Management.API.dll`
     - ✅ All `.dll` files
     - ✅ `appsettings.json`
     - ✅ `web.config`
     - ✅ `runtimes` folder (if present)

### Method 2: Using FTP/SFTP

1. **Get FTP Credentials**
   - In Plesk: **Websites & Domains** → **FTP Access**
   - Note your FTP host, username, and password

2. **Connect with FTP Client**
   - Use FileZilla, WinSCP, or similar
   - Connect to your Plesk server

3. **Upload Files**
   - Navigate to `httpdocs/api/` (or your chosen folder)
   - Upload all files from `publish\LoginAPI`

---

## ⚙️ Step 3: Configure Plesk for .NET Application

### Enable .NET Support

1. **Go to Domain Settings**
   - In Plesk, select your domain
   - Go to **Websites & Domains**

2. **Enable ASP.NET Core**
   - Look for **ASP.NET Core** or **.NET** settings
   - Enable **ASP.NET Core** support
   - Select **.NET 8.0** (or latest available)

3. **Set Application Path**
   - Point to your uploaded folder (e.g., `/api`)
   - Set startup file: `User.Management.API.exe`

### Configure Application Pool

1. **Application Pool Settings**
   - Go to **Websites & Domains** → **Application Pools**
   - Create new pool or use existing
   - Set **.NET CLR Version**: `No Managed Code` (for .NET Core)
   - Set **Managed Pipeline Mode**: `Integrated`

---

## 🔐 Step 4: Update Configuration Files

### Update `appsettings.json`

Edit the `appsettings.json` file in Plesk File Manager:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "ConnectionStrings": {
    "ConnStr": "Server=YOUR_SERVER;Database=YOUR_DB;User Id=YOUR_USER;Password=YOUR_PASSWORD;MultipleActiveResultSets=true;Encrypt=True;TrustServerCertificate=True;"
  },
  "JWT": {
    "ValidAudience": "https://api.poultrycore.com",
    "ValidIssuer": "https://api.poultrycore.com",
    "Secret": "YOUR_SECRET_KEY_HERE",
    "TokenValidityInMinutes": 60,
    "RefreshTokenValidity": 7
  },
  "WebApp": {
    "BaseUrl": "https://your-frontend-domain.com"
  },
  "FrontendApp": {
    "BaseUrl": "https://your-frontend-domain.com"
  },
  "EmailConfiguration": {
    "From": "your-email@gmail.com",
    "SmtpServer": "smtp.gmail.com",
    "Port": 465,
    "Username": "your-email@gmail.com",
    "Password": "your-app-password"
  }
}
```

### Update `web.config` (if needed)

Plesk may auto-generate this, but you can customize:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <location path="." inheritInChildApplications="false">
    <system.webServer>
      <handlers>
        <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModuleV2" resourceType="Unspecified" />
      </handlers>
      <aspNetCore processPath=".\User.Management.API.exe" 
                  stdoutLogEnabled="true" 
                  stdoutLogFile=".\logs\stdout" 
                  hostingModel="inprocess" />
    </system.webServer>
  </location>
</configuration>
```

---

## 🌐 Step 5: Configure Domain/Subdomain

### Option A: Use Subdomain (Recommended)

1. **Create Subdomain**
   - In Plesk: **Websites & Domains** → **Add Subdomain**
   - Subdomain: `api` (or `auth`, `login`)
   - Document root: `/api` (or your folder)
   - Enable **ASP.NET Core**

2. **SSL Certificate**
   - Go to **SSL/TLS Settings**
   - Install SSL certificate (Let's Encrypt is free)
   - Enable **Force HTTPS**

### Option B: Use Path (e.g., `/api`)

1. **Configure Application**
   - Set application path in Plesk
   - Ensure routing works correctly

---

## 🔒 Step 6: Configure Security & CORS

### Update CORS in `Program.cs` (if needed)

If you need to update CORS settings, you'll need to rebuild, but for now, ensure your `appsettings.json` has the correct frontend URL.

### Firewall Rules

1. **Open Required Ports**
   - In Plesk: **Tools & Settings** → **Firewall**
   - Ensure port 80 (HTTP) and 443 (HTTPS) are open
   - If using custom port, open that too

---

## 🗄️ Step 7: Database Configuration

1. **Create Database in Plesk**
   - Go to **Databases** → **Add Database**
   - Create database: `poultry_auth` (or your name)
   - Create database user
   - Note the connection details

2. **Update Connection String**
   - Edit `appsettings.json` with your database credentials
   - Test connection

3. **Run Migrations** (if needed)
   - You may need to run Entity Framework migrations
   - This can be done via SSH or Plesk terminal

---

## 🧪 Step 8: Test the Deployment

### Test API Endpoints

1. **Health Check**
   ```
   https://api.poultrycore.com/swagger
   ```

2. **Test Endpoint**
   ```
   https://api.poultrycore.com/api/Test/ping
   ```

3. **Login Endpoint**
   ```
   POST https://api.poultrycore.com/api/Authentication/login
   ```

### Check Logs

1. **View Application Logs**
   - In Plesk: **Logs** → **Application Logs**
   - Or check `logs\stdout` folder in your API directory

2. **Check for Errors**
   - Look for startup errors
   - Check database connection errors
   - Verify CORS issues

---

## 🔧 Step 9: Troubleshooting

### Issue: 500 Internal Server Error

**Solutions:**
1. Check application logs in Plesk
2. Verify `.NET 8.0` runtime is installed
3. Check `web.config` configuration
4. Verify file permissions (should be readable)

### Issue: Application Won't Start

**Solutions:**
1. Check if `User.Management.API.exe` has execute permissions
2. Verify all DLL files are uploaded
3. Check `appsettings.json` for syntax errors
4. Review application pool settings

### Issue: Database Connection Failed

**Solutions:**
1. Verify connection string in `appsettings.json`
2. Check database server allows remote connections
3. Verify firewall allows database port (usually 1433)
4. Test connection string locally first

### Issue: CORS Errors

**Solutions:**
1. Update CORS settings in `Program.cs` (requires rebuild)
2. Or use Plesk URL rewrite rules
3. Check `appsettings.json` frontend URLs

### Issue: SSL Certificate Problems

**Solutions:**
1. Install Let's Encrypt certificate in Plesk
2. Enable "Force HTTPS" redirect
3. Update JWT settings to use HTTPS URLs

---

## 📝 Step 10: Production Checklist

- [ ] All files uploaded to Plesk
- [ ] ASP.NET Core enabled in Plesk
- [ ] Application pool configured correctly
- [ ] `appsettings.json` updated with production values
- [ ] Database connection string configured
- [ ] SSL certificate installed and HTTPS enabled
- [ ] CORS configured for frontend domain
- [ ] JWT settings updated with production URLs
- [ ] Email configuration updated
- [ ] Firewall rules configured
- [ ] API tested and working
- [ ] Logs accessible and monitored

---

## 🚀 Quick Start Commands

### If You Have SSH Access

```bash
# Navigate to your API folder
cd /var/www/vhosts/poultrycore.com/httpdocs/api

# Set permissions
chmod +x User.Management.API.exe
chmod 644 *.dll
chmod 644 appsettings.json

# Test run (if needed)
./User.Management.API.exe
```

---

## 📞 Support Resources

- **Plesk Documentation**: https://docs.plesk.com/
- **.NET Core Hosting**: https://docs.microsoft.com/en-us/aspnet/core/host-and-deploy/
- **Plesk Support**: Contact your hosting provider

---

## 🎯 Summary

Your API should now be accessible at:
- **Swagger UI**: `https://api.poultrycore.com/swagger`
- **API Base**: `https://api.poultrycore.com/api/`
- **Login Endpoint**: `https://api.poultrycore.com/api/Authentication/login`

**Remember to:**
1. ✅ Update frontend `.env.local` with production API URL
2. ✅ Test all endpoints
3. ✅ Monitor logs for errors
4. ✅ Set up automated backups

---

**Your User Management API is now hosted on Plesk! 🎉**

