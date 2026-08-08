namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// The four numbers on one Business Office company card. What each slot means
    /// depends on the company type — Metric1 is "Production today" for Water and
    /// "Eggs today" for Poultry — because the card's labels are already defined
    /// per type on the client and there is no value in stating them twice.
    /// See spBusinessOffice_CompanySnapshot (migration 195) for the definitions.
    ///
    /// Null means "not measured for this company type", and the card renders it
    /// as a dash. Zero means measured and genuinely nothing, which reads very
    /// differently to whoever is looking at the card.
    /// </summary>
    public class CompanySnapshotModel
    {
        public string FarmId { get; set; } = string.Empty;
        public string CompanyType { get; set; } = string.Empty;
        public decimal? Metric1 { get; set; }
        public decimal? Metric2 { get; set; }
        public decimal? Metric3 { get; set; }
        public decimal? Metric4 { get; set; }
    }
}
