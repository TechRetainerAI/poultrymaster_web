using System.ComponentModel.DataAnnotations;

namespace User.Management.API.Models
{
	public class CreateCheckoutSessionRequest
	{
		/// <summary>Stripe Price ID — required unless <see cref="TotalBirds"/> is sent for farm-tier checkout.</summary>
		public string? PriceId { get; set; }

		[Required]
		public string SuccessUrl { get; set; } = "";

		[Required]
		public string FailureUrl { get; set; } = "";

		/// <summary>When set, create subscription using dynamic recurring price for the matching tier (no Stripe catalog price ID).</summary>
		public int? TotalBirds { get; set; }

		/// <summary>When subscribing with <see cref="PriceId"/> only; if true (default), apply farm trial days from config.</summary>
		public bool? IncludeTrialWithPriceId { get; set; }
	}
}
