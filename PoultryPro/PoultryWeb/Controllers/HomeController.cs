using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using PoultryWeb.Models;
using System.Diagnostics;
using System.Security.Claims;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class HomeController : Controller
    {
        private readonly ILogger<HomeController> _logger;

        public HomeController(ILogger<HomeController> logger)
        {
            _logger = logger;
        }

        public IActionResult Index()
        {
            // Check if user is Staff or Admin
            var isStaff = User.FindFirst("IsStaff")?.Value;
            var role = User.FindFirst(ClaimTypes.Role)?.Value;

            _logger.LogInformation("User logged in - IsStaff: {IsStaff}, Role: {Role}", isStaff, role);

            // Redirect to appropriate dashboard
            if (isStaff == "true" || role == "Staff")
            {
                // Employee Dashboard
                return RedirectToAction("EmployeeDashboard");
            }
            else
            {
                // Admin Dashboard
                return RedirectToAction("AdminDashboard");
            }
        }

        /// <summary>
        /// Admin Dashboard - Full access to all features
        /// </summary>
        [Authorize(Roles = "Admin,FarmAdmin")]
        public IActionResult AdminDashboard()
        {
            ViewBag.UserName = User.FindFirst(ClaimTypes.Name)?.Value;
            ViewBag.FarmName = User.FindFirst("FarmName")?.Value;
            return View();
        }

        /// <summary>
        /// Employee Dashboard - Limited access (view-only for most features)
        /// </summary>
        [Authorize(Roles = "Staff,User")]
        public IActionResult EmployeeDashboard()
        {
            ViewBag.UserName = User.FindFirst(ClaimTypes.Name)?.Value;
            ViewBag.FarmName = User.FindFirst("FarmName")?.Value;
            return View();
        }

        public IActionResult Privacy()
        {
            return View();
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }
    }
}
