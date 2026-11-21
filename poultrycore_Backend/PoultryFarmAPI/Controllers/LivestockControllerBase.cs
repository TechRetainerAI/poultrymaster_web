// Shared plumbing for every Livestock controller (migration 458+).
//
// Bodies are taken as raw JSON and handed to the database function unchanged:
// the function reads the fields it knows and ignores the rest (farmId included,
// which is passed separately). Results are the function's own JSON.

using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    public abstract class LivestockControllerBase : ControllerBase
    {
        protected readonly ILivestockDb Db;
        protected LivestockControllerBase(ILivestockDb db) => Db = db;

        /// <summary>Who is acting, for createdby / updatedby.</summary>
        protected string? Actor()
            => User.FindFirst(ClaimTypes.Name)?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        protected ContentResult JsonText(string json) => Content(json, "application/json");

        protected static string? Str(JsonElement body, string name)
            => body.ValueKind == JsonValueKind.Object && body.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
                ? v.GetString() : null;

        protected static int? IntOf(JsonElement body, string name)
        {
            if (body.ValueKind != JsonValueKind.Object || !body.TryGetProperty(name, out var v)) return null;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var i)) return i;
            if (v.ValueKind == JsonValueKind.String && int.TryParse(v.GetString(), out var s)) return s;
            return null;
        }

        protected static DateTime? DateOf(JsonElement body, string name)
            => DateTime.TryParse(Str(body, name), out var d) ? d.Date : null;

        protected static string? FarmOf(JsonElement body) => Str(body, "farmId");

        /// <summary>
        /// Runs a write with the company and the actor checked first, and the
        /// database's refusals turned into readable 400s.
        /// </summary>
        protected async Task<IActionResult> Write(string? farmId, Func<string, Task<IActionResult>> run)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again." });
            // The company-type and IAM filters judge a write by the query string
            // or, failing that, the token's active company -- not by the body.
            // So a body naming a different company than the token's would slip
            // past both. Refuse it here.
            var tokenFarm = User.FindFirst("FarmId")?.Value;
            if (Request.Query.ContainsKey("farmId") ? Request.Query["farmId"] != farmId
                : !string.IsNullOrWhiteSpace(tokenFarm) && !string.Equals(tokenFarm, farmId, StringComparison.OrdinalIgnoreCase))
                return StatusCode(403, new { message = "Switch to this company before changing it." });
            return await Refusals(() => run(by));
        }

        protected async Task<IActionResult> Read(string? farmId, Func<Task<IActionResult>> run)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return await Refusals(run);
        }

        private async Task<IActionResult> Refusals(Func<Task<IActionResult>> run)
        {
            try
            {
                return await run();
            }
            catch (PostgresException ex) when (ex.SqlState is "P0001" or "23514")
            {
                return BadRequest(new { message = ex.MessageText });
            }
            catch (PostgresException ex) when (ex.SqlState == "LV003")
            {
                // Not enough of a stock item for what is being used.
                return Conflict(new { message = ex.MessageText, code = "InsufficientStock" });
            }
            catch (PostgresException ex) when (ex.SqlState == "LV004")
            {
                // A cash account cannot cover the payment.
                return Conflict(new { message = ex.MessageText, code = "InsufficientCash" });
            }
            catch (PostgresException ex) when (ex.SqlState == "LV005")
            {
                // Animals under a medicine withdrawal period: the page asks the
                // seller to confirm with a reason and sends overrideWithdrawal.
                return Conflict(new { message = ex.MessageText, code = "WithdrawalPeriod" });
            }
            catch (PostgresException ex) when (ex.SqlState == "LV006")
            {
                // The day is closed (464's lock).
                return Conflict(new { message = ex.MessageText, code = "DayClosed" });
            }
            catch (PostgresException ex) when (ex.SqlState == "LV007")
            {
                // Closing a day that has problems: the page shows them and asks for a note.
                return Conflict(new { message = ex.MessageText, code = "DayHasProblems" });
            }
            catch (PostgresException ex) when (ex.SqlState == "P0010")
            {
                // The group already has a record for that day.
                return Conflict(new { message = ex.MessageText, code = "AlreadyRecorded" });
            }
            catch (PostgresException ex) when (ex.SqlState == "23505")
            {
                // A unique index caught a race the function's own check missed.
                return Conflict(new { message = "That name or tag was just used by someone else. Refresh and try again." });
            }
            catch (PostgresException ex) when (ex.SqlState is "22P02" or "22007" or "22008" or "22003")
            {
                return BadRequest(new { message = "One of the values entered is not valid. Check the numbers and dates." });
            }
        }
    }
}
