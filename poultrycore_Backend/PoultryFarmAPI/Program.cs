using Microsoft.AspNetCore.Identity;
using System.Configuration;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Middleware;
using QuestPDF.Infrastructure;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using DocumentFormat.OpenXml.Office2016.Drawing.ChartDrawing;
using System.Text;
using System.Collections.Generic;


var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 10 * 1024 * 1024;
});

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

builder.Services.AddScoped<ISupplierService>(sp => new SupplierService(connectionString));

builder.Services.AddScoped<IEggInventoryAdjustmentService>(sp => new EggInventoryAdjustmentService(connectionString));

builder.Services.AddScoped<IFarmProductionSettingsService>(sp => new FarmProductionSettingsService(connectionString));

builder.Services.AddScoped<IFeedInventoryAdjustmentService>(sp => new FeedInventoryAdjustmentService(connectionString));

builder.Services.AddScoped<IDashboardService>(sp => new DashboardService(connectionString));

builder.Services.AddScoped<IProductionRecordService>(sp => new ProductionRecordService(connectionString));
builder.Services.AddScoped<IProductionBatchRecordService>(sp => new ProductionBatchRecordService(connectionString));
builder.Services.AddScoped<IPoultryPaymentService>(sp => new PoultryPaymentService(connectionString));

builder.Services.AddScoped<IHouseService>(sp => new HouseService(connectionString));
builder.Services.AddScoped<IHealthRecordService>(sp => new HealthRecordService(connectionString));

// Audit logs service
builder.Services.AddScoped<IAuditLogService>(sp => new AuditLogService(connectionString));

// Weekly observations (notes per farm + week) — migration 018
builder.Services.AddScoped<IFarmObservationService>(sp => new FarmObservationService(connectionString));

// Chat service
builder.Services.AddScoped<IChatService>(sp => new ChatService(connectionString));

// =================================================================
// NEW SERVICE REGISTRATION FOR MainFlockBatch
// =================================================================
builder.Services.AddScoped<IMainFlockBatchService>(sp => new MainFlockBatchService(connectionString));
// =================================================================

// =================================================================
// Water company module (multi-company support, separate from poultry)
// =================================================================
builder.Services.AddScoped<IWaterProductService>(sp => new WaterProductService(connectionString));
builder.Services.AddScoped<IWaterCustomerService>(sp => new WaterCustomerService(connectionString));
builder.Services.AddScoped<IWaterStockService>(sp => new WaterStockService(connectionString));
builder.Services.AddScoped<IWaterSaleService>(sp => new WaterSaleService(connectionString));
builder.Services.AddScoped<IWaterPaymentService>(sp => new WaterPaymentService(connectionString));
builder.Services.AddScoped<IWaterDashboardService>(sp => new WaterDashboardService(connectionString));

// Phase W1: Water Production (Boreholes, Machines, Production Batches, Quality Tests, Daily Pumping Logs)
builder.Services.AddScoped<IWaterBoreholeService>(sp => new WaterBoreholeService(connectionString));
builder.Services.AddScoped<IWaterMachineService>(sp => new WaterMachineService(connectionString));
builder.Services.AddScoped<IWaterProductionBatchService>(sp => new WaterProductionBatchService(connectionString));
// Migration 193: Daily Production — day totals allocated across machines, posting
// into real production batches (the water mirror of poultry Batch Production)
builder.Services.AddScoped<IWaterDailyProductionService>(sp => new WaterDailyProductionService(connectionString));
// Migration 063: Production Recipes + Raw Material Usage history
builder.Services.AddScoped<IWaterProductionRecipeService>(sp => new WaterProductionRecipeService(connectionString));
// Migration 067: Production Loss page
builder.Services.AddScoped<IWaterProductionLossService>(sp => new WaterProductionLossService(connectionString));
// Migration 068: Farm-level settings (currency)
builder.Services.AddScoped<IWaterFarmSettingsService>(sp => new WaterFarmSettingsService(connectionString));
builder.Services.AddScoped<IWaterQualityTestService>(sp => new WaterQualityTestService(connectionString));
builder.Services.AddScoped<IWaterDailyPumpingLogService>(sp => new WaterDailyPumpingLogService(connectionString));

// Phase W2: Water Distribution (Drivers, Vehicles, Routes, Vehicle Loadings, Driver Returns + reconciliation, Shortages)
builder.Services.AddScoped<IWaterDriverService>(sp => new WaterDriverService(connectionString));
builder.Services.AddScoped<IWaterVehicleService>(sp => new WaterVehicleService(connectionString));
builder.Services.AddScoped<IWaterRouteService>(sp => new WaterRouteService(connectionString));
builder.Services.AddScoped<IWaterVehicleLoadingService>(sp => new WaterVehicleLoadingService(connectionString));
builder.Services.AddScoped<IWaterDriverReturnService>(sp => new WaterDriverReturnService(connectionString));
builder.Services.AddScoped<IWaterDriverShortageService>(sp => new WaterDriverShortageService(connectionString));

// Phase W3: Water Raw Materials + Daily Closing + Loss Records + Reports
builder.Services.AddScoped<IWaterRawMaterialItemService>(sp => new WaterRawMaterialItemService(connectionString));
builder.Services.AddScoped<IWaterRawMaterialPurchaseService>(sp => new WaterRawMaterialPurchaseService(connectionString));
builder.Services.AddScoped<IWaterRawMaterialUsageService>(sp => new WaterRawMaterialUsageService(connectionString));
builder.Services.AddScoped<IWaterLossRecordService>(sp => new WaterLossRecordService(connectionString));
builder.Services.AddScoped<IWaterDailyClosingService>(sp => new WaterDailyClosingService(connectionString));
builder.Services.AddScoped<IWaterReportService>(sp => new WaterReportService(connectionString));

// Poultry Inventory + Raw Materials (additive; mirrors the Water raw-material services)
builder.Services.AddScoped<IPoultryRawMaterialItemService>(sp => new PoultryRawMaterialItemService(connectionString));
builder.Services.AddScoped<IPoultryRawMaterialPurchaseService>(sp => new PoultryRawMaterialPurchaseService(connectionString));
builder.Services.AddScoped<IPoultryRawMaterialUsageService>(sp => new PoultryRawMaterialUsageService(connectionString));
builder.Services.AddScoped<IPoultryProductService>(sp => new PoultryProductService(connectionString));
builder.Services.AddScoped<IPoultryStockService>(sp => new PoultryStockService(connectionString));
builder.Services.AddScoped<IPoultryProductionRecipeService>(sp => new PoultryProductionRecipeService(connectionString));
builder.Services.AddScoped<IPoultryProductionBatchService>(sp => new PoultryProductionBatchService(connectionString));
builder.Services.AddScoped<IPoultryFeedFormulaService>(sp => new PoultryFeedFormulaService(connectionString));
builder.Services.AddScoped<IPoultryFeedProductionBatchService>(sp => new PoultryFeedProductionBatchService(connectionString));
builder.Services.AddScoped<IPoultryLossRecordService>(sp => new PoultryLossRecordService(connectionString));
builder.Services.AddScoped<IPoultryDailyClosingService>(sp => new PoultryDailyClosingService(connectionString));
builder.Services.AddScoped<IPoultryReportService>(sp => new PoultryReportService(connectionString));
builder.Services.AddScoped<IPoultryDeliveryService>(sp => new PoultryDeliveryService(connectionString));
// Poultry Driver Distribution (Drivers, Vehicles, Routes, Vehicle Loadings, Driver
// Returns + reconciliation, Shortages, Delivery Expenses, Reports). Migrations 138-140.
builder.Services.AddScoped<IPoultryDriverDistributionService>(sp => new PoultryDriverDistributionService(connectionString));

// Phase W4: Finance — expense categories + expenses (approval workflow + cash
// side-effects), multi-account cash accounts + ledger, cash transfers (paired
// TransferOut/TransferIn), customer ledger. Schema: migration 047. SPs: 048.
builder.Services.AddScoped<IWaterExpenseCategoryService>(sp => new WaterExpenseCategoryService(connectionString));
builder.Services.AddScoped<IWaterExpenseService>(sp => new WaterExpenseService(connectionString));
// Migration 076: Suppliers master list (Paid To). Used by Expenses, RM purchases.
builder.Services.AddScoped<IWaterSupplierService>(sp => new WaterSupplierService(connectionString));
builder.Services.AddScoped<IWaterCashAccountService>(sp => new WaterCashAccountService(connectionString));
builder.Services.AddScoped<IWaterCashTransferService>(sp => new WaterCashTransferService(connectionString));
builder.Services.AddScoped<IWaterCustomerLedgerService>(sp => new WaterCustomerLedgerService(connectionString));

