using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Water/drivers")]
    public class WaterDriverController : ControllerBase
    {
        private readonly IWaterDriverService _svc;
        public WaterDriverController(IWaterDriverService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterDriverModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterDriverModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterDriverModel>> Create([FromBody] WaterDriverModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] WaterDriverModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterDriverId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }

        // #18 — drivers as employees-with-driver-role (+ legacy standalone rows).
        [HttpGet("list-for-farm")] public async Task<ActionResult<IEnumerable<WaterDriverModel>>> ListForFarm([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.ListForFarmAsync(farmId));

        // #18 — make an existing employee a driver (assign role + upsert profile, one tx).
        [HttpPost("from-employee")] public async Task<ActionResult<WaterDriverModel>> CreateFromEmployee([FromBody] WaterDriverFromEmployeeRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(req.EmployeeUserId)) return BadRequest("Employee is required.");
            var created = await _svc.UpsertForEmployeeAsync(req);
            return Ok(created);
        }

        // #18 — read/replace an employee's job roles (Driver, Salesperson, …).
        [HttpGet("job-roles")] public async Task<ActionResult<IEnumerable<string>>> GetJobRoles([FromQuery] string farmId, [FromQuery] string employeeUserId)
            => (string.IsNullOrWhiteSpace(farmId) || string.IsNullOrWhiteSpace(employeeUserId))
                ? BadRequest("Company ID and employee are required.")
                : Ok(await _svc.GetJobRolesAsync(employeeUserId, farmId));

        [HttpPost("job-roles")] public async Task<IActionResult> SetJobRoles([FromBody] WaterEmployeeJobRolesRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId) || string.IsNullOrWhiteSpace(req.EmployeeUserId))
                return BadRequest("Company ID and employee are required.");
            await _svc.SetJobRolesAsync(req.EmployeeUserId, req.FarmId, req.RolesCsv);
            return NoContent();
        }
    }

    public class WaterEmployeeJobRolesRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string EmployeeUserId { get; set; } = string.Empty;
        public string? RolesCsv { get; set; }
    }

    [ApiController]
    [Route("api/Water/vehicles")]
    public class WaterVehicleController : ControllerBase
    {
        private readonly IWaterVehicleService _svc;
        public WaterVehicleController(IWaterVehicleService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterVehicleModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterVehicleModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterVehicleModel>> Create([FromBody] WaterVehicleModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] WaterVehicleModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterVehicleId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/routes")]
    public class WaterRouteController : ControllerBase
    {
        private readonly IWaterRouteService _svc;
        public WaterRouteController(IWaterRouteService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterRouteModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterRouteModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterRouteModel>> Create([FromBody] WaterRouteModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] WaterRouteModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterRouteId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/vehicle-loadings")]
    public class WaterVehicleLoadingController : ControllerBase
    {
        private readonly IWaterVehicleLoadingService _svc;
        public WaterVehicleLoadingController(IWaterVehicleLoadingService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterVehicleLoadingModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterVehicleLoadingModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterVehicleLoadingModel>> Create([FromBody] WaterVehicleLoadingModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")] public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId);
            return NoContent();
        }

        // Migration 065: void a Draft or Loaded loading. Reverses stock when
        // status was Loaded; blocks if a non-cancelled return exists.
        [HttpPost("{id:int}/void")]
        public async Task<IActionResult> Void(int id, [FromQuery] string farmId, [FromQuery] string? voidedBy, [FromBody] VoidLoadingRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.VoidAsync(id, farmId, voidedBy, body?.Reason);
            return NoContent();
        }

        public class VoidLoadingRequest { public string? Reason { get; set; } }

        // Migration 068 — Reload / Edit Load. Reverses existing LoadOut txns
        // and applies new ones atomically. Only valid on Draft + Loaded.
        [HttpPost("{id:int}/reload")]
        public async Task<IActionResult> Reload(int id, [FromQuery] string farmId, [FromQuery] string? updatedBy,
            [FromBody] WaterVehicleLoadingReloadInput body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (body is null) return BadRequest("Request body is required.");
            await _svc.ReloadAsync(id, body, farmId, updatedBy);
            return NoContent();
        }

        // Migration 064: per-product loading lines.
        [HttpGet("{id:int}/items")]
        public async Task<ActionResult<IEnumerable<WaterVehicleLoadingItemModel>>> GetItems(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetItemsAsync(id, farmId));
        }
    }

    [ApiController]
    [Route("api/Water/driver-returns")]
    public class WaterDriverReturnController : ControllerBase
    {
        private readonly IWaterDriverReturnService _svc;
        public WaterDriverReturnController(IWaterDriverReturnService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterDriverReturnModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterDriverReturnModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterDriverReturnModel>> Create([FromBody] WaterDriverReturnModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")] public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId);
            return NoContent();
        }

        // Migration 071 — Uncancel. Flips a Cancelled return back to Draft so
        // the user can edit and re-approve it. The SP RAISERRORs if the row
        // isn't currently Cancelled.
        [HttpPost("{id:int}/uncancel")] public async Task<IActionResult> Uncancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.UncancelAsync(id, farmId);
            return NoContent();
        }

        // Migration 072 — admin-only hard delete of a Cancelled return.
        // The SP guards on Status='Cancelled'; the frontend gates the button
        // behind permissions.isAdmin. This endpoint doesn't add a JWT role
        // check yet — same trust model as the other write endpoints on this
        // controller (auth scope is handled at the gateway / proxy layer).
        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }

        // Migration 068 — Reverse Reconciliation. Unwinds sales/payments/stock
        // and flips back to Draft so the user can edit + re-reconcile.
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromQuery] string? reversedBy,
            [FromBody] ReverseReturnRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, reversedBy, body?.Reason);
            return NoContent();
        }

        public class ReverseReturnRequest { public string? Reason { get; set; } }

        // Migration 064: per-product reconciliation lines.
        [HttpGet("{id:int}/items")]
        public async Task<ActionResult<IEnumerable<WaterDriverReturnItemModel>>> GetItems(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetItemsAsync(id, farmId));
        }

        // Migration 064: customer breakdown with line items.
        [HttpGet("{id:int}/customer-sales")]
        public async Task<ActionResult<IEnumerable<WaterDriverReturnCustomerSaleRow>>> GetCustomerSales(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetCustomerSalesAsync(id, farmId));
        }

        // Migration 064: delivery expenses logged for this return.
        [HttpGet("{id:int}/expenses")]
        public async Task<ActionResult<IEnumerable<WaterDeliveryExpenseModel>>> GetExpenses(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetExpensesAsync(id, farmId));
        }

        // Migration 085: list ALL delivery expenses for the farm, with optional
        // date range. The unified /water-expenses page calls this alongside
        // spWaterExpense_List and merges client-side so Step 4 expenses from
        // driver returns no longer "disappear" from the operator's view.
        [HttpGet("/api/Water/delivery-expenses")]
        public async Task<ActionResult<IEnumerable<WaterDeliveryExpenseModel>>> ListAllDeliveryExpenses(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.ListAllDeliveryExpensesAsync(farmId, fromDate, toDate));
        }

        // Migration 083 — Approve & Reconcile a Draft return in one shot.
        // Validates bag accounting, posts sales using the row's SalesPostingMode,
        // updates inventory + cash + customer balances.
        [HttpPost("{id:int}/approve-reconcile")]
        public async Task<IActionResult> ApproveReconcile(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveReconcileAsync(id, farmId, approvedBy);
            return NoContent();
        }

        // Migration 083 — set posting mode + primary customer on a Draft return.
        [HttpPost("{id:int}/posting-mode")]
        public async Task<IActionResult> UpdatePostingMode(int id, [FromQuery] string farmId,
            [FromBody] WaterDriverReturnPostingModeInput body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            await _svc.UpdatePostingModeAsync(id, farmId, body.SalesPostingMode, body.PrimaryCustomerId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/driver-shortages")]
    public class WaterDriverShortageController : ControllerBase
    {
        private readonly IWaterDriverShortageService _svc;
        public WaterDriverShortageController(IWaterDriverShortageService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterDriverShortageModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status));

        [HttpPost("{id:int}/resolve")] public async Task<IActionResult> Resolve(int id, [FromQuery] string farmId,
            [FromBody] WaterDriverShortageResolveRequest req, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            await _svc.ResolveAsync(id, farmId, req.NewStatus, req.Reason, approvedBy);
            return NoContent();
        }
    }
}
