namespace User.Management.API.Models
{
	public class CreateCheckoutSessionResponse
	{
		public string? SessionId { get; set; }
		public string? PublicKey { get; set; }
		public string? CheckoutUrl { get; set; }
		public string? Reference { get; set; }
	}
}