// Poultry Cash Accounts (port of the Water cash module). Multi-account cash
// management + signed ledger + paired transfers. Migrations 128 (schema) + 129 (SPs).
builder.Services.AddScoped<IPoultryCashAccountService>(sp => new PoultryCashAccountService(connectionString));
builder.Services.AddScoped<IPoultryCashTransferService>(sp => new PoultryCashTransferService(connectionString));

// Poultry Staff + Attendance + Payroll (port of the Water W6 module). Payroll
// approve upserts a linked dbo.Expense (Category 'Payroll'); mark-paid posts a
// CashOut against the run's PoultryCashAccountId. Migrations 126/127 (staff),
// 130/131 (payroll), 125 (expense linkage).
builder.Services.AddScoped<IPoultryStaffService>(sp => new PoultryStaffService(connectionString));
builder.Services.AddScoped<IPoultryStaffAttendanceService>(sp => new PoultryStaffAttendanceService(connectionString));
builder.Services.AddScoped<IPoultryPayrollService>(sp => new PoultryPayrollService(connectionString));

// Phase W5: Water Company profile (setup metadata: brand, business type,
// water source, default currency/bag-sachet count, owner contact). Setup SP
// is idempotent and also runs the finance defaults seed. Migration 049.
builder.Services.AddScoped<IWaterCompanyService>(sp => new WaterCompanyService(connectionString));

// Phase W6: Staff + Attendance + Payroll. Payroll items use a computed NetPay
// column; spWaterPayrollItem_Upsert rolls run totals atomically. Mark-paid
// writes one CashOut for the run total against the run's WaterCashAccountId.
// Migrations 050 (schema) + 051 (SPs).
builder.Services.AddScoped<IWaterStaffService>(sp => new WaterStaffService(connectionString));
builder.Services.AddScoped<IWaterStaffAttendanceService>(sp => new WaterStaffAttendanceService(connectionString));
builder.Services.AddScoped<IWaterPayrollService>(sp => new WaterPayrollService(connectionString));

// Phase W7: Maintenance logs for machines/vehicles/boreholes/generators.
// Complete-SP can also book a CashOut for repair cost against a cash account
// (idempotent — CashTransactionWritten guards double-booking). Migration 052.
builder.Services.AddScoped<IWaterMaintenanceLogService>(sp => new WaterMaintenanceLogService(connectionString));

// Prompt 4 — Business Office announcements / notifications (migration 121).
builder.Services.AddScoped<IAnnouncementService>(sp => new AnnouncementService(connectionString));

// Today's numbers on the Business Office company cards (migration 195).
builder.Services.AddScoped<IBusinessOfficeService>(sp => new BusinessOfficeService(connectionString));

// Water report/closing → PDF → email. Depends only on already-registered DI
// services (IWaterReportService for report data, IEmailService for delivery).
builder.Services.AddScoped<IWaterReportEmailService, WaterReportEmailService>();

// Composes + sends notification emails (report share, credentials, welcome).
// Owns the HTML templates that used to live in EmailController; delivers via
// IEmailService.
builder.Services.AddScoped<IEmailNotificationService, EmailNotificationService>();
// =================================================================

// =================================================================
// Generic Company module (multi-company support: shops, restaurants,
// hotels, salons, pharmacies, etc.). Foundation only in Phase 1:
// profile, business categories, expense categories, cash accounts,
// customer/supplier type and payment-method seeds.
// =================================================================
builder.Services.AddScoped<IGenericCompanyService>(sp => new GenericCompanyService(connectionString));

