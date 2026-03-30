# 🚀 API Deployment Instructions

## 📁 Publish Folder Location

The published files are located at:
```
C:\Users\CODEWITHFIIFI\Desktop\gg\poultrycore\PoultryPro\LoginAPI\User.Management.API\publish
```

## 📦 What to Upload

**Upload ALL files and folders** from the `publish` folder to your hosting server. This includes:

### Essential Files:
- ✅ `User.Management.API.dll` - Main API executable
- ✅ `User.Management.API.exe` - Windows executable
- ✅ `User.Management.API.runtimeconfig.json` - Runtime configuration
- ✅ `appsettings.json` - Application settings
- ✅ `appsettings.Production.json` - Production settings
- ✅ `web.config` - IIS configuration (if using IIS)
- ✅ All `.dll` files (dependencies)
- ✅ All folders (`runtimes`, language folders, etc.)

### Important Notes:
- **DO NOT** upload `.pdb` files (debug symbols) unless you need debugging
- **DO** upload all subdirectories (they contain required resources)
- **DO** maintain the folder structure

## 🌐 Deployment Methods

### Option 1: FTP/SFTP Upload
1. Connect to your hosting server via FTP/SFTP (FileZilla, WinSCP, etc.)
2. Navigate to your API deployment folder (usually `/wwwroot` or `/api`)
3. Upload **all contents** from the `publish` folder
4. Ensure file permissions are set correctly (executable permissions for `.exe` and `.dll` files)

### Option 2: Azure App Service
1. Go to Azure Portal → Your App Service
2. Navigate to **Deployment Center** or **Advanced Tools (Kudu)**
3. Use **Zip Deploy** or **Drag & Drop** to upload the entire `publish` folder contents
4. Or use Azure CLI:
   ```bash
   az webapp deploy --resource-group <your-resource-group> --name <your-app-name> --src-path ./publish
   ```

### Option 3: IIS (Windows Server)
1. Stop the IIS application pool
2. Copy all files from `publish` folder to your IIS site directory (usually `C:\inetpub\wwwroot\YourApiName`)
3. Replace existing files
4. Restart the application pool
5. Start the website

### Option 4: Docker Container
If deploying as a container:
```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY publish/ .
ENTRYPOINT ["dotnet", "User.Management.API.dll"]
```

## ⚙️ Post-Deployment Checklist

After uploading:

1. **Verify Configuration Files:**
   - Check `appsettings.Production.json` has correct:
     - Database connection string
     - JWT secret keys
     - API URLs
     - CORS settings

2. **Test the API:**
   - Health check endpoint: `https://your-api-url/api/System/health`
   - Swagger UI: `https://your-api-url/swagger` (if enabled)

3. **Check Logs:**
   - Monitor application logs for any startup errors
   - Verify database connections are working

4. **Restart Services:**
   - Restart the application/service after deployment
   - Clear any cached files if needed

## 🔧 Configuration Updates

Before deploying, ensure `appsettings.Production.json` contains:

```json
{
  "ConnectionStrings": {
    "ConnStr": "your-production-connection-string"
  },
  "JWT": {
    "ValidIssuer": "your-issuer",
    "ValidAudience": "your-audience",
    "Secret": "your-secret-key"
  },
  "AllowedHosts": "*",
  "CORS": {
    "AllowedOrigins": ["https://your-frontend-url"]
  }
}
```

## 📝 Quick Upload Commands

### Using PowerShell (if you have SSH access):
```powershell
# Compress the publish folder
Compress-Archive -Path .\publish\* -DestinationPath .\api-deploy.zip

# Upload via SCP (replace with your server details)
scp .\api-deploy.zip user@your-server:/path/to/deploy/
```

### Using Azure CLI:
```bash
cd PoultryPro/LoginAPI/User.Management.API
az webapp deploy --resource-group YourResourceGroup --name YourAppName --src-path ./publish --type zip
```

## ⚠️ Important Reminders

- ✅ Always backup your current deployment before updating
- ✅ Test in a staging environment first if possible
- ✅ Update connection strings for production database
- ✅ Ensure all environment variables are set correctly
- ✅ Check firewall rules allow traffic to your API port
- ✅ Verify SSL certificates are configured if using HTTPS

---

**Publish Folder Path:**
```
C:\Users\CODEWITHFIIFI\Desktop\gg\poultrycore\PoultryPro\LoginAPI\User.Management.API\publish
```

**Total Size:** Approximately 50-100 MB (depending on dependencies)

