using System.Security.Claims;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Field- and row-level permission checks for responses that mix data from
    /// several pages — dashboards, combined ledgers, reports.
    ///
    /// <para>
    /// The enforcement filter decides whether a request may run at all. Some
    /// endpoints are rightly open to every member (the dashboard) but carry
    /// figures only some members may see (sales, profit, cash). Those
    /// endpoints ask this guard and blank the restricted part instead of
    /// refusing the whole response, so a storekeeper still sees today's egg
    /// count without seeing revenue.
    /// </para>
    ///
    /// <para>
    /// Follows <c>Iam:Enforced</c> exactly like the filter: in shadow mode it
    /// answers "allowed" and logs what it would have hidden, so switching
    /// enforcement on is still one setting.
    /// </para>
    ///
    /// <para>
    /// Future views that join records from several pages (the planned
    /// Transaction Impact Explorer, combined exports) must filter through
    /// <see cref="FilterRowsAsync{T}"/> so a drill-down can never show what the
    /// page itself would not.
    /// </para>
    /// </summary>
    public interface IIamDataGuard
    {
        /// <summary>May the current caller see data covered by <paramref name="permissionKey"/> in this company?</summary>
        Task<bool> AllowsAsync(ClaimsPrincipal user, string? farmId, string permissionKey);

        /// <summary>
        /// Keep only the rows whose permission key (from <paramref name="keyOf"/>)
        /// the caller holds. A row with no key is kept.
        /// </summary>
        Task<List<T>> FilterRowsAsync<T>(ClaimsPrincipal user, string? farmId, IEnumerable<T> rows, Func<T, string?> keyOf);
    }

    public class IamDataGuard : IIamDataGuard
    {
        private readonly IIamService _iam;
        private readonly ILogger<IamDataGuard> _logger;
        private readonly bool _enforced;

        public IamDataGuard(IIamService iam, ILogger<IamDataGuard> logger, IConfiguration config)
        {
            _iam = iam;
            _logger = logger;
            _enforced = config.GetValue("Iam:Enforced", false);
        }

        public async Task<bool> AllowsAsync(ClaimsPrincipal user, string? farmId, string permissionKey)
        {
            var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(userId)) return !_enforced;

            var scope = string.IsNullOrWhiteSpace(farmId) ? user.FindFirst("FarmId")?.Value : farmId;
            if (await _iam.HasPermissionAsync(userId, scope, permissionKey)) return true;

            if (_enforced) return false;
            _logger.LogInformation("IAM SHADOW would hide {Key} data from {User} in {Farm}", permissionKey, userId, scope);
            return true;
        }

        public async Task<List<T>> FilterRowsAsync<T>(ClaimsPrincipal user, string? farmId, IEnumerable<T> rows, Func<T, string?> keyOf)
        {
            var decided = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            var kept = new List<T>();
            foreach (var row in rows)
            {
                var key = keyOf(row);
                if (string.IsNullOrWhiteSpace(key)) { kept.Add(row); continue; }
                if (!decided.TryGetValue(key, out var ok))
                {
                    ok = await AllowsAsync(user, farmId, key);
                    decided[key] = ok;
                }
                if (ok) kept.Add(row);
            }
            return kept;
        }
    }
}
