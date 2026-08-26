using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace PoultryFarmAPIWeb.Helpers
{
    /// <summary>
    /// Shared helpers for Hotel controllers: farmId ownership verification and input validation.
    /// </summary>
    public static class HotelAuthHelper
    {
        /// <summary>
        /// Verifies the authenticated user's JWT FarmId claim matches the requested farmId.
        /// Returns null if valid, or an IActionResult (Forbid/BadRequest) if invalid.
        /// </summary>
        public static IActionResult? VerifyFarmOwnership(ClaimsPrincipal user, string? farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId))
                return new BadRequestObjectResult(new { message = "Company ID is required." });

            var claimFarmId = user.FindFirst("FarmId")?.Value;
            if (string.IsNullOrEmpty(claimFarmId) ||
                !string.Equals(claimFarmId, farmId, StringComparison.OrdinalIgnoreCase))
            {
                return new ObjectResult(new { message = "Access denied: you do not belong to this company." })
                {
                    StatusCode = 403
                };
            }

            return null; // Valid
        }

        /// <summary>
        /// Extracts the userId from JWT claims.
        /// </summary>
        public static string GetUserId(ClaimsPrincipal user)
        {
            return user.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "Unknown";
        }

        /// <summary>
        /// Extracts the userName from JWT claims.
        /// </summary>
        public static string GetUserName(ClaimsPrincipal user)
        {
            return user.FindFirst(ClaimTypes.Name)?.Value
                ?? user.FindFirst("name")?.Value
                ?? "Unknown";
        }
    }

    /// <summary>
    /// Input validation helpers for Hotel controllers.
    /// </summary>
    public static class HotelValidation
    {
        public static IActionResult? ValidateAmount(decimal amount, string fieldName = "Amount")
        {
            if (amount < 0)
                return new BadRequestObjectResult(new { message = $"{fieldName} cannot be negative." });
            return null;
        }

        public static IActionResult? ValidatePositiveAmount(decimal amount, string fieldName = "Amount")
        {
            if (amount <= 0)
                return new BadRequestObjectResult(new { message = $"{fieldName} must be greater than zero." });
            return null;
        }

        public static IActionResult? ValidateRequiredString(string? value, string fieldName)
        {
            if (string.IsNullOrWhiteSpace(value))
                return new BadRequestObjectResult(new { message = $"{fieldName} is required." });
            return null;
        }

        public static IActionResult? ValidateDateRange(string? startDate, string? endDate)
        {
            if (string.IsNullOrWhiteSpace(startDate) || string.IsNullOrWhiteSpace(endDate))
                return new BadRequestObjectResult(new { message = "Start date and end date are required." });

            if (!DateTime.TryParse(startDate, out var start) || !DateTime.TryParse(endDate, out var end))
                return new BadRequestObjectResult(new { message = "Invalid date format." });

            if (end < start)
                return new BadRequestObjectResult(new { message = "End date cannot be before start date." });

            return null;
        }

        public static IActionResult? ValidatePositiveInt(int value, string fieldName)
        {
            if (value <= 0)
                return new BadRequestObjectResult(new { message = $"{fieldName} must be greater than zero." });
            return null;
        }
    }
}
