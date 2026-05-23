using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using System.Security.Claims;
using System.Text.Json;

namespace PoultryFarmAPIWeb.Filters
{
    public class AuditLogActionFilter : IAsyncActionFilter
    {
        private readonly IAuditLogService _auditLogService;
        private readonly ILogger<AuditLogActionFilter> _logger;

        public AuditLogActionFilter(IAuditLogService auditLogService, ILogger<AuditLogActionFilter> logger)
        {
            _auditLogService = auditLogService;
            _logger = logger;
        }

        public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
        {
            var executedContext = await next();

            // Only log changes (POST, PUT, DELETE). Skip GET to avoid duplicate/noisy entries
            var httpMethod = context.HttpContext.Request.Method;
            if (httpMethod != "POST" && httpMethod != "PUT" && httpMethod != "DELETE")
            {
                return;
            }

            // Skip logging for audit logs endpoint itself to avoid infinite loops
            var controllerName = context.RouteData.Values["controller"]?.ToString();
            if (controllerName == "AuditLogs")
            {
                return;
            }

            try
            {
                var userId = context.HttpContext.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                    ?? context.HttpContext.Request.Query["userId"].FirstOrDefault()
                    ?? context.HttpContext.Request.Query["UserId"].FirstOrDefault()
                    ?? GetUserIdFromBody(context)
                    ?? "Anonymous";

                var userName = context.HttpContext.User?.FindFirst(ClaimTypes.Name)?.Value 
                    ?? context.HttpContext.User?.Identity?.Name
                    ?? context.HttpContext.Request.Headers["username"].FirstOrDefault()
                    ?? context.HttpContext.Request.Headers["X-Username"].FirstOrDefault()
                    ?? userId
                    ?? "Unknown";

                var farmId = context.HttpContext.Request.Query["farmId"].FirstOrDefault()
                    ?? context.HttpContext.Request.Query["FarmId"].FirstOrDefault()
                    ?? GetFarmIdFromBody(context)
                    ?? "Unknown";

                var actionName = context.ActionDescriptor.RouteValues["action"] ?? "Unknown";
                
                // Try to get resource ID from multiple sources
                var resourceId = context.RouteData.Values["id"]?.ToString() 
                    ?? GetResourceIdFromBody(context)
                    ?? GetResourceIdFromResponse(executedContext);

                var status = executedContext.Exception != null || 
                            (executedContext.Result as ObjectResult)?.StatusCode >= 400 
                            ? "Failed" : "Success";

                // Build more descriptive details
                var details = BuildDetails(context, executedContext, controllerName, actionName, resourceId);
                var data = BuildDataPayload(context, executedContext);

                // Use a cleaner resource name (just the controller name, not controller/action)
                var resourceName = GetResourceName(controllerName);

                var auditLog = new AuditLogModel
                {
                    UserId = userId,
                    UserName = userName,
                    Action = httpMethod,
                    Resource = resourceName,
                    ResourceId = resourceId,
                    Details = details,
                    Data = data,
                    IpAddress = context.HttpContext.Connection.RemoteIpAddress?.ToString(),
                    UserAgent = context.HttpContext.Request.Headers["User-Agent"].FirstOrDefault(),
                    Timestamp = DateTime.UtcNow,
                    Status = status,
                    FarmId = farmId
                };

                // Log asynchronously without blocking
                _ = Task.Run(async () =>
                {
                    try
                    {
                        _logger.LogInformation("Inserting audit log: {Action} {Resource} by {UserId} for farm {FarmId}", 
                            auditLog.Action, auditLog.Resource, auditLog.UserId, auditLog.FarmId);
                        var id = await _auditLogService.InsertAsync(auditLog);
                        _logger.LogInformation("Audit log inserted successfully with ID: {Id}", id);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Failed to insert audit log: {Action} {Resource}", auditLog.Action, auditLog.Resource);
                    }
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in audit log filter");
            }
        }

        /// <summary>
        /// PUT routes take (int id, Model model) as args. Values.FirstOrDefault() can return
        /// the int — calling GetProperty("FarmId") on int returns null and the helper falls
        /// through to "Unknown". Iterate every argument and pick the first one that exposes
        /// the named property with a non-empty value.
        /// </summary>
        private static string? FindStringPropFromArgs(ActionExecutingContext context, params string[] propertyNames)
        {
            foreach (var obj in context.ActionArguments.Values)
            {
                if (obj == null) continue;
                var t = obj.GetType();
                // Skip primitives/strings/value types — they can't carry the property we want.
                if (t.IsPrimitive || t.IsEnum || t == typeof(string) || t == typeof(decimal) || t == typeof(Guid)) continue;
                foreach (var name in propertyNames)
                {
                    var prop = t.GetProperty(name);
                    if (prop == null) continue;
                    var value = prop.GetValue(obj)?.ToString();
                    if (!string.IsNullOrWhiteSpace(value)) return value;
                }
            }
            return null;
        }

        private string? GetUserIdFromBody(ActionExecutingContext context) =>
            FindStringPropFromArgs(context, "UserId", "CreatedBy", "UpdatedBy");

        private string? GetFarmIdFromBody(ActionExecutingContext context) =>
            FindStringPropFromArgs(context, "FarmId");

        private string? GetResourceIdFromBody(ActionExecutingContext context) =>
            FindStringPropFromArgs(context, "Id", "FlockId", "BatchId", "ProductionRecordId");

        private string? GetResourceIdFromResponse(ActionExecutedContext context)
        {
            // Try to extract ID from the response (useful for POST operations)
            if (context.Result is ObjectResult objectResult && objectResult.Value != null)
            {
                var obj = objectResult.Value;
                var idProp = obj.GetType().GetProperty("Id")
                    ?? obj.GetType().GetProperty("FlockId")
                    ?? obj.GetType().GetProperty("BatchId")
                    ?? obj.GetType().GetProperty("ProductionRecordId");
                if (idProp != null)
                {
                    var value = idProp.GetValue(obj);
                    if (value != null)
                    {
                        return value.ToString();
                    }
                }
                
                // For CreatedAtAction results, try to get ID from route values
                if (context.Result is CreatedAtActionResult createdAtAction)
                {
                    if (createdAtAction.RouteValues != null && createdAtAction.RouteValues.ContainsKey("id"))
                    {
                        return createdAtAction.RouteValues["id"]?.ToString();
                    }
                }
            }
            return null;
        }

        private string GetResourceName(string? controllerName)
        {
            if (string.IsNullOrEmpty(controllerName))
                return "Unknown";

            // Map controller names to more user-friendly resource names
            return controllerName switch
            {
                "ProductionRecord" => "ProductionRecord",
                "Flock" => "Flock",
                "MainFlockBatch" => "FlockBatch",
                "FeedUsage" => "FeedUsage",
                "EggProduction" => "EggProduction",
                "Expense" => "Expense",
                "Sale" => "Sale",
                "Customer" => "Customer",
                "InventoryItem" => "InventoryItem",
                "House" => "House",
                "Cash" => "CashAdjustment",
                "EggInventoryAdjustment" => "EggInventoryAdjustment",
                "FeedInventoryAdjustment" => "FeedInventoryAdjustment",
                "Supplier" => "Supplier",
                _ => controllerName
            };
        }

        private string BuildDetails(ActionExecutingContext context, ActionExecutedContext executedContext, 
            string? controllerName, string? actionName, string? resourceId)
        {
            if (executedContext.Exception != null)
            {
                return $"Error: {executedContext.Exception.Message}";
            }

            var action = context.HttpContext.Request.Method;
            var resource = GetResourceName(controllerName);
            
            var details = $"{action} {resource}";
            
            if (!string.IsNullOrEmpty(resourceId))
            {
                details += $" (ID: {resourceId})";
            }
            
            if (action == "POST")
            {
                details += " - Created";
            }
            else if (action == "PUT")
            {
                details += " - Updated";
            }
            else if (action == "DELETE")
            {
                details += " - Deleted";
            }

            return details;
        }

        private const int MaxDataChars = 32000;

        private static string? BuildDataPayload(ActionExecutingContext context, ActionExecutedContext executedContext)
        {
            try
            {
                var payload = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase)
                {
                    ["method"] = context.HttpContext.Request.Method,
                    ["path"] = context.HttpContext.Request.Path.Value,
                };

                if (context.ActionArguments.Count > 0)
                {
                    var request = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
                    foreach (var kv in context.ActionArguments)
                    {
                        if (kv.Value == null) continue;
                        request[kv.Key] = kv.Value;
                    }
                    if (request.Count > 0)
                        payload["request"] = request;
                }

                if (executedContext.Exception != null)
                {
                    payload["error"] = executedContext.Exception.Message;
                }
                else if (executedContext.Result is ObjectResult objectResult && objectResult.Value != null)
                {
                    payload["response"] = objectResult.Value;
                }

                var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions
                {
                    WriteIndented = false,
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                });

                if (json.Length > MaxDataChars)
                    return json[..MaxDataChars] + "…[truncated]";

                return json;
            }
            catch
            {
                return null;
            }
        }
    }
}

