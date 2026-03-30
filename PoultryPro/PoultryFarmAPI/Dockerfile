# PoultryFarmAPI → Cloud Run (port 8080)
# Build from this folder:  docker build -t farm-api:local .

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_URLS=http://0.0.0.0:8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY PoultryFarmAPI.csproj .
RUN dotnet restore PoultryFarmAPI.csproj
COPY . .
RUN dotnet publish PoultryFarmAPI.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "PoultryFarmAPI.dll"]