// Phase 2: Products + Services + Inventory (stock movements, stock adjustments
// with Draft → Submitted → Approved/Rejected workflow).
builder.Services.AddScoped<IGenericProductService>(sp => new GenericProductService(connectionString));
builder.Services.AddScoped<IGenericServiceCatalogService>(sp => new GenericServiceCatalogService(connectionString));
builder.Services.AddScoped<IGenericInventoryService>(sp => new GenericInventoryService(connectionString));

// Phase 3: Customers + Sales + Customer Payments + Cash Transactions.
// Sale_Approve is the meaty one: writes stock movement SaleOut per product,
// CashTransaction CashIn for AmountPaid, CustomerLedger SaleDebit + balance
// update if Balance > 0 — all in one transaction.
builder.Services.AddScoped<IGenericCustomerService>(sp => new GenericCustomerService(connectionString));
builder.Services.AddScoped<IGenericSaleService>(sp => new GenericSaleService(connectionString));
builder.Services.AddScoped<IGenericCashTransactionService>(sp => new GenericCashTransactionService(connectionString));

// Phase 4: Suppliers + Purchases + Expenses + Cash Transfers (the money-out
// side). Purchase_Approve mirrors Sale_Approve; Expense_Approve branches on
// PaymentMethod (Credit → supplier ledger vs cash account → CashOut);
// CashTransfer_Approve writes a paired TransferOut/TransferIn.
builder.Services.AddScoped<IGenericSupplierService>(sp => new GenericSupplierService(connectionString));
builder.Services.AddScoped<IGenericPurchaseService>(sp => new GenericPurchaseService(connectionString));
builder.Services.AddScoped<IGenericExpenseRecordService>(sp => new GenericExpenseRecordService(connectionString));
builder.Services.AddScoped<IGenericCashTransferService>(sp => new GenericCashTransferService(connectionString));

// Phase 5: Daily Closing + Reports + Dashboard. The Submit SP auto-aggregates
// from the immutable tables, so the closing is a snapshot, not re-entered data.
builder.Services.AddScoped<IGenericDailyClosingService>(sp => new GenericDailyClosingService(connectionString));
builder.Services.AddScoped<IGenericReportService>(sp => new GenericReportService(connectionString));

// Advanced Poultry Reports (20 new poultry-only reports under /api/poultry/reports/*).
builder.Services.AddScoped<IPoultryAdvancedReportService>(sp => new PoultryAdvancedReportService(connectionString));

// Phase 6: Staff + Attendance + Payroll (spec §13, §14). Payroll items use a
// computed NetPay column; spGenericPayrollItem_Upsert rolls run totals
// atomically. MarkPaid writes one CashOut for the run total against the run's
// GenericCashAccountId. Migrations 055 (schema) + 056 (SPs).
builder.Services.AddScoped<IGenericStaffService>(sp => new GenericStaffService(connectionString));
builder.Services.AddScoped<IGenericStaffAttendanceService>(sp => new GenericStaffAttendanceService(connectionString));
builder.Services.AddScoped<IGenericPayrollService>(sp => new GenericPayrollService(connectionString));
// =================================================================

// =================================================================
// Email (SMTP via MailKit) — used by EmailController for report PDFs.
// Set EmailConfiguration__From / __SmtpServer / __Port / __UserName /
// __Password on Cloud Run. Leave blank locally to disable.
// =================================================================
var emailConfig = builder.Configuration.GetSection("EmailConfiguration").Get<PoultryFarmAPIWeb.Models.EmailConfiguration>()
    ?? new PoultryFarmAPIWeb.Models.EmailConfiguration();
builder.Services.AddSingleton(emailConfig);
builder.Services.AddScoped<PoultryFarmAPIWeb.Business.IEmailService, PoultryFarmAPIWeb.Business.EmailService>();
// =================================================================

// 2) Add controllers with audit logging
builder.Services.AddControllers(options =>
{
    options.Filters.AddService<AuditLogActionFilter>();
});
builder.Services.AddScoped<AuditLogActionFilter>();
builder.Services.AddSignalR();

