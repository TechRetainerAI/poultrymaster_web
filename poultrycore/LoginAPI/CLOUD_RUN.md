# LoginAPI on Google Cloud Run

## Why PowerShell showed `FROM` errors

**Never paste Dockerfile lines into PowerShell.** PowerShell tries to run them as commands.  
`FROM` is not a PowerShell command — it belongs only inside a file named `Dockerfile`.

## Build the image (Docker Desktop must be running)

Open **PowerShell** and run:

```powershell
cd C:\Users\CODEWITHFIIFI\Desktop\gg\poultrycore\PoultryPro\LoginAPI

docker build -t login-api:local .
```

If that succeeds, push to Artifact Registry and deploy as in your Cloud Run guide.

## Fix if you used wrong COPY stage

A correct Dockerfile uses:

`COPY --from=build /app/publish .`

not `COPY --from=final` (that was a mistake in some copy-paste snippets).
