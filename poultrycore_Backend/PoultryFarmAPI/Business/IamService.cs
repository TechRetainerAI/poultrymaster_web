using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;
using System.Data;

namespace PoultryFarmAPIWeb.Business
{
    public interface IIamService
    {
        Task<List<IamPermissionModel>> GetCatalogAsync();
        Task<IamEffectivePermissionsModel> GetEffectivePermissionsAsync(string userId, string? farmId);
        /// <summary>Fast path for enforcement: does this user hold this key in this company?</summary>
        Task<bool> HasPermissionAsync(string userId, string? farmId, string permissionKey);
        /// <summary>
        /// "poultry" | "water" | "generic" for a farm, or null if unknown. Used to
        /// resolve the shared controllers' module at request time.
        /// </summary>
        Task<string?> GetModuleForFarmAsync(string? farmId);
        Task<List<IamRoleModel>> GetRolesAsync(string? ownerUserId);
        Task<List<string>> GetRolePermissionsAsync(int roleId);
        Task<List<IamUserRoleModel>> GetUserRolesAsync(string userId, string? farmId);

        // ---- Writes (migration 201) --------------------------------------
        Task<int> SaveRoleAsync(IamRoleSaveRequest request, string callerUserId);
        Task DeleteRoleAsync(int roleId, string callerUserId);
        Task<int> SetRolePermissionsAsync(int roleId, string callerUserId, IEnumerable<string> permissionKeys);
        Task AssignUserRoleAsync(IamAssignRoleRequest request, string assignedBy);
        Task RevokeUserRoleAsync(int id);
        Task SetUserPermissionAsync(IamOverrideRequest request, string grantedBy);
        Task ClearUserPermissionAsync(int id);
        Task<List<IamOverrideModel>> GetUserOverridesAsync(string userId, string? farmId);

        // ---- Phase 4: governance (migration 203) -------------------------
        Task TouchSessionAsync(string sessionId, string userId, string? farmId, string? ip, string? userAgent, string? device);
        Task<List<IamSessionModel>> GetSessionsAsync(string userId, bool includeRevoked);
        Task RevokeSessionAsync(string sessionId, string? revokedBy);
        Task RevokeAllSessionsAsync(string userId, string? revokedBy);
        /// <summary>Tokens issued before this instant are no longer accepted. Null = never revoked.</summary>
        Task<DateTime?> GetTokensValidFromAsync(string userId);
        Task<IamPolicyModel?> GetPolicyAsync(string callerUserId);
        Task SetPolicyAsync(string callerUserId, IamPolicyModel policy);
        Task<List<IamAccessAuditModel>> GetAccessAuditAsync(string callerUserId, string? subjectId, int days);
        Task<List<IamAccessReviewRow>> GetAccessReviewAsync(string callerUserId);
        Task RecordAccessReviewAsync(IamAccessReviewRequest request, string? reviewedBy);
    }

    /// <summary>
    /// Read side of Identity &amp; Access Management (migration 199).
    ///
    /// Phase 0 is read-only on purpose: the tables exist and can be queried, but
    /// nothing writes to them yet and nothing enforces them. Role management
    /// lands in phase 2, enforcement in phase 3 via RequirePermissionAttribute.
    /// </summary>
    public class IamService : IIamService
    {
        private readonly string _connectionString;

        public IamService(string connectionString)
        {
            _connectionString = connectionString;
        }

        /// <summary>
        /// Read a column that a newer migration added, tolerating a database that
        /// has not had it applied yet.
        /// </summary>
        private static int? ReadOptionalInt32(NpgsqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? (int?)null : reader.GetInt32(i);
            }
            return null;
        }

        private static string? ReadOptionalString(NpgsqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? null : reader.GetString(i);
            }
            return null;
        }

        private static object DbNullable(string? value) =>
            string.IsNullOrWhiteSpace(value) ? DBNull.Value : value.Trim();

        public async Task<List<IamPermissionModel>> GetCatalogAsync()
        {
            var results = new List<IamPermissionModel>();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_getcatalog()", conn);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                results.Add(new IamPermissionModel
                {
                    PermissionKey = reader.GetString(reader.GetOrdinal("PermissionKey")),
                    Module = reader.GetString(reader.GetOrdinal("Module")),
                    Resource = reader.GetString(reader.GetOrdinal("Resource")),
                    Action = reader.GetString(reader.GetOrdinal("Action")),
                    PermissionGroup = reader.GetString(reader.GetOrdinal("PermissionGroup")),
                    ResourceLabel = reader.GetString(reader.GetOrdinal("ResourceLabel")),
                    Description = reader.IsDBNull(reader.GetOrdinal("Description"))
                        ? null : reader.GetString(reader.GetOrdinal("Description")),
                    CompanyType = reader.IsDBNull(reader.GetOrdinal("CompanyType"))
                        ? null : reader.GetString(reader.GetOrdinal("CompanyType")),
                    IsDangerous = reader.GetBoolean(reader.GetOrdinal("IsDangerous")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                });
            }

            return results;
        }

        public async Task<IamEffectivePermissionsModel> GetEffectivePermissionsAsync(string userId, string? farmId)
        {
            var model = new IamEffectivePermissionsModel { UserId = userId, FarmId = farmId };

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_geteffectivepermissions(p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", (object?)farmId ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                model.Grants.Add(new IamGrantModel
                {
                    PermissionKey = reader.GetString(reader.GetOrdinal("PermissionKey")),
                    Source = reader.IsDBNull(reader.GetOrdinal("Source"))
                        ? string.Empty : reader.GetString(reader.GetOrdinal("Source")),
                });
            }

            return model;
        }

        public async Task<List<IamRoleModel>> GetRolesAsync(string? ownerUserId)
        {
            var results = new List<IamRoleModel>();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_getroles(p_owneruserid => @OwnerUserId::text)", conn);
            cmd.Parameters.AddWithValue("@OwnerUserId", (object?)ownerUserId ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                results.Add(new IamRoleModel
                {
                    RoleId = reader.GetInt32(reader.GetOrdinal("RoleId")),
                    RoleKey = reader.IsDBNull(reader.GetOrdinal("RoleKey"))
                        ? null : reader.GetString(reader.GetOrdinal("RoleKey")),
                    Name = reader.GetString(reader.GetOrdinal("Name")),
                    Description = reader.IsDBNull(reader.GetOrdinal("Description"))
                        ? null : reader.GetString(reader.GetOrdinal("Description")),
                    CompanyType = reader.IsDBNull(reader.GetOrdinal("CompanyType"))
                        ? null : reader.GetString(reader.GetOrdinal("CompanyType")),
                    IsSystem = reader.GetBoolean(reader.GetOrdinal("IsSystem")),
                    IsSuperuser = reader.GetBoolean(reader.GetOrdinal("IsSuperuser")),
                    IsActive = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    PermissionCount = reader.GetInt32(reader.GetOrdinal("PermissionCount")),
                    // Added by migration 201; a database still on 200 simply
                    // reports zero rather than failing the whole roles call.
                    AssignedUserCount = ReadOptionalInt32(reader, "AssignedUserCount") ?? 0,
                });
            }

            return results;
        }

        public async Task<List<string>> GetRolePermissionsAsync(int roleId)
        {
            var keys = new List<string>();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_getrolepermissions(p_roleid => @RoleId::int)", conn);
            cmd.Parameters.AddWithValue("@RoleId", roleId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) keys.Add(reader.GetString(0));

            return keys;
        }

        public async Task<List<IamUserRoleModel>> GetUserRolesAsync(string userId, string? farmId)
        {
            var results = new List<IamUserRoleModel>();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_getuserroles(p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", (object?)farmId ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                results.Add(new IamUserRoleModel
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    RoleId = reader.GetInt32(reader.GetOrdinal("RoleId")),
                    RoleKey = reader.IsDBNull(reader.GetOrdinal("RoleKey"))
                        ? null : reader.GetString(reader.GetOrdinal("RoleKey")),
                    Name = reader.GetString(reader.GetOrdinal("Name")),
                    Description = reader.IsDBNull(reader.GetOrdinal("Description"))
                        ? null : reader.GetString(reader.GetOrdinal("Description")),
                    IsSystem = reader.GetBoolean(reader.GetOrdinal("IsSystem")),
                    IsSuperuser = reader.GetBoolean(reader.GetOrdinal("IsSuperuser")),
                    FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId"))
                        ? null : reader.GetString(reader.GetOrdinal("FarmId")),
                    IsOrgWide = reader.GetBoolean(reader.GetOrdinal("IsOrgWide")),
                    AssignedBy = reader.IsDBNull(reader.GetOrdinal("AssignedBy"))
                        ? null : reader.GetString(reader.GetOrdinal("AssignedBy")),
                    AssignedAt = reader.GetDateTime(reader.GetOrdinal("AssignedAt")),
                    ExpiresAt = reader.IsDBNull(reader.GetOrdinal("ExpiresAt"))
                        ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("ExpiresAt")),
                });
            }

            return results;
        }

        // The service is registered scoped, so these caches live for one request.
        // Enforcement asks for the same user's permissions on every call, and the
        // permission check itself runs on every request once phase 3 is on —
        // without this a single request would re-query the same set repeatedly.
        private readonly Dictionary<string, HashSet<string>> _effectiveCache = new();
        private readonly Dictionary<string, string?> _moduleCache = new();

        public async Task<bool> HasPermissionAsync(string userId, string? farmId, string permissionKey)
        {
            if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(permissionKey))
                return false;

            var cacheKey = $"{userId}|{farmId ?? string.Empty}";
            if (!_effectiveCache.TryGetValue(cacheKey, out var keys))
            {
                var effective = await GetEffectivePermissionsAsync(userId, farmId);
                keys = effective.Grants
                    .Select(g => g.PermissionKey)
                    .ToHashSet(StringComparer.OrdinalIgnoreCase);
                _effectiveCache[cacheKey] = keys;
            }

            return keys.Contains(permissionKey);
        }

        public async Task<string?> GetModuleForFarmAsync(string? farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return null;
            if (_moduleCache.TryGetValue(farmId, out var cached)) return cached;

            string? module = null;
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                // Farms.Id is the real primary key; FarmId is vestigial but still
                // carried on some rows, so both are matched (see CLAUDE.md).
                using var cmd = new NpgsqlCommand(
                    "SELECT f.type FROM farms f WHERE f.id = @FarmId OR f.farmid = @FarmId LIMIT 1", conn);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                module = result?.ToString()?.Trim().ToLowerInvariant() switch
                {
                    "poultry" => "poultry",
                    "water" => "water",
                    "generic" => "generic",
                    _ => null,
                };
            }
            catch (PostgresException)
            {
                // Fail soft: an unresolvable module produces an unmapped route,
                // which the enforcement filter reports rather than denying unless
                // it has been explicitly told to.
                module = null;
            }

            _moduleCache[farmId] = module;
            return module;
        }

        // ---- Writes (migration 201) ------------------------------------------
        //
        // The procs enforce the rules (built-ins are immutable, roles belong to
        // one organization, a role in use cannot be deleted) and RAISERROR when
        // they are broken. The controller turns those into 400s carrying the
        // message, so the reason reaches the admin instead of a generic failure.

        public async Task<int> SaveRoleAsync(IamRoleSaveRequest request, string callerUserId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_role_save(p_roleid => @RoleId::int, p_calleruserid => @CallerUserId::text, p_name => @Name::text, p_description => @Description::text, p_companytype => @CompanyType::text, p_copyfromroleid => @CopyFromRoleId::int)", conn);
            cmd.Parameters.AddWithValue("@RoleId", (object?)request.RoleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CallerUserId", callerUserId);
            cmd.Parameters.AddWithValue("@Name", request.Name ?? string.Empty);
            cmd.Parameters.AddWithValue("@Description", DbNullable(request.Description));
            cmd.Parameters.AddWithValue("@CompanyType", DbNullable(request.CompanyType));
            cmd.Parameters.AddWithValue("@CopyFromRoleId", (object?)request.CopyFromRoleId ?? DBNull.Value);

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result is null or DBNull ? 0 : Convert.ToInt32(result);
        }

        public async Task DeleteRoleAsync(int roleId, string callerUserId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_role_delete(p_roleid => @RoleId::int, p_calleruserid => @CallerUserId::text)", conn);
            cmd.Parameters.AddWithValue("@RoleId", roleId);
            cmd.Parameters.AddWithValue("@CallerUserId", callerUserId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> SetRolePermissionsAsync(int roleId, string callerUserId, IEnumerable<string> permissionKeys)
        {
            var csv = string.Join(",", permissionKeys
                .Where(k => !string.IsNullOrWhiteSpace(k))
                .Select(k => k.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase));

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_rolepermissions_set(p_roleid => @RoleId::int, p_calleruserid => @CallerUserId::text, p_permissionkeys => @PermissionKeys::text)", conn);
            cmd.Parameters.AddWithValue("@RoleId", roleId);
            cmd.Parameters.AddWithValue("@CallerUserId", callerUserId);
            cmd.Parameters.Add("@PermissionKeys", NpgsqlDbType.Text, -1).Value = csv;

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result is null or DBNull ? 0 : Convert.ToInt32(result);
        }

        public async Task AssignUserRoleAsync(IamAssignRoleRequest request, string assignedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_userrole_assign(p_userid => @UserId::text, p_roleid => @RoleId::int, p_farmid => @FarmId::text, p_assignedby => @AssignedBy::text, p_expiresat => @ExpiresAt::timestamp)", conn);
            cmd.Parameters.AddWithValue("@UserId", request.UserId);
            cmd.Parameters.AddWithValue("@RoleId", request.RoleId);
            cmd.Parameters.AddWithValue("@FarmId", DbNullable(request.FarmId));
            cmd.Parameters.AddWithValue("@AssignedBy", DbNullable(assignedBy));
            cmd.Parameters.AddWithValue("@ExpiresAt", (object?)request.ExpiresAt ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RevokeUserRoleAsync(int id)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_userrole_revoke(p_id => @Id::int)", conn);
            cmd.Parameters.AddWithValue("@Id", id);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task SetUserPermissionAsync(IamOverrideRequest request, string grantedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_userpermission_set(p_userid => @UserId::text, p_farmid => @FarmId::text, p_permissionkey => @PermissionKey::text, p_effect => @Effect::text, p_reason => @Reason::text, p_grantedby => @GrantedBy::text, p_expiresat => @ExpiresAt::timestamp)", conn);
            cmd.Parameters.AddWithValue("@UserId", request.UserId);
            cmd.Parameters.AddWithValue("@FarmId", DbNullable(request.FarmId));
            cmd.Parameters.AddWithValue("@PermissionKey", request.PermissionKey ?? string.Empty);
            cmd.Parameters.AddWithValue("@Effect", request.Effect ?? string.Empty);
            cmd.Parameters.AddWithValue("@Reason", request.Reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@GrantedBy", DbNullable(grantedBy));
            cmd.Parameters.AddWithValue("@ExpiresAt", (object?)request.ExpiresAt ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ClearUserPermissionAsync(int id)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_userpermission_clear(p_id => @Id::int)", conn);
            cmd.Parameters.AddWithValue("@Id", id);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ---- Phase 4: governance (migration 203) -----------------------------

        public async Task TouchSessionAsync(string sessionId, string userId, string? farmId, string? ip, string? userAgent, string? device)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_session_touch(p_sessionid => @SessionId::text, p_userid => @UserId::text, p_farmid => @FarmId::text, p_ipaddress => @IpAddress::text, p_useragent => @UserAgent::text, p_device => @Device::text)", conn);
            cmd.Parameters.AddWithValue("@SessionId", sessionId);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", DbNullable(farmId));
            cmd.Parameters.AddWithValue("@IpAddress", DbNullable(ip));
            cmd.Parameters.AddWithValue("@UserAgent", DbNullable(userAgent));
            cmd.Parameters.AddWithValue("@Device", DbNullable(device));

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<IamSessionModel>> GetSessionsAsync(string userId, bool includeRevoked)
        {
            var results = new List<IamSessionModel>();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_sessions_get(p_userid => @UserId::text, p_includerevoked => @IncludeRevoked::boolean)", conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@IncludeRevoked", includeRevoked);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                results.Add(new IamSessionModel
                {
                    SessionId = reader.GetString(reader.GetOrdinal("SessionId")),
                    UserId = reader.GetString(reader.GetOrdinal("UserId")),
                    FarmId = ReadOptionalString(reader, "FarmId"),
                    IpAddress = ReadOptionalString(reader, "IpAddress"),
                    UserAgent = ReadOptionalString(reader, "UserAgent"),
                    Device = ReadOptionalString(reader, "Device"),
                    CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    LastSeenAt = reader.GetDateTime(reader.GetOrdinal("LastSeenAt")),
                    RevokedAt = reader.IsDBNull(reader.GetOrdinal("RevokedAt"))
                        ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("RevokedAt")),
                    RevokedBy = ReadOptionalString(reader, "RevokedBy"),
                    IsActive = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                });
            }

            return results;
        }

        public async Task RevokeSessionAsync(string sessionId, string? revokedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_session_revoke(p_sessionid => @SessionId::text, p_revokedby => @RevokedBy::text)", conn);
            cmd.Parameters.AddWithValue("@SessionId", sessionId);
            cmd.Parameters.AddWithValue("@RevokedBy", DbNullable(revokedBy));

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RevokeAllSessionsAsync(string userId, string? revokedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_revokeallsessions(p_userid => @UserId::text, p_revokedby => @RevokedBy::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@RevokedBy", DbNullable(revokedBy));

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<DateTime?> GetTokensValidFromAsync(string userId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return null;

            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spiam_gettokensvalidfrom(p_userid => @UserId::text)", conn);
                cmd.Parameters.AddWithValue("@UserId", userId);

                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                return result is null or DBNull ? null : Convert.ToDateTime(result);
            }
            catch (PostgresException)
            {
                // Migration 203 not applied. Treat as "never revoked" rather than
                // failing shut, which would sign everyone out.
                return null;
            }
        }

        public async Task<IamPolicyModel?> GetPolicyAsync(string callerUserId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_policy_get(p_calleruserid => @CallerUserId::text)", conn);
            cmd.Parameters.AddWithValue("@CallerUserId", callerUserId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return null;

            return new IamPolicyModel
            {
                OwnerUserId = reader.GetString(reader.GetOrdinal("OwnerUserId")),
                PasswordMinLength = reader.GetInt32(reader.GetOrdinal("PasswordMinLength")),
                PasswordRequireUpper = reader.GetBoolean(reader.GetOrdinal("PasswordRequireUpper")),
                PasswordRequireDigit = reader.GetBoolean(reader.GetOrdinal("PasswordRequireDigit")),
                PasswordRequireSymbol = reader.GetBoolean(reader.GetOrdinal("PasswordRequireSymbol")),
                PasswordExpiryDays = reader.GetInt32(reader.GetOrdinal("PasswordExpiryDays")),
                SessionIdleMinutes = reader.GetInt32(reader.GetOrdinal("SessionIdleMinutes")),
                SessionMaxHours = reader.GetInt32(reader.GetOrdinal("SessionMaxHours")),
                RequireMfaForAdmins = reader.GetBoolean(reader.GetOrdinal("RequireMfaForAdmins")),
                DormantAfterDays = reader.GetInt32(reader.GetOrdinal("DormantAfterDays")),
                AccessReviewDays = reader.GetInt32(reader.GetOrdinal("AccessReviewDays")),
                UpdatedAt = reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                UpdatedBy = ReadOptionalString(reader, "UpdatedBy"),
            };
        }

        public async Task SetPolicyAsync(string callerUserId, IamPolicyModel p)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_policy_set(p_calleruserid => @CallerUserId::text, p_passwordminlength => @PasswordMinLength::int, p_passwordrequireupper => @PasswordRequireUpper::boolean, p_passwordrequiredigit => @PasswordRequireDigit::boolean, p_passwordrequiresymbol => @PasswordRequireSymbol::boolean, p_passwordexpirydays => @PasswordExpiryDays::int, p_sessionidleminutes => @SessionIdleMinutes::int, p_sessionmaxhours => @SessionMaxHours::int, p_requiremfaforadmins => @RequireMfaForAdmins::boolean, p_dormantafterdays => @DormantAfterDays::int, p_accessreviewdays => @AccessReviewDays::int)", conn);
            cmd.Parameters.AddWithValue("@CallerUserId", callerUserId);
            cmd.Parameters.AddWithValue("@PasswordMinLength", p.PasswordMinLength);
            cmd.Parameters.AddWithValue("@PasswordRequireUpper", p.PasswordRequireUpper);
            cmd.Parameters.AddWithValue("@PasswordRequireDigit", p.PasswordRequireDigit);
            cmd.Parameters.AddWithValue("@PasswordRequireSymbol", p.PasswordRequireSymbol);
            cmd.Parameters.AddWithValue("@PasswordExpiryDays", p.PasswordExpiryDays);
            cmd.Parameters.AddWithValue("@SessionIdleMinutes", p.SessionIdleMinutes);
            cmd.Parameters.AddWithValue("@SessionMaxHours", p.SessionMaxHours);
            cmd.Parameters.AddWithValue("@RequireMfaForAdmins", p.RequireMfaForAdmins);
            cmd.Parameters.AddWithValue("@DormantAfterDays", p.DormantAfterDays);
            cmd.Parameters.AddWithValue("@AccessReviewDays", p.AccessReviewDays);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<IamAccessAuditModel>> GetAccessAuditAsync(string callerUserId, string? subjectId, int days)
        {
            var results = new List<IamAccessAuditModel>();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_getaccessaudit(p_calleruserid => @CallerUserId::text, p_subjectid => @SubjectId::text, p_days => @Days::int)", conn);
            cmd.Parameters.AddWithValue("@CallerUserId", callerUserId);
            cmd.Parameters.AddWithValue("@SubjectId", DbNullable(subjectId));
            cmd.Parameters.AddWithValue("@Days", days);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                results.Add(new IamAccessAuditModel
                {
                    Id = reader.GetInt64(reader.GetOrdinal("Id")),
                    OccurredAt = reader.GetDateTime(reader.GetOrdinal("OccurredAt")),
                    Entity = reader.GetString(reader.GetOrdinal("Entity")),
                    Operation = reader.GetString(reader.GetOrdinal("Operation")),
                    SubjectId = ReadOptionalString(reader, "SubjectId"),
                    ActorId = ReadOptionalString(reader, "ActorId"),
                    FarmId = ReadOptionalString(reader, "FarmId"),
                    Detail = ReadOptionalString(reader, "Detail"),
                    SubjectName = ReadOptionalString(reader, "SubjectName"),
                    ActorName = ReadOptionalString(reader, "ActorName"),
                });
            }

            return results;
        }

        public async Task<List<IamAccessReviewRow>> GetAccessReviewAsync(string callerUserId)
        {
            var results = new List<IamAccessReviewRow>();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_getaccessreview(p_calleruserid => @CallerUserId::text)", conn);
            cmd.Parameters.AddWithValue("@CallerUserId", callerUserId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                results.Add(new IamAccessReviewRow
                {
                    UserId = reader.GetString(reader.GetOrdinal("UserId")),
                    FirstName = ReadOptionalString(reader, "FirstName"),
                    LastName = ReadOptionalString(reader, "LastName"),
                    Email = ReadOptionalString(reader, "Email"),
                    UserName = ReadOptionalString(reader, "UserName"),
                    IsStaff = reader.GetBoolean(reader.GetOrdinal("IsStaff")),
                    RoleCount = reader.GetInt32(reader.GetOrdinal("RoleCount")),
                    OverrideCount = reader.GetInt32(reader.GetOrdinal("OverrideCount")),
                    LastSeenAt = reader.IsDBNull(reader.GetOrdinal("LastSeenAt"))
                        ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("LastSeenAt")),
                    LastReviewedAt = reader.IsDBNull(reader.GetOrdinal("LastReviewedAt"))
                        ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("LastReviewedAt")),
                    LastDecision = ReadOptionalString(reader, "LastDecision"),
                    IsDormant = reader.GetBoolean(reader.GetOrdinal("IsDormant")),
                    ReviewIsStale = reader.GetBoolean(reader.GetOrdinal("ReviewIsStale")),
                });
            }

            return results;
        }

        public async Task RecordAccessReviewAsync(IamAccessReviewRequest request, string? reviewedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_accessreview_record(p_userid => @UserId::text, p_farmid => @FarmId::text, p_decision => @Decision::text, p_note => @Note::text, p_reviewedby => @ReviewedBy::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", request.UserId);
            cmd.Parameters.AddWithValue("@FarmId", DbNullable(request.FarmId));
            cmd.Parameters.AddWithValue("@Decision", request.Decision ?? string.Empty);
            cmd.Parameters.AddWithValue("@Note", DbNullable(request.Note));
            cmd.Parameters.AddWithValue("@ReviewedBy", DbNullable(reviewedBy));

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<IamOverrideModel>> GetUserOverridesAsync(string userId, string? farmId)
        {
            var results = new List<IamOverrideModel>();

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spiam_getuseroverrides(p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", DbNullable(farmId));

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                results.Add(new IamOverrideModel
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    PermissionKey = reader.GetString(reader.GetOrdinal("PermissionKey")),
                    Effect = reader.GetString(reader.GetOrdinal("Effect")),
                    Reason = reader.IsDBNull(reader.GetOrdinal("Reason"))
                        ? null : reader.GetString(reader.GetOrdinal("Reason")),
                    GrantedBy = reader.IsDBNull(reader.GetOrdinal("GrantedBy"))
                        ? null : reader.GetString(reader.GetOrdinal("GrantedBy")),
                    GrantedAt = reader.GetDateTime(reader.GetOrdinal("GrantedAt")),
                    ExpiresAt = reader.IsDBNull(reader.GetOrdinal("ExpiresAt"))
                        ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("ExpiresAt")),
                    FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId"))
                        ? null : reader.GetString(reader.GetOrdinal("FarmId")),
                    IsOrgWide = reader.GetBoolean(reader.GetOrdinal("IsOrgWide")),
                    HasExpired = reader.GetBoolean(reader.GetOrdinal("HasExpired")),
                    ResourceLabel = reader.GetString(reader.GetOrdinal("ResourceLabel")),
                    Action = reader.GetString(reader.GetOrdinal("Action")),
                    Module = reader.GetString(reader.GetOrdinal("Module")),
                    PermissionGroup = reader.GetString(reader.GetOrdinal("PermissionGroup")),
                });
            }

            return results;
        }
    }
}
