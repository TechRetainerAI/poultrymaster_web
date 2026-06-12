# Root Dockerfile for Google Cloud Build / Cloud Run "Deploy from source"
# Builds LoginAPI (User.Management.API). Context = repository root.
# For PoultryFarmAPI, create a second Cloud Run service (see CLOUD_RUN_TWO_APIS.md).

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_URLS=http://0.0.0.0:8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY LoginAPI/User.Management.API.sln ./
COPY LoginAPI/User.Management.API/User.Management.API.csproj User.Management.API/
COPY LoginAPI/User.Management.Service/User.Management.Service.csproj User.Management.Service/
COPY LoginAPI/User.Management.Data/User.Management.Data.csproj User.Management.Data/
RUN dotnet restore User.Management.API/User.Management.API.csproj
COPY LoginAPI/ .
WORKDIR /src/User.Management.API
RUN dotnet publish User.Management.API.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "User.Management.API.dll"]
