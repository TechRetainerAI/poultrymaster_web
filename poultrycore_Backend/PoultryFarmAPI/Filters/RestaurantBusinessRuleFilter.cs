using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Npgsql;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// The restaurant money functions (migration 323) refuse bad requests with
    /// RAISE EXCEPTION -- "this payment is more than the balance due", "the books
    /// are closed up to 21 Sep", "the till only holds 40.00". That is SQLSTATE
    /// P0001, and GlobalExceptionMiddleware would answer it with a 500, which
    /// reads as "the server broke". These are the caller's mistakes, so they go
    /// back as 400 with the function's own sentence as the message.
    ///
    /// Scoped by attribute to the restaurant controllers that call those
    /// functions, so no other module's error codes change.
    /// </summary>
    public sealed class RestaurantBusinessRuleFilter : ExceptionFilterAttribute
    {
        public override void OnException(ExceptionContext context)
        {
            var pg = Find(context.Exception);
            if (pg == null || pg.SqlState != "P0001") return;

            context.Result = new BadRequestObjectResult(new { message = pg.MessageText });
            context.ExceptionHandled = true;
        }

        private static PostgresException? Find(Exception? ex)
        {
            while (ex != null)
            {
                if (ex is PostgresException pg) return pg;
                ex = ex.InnerException;
            }
            return null;
        }
    }
}
