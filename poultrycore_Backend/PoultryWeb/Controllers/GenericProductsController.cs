using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class GenericProductsController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericProductsController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index()
        {
            var products = await _api.GetProductsAsync();
            return View(products);
        }
    }
}
