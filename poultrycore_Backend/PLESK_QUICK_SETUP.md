# ⚡ Plesk Quick Setup Guide

## 🎯 Fast Deployment Steps

### 1. Upload Files (5 minutes)

```
1. Login to Plesk
2. Go to your domain → File Manager
3. Create folder: /httpdocs/api/
4. Upload ALL files from: publish\LoginAPI\
```

### 2. Enable .NET (2 minutes)

```
1. Websites & Domains → Your Domain
2. Find "ASP.NET Core" or ".NET" section
3. Enable it
4. Select .NET 8.0
5. Point to: /api
6. Startup file: User.Management.API.exe
```

### 3. Configure Database (3 minutes)

```
1. Databases → Add Database
2. Create: poultry_auth
3. Create user with password
4. Edit appsettings.json:
   - Update ConnectionStrings.ConnStr
   - Use: Server=localhost;Database=poultry_auth;...
```

### 4. Update Settings (2 minutes)

Edit `appsettings.json` in Plesk File Manager:

```json
{
  "JWT": {
    "ValidAudience": "https://api.poultrycore.com",
    "ValidIssuer": "https://api.poultrycore.com"
  },
  "FrontendApp": {
    "BaseUrl": "https://your-frontend.com"
  }
}
```

### 5. SSL Certificate (3 minutes)

```
1. SSL/TLS Settings
2. Install Let's Encrypt (free)
3. Enable "Force HTTPS"
```

### 6. Test (1 minute)

```
Visit: https://api.poultrycore.com/swagger
```

---

## ✅ Done!

Your API is live at: `https://api.poultrycore.com`

**Total Time: ~15 minutes**

---

## 🆘 Common Issues

| Issue | Solution |
|-------|----------|
| 500 Error | Check logs, verify .NET 8.0 installed |
| Won't Start | Check file permissions, verify all DLLs uploaded |
| DB Error | Verify connection string, check firewall |
| CORS Error | Update FrontendApp.BaseUrl in appsettings.json |

---

## 📞 Need Help?

1. Check Plesk logs: **Logs** → **Application Logs**
2. Check API logs: `/api/logs/stdout` folder
3. Test locally first before deploying

