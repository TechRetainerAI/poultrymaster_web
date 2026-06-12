using System.Threading.Tasks;
using PoultryFarmApp.Business;
using PoultryWeb.Models;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using System.Diagnostics;
using Microsoft.AspNetCore.Authorization;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class FlockController : Controller
    {
        private readonly IFlockWebApiService _flockService;
        // or your direct DB service if you prefer

        // Constructor injection
        public FlockController(IFlockWebApiService flockService)
        {
            _flockService = flockService;
        }

        // Renders a page with a list of flocks (Option A: server calls the API)
        // Then the view can show them in plain Razor, or Knockout can do it dynamically.
        public async Task<ActionResult> Index()
        {
            // If you want to load data server-side:
            var flocks = await _flockService.GetAllFlocksAsync();
            return View(flocks);

            // OR if you're using Knockout to load data from the client side,
            // just return an empty model or no model. The Knockout script
            // will call the API endpoints directly to populate the data.
            //return View();
        }

        // Example of a "Details" page server side
        public async Task<ActionResult> Details(int id)
        {
            var flock = await _flockService.GetFlockByIdAsync(id);
            if (flock == null)
                return NotFound(); // or NotFound() in ASP.NET Core

            return View(flock);
        }

        // Example "Create" (GET) to show a form
        public ActionResult Create()
        {
            return View(new FlockModel());
        }

        // Example "Create" (POST) - Option A: server calls the Web API
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<ActionResult> Create(FlockModel model)
        {
            // Remove keys the client didn't post so they don't trigger validation errors
            ModelState.Remove(nameof(model.FarmId));

            if (!ModelState.IsValid)
            {
                return View(model);
            }

            var createdFlock = await _flockService.CreateFlockAsync(model);
            // after creation, redirect to Index
            return RedirectToAction("Index");
        }

        // Example "Edit" (GET)
        public async Task<ActionResult> Edit(int id)
        {
            var flock = await _flockService.GetFlockByIdAsync(id);
            if (flock == null)
                return NotFound();

            return View(flock);
        }

        // Example "Edit" (POST)
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<ActionResult> Edit(FlockModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            await _flockService.UpdateFlockAsync(model.FlockId, model);
            return RedirectToAction("Index");
        }

        // Example "Delete" (GET)
        public async Task<ActionResult> Delete(int id)
        {
            var flock = await _flockService.GetFlockByIdAsync(id);
            if (flock == null)
                return NotFound();

            return View(flock);
        }

        // Example "Delete" (POST)
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<ActionResult> DeleteConfirmed(int flockId)
        {
            await _flockService.DeleteFlockAsync(flockId);
            return RedirectToAction("Index");
        }


        // GET: /Flock/EditPartial/5
        [HttpGet]
        public async Task<ActionResult> EditPartial(int id)
        {
            //var flock = _flockService.GetFlockById(id);
            var flock = await _flockService.GetFlockByIdAsync(id);
            if (flock == null) return NotFound();
            return PartialView("_EditPartial", flock);
        }

        // GET: /Flock/CreatePartial
        [HttpGet]
        public IActionResult CreatePartial()
        {
            // Return an empty new flock model
            return PartialView("_CreatePartial", new FlockModel
            {
                StartDate = DateTime.Today,
                Active = true
            });
        }

        // GET: /Flock/DeletePartial/5
        [HttpGet]
        public async Task<ActionResult> DeletePartial(int id)
        {
            //var flock = _flockService.GetFlockById(id);
            var flock = await _flockService.GetFlockByIdAsync(id);
            if (flock == null) return NotFound();
            return PartialView("_DeletePartial", flock);
        }
    }
}
