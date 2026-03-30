using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using User.Management.Data;
using Stripe;
using System.Configuration;
using System.Text;
using User.Management.API.Models;
using User.Management.Data.Models;
using User.Management.Service.Models;
using User.Management.Service.Services;
using SubscriptionService = User.Management.Service.Services.SubscriptionService;

var builder = WebApplication.CreateBuilder(args);



// For Entity Framework
var configuration = builder.Configuration;
builder.Services.AddDbContext<ApplicationDbContext>(options => options.UseSqlServer(configuration.GetConnectionString("ConnStr")));

var connectionString = builder.Configuration.GetConnectionString("ConnStr") ?? throw new InvalidOperationException("Connection string 'CryptoContextConnection' not found.");

//configure stripe
StripeConfiguration.ApiKey = builder.Configuration.GetValue<string>("StripeSettings:PrivateKey");
builder.Services.Configure<StripeSettings>(builder.Configuration.GetSection("StripeSettings"));

// Cloud Run / reverse proxies
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

// CORS Configuration: Allow Next.js frontend
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowOrigin", corsBuilder =>
    {
        var allowedOrigins = new List<string>
        {
            "http://localhost:3000",
            "https://localhost:3000",
            "http://localhost:3001",
            "https://localhost:3001",
            "https://localhost:7278"  // WebApp if needed
        };

        // Get production frontend URL from configuration
        var frontendBaseUrl = configuration["FrontendApp:BaseUrl"];
        if (!string.IsNullOrEmpty(frontendBaseUrl) && !allowedOrigins.Contains(frontendBaseUrl))
        {
            allowedOrigins.Add(frontendBaseUrl);
        }

        // Get additional allowed origins from configuration
        var additionalOrigins = configuration.GetSection("AllowedOrigins").Get<string[]>();
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

                // Production web app + Render / legacy hostnames (align with Farm API)
                if (origin.Contains("poultrymaster.com", StringComparison.OrdinalIgnoreCase) ||
                    origin.Contains("techretainer.com", StringComparison.OrdinalIgnoreCase) ||
                    origin.Contains(".onrender.com", StringComparison.OrdinalIgnoreCase))
                    return true;

                return false;
            })
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});

builder.Services.AddTransient<UserProfileDAL>(provider => new UserProfileDAL(connectionString));
builder.Services.AddScoped<IUserProfileService, UserProfileService>();

// If UserProfileDAL needs a connection string directly
builder.Services.AddScoped<IUserProfileDAL>(provider =>
{
    //var config = provider.GetRequiredService<IConfiguration>();
    return new UserProfileDAL(connectionString);
});

// Configure Identity with simple password requirements
builder.Services.AddIdentity<ApplicationUser, IdentityRole>(options =>
{
    // Simple password requirements - minimal restrictions for easy account creation
    options.Password.RequireDigit = false;
    options.Password.RequireNonAlphanumeric = false;
    options.Password.RequireUppercase = false;
    options.Password.RequireLowercase = false;
    options.Password.RequiredLength = 4;
    options.Password.RequiredUniqueChars = 1;
    
    // Account lockout policy
    options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(15);
    options.Lockout.MaxFailedAccessAttempts = 5;
    options.Lockout.AllowedForNewUsers = true;
    
    // Other identity options
    options.Tokens.ProviderMap["Email"] = new TokenProviderDescriptor(typeof(EmailTokenProvider<ApplicationUser>));
}).AddEntityFrameworkStores<ApplicationDbContext>()
    .AddDefaultTokenProviders();



builder.Services.Configure<DataProtectionTokenProviderOptions>(options =>
{
    // Set the expiration time for the OTP
    options.TokenLifespan = TimeSpan.FromMinutes(5); // Adjust the time span as needed
});


//Add Config for Required Email
builder.Services.Configure<IdentityOptions>(
    opts => opts.SignIn.RequireConfirmedEmail = true
    );

// Cloud Run: set JWT__Secret (non-empty, >= 32 bytes for HS256). Empty → IDX10703.
var jwtSecret = configuration["JWT:Secret"]?.Trim();
if (string.IsNullOrWhiteSpace(jwtSecret))
{
    throw new InvalidOperationException(
        "JWT:Secret is not configured. In Cloud Run → Login service → Variables, set JWT__Secret to your signing key.");
}

