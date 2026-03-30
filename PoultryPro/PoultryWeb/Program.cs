using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using NLog;
using PoultryFarmApp.Business;
using PoultryWeb.Business;
using PoultryWeb.Models;
using User.Management.Service.Models;
using User.Management.Service.Services;

var builder = WebApplication.CreateBuilder(args);

// Configure NLog
var logger = LogManager.Setup()
    .LoadConfigurationFromFile("nlog.config")
    .GetCurrentClassLogger();

builder.Logging.ClearProviders();

string connectionString = builder.Configuration.GetConnectionString("PoultryConn")
                          ?? throw new InvalidOperationException("Connection string 'PoultryConn' not found.");

// Add MVC with JSON options
builder.Services.AddControllers()
    .AddJsonOptions(opts => {
        // optional custom settings
    });

// Add Identity services
builder.Services.AddScoped<IUserStore<AppUser>, CustomUserStore>();
builder.Services.AddScoped<IUserPasswordStore<AppUser>, CustomUserStore>();

builder.Services.AddIdentityCore<AppUser>(options =>
{
    options.SignIn.RequireConfirmedAccount = false;
})
    .AddSignInManager()
    .AddDefaultTokenProviders();

builder.Services.AddScoped<UserManager<AppUser>>();
builder.Services.AddScoped<SignInManager<AppUser>>();

// Add HTTP context and session services
builder.Services.AddHttpContextAccessor();
builder.Services.AddDistributedMemoryCache();
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(30);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});

// Authentication
const string CookieAuthScheme = "PoultryFarmSoftwareCookieScheme";
builder.Services.AddAuthentication(CookieAuthScheme)
    .AddCookie(CookieAuthScheme, options =>
    {
        options.LoginPath = "/Account/Login";
        options.LogoutPath = "/Account/Logout";
        options.AccessDeniedPath = "/Account/AccessDenied";
        options.ExpireTimeSpan = TimeSpan.FromMinutes(30);
        options.SlidingExpiration = true;
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("LoggedIn", policy => policy.RequireAuthenticatedUser());
});

// Register services
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<IAuthenticationService, AuthenticationService>();
builder.Services.AddScoped<AuthenticationService>();

// Register all API services with HttpClient
builder.Services.AddHttpClient<ICustomerWebApiService, CustomerWebApiService>();
builder.Services.AddHttpClient<IFlockWebApiService, FlockWebApiService>();
builder.Services.AddHttpClient<IEggProductionWebApiService, EggProductionWebApiService>();
builder.Services.AddHttpClient<IFeedUsageWebApiService, FeedUsageWebApiService>();
builder.Services.AddHttpClient<IInventoryWebApiService, InventoryWebApiService>();
builder.Services.AddHttpClient<IExpenseWebApiService, ExpenseWebApiService>();
builder.Services.AddHttpClient<ISaleWebApiService, SaleWebApiService>();
builder.Services.AddHttpClient<IDashboardWebApiService, DashboardWebApiService>();
builder.Services.AddHttpClient<IReportWebApiService, ReportWebApiService>();
builder.Services.AddHttpClient<IProductionRecordWebApiService, ProductionRecordWebApiService>();
builder.Services.AddHttpClient<IEmployeeWebApiService, EmployeeWebApiService>();

// Add generic HttpClientFactory
builder.Services.AddHttpClient();

// Add services to the container
builder.Services.AddControllersWithViews();

// Email configuration
var emailConfig = builder.Configuration.GetSection("EmailConfiguration").Get<EmailConfiguration>();
builder.Services.AddSingleton(emailConfig);
builder.Services.AddScoped<IEmailService, EmailService>();

var app = builder.Build();

// Configure the HTTP request pipeline
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseSession();
app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();