// User Quick Links (migration 318).
//
// What one user wants in their own Quick Links bar, for one company. These are
// PREFERENCES ABOUT WHAT IS SHOWN and nothing else -- the rail still runs every
// financial row through its own permission gate when it renders, so an href
// stored here grants no access it did not already have.
//
// `Customised` is the field that matters. An empty Hrefs list means two
// different things depending on it: never chosen (fall back to the page's
// defaults) or deliberately cleared (show nothing). Collapsing the two is the
// bug this whole feature would otherwise ship with.

namespace PoultryFarmAPIWeb.Models
{
    public class UserQuickLinksModel
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;

        /// <summary>
        /// False when this user has never customised the bar for this company.
        /// The caller shows its own defaults; it must not treat an empty list
        /// as a choice.
        /// </summary>
        public bool Customised { get; set; }

        /// <summary>The chosen hrefs, in the order they are to be shown.</summary>
        public List<string> Hrefs { get; set; } = new();

        public DateTime? UpdatedAt { get; set; }
    }

    /// <summary>
    /// Replace-all. The dialog sends the whole bar as the user left it, so
    /// there is no add/remove pair that can get out of step and no
    /// half-applied save.
    /// </summary>
    public class UserQuickLinksSaveRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public List<string> Hrefs { get; set; } = new();
    }
}
