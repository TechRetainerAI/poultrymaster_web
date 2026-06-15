using Microsoft.Data.SqlClient;
using System.Net;
using System.Text.Json;

namespace PoultryFarmAPIWeb.Middleware
{
    // Converts unhandled exceptions into structured JSON. Without this, ASP.NET
    // returns an HTML stack trace (dev) or empty 500 (prod) which the Next.js
    // proxy then collapses into a generic "Failed to load resource: 500".
    //
    // The Generic Company endpoints throw SqlException when migrations 028-042
    // aren't applied (missing SP / missing table / Type column). Surface the
    // exact SqlException number + message so the caller can see "Invalid column
    // name 'Type'" or "Could not find stored procedure 'spGenericProduct_GetAll'"
    // instead of a black-box 500.
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
            catch (SqlException sqlEx)
            {
                _logger.LogError(sqlEx,
                    "SqlException on {Method} {Path}: number={Number} state={State}",
                    context.Request.Method, context.Request.Path, sqlEx.Number, sqlEx.State);
                await WriteSqlError(context, sqlEx);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unhandled exception on {Method} {Path}",
                    context.Request.Method, context.Request.Path);
                await WriteGenericError(context, ex);
            }
        }

        private static async Task WriteSqlError(HttpContext context, SqlException ex)
        {
            if (context.Response.HasStarted) return;

            context.Response.Clear();
            context.Response.StatusCode = (int)HttpStatusCode.InternalServerError;
            context.Response.ContentType = "application/json; charset=utf-8";

            var hint = HintFor(ex);
            var payload = new
            {
                success = false,
                errorType = "SqlException",
                sqlNumber = ex.Number,
                sqlState = ex.State,
                message = ex.Message,
                hint,
                path = context.Request.Path.Value,
            };

            await JsonSerializer.SerializeAsync(context.Response.Body, payload);
        }

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

        // Map common SqlException numbers to migration / permission hints so the
        // frontend doesn't need to know the SQL internals to act on the error.
        private static string? HintFor(SqlException ex)
        {
            return ex.Number switch
            {
                // Could not find stored procedure
                2812 => "A stored procedure is missing. Re-run the SQL migrations in poultrycore/PoultryFarmAPI/Migrations (028-042 for Generic Company).",
                // Invalid object name (table/view missing)
                208  => "A table or view referenced by this query does not exist. Re-run the matching migration in poultrycore/PoultryFarmAPI/Migrations.",
                // Invalid column name
                207  => "A column is missing from a table. The schema is older than the code expects — re-run the latest migration that adds the column.",
                // EXECUTE permission denied on the object
                229  => "The DB user has no EXECUTE permission on a stored procedure. Run migration 042 as a DB owner to grant EXECUTE on the new SPs.",
                // Login failed
                18456 => "SQL login failed. Check ConnectionStrings__PoultryConn credentials.",
                _ => null,
            };
        }
    }
}