// 2b) Friendly auto-validation messages for Water + Generic routes only.
//     ASP.NET's default `[ApiController]` model-binding error for a missing
//     [FromQuery] farmId is "The farmId field is required." — leaks the param
//     name (which says "farm") to end users on Water and Generic Company
//     pages where the app's noun is "company", not "farm".
//
//     This factory only rewrites for /api/Water/* and /api/generic-company/*
//     paths so that poultry endpoints — which legitimately deal with farms —
//     keep the original wording. Pure string rewrite on the error MESSAGE
//     (not the key) so frontend code that inspects `errors.farmId` keeps
//     working.
builder.Services.Configure<Microsoft.AspNetCore.Mvc.ApiBehaviorOptions>(options =>
{
    options.InvalidModelStateResponseFactory = context =>
    {
        var path = context.HttpContext.Request.Path.Value ?? string.Empty;
        var rewrite = path.StartsWith("/api/Water/",          StringComparison.OrdinalIgnoreCase)
                   || path.StartsWith("/api/generic-company", StringComparison.OrdinalIgnoreCase);

        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        foreach (var kvp in context.ModelState)
        {
            var modelErrors = kvp.Value?.Errors;
            if (modelErrors is null || modelErrors.Count == 0) continue;

            var messages = new string[modelErrors.Count];
            for (int i = 0; i < modelErrors.Count; i++)
            {
                var msg = modelErrors[i].ErrorMessage;
                if (rewrite && !string.IsNullOrEmpty(msg))
                {
                    // "The farmId field is required." → "The Company ID field is required."
                    msg = msg.Replace("farmId", "Company ID", StringComparison.Ordinal)
                             .Replace("FarmId", "Company ID", StringComparison.Ordinal);
                }
                messages[i] = msg ?? string.Empty;
            }
            errors[kvp.Key] = messages;
        }

        var problem = new Microsoft.AspNetCore.Mvc.ValidationProblemDetails(errors)
        {
            Type     = "https://tools.ietf.org/html/rfc9110#section-15.5.1",
            Title    = "One or more validation errors occurred.",
            Status   = StatusCodes.Status400BadRequest,
            Instance = context.HttpContext.Request.Path,
        };
        return new Microsoft.AspNetCore.Mvc.BadRequestObjectResult(problem)
        {
            ContentTypes = { "application/problem+json" }
        };
    };
});

// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    // Adds the "Authorize" button to Swagger UI so [Authorize] endpoints (e.g.
    // EmailController) can be tested. Paste the raw JWT from the Login API — the
    // Bearer scheme prefixes "Bearer " for you, so don't include it.
    var jwtScheme = new Microsoft.OpenApi.Models.OpenApiSecurityScheme
    {
        Name = "Authorization",
        Description = "Enter your JWT bearer token (without the \"Bearer \" prefix).",
        In = Microsoft.OpenApi.Models.ParameterLocation.Header,
        Type = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Reference = new Microsoft.OpenApi.Models.OpenApiReference
        {
            Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
            Id = "Bearer",
        },
    };
    c.AddSecurityDefinition("Bearer", jwtScheme);
    c.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
    {
        [jwtScheme] = Array.Empty<string>(),
    });
});

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
        RoleClaimType = System.Security.Claims.ClaimTypes.Role,
        NameClaimType = System.Security.Claims.ClaimTypes.NameIdentifier,
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

                // Farm registry developer portal (separate Cloud Run SPA → Farm API for /api/AuditLogs/platform)
                if (origin.Contains(".run.app", StringComparison.OrdinalIgnoreCase) &&
                    origin.Contains("farm-registry-portal", StringComparison.OrdinalIgnoreCase))
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

// Catch unhandled exceptions FIRST so SqlException -> JSON body with the actual
// SQL error number/message instead of an HTML 500. Must come before any other
// middleware that could throw (auth, routing, controllers).
app.UseMiddleware<GlobalExceptionMiddleware>();

// Swagger was previously Development-only, which breaks /swagger on Cloud Run (Production).
var enableSwagger = app.Environment.IsDevelopment()
    || app.Configuration.GetValue("EnableSwagger", false);
if (enableSwagger)
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Skip HTTPS redirection in Development so the Next.js proxy can reach the
// plain-HTTP port without bouncing into the untrusted self-signed dev cert.
if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}

// Add CORS middleware - allow both web app and React app
app.UseCors("AllowAllApps");

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapHub<PoultryFarmAPIWeb.Hubs.ChatHub>("/hubs/chat");

app.Run();
