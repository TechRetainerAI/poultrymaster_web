# LoginAPI → Cloud Run
# Cloud Run sets PORT at runtime; Kestrel must listen on that port. Default 8080 if PORT is unset (local docker).
# Deploy: gcloud run deploy <service> --source ... --region ... --port 8080 --allow-unauthenticated

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY User.Management.API.sln ./
COPY User.Management.API/User.Management.API.csproj User.Management.API/
COPY User.Management.Service/User.Management.Service.csproj User.Management.Service/
COPY User.Management.Data/User.Management.Data.csproj User.Management.Data/
RUN dotnet restore User.Management.API/User.Management.API.csproj
COPY . .
WORKDIR /src/User.Management.API
RUN dotnet publish User.Management.API.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["/bin/sh", "-c"]
# $$ → $ in image JSON so the shell expands PORT at container start (not at docker build).
CMD ["export ASPNETCORE_URLS=http://0.0.0.0:$${PORT:-8080} && exec dotnet User.Management.API.dll"]