var jwtKeyBytes = Encoding.UTF8.GetBytes(jwtSecret);
if (jwtKeyBytes.Length < 32)
{
    throw new InvalidOperationException(
        "JWT:Secret is too short: use at least 32 characters for HS256.");
}

// Adding Authentication
builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultScheme = JwtBearerDefaults.AuthenticationScheme;
}).AddJwtBearer(options =>
{
    options.SaveToken = true;
    options.RequireHttpsMetadata = false;
    options.TokenValidationParameters = new TokenValidationParameters()
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ClockSkew = TimeSpan.Zero,

        ValidAudience = configuration["JWT:ValidAudience"],
        ValidIssuer = configuration["JWT:ValidIssuer"],

        //new
        // Use a custom validator to allow multiple audiences
        AudienceValidator = (audiences, securityToken, validationParameters) =>
        {
            // Define the allowed audiences
            var allowedAudiences = new List<string>
                {
                    configuration["JWT:ValidAudience"], // loginapi issuing token
                    "https://localhost:7190"  // PoultryAPI
                };

            // Check if any of the token's audiences match one of the allowed values
            return audiences != null && audiences.Any(a => allowedAudiences.Contains(a));
        },



        IssuerSigningKey = new SymmetricSecurityKey(jwtKeyBytes)
    };
});

// Register IHttpClientFactory
builder.Services.AddHttpClient();

builder.Services.AddTransient<ISubscriptionDAL>(provider => new SubscriptionDAL(connectionString));
builder.Services.AddTransient<ISubscriptionService, SubscriptionService>();

builder.Services.Configure<DataProtectionTokenProviderOptions>(options =>
{
    options.TokenLifespan = TimeSpan.FromHours(3); // Set token lifespan as needed
});


//Add Email Configs
var emailConfig = configuration.GetSection("EmailConfiguration").Get<EmailConfiguration>();
builder.Services.AddSingleton(emailConfig);

builder.Services.AddScoped<IEmailService, EmailService>();
builder.Services.AddScoped<IUserManagement, UserManagement>();

// Register Admin Service for employee management
builder.Services.AddScoped<IAdminService, AdminService>();

// Register UserDataDAL with the connection string
builder.Services.AddScoped<IUserDataDAL>(provider => new UserDataDAL(connectionString));
// Register the service
builder.Services.AddScoped<IUserService, UserService>();



builder.Services.AddControllers();
// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(option =>
{
    option.SwaggerDoc("v1", new OpenApiInfo { Title = "Auth API", Version = "v1" });
    option.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        In = ParameterLocation.Header,
        Description = "Please enter a valid token",
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        BearerFormat = "JWT",
        Scheme = "Bearer"
    });
    option.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type=ReferenceType.SecurityScheme,
                    Id="Bearer"
                }
            },
            new string[]{}
        }
    });
});


var app = builder.Build();

app.UseForwardedHeaders();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseRouting();
// CORS must run before HTTPS redirect. On Cloud Run, TLS ends at the edge; redirecting the
// container's HTTP request (especially OPTIONS preflight) often drops CORS headers → browser error.
app.UseCors("AllowOrigin");
if (!app.Environment.IsProduction())
{
    app.UseHttpsRedirection();
}
app.UseAuthentication();
app.UseAuthorization();
//UseAuthorization comes before this
app.UseEndpoints(endpoints =>
{
    // Define a default route for the API
    endpoints.MapGet("/", async context =>
    {
        await context.Response.WriteAsync("Welcome to the CryptoTax API. Please use the correct endpoint.");
    });

    // Map controllers
    endpoints.MapControllers();
});

// Handle 404 errors
app.UseStatusCodePages(async context =>
{
    if (context.HttpContext.Response.StatusCode == 404)
    {
        context.HttpContext.Response.ContentType = "text/html";
        await context.HttpContext.Response.WriteAsync(
            "<html><body><h1>Page not found</h1><p>The page you are looking for does not exist. Please check the URL or visit the <a href='/'>homepage</a>.</p></body></html>");
    }
});

app.Run();