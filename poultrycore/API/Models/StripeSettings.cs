namespace API.Models
{
	public class StripeSettings
	{
		public string PrivateKey { get; set; } = "";
		public string PublicKey { get; set; } = "";
		public string WHSecret { get; set; } = "";
	}
}