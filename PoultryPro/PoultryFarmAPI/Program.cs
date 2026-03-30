using Microsoft.AspNetCore.Identity;
using System.Configuration;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using QuestPDF.Infrastructure;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using DocumentFormat.OpenXml.Office2016.Drawing.ChartDrawing;
using System.Text;
using System.Collections.Generic;


var builder = WebApplication.CreateBuilder(args);

// Set license mode
QuestPDF.Settings.License = LicenseType.Community;

// Add services to the container.
//1) Add services to the container.
string connectionString = builder.Configuration.GetConnectionString("PoultryConn")
                          ?? throw new InvalidOperationException("Connection string 'PoultryConn' not found.");
if (string.IsNullOrWhiteSpace(connectionString))
{
    throw new InvalidOperationException(
        "Connection string 'PoultryConn' is empty. Set ConnectionStrings__PoultryConn on Cloud Run (or User Secrets locally).");
}

// Cloud Run: set JWT__Secret (same value as Login API). Empty → IDX10703 / "key length is zero" at runtime.
var jwtSecret = builder.Configuration["JWT:Secret"]?.Trim();
if (string.IsNullOrWhiteSpace(jwtSecret))
{
    throw new InvalidOperationException(
        "JWT:Secret is not configured. In Cloud Run → Farm service → Variables: set JWT__Secret to the same signing key as the Login API.");
}

var jwtKeyBytes = Encoding.UTF8.GetBytes(jwtSecret);
if (jwtKeyBytes.Length < 32)
{
    throw new InvalidOperationException(
        "JWT:Secret is too short: use at least 32 characters (256 bits) for HS256. Set JWT__Secret on Cloud Run.");
}

// Existing Service Registrations
builder.Services.AddScoped<IBirdFlockService>(sp => new BirdFlockService(connectionString, sp.GetRequiredService<IMainFlockBatchService>()));

builder.Services.AddScoped<IEggProductionService>(sp => 
    new EggProductionService(connectionString, sp.GetRequiredService<ILogger<EggProductionService>>()));

builder.Services.AddScoped<IFeedUsageService>(sp => new FeedUsageService(connectionString));

builder.Services.AddScoped<IInventoryService>(sp => new InventoryService(connectionString));

// Register ExpenseService
builder.Services.AddScoped<IExpenseService>(sp => new ExpenseService(connectionString));

// Register SaleService with DI
builder.Services.AddScoped<ISaleService>(sp => new SaleService(connectionString));

// Register CashAdjustmentService
builder.Services.AddScoped<ICashAdjustmentService>(sp => new CashAdjustmentService(connectionString));

// register ICustomerService
builder.Services.AddScoped<ICustomerService>(sp => new CustomerService(connectionString));

builder.Services.AddScoped<IDashboardService>(sp => new DashboardService(connectionString));
builder.Services.AddScoped<IReportService>(sp => new ReportService(connectionString));

builder.Services.AddScoped<IProductionRecordService>(sp => new ProductionRecordService(connectionString));

builder.Services.AddScoped<IHouseService>(sp => new HouseService(connectionString));
builder.Services.AddScoped<IHealthRecordService>(sp => new HealthRecordService(connectionString));

// Audit logs service
builder.Services.AddScoped<IAuditLogService>(sp => new AuditLogService(connectionString));

// Chat service
builder.Services.AddScoped<IChatService>(sp => new ChatService(connectionString));

// =================================================================
// NEW SERVICE REGISTRATION FOR MainFlockBatch
// =================================================================
builder.Services.AddScoped<IMainFlockBatchService>(sp => new MainFlockBatchService(connectionString));
// =================================================================

// 2) Add controllers with audit logging
builder.Services.AddControllers(options =>
{
    options.Filters.AddService<AuditLogActionFilter>();
});
builder.Services.AddScoped<AuditLogActionFilter>();
builder.Services.AddSignalR();
// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Cloud Run / reverse proxies: honor X-Forwarded-Proto so redirects and Swagger work over HTTPS
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

builder.Services.AddAuthentication(cfg =>
{
    cfg.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    cfg.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
}).AddJwtBearer(options =>
{
    options.RequireHttpsMetadata = false;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(jwtKeyBytes),
        ValidIssuer = builder.Configuration["JWT:ValidIssuer"],
        ValidateIssuer = true,
        ValidateAudience = false,
    };
});

// Add CORS configuration
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAllApps", corsBuilder =>
    {
        var allowedOrigins = new List<string>
        {
            "http://localhost:3000",
            "https://localhost:3000",
            "http://localhost:3001",
            "https://localhost:3001",
            "https://localhost:7278",
            "http://localhost:7278",  // Web app
            "https://poultrymaster.com",
            "https://www.poultrymaster.com",
            "http://poultrymaster.com",
            "http://www.poultrymaster.com"
        };

        // Get production frontend URL from configuration
        var frontendBaseUrl = builder.Configuration["FrontendApp:BaseUrl"];
        if (!string.IsNullOrEmpty(frontendBaseUrl) && !allowedOrigins.Contains(frontendBaseUrl))
        {
            allowedOrigins.Add(frontendBaseUrl);
        }

        // Get additional allowed origins from configuration
        var additionalOrigins = builder.Configuration.GetSection("AllowedOrigins").Get<string[]>();
        if (additionalOrigins != null && additionalOrigins.Length > 0)
        {
            foreach (var origin in additionalOrigins)
            {
                if (!string.IsNullOrEmpty(origin) && !allowedOrigins.Contains(origin))
                {
                    allowedOrigins.Add(origin);
                }
            }
        }

        // Use flexible origin checking to allow both configured origins and ngrok domains
        corsBuilder
            .SetIsOriginAllowed(origin =>
            {
                if (string.IsNullOrEmpty(origin))
                    return false;

                // Allow localhost in any environment
                if (origin.StartsWith("http://localhost:") || origin.StartsWith("https://localhost:"))
                    return true;

                // Allow configured origins
                if (allowedOrigins.Contains(origin))
                    return true;

                // Allow ngrok domains (useful for testing even in production)
                // This allows temporary ngrok URLs for testing without code changes
                if (origin.Contains(".ngrok-free.app") || 
                    origin.Contains(".ngrok.io") || 
                    origin.Contains(".ngrok-free.dev") ||
                    origin.Contains(".ngrok.app"))
                    return true;

                // Allow production domains
                if (origin.Contains("poultrymaster.com") || 
                    origin.Contains("techretainer.com"))
                    return true;

                return false;
            })
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials(); // Important for cookie authentication
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseForwardedHeaders();

// Swagger was previously Development-only, which breaks /swagger on Cloud Run (Production).
var enableSwagger = app.Environment.IsDevelopment()
    || app.Configuration.GetValue("EnableSwagger", false);
if (enableSwagger)
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

// Add CORS middleware - allow both web app and React app
app.UseCors("AllowAllApps");

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapHub<PoultryFarmAPIWeb.Hubs.ChatHub>("/hubs/chat");

app.Run();
