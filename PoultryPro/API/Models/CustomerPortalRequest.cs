using System.ComponentModel.DataAnnotations;

namespace API.Models
{
	public class CustomerPortalRequest
	{
		[Required]
		public string ReturnUrl { get; set; }
		
		//No longer passing it. We get it directly from the db
		//[Required]
		//public string CustomerId { get; set; }
	}
}