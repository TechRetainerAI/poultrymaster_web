using Microsoft.AspNetCore.Mvc;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class TestController : ControllerBase
    {
        [HttpGet("ping")]
        public IActionResult Ping()
        {
            return Ok(new { message = "PoultryFarm API is running!", timestamp = DateTime.UtcNow });
        }

        [HttpGet("health")]
        public IActionResult Health()
        {
            return Ok(new { 
                status = "healthy", 
                api = "PoultryFarmAPI", 
                version = "1.0.0",
                timestamp = DateTime.UtcNow 
            });
        }
    }
}
