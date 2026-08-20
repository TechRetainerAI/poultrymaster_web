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
            context.Response.StatusCode = (int)HttpStatusCode.InternalServerError;
            context.Response.ContentType = "application/json; charset=utf-8";

            var hint = HintFor(ex);
            var payload = new
            {
                success = false,
                errorType = "SqlException",   // kept for frontend compatibility
                sqlState = ex.SqlState,
                message = ex.MessageText,
                detail = ex.Detail,
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
