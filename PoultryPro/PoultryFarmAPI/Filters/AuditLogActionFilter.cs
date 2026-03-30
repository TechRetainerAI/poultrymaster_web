using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using System.Security.Claims;

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

        private string? GetUserIdFromBody(ActionExecutingContext context)
        {
            var obj = context.ActionArguments.Values.FirstOrDefault();
            if (obj != null)
            {
                var prop = obj.GetType().GetProperty("UserId");
                if (prop != null)
                {
                    return prop.GetValue(obj)?.ToString();
                }
                var prop2 = obj.GetType().GetProperty("CreatedBy");
                if (prop2 != null)
                {
                    return prop2.GetValue(obj)?.ToString();
                }
                var prop3 = obj.GetType().GetProperty("UpdatedBy");
                if (prop3 != null)
                {
                    return prop3.GetValue(obj)?.ToString();
                }
            }
            return null;
        }

        private string? GetFarmIdFromBody(ActionExecutingContext context)
        {
            var obj = context.ActionArguments.Values.FirstOrDefault();
            if (obj != null)
            {
                var prop = obj.GetType().GetProperty("FarmId");
                if (prop != null)
                {
                    return prop.GetValue(obj)?.ToString();
                }
            }
            return null;
        }

        private string? GetResourceIdFromBody(ActionExecutingContext context)
        {
            var obj = context.ActionArguments.Values.FirstOrDefault();
            if (obj != null)
            {
                // Try common ID property names
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
            }
            return null;
        }

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
    }
}

