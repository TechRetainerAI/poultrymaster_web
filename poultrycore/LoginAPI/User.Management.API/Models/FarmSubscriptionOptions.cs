using System.Collections.Generic;

namespace User.Management.API.Models
{
	/// <summary>Binds <c>FarmSubscription</c> from appsettings / env (tier limits + monthly amounts).</summary>
	public class FarmSubscriptionOptions
	{
		public int TrialDays { get; set; } = 7;
		public string Currency { get; set; } = "ghs";
		public int Tier1MaxBirds { get; set; }
		public int Tier2MaxBirds { get; set; }
		public decimal Tier1MonthlyAmount { get; set; }
		public decimal Tier2MonthlyAmount { get; set; }
		public decimal Tier3MonthlyAmount { get; set; }
	}

	public class FarmSubscriptionTiersOptions
	{
		public int TrialDays { get; set; } = 7;
		public string Currency { get; set; } = "ghs";
		public string? Note { get; set; }
		public List<FarmTierOption> Tiers { get; set; } = new();
	}

	public class FarmTierOption
	{
		public string Id { get; set; } = "";
		/// <summary>Null or missing = unlimited upper bound (top tier).</summary>
		public int? MaxBirds { get; set; }
		/// <summary>Monthly amount in major currency units (e.g. GHS). Converted to smallest unit for Stripe.</summary>
		public decimal MonthlyAmount { get; set; }
		public string Label { get; set; } = "";
	}
}
