# PoultryFarmAPI Deployment Guide

## 📦 Published Files Location
```
PoultryPro\publish\PoultryFarmAPI\
```

## 🚀 Deployment Steps

### Option 1: Manual Deployment (IIS/Plesk)

1. **Backup Current Deployment**
   - Backup the current production folder
   - Backup the database (if needed)

2. **Stop the Application**
   - Stop IIS application pool or Windows Service
   - Or stop the running process

3. **Copy Files to Server**
   - Copy all files from `PoultryPro\publish\PoultryFarmAPI\` to your server
   - Typical server location: `C:\inetpub\wwwroot\PoultryFarmAPI\` or your Plesk domain folder

4. **Update Configuration**
   - Edit `appsettings.Production.json` with production values:
     - Connection strings
     - JWT settings
     - API URLs
     - Other production-specific settings

5. **Set Permissions**
   - Ensure IIS_IUSRS has read/execute permissions
   - Ensure the application pool identity has write access to the `logs` folder

6. **Start the Application**
   - Start IIS application pool
   - Or restart the Windows Service
   - Verify the application is running

7. **Test the Deployment**
   - Test the API endpoint: `https://your-domain.com/api/Flock`
   - Verify flock creation works
   - Check logs for any errors

### Option 2: Using FTP/SFTP

1. **Connect to Server**
   ```powershell
   # Using PowerShell with FTP
   # Or use FileZilla, WinSCP, or similar tool
   ```

2. **Upload Files**
   - Upload all files from `PoultryPro\publish\PoultryFarmAPI\`
   - Maintain folder structure (especially `runtimes\`, `LatoFont\`, etc.)

3. **Follow steps 4-7 from Option 1**

### Option 3: Using Deployment Script

Create a PowerShell script to automate deployment (see below).

## 📋 Pre-Deployment Checklist

- [ ] Code is built and tested locally
- [ ] All files are in `PoultryPro\publish\PoultryFarmAPI\`
- [ ] `appsettings.Production.json` is configured
- [ ] Database connection string is correct
- [ ] Server has .NET 8.0 Runtime installed
- [ ] Backup of current deployment exists
- [ ] Maintenance window scheduled (if needed)

## 🔧 Post-Deployment Verification

1. **Health Check**
   ```bash
   curl https://your-domain.com/api/health
   ```

2. **Test Flock Creation**
   - Use Postman or your frontend
   - Verify the stored procedure error is fixed
   - Check that flocks are created successfully

3. **Check Logs**
   - Review `logs\stdout*.log` for any errors
   - Check Windows Event Viewer for application errors

4. **Monitor Performance**
   - Check CPU and memory usage
   - Monitor API response times

## 🐛 Troubleshooting

### Application Won't Start
- Check .NET 8.0 Runtime is installed
- Verify `web.config` is present
- Check application pool is running
- Review `logs\stdout*.log` for errors

### Database Connection Issues
- Verify connection string in `appsettings.Production.json`
- Check SQL Server is accessible
- Verify firewall rules allow database connections

### 500 Internal Server Error
- Check `logs\stdout*.log` for detailed errors
- Verify all DLL files are present
- Check file permissions

## 📝 Important Files

- `PoultryFarmAPI.exe` - Main executable
- `PoultryFarmAPI.dll` - Main DLL (updated with fix)
- `web.config` - IIS/Plesk configuration
- `appsettings.Production.json` - Production settings
- `runtimes\` - Platform-specific runtime files
- `logs\` - Application logs directory

## 🔄 Rollback Procedure

If deployment fails:

1. Stop the application
2. Restore backup files
3. Restart the application
4. Verify previous version is working
5. Investigate deployment issues

## 📞 Support

If you encounter issues:
1. Check the logs in `logs\` folder
2. Review error messages in the console
3. Verify all dependencies are present
4. Check server event logs

