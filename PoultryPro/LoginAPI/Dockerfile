# LoginAPI → Cloud Run (listens on port 8080)
# Do NOT paste these lines into PowerShell. Save this file, then run docker build (see CLOUD_RUN.md).

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_URLS=http://0.0.0.0:8080

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
ENTRYPOINT ["dotnet", "User.Management.API.dll"]
