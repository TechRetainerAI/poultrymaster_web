# Database Configuration Guide

## Production database (configure on server only)

Use **environment variables**, **User Secrets**, or **hosting panel** — **do not** commit real passwords to Git.

**Typical shape** (replace placeholders on the server):

- **Server:** your SQL host  
- **Database:** your production database name  
- **User / password:** from your DBA or hosting provider  

### Connection string template

#### PoultryFarmAPI

```json
"ConnectionStrings": {
  "PoultryConn": "Server=YOUR_SERVER;Database=YOUR_DB;User Id=YOUR_USER;Password=YOUR_PASSWORD;MultipleActiveResultSets=true;Encrypt=True;TrustServerCertificate=True;"
}
```

#### User Management API (LoginAPI)

```json
"ConnectionStrings": {
  "ConnStr": "Server=YOUR_SERVER;Database=YOUR_DB;User Id=YOUR_USER;Password=YOUR_PASSWORD;MultipleActiveResultSets=true;Encrypt=True;TrustServerCertificate=True;"
}
```

## Security

1. **Never** commit production credentials to source control.  
2. Use separate DBs/users for dev / staging / production.  
3. Repo `appsettings*.json` files use **empty** connection strings; fill them locally via User Secrets or env vars.

## Testing after deploy

1. Check logs for connection errors.  
2. Test login: `POST /api/Authentication/login`.  

---

**Note:** Real server names and passwords belong in your deployment docs or a private vault — not in this public file.
