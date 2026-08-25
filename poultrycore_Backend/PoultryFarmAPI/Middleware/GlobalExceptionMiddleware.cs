using Npgsql;
using System.Net;
using System.Text.Json;

namespace PoultryFarmAPIWeb.Middleware
{
    // Converts unhandled exceptions into structured JSON. Without this, ASP.NET
    // returns an HTML stack trace (dev) or empty 500 (prod) which the Next.js
    // proxy then collapses into a generic "Failed to load resource: 500".
    //
    // Surfaces the exact PostgresException SQLSTATE + message so the caller can
    // see "function spgenericproduct_getall(...) does not exist" or "column
    // \"type\" does not exist" instead of a black-box 500.
    public class GlobalExceptionMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly ILogger<GlobalExceptionMiddleware> _logger;

        public GlobalExceptionMiddleware(RequestDelegate next, ILogger<GlobalExceptionMiddleware> logger)
        {
            _next = next;
            _logger = logger;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            try
            {
                await _next(context);
            }
            catch (PostgresException pgEx)
            {
                _logger.LogError(pgEx,
                    "PostgresException on {Method} {Path}: sqlstate={SqlState}",
                    context.Request.Method, context.Request.Path, pgEx.SqlState);
                await WriteSqlError(context, pgEx);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unhandled exception on {Method} {Path}",
                    context.Request.Method, context.Request.Path);
                await WriteGenericError(context, ex);
            }
        }

        private static async Task WriteSqlError(HttpContext context, PostgresException ex)
        {
            if (context.Response.HasStarted) return;

            context.Response.Clear();

            // A unique-constraint breach is not a server fault -- the user asked
            // for something that is already there. 409 says so, and the message
            // has to be a sentence: the caller shows it verbatim, and
            // "duplicate key value violates unique constraint
            // "uq_poultryproducts_farm_name"" is not something to put in front
            // of a farm manager.
            var duplicate = ex.SqlState == PostgresErrorCodes.UniqueViolation;

            context.Response.StatusCode = (int)(duplicate
                ? HttpStatusCode.Conflict
                : HttpStatusCode.InternalServerError);
            context.Response.ContentType = "application/json; charset=utf-8";

            var hint = HintFor(ex);
            var payload = new
            {
                success = false,
                errorType = "SqlException",   // kept for frontend compatibility
                sqlState = ex.SqlState,
                message = duplicate ? DuplicateMessage(ex) : ex.MessageText,
                // The raw Postgres text stays available for the log and for
                // anyone debugging; it is just no longer what the user reads.
                sqlMessage = ex.MessageText,
                detail = ex.Detail,
                hint,
                path = context.Request.Path.Value,
            };

            await JsonSerializer.SerializeAsync(context.Response.Body, payload);
        }

        // ---------------------------------------------------------------------
        // Duplicate-key wording
        // ---------------------------------------------------------------------
        // Postgres hands us the table that rejected the row and a Detail of the
        // form: Key (farmid, name)=(abc-123, Layer Mash) already exists.
        // That is everything needed for a plain sentence, so build one.
        private static string DuplicateMessage(PostgresException ex)
        {
            var what = FriendlyTable(ex.TableName);
            var (column, value) = DuplicateKey(ex.Detail);

            if (value is null)
                return $"That {what} already exists.";

            if (string.Equals(column, "name", StringComparison.OrdinalIgnoreCase))
                return $"A {what} named \"{value}\" already exists. Use a different name.";

            return $"A {what} with that {Humanise(column!)} (\"{value}\") already exists.";
        }

        // Returns the column/value pair that actually identifies the clash.
        // farmid and its cousins scope every row in this database, so they are
        // never the interesting half of a composite key.
        private static (string? Column, string? Value) DuplicateKey(string? detail)
        {
            if (string.IsNullOrWhiteSpace(detail)) return (null, null);

            var m = System.Text.RegularExpressions.Regex.Match(
                detail, @"Key \((?<cols>[^)]*)\)=\((?<vals>.*)\) already exists");
            if (!m.Success) return (null, null);

            var cols = m.Groups["cols"].Value.Split(", ", StringSplitOptions.TrimEntries);
            var vals = m.Groups["vals"].Value.Split(", ", StringSplitOptions.TrimEntries);
            if (cols.Length == 0 || cols.Length != vals.Length) return (null, null);

            for (var i = cols.Length - 1; i >= 0; i--)
            {
                var c = cols[i].ToLowerInvariant();
                if (c is "farmid" or "companyid" or "branchid" or "userid") continue;
                return (cols[i], vals[i]);
            }
            return (null, null);
        }

        private static string FriendlyTable(string? table) => (table ?? "").ToLowerInvariant() switch
        {
            "poultryproducts"          => "poultry product",
            "waterproducts"            => "water product",
            "genericproducts"          => "product",
            "genericproductcategories" => "product category",
            "genericservicecategories" => "service category",
            "watercustomers"           => "customer",
            "genericcustomers"         => "customer",
            "flocks"                   => "flock",
            "farms"                    => "company",
            _                          => "record",
        };

        // referenceno -> "reference no", sachetprice -> "sachetprice". Only the
        // obvious separations; a wrong guess reads worse than the raw column.
        private static string Humanise(string column) => column.ToLowerInvariant() switch
        {
            "referenceno"    => "reference number",
            "productionnumber" => "production number",
            "email"          => "email address",
            "phonenumber"    => "phone number",
            _                => column.ToLowerInvariant(),
        };

        private static async Task WriteGenericError(HttpContext context, Exception ex)
        {
            if (context.Response.HasStarted) return;

            context.Response.Clear();
            context.Response.StatusCode = (int)HttpStatusCode.InternalServerError;
            context.Response.ContentType = "application/json; charset=utf-8";

            var payload = new
            {
                success = false,
                errorType = ex.GetType().Name,
                message = ex.Message,
                path = context.Request.Path.Value,
            };

            await JsonSerializer.SerializeAsync(context.Response.Body, payload);
        }

        // Map common SQLSTATEs to migration / permission hints so the frontend
        // doesn't need to know the SQL internals to act on the error.
        private static string? HintFor(PostgresException ex)
        {
            return ex.SqlState switch
            {
                // undefined_function — converted function missing
                "42883" => "A database function is missing. Re-load the converted function from postgres-migration/converted/procedures.",
                // undefined_table
                "42P01" => "A table or view referenced by this query does not exist in VisibilityCoreDB.",
                // undefined_column
                "42703" => "A column is missing from a table. The Postgres schema is older than the code expects.",
                // insufficient_privilege
                "42501" => "The DB user has no permission on the object. Grant it to the poultryapp role.",
                // invalid_password
                "28P01" => "Postgres login failed. Check ConnectionStrings__PoultryConn credentials.",
                _ => null,
            };
        }
    }
}
