using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Npgsql;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// The hotel loan and payroll functions (migration 325) refuse bad requests
    /// with RAISE EXCEPTION -- "the repayment is more than Ama still owes",
    /// "only an Approved payroll run can be marked paid". That is SQLSTATE
    /// P0001, which GlobalExceptionMiddleware would answer with a 500 that reads
    /// as "the server broke". These are the caller's mistakes, so they go back as
    /// 400 with the function's own sentence as the message.
    ///
    /// Same idea as RestaurantBusinessRuleFilter, kept separate so the two
    /// modules never change each other's error codes. Applied by attribute to the
    /// hotel controllers that call those functions.
    /// </summary>
    public sealed class HotelBusinessRuleFilter : ExceptionFilterAttribute
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
