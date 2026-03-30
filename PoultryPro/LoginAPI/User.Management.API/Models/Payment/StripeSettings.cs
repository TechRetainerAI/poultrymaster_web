namespace User.Management.API.Models
{
	public class StripeSettings
	{
		public string PrivateKey { get; set; } = "";
		public string PublicKey { get; set; } = "";
		public string WHSecret { get; set; } = "";
	}
}