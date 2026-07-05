using System.Text.RegularExpressions;

namespace User.Management.Service.Helpers
{
    // Prompt 3 — Organization Code rules, shared by signup + the availability
    // endpoint so validation never drifts between them.
    public static class OrgCode
    {
        public static readonly HashSet<string> Reserved = new(StringComparer.OrdinalIgnoreCase)
        {
            "ADMIN","SUPPORT","SYSTEM","TEST","DEMO","ROOT","API","LOGIN","NULL",
            "VISIBILITYCORE","POULTRYMASTER","BUSINESSOFFICE","ORG","ORGANIZATION"
        };

        public static string Normalize(string? code) => (code ?? string.Empty).Trim().ToUpperInvariant();

        // Returns null when valid, else a user-facing reason.
        public static string? Validate(string code)
        {
            if (string.IsNullOrWhiteSpace(code)) return "Organization Code is required.";
            if (code.Length < 4 || code.Length > 30) return "Organization Code must be 4–30 characters.";
            if (!Regex.IsMatch(code, "^[A-Z0-9_-]+$")) return "Use letters, numbers, hyphen or underscore only (no spaces).";
            if (Reserved.Contains(code)) return "That Organization Code is reserved. Please choose another.";
            return null;
        }

        // A few deterministic suggestions when a code is taken/invalid.
        public static List<string> Suggestions(string baseCode)
        {
            var b = Normalize(baseCode);
            if (b.Length < 3) b = "ORG" + b;
            if (b.Length > 26) b = b.Substring(0, 26);
            return new List<string> { b + "1", b + "GH", b + "2026", b + "-01" };
        }
    }
}
