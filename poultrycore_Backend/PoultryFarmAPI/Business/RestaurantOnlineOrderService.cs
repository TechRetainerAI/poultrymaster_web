using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantOnlineOrderService : IRestaurantOnlineOrderService
    {
        private readonly string _cs;
        public RestaurantOnlineOrderService(string cs) => _cs = cs;

        // =====================================================================
        // SETTINGS
        // =====================================================================

        public async Task<RestaurantOnlineOrderingSettingsModel?> GetSettingsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_onlinesettings_get(p_farmid => @F::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new()
            {
                OnlineOrderingSettingId = r.GetInt32(r.GetOrdinal("onlineorderingsettingid")),
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                IsEnabled = r.GetBoolean(r.GetOrdinal("isenabled")),
                AllowDineInQr = r.GetBoolean(r.GetOrdinal("allowdineinqr")),
                AllowTakeaway = r.GetBoolean(r.GetOrdinal("allowtakeaway")),
                AllowDelivery = r.GetBoolean(r.GetOrdinal("allowdelivery")),
                MinOrderAmount = r.GetDecimal(r.GetOrdinal("minorderamount")),
                MaxOrdersPerSlot = r.GetInt32(r.GetOrdinal("maxordersperslot")),
                SlotDurationMins = r.GetInt32(r.GetOrdinal("slotdurationmins")),
                EstimatedPrepMinsDine = r.GetInt32(r.GetOrdinal("estimatedprepminsdine")),
                EstimatedPrepMinsTake = r.GetInt32(r.GetOrdinal("estimatedprepminstake")),
                EstimatedPrepminsDeliv = r.GetInt32(r.GetOrdinal("estimatedprepminsdeliv")),
                DeliveryFeeType = r.GetString(r.GetOrdinal("deliveryfeetype")),
                DeliveryFeeAmount = r.GetDecimal(r.GetOrdinal("deliveryfeeamount")),
                FreeDeliveryAbove = r.IsDBNull(r.GetOrdinal("freedeliveryabove")) ? null : r.GetDecimal(r.GetOrdinal("freedeliveryabove")),
                MaxDeliveryDistanceKm = r.GetDecimal(r.GetOrdinal("maxdeliverydistancekm")),
                AcceptingOrders = r.GetBoolean(r.GetOrdinal("acceptingorders")),
                PausedReason = r.IsDBNull(r.GetOrdinal("pausedreason")) ? null : r.GetString(r.GetOrdinal("pausedreason")),
                WelcomeMessage = r.IsDBNull(r.GetOrdinal("welcomemessage")) ? null : r.GetString(r.GetOrdinal("welcomemessage")),
                TermsAndConditions = r.IsDBNull(r.GetOrdinal("termsandconditions")) ? null : r.GetString(r.GetOrdinal("termsandconditions")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            };
        }

        public async Task UpsertSettingsAsync(RestaurantOnlineOrderingSettingsModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "INSERT INTO restaurantonlineorderingsettings (farmid, isenabled, allowdineinqr, allowtakeaway, allowdelivery, " +
                "minorderamount, maxordersperslot, slotdurationmins, estimatedprepminsdine, estimatedprepminstake, estimatedprepminsdeliv, " +
                "deliveryfeetype, deliveryfeeamount, freedeliveryabove, maxdeliverydistancekm, acceptingorders, pausedreason, " +
                "welcomemessage, termsandconditions) VALUES (@FarmId, @Enabled, @DineInQr, @Takeaway, @Delivery, " +
                "@MinOrder, @MaxSlot, @SlotDur, @PrepDine, @PrepTake, @PrepDeliv, " +
                "@FeeType, @FeeAmt, @FreeAbove, @MaxDist, @Accepting, @Paused, " +
                "@Welcome, @Terms) " +
                "ON CONFLICT (farmid) DO UPDATE SET isenabled=@Enabled, allowdineinqr=@DineInQr, " +
                "allowtakeaway=@Takeaway, allowdelivery=@Delivery, minorderamount=@MinOrder, " +
                "maxordersperslot=@MaxSlot, slotdurationmins=@SlotDur, estimatedprepminsdine=@PrepDine, " +
                "estimatedprepminstake=@PrepTake, estimatedprepminsdeliv=@PrepDeliv, " +
                "deliveryfeetype=@FeeType, deliveryfeeamount=@FeeAmt, freedeliveryabove=@FreeAbove, " +
                "maxdeliverydistancekm=@MaxDist, acceptingorders=@Accepting, pausedreason=@Paused, " +
                "welcomemessage=@Welcome, termsandconditions=@Terms, updatedat=NOW()", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Enabled", m.IsEnabled);
            cmd.Parameters.AddWithValue("@DineInQr", m.AllowDineInQr);
            cmd.Parameters.AddWithValue("@Takeaway", m.AllowTakeaway);
            cmd.Parameters.AddWithValue("@Delivery", m.AllowDelivery);
            cmd.Parameters.AddWithValue("@MinOrder", m.MinOrderAmount);
            cmd.Parameters.AddWithValue("@MaxSlot", m.MaxOrdersPerSlot);
            cmd.Parameters.AddWithValue("@SlotDur", m.SlotDurationMins);
            cmd.Parameters.AddWithValue("@PrepDine", m.EstimatedPrepMinsDine);
            cmd.Parameters.AddWithValue("@PrepTake", m.EstimatedPrepMinsTake);
            cmd.Parameters.AddWithValue("@PrepDeliv", m.EstimatedPrepminsDeliv);
            cmd.Parameters.AddWithValue("@FeeType", m.DeliveryFeeType);
            cmd.Parameters.AddWithValue("@FeeAmt", m.DeliveryFeeAmount);
            cmd.Parameters.AddWithValue("@FreeAbove", (object?)m.FreeDeliveryAbove ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MaxDist", m.MaxDeliveryDistanceKm);
            cmd.Parameters.AddWithValue("@Accepting", m.AcceptingOrders);
            cmd.Parameters.AddWithValue("@Paused", (object?)m.PausedReason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Welcome", (object?)m.WelcomeMessage ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Terms", (object?)m.TermsAndConditions ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ToggleAcceptingOrdersAsync(string farmId, bool accepting, string? reason)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_onlinesettings_toggle(p_farmid=>@F::text,p_accepting=>@A::boolean,p_reason=>@R::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            cmd.Parameters.AddWithValue("@A", accepting);
            cmd.Parameters.AddWithValue("@R", (object?)reason ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // QR CODES
        // =====================================================================

        public async Task<List<RestaurantQrCodeModel>> ListQrCodesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_qrcode_list(p_farmid=>@F::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantQrCodeModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                QrCodeId = r.GetInt32(r.GetOrdinal("qrcodeid")),
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                TableId = r.IsDBNull(r.GetOrdinal("tableid")) ? null : r.GetInt32(r.GetOrdinal("tableid")),
                TableNumber = r.GetString(r.GetOrdinal("tablenumber")),
                QrToken = r.GetString(r.GetOrdinal("qrtoken")),
                IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                ScanCount = r.GetInt32(r.GetOrdinal("scanccount")),
                LastScannedAt = r.IsDBNull(r.GetOrdinal("lastscanndat")) ? null : r.GetDateTime(r.GetOrdinal("lastscanndat")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
            });
            return list;
        }

        public async Task<(int id, string token)> GenerateQrCodeAsync(string farmId, int tableId, string tableNumber)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_qrcode_generate(p_farmid=>@F::text,p_tableid=>@T::int,p_tablenumber=>@N::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            cmd.Parameters.AddWithValue("@T", tableId);
            cmd.Parameters.AddWithValue("@N", tableNumber);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return (r.GetInt32(r.GetOrdinal("qrcodeid")), r.GetString(r.GetOrdinal("qrtoken")));
        }

        public async Task DeleteQrCodeAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_qrcode_delete(p_id=>@I::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<RestaurantQrCodeModel?> ScanQrCodeAsync(string token)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_qrcode_scan(p_token=>@T::text)", conn);
            cmd.Parameters.AddWithValue("@T", token);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new()
            {
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                TableId = r.IsDBNull(r.GetOrdinal("tableid")) ? null : r.GetInt32(r.GetOrdinal("tableid")),
                TableNumber = r.GetString(r.GetOrdinal("tablenumber")),
                IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
            };
        }

        // =====================================================================
        // PROMO CODES
        // =====================================================================

        public async Task<List<RestaurantPromoCodeModel>> ListPromoCodesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_promocode_list(p_farmid=>@F::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantPromoCodeModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                PromoCodeId = r.GetInt32(r.GetOrdinal("promocodeid")),
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                Code = r.GetString(r.GetOrdinal("code")),
                Description = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
                DiscountType = r.GetString(r.GetOrdinal("discounttype")),
                DiscountValue = r.GetDecimal(r.GetOrdinal("discountvalue")),
                MinOrderAmount = r.GetDecimal(r.GetOrdinal("minorderamount")),
                MaxDiscountAmount = r.IsDBNull(r.GetOrdinal("maxdiscountamount")) ? null : r.GetDecimal(r.GetOrdinal("maxdiscountamount")),
                MaxUses = r.GetInt32(r.GetOrdinal("maxuses")),
                CurrentUses = r.GetInt32(r.GetOrdinal("currentuses")),
                ValidFrom = r.IsDBNull(r.GetOrdinal("validfrom")) ? null : r.GetDateTime(r.GetOrdinal("validfrom")),
                ValidUntil = r.IsDBNull(r.GetOrdinal("validuntil")) ? null : r.GetDateTime(r.GetOrdinal("validuntil")),
                IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                ChannelRestriction = r.IsDBNull(r.GetOrdinal("channelrestriction")) ? null : r.GetString(r.GetOrdinal("channelrestriction")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            });
            return list;
        }

        public async Task<int> InsertPromoCodeAsync(RestaurantPromoCodeModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "INSERT INTO RestaurantPromoCodes (FarmId, Code, Description, DiscountType, DiscountValue, MinOrderAmount, MaxDiscountAmount, MaxUses, ValidFrom, ValidUntil, IsActive, ChannelRestriction) " +
                "VALUES (@FarmId, @Code, @Description, @DiscountType, @DiscountValue, @MinOrderAmount, @MaxDiscountAmount, @MaxUses, @ValidFrom, @ValidUntil, @IsActive, @ChannelRestriction) " +
                "RETURNING PromoCodeId", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@FarmId", NpgsqlTypes.NpgsqlDbType.Text) { Value = m.FarmId });
            cmd.Parameters.AddWithValue("@Code", m.Code);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DiscountType", m.DiscountType);
            cmd.Parameters.AddWithValue("@DiscountValue", m.DiscountValue);
            cmd.Parameters.AddWithValue("@MinOrderAmount", m.MinOrderAmount);
            cmd.Parameters.AddWithValue("@MaxDiscountAmount", (object?)m.MaxDiscountAmount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MaxUses", m.MaxUses);
            cmd.Parameters.AddWithValue("@ValidFrom", (object?)m.ValidFrom ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ValidUntil", (object?)m.ValidUntil ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@ChannelRestriction", (object?)m.ChannelRestriction ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdatePromoCodeAsync(RestaurantPromoCodeModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_promocode_update(p_id=>@I::int,p_farmid=>@F::text,p_code=>@a::text,p_description=>@b::text," +
                "p_discounttype=>@c::text,p_discountvalue=>@d::numeric,p_minorderamount=>@e::numeric," +
                "p_maxdiscountamount=>@f::numeric,p_maxuses=>@g::int,p_validfrom=>@h::timestamp," +
                "p_validuntil=>@i::timestamp,p_isactive=>@j::boolean,p_channelrestriction=>@k::text)", conn);
            cmd.Parameters.AddWithValue("@I", m.PromoCodeId);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = m.FarmId });
            cmd.Parameters.AddWithValue("@a", m.Code);
            cmd.Parameters.AddWithValue("@b", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@c", m.DiscountType);
            cmd.Parameters.AddWithValue("@d", m.DiscountValue);
            cmd.Parameters.AddWithValue("@e", m.MinOrderAmount);
            cmd.Parameters.AddWithValue("@f", (object?)m.MaxDiscountAmount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@g", m.MaxUses);
            cmd.Parameters.AddWithValue("@h", (object?)m.ValidFrom ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@i", (object?)m.ValidUntil ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@j", m.IsActive);
            cmd.Parameters.AddWithValue("@k", (object?)m.ChannelRestriction ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeletePromoCodeAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_promocode_delete(p_id=>@I::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<PromoValidationResult> ValidatePromoCodeAsync(string farmId, string code, decimal orderAmount, string? channel)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_promocode_validate(p_farmid=>@F::text,p_code=>@C::text,p_orderamount=>@A::numeric,p_channel=>@Ch::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            cmd.Parameters.AddWithValue("@C", code);
            cmd.Parameters.AddWithValue("@A", orderAmount);
            cmd.Parameters.AddWithValue("@Ch", (object?)channel ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return new()
            {
                Valid = r.GetBoolean(r.GetOrdinal("valid")),
                PromoCodeId = r.GetInt32(r.GetOrdinal("promocodeid")),
                DiscountType = r.GetString(r.GetOrdinal("discounttype")),
                DiscountValue = r.GetDecimal(r.GetOrdinal("discountvalue")),
                MaxDiscountAmount = r.IsDBNull(r.GetOrdinal("maxdiscountamount")) ? null : r.GetDecimal(r.GetOrdinal("maxdiscountamount")),
                CalculatedDiscount = r.GetDecimal(r.GetOrdinal("calculatediscount")),
                Message = r.GetString(r.GetOrdinal("message")),
            };
        }

        // =====================================================================
        // DELIVERY ADDRESSES
        // =====================================================================

        public async Task<List<RestaurantDeliveryAddressModel>> ListDeliveryAddressesAsync(string farmId, string? phone, string? email)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_deliveryaddress_list(p_farmid=>@F::text,p_phone=>@P::text,p_email=>@E::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            cmd.Parameters.AddWithValue("@P", (object?)phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@E", (object?)email ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantDeliveryAddressModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                DeliveryAddressId = r.GetInt32(r.GetOrdinal("deliveryaddressid")),
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                CustomerPhone = r.IsDBNull(r.GetOrdinal("customerphone")) ? null : r.GetString(r.GetOrdinal("customerphone")),
                CustomerEmail = r.IsDBNull(r.GetOrdinal("customeremail")) ? null : r.GetString(r.GetOrdinal("customeremail")),
                Label = r.GetString(r.GetOrdinal("label")),
                AddressLine1 = r.GetString(r.GetOrdinal("addressline1")),
                AddressLine2 = r.IsDBNull(r.GetOrdinal("addressline2")) ? null : r.GetString(r.GetOrdinal("addressline2")),
                City = r.IsDBNull(r.GetOrdinal("city")) ? null : r.GetString(r.GetOrdinal("city")),
                PostalCode = r.IsDBNull(r.GetOrdinal("postalcode")) ? null : r.GetString(r.GetOrdinal("postalcode")),
                Latitude = r.IsDBNull(r.GetOrdinal("latitude")) ? null : r.GetDecimal(r.GetOrdinal("latitude")),
                Longitude = r.IsDBNull(r.GetOrdinal("longitude")) ? null : r.GetDecimal(r.GetOrdinal("longitude")),
                DeliveryNotes = r.IsDBNull(r.GetOrdinal("deliverynotes")) ? null : r.GetString(r.GetOrdinal("deliverynotes")),
                IsDefault = r.GetBoolean(r.GetOrdinal("isdefault")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
            });
            return list;
        }

        public async Task<int> InsertDeliveryAddressAsync(RestaurantDeliveryAddressModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_deliveryaddress_insert(p_farmid=>@F::text,p_customerphone=>@a::text," +
                "p_customeremail=>@b::text,p_label=>@c::text,p_addressline1=>@d::text,p_addressline2=>@e::text," +
                "p_city=>@f::text,p_postalcode=>@g::text,p_latitude=>@h::numeric,p_longitude=>@i::numeric," +
                "p_deliverynotes=>@j::text,p_isdefault=>@k::boolean)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = m.FarmId });
            cmd.Parameters.AddWithValue("@a", (object?)m.CustomerPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@b", (object?)m.CustomerEmail ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@c", m.Label);
            cmd.Parameters.AddWithValue("@d", m.AddressLine1);
            cmd.Parameters.AddWithValue("@e", (object?)m.AddressLine2 ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@f", (object?)m.City ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@g", (object?)m.PostalCode ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@h", (object?)m.Latitude ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@i", (object?)m.Longitude ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@j", (object?)m.DeliveryNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@k", m.IsDefault);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteDeliveryAddressAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_deliveryaddress_delete(p_id=>@I::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // PUBLIC MENU (no auth)
        // =====================================================================

        public async Task<List<PublicMenuItemModel>> GetPublicMenuAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_public_menu(p_farmid=>@F::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<PublicMenuItemModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                MenuItemId = r.GetInt32(r.GetOrdinal("menuitemid")),
                Name = r.GetString(r.GetOrdinal("name")),
                Description = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
                Price = r.GetDecimal(r.GetOrdinal("price")),
                ImageUrl = r.IsDBNull(r.GetOrdinal("imageurl")) ? null : r.GetString(r.GetOrdinal("imageurl")),
                PrepTime = r.GetInt32(r.GetOrdinal("preptime")),
                Calories = r.IsDBNull(r.GetOrdinal("calories")) ? null : r.GetInt32(r.GetOrdinal("calories")),
                Allergens = r.IsDBNull(r.GetOrdinal("allergens")) ? null : r.GetString(r.GetOrdinal("allergens")),
                SpicyLevel = r.GetInt32(r.GetOrdinal("spicylevel")),
                IsVegetarian = r.GetBoolean(r.GetOrdinal("isvegetarian")),
                IsVegan = r.GetBoolean(r.GetOrdinal("isvegan")),
                IsGlutenFree = r.GetBoolean(r.GetOrdinal("isglutenfree")),
                IsHalal = r.GetBoolean(r.GetOrdinal("ishalal")),
                IsKosher = r.GetBoolean(r.GetOrdinal("iskosher")),
                CategoryId = r.GetInt32(r.GetOrdinal("categoryid")),
                CategoryName = r.GetString(r.GetOrdinal("categoryname")),
            });
            return list;
        }

        public async Task<List<PublicCategoryModel>> GetPublicCategoriesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_public_categories(p_farmid=>@F::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<PublicCategoryModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                MenuCategoryId = r.GetInt32(r.GetOrdinal("menucategoryid")),
                Name = r.GetString(r.GetOrdinal("name")),
                Description = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
                ImageUrl = r.IsDBNull(r.GetOrdinal("imageurl")) ? null : r.GetString(r.GetOrdinal("imageurl")),
                SortOrder = r.GetInt32(r.GetOrdinal("sortorder")),
            });
            return list;
        }

        // =====================================================================
        // ONLINE ORDER PLACEMENT
        // =====================================================================

        public async Task<(int orderId, string orderNumber, string trackingToken)> PlaceOnlineOrderAsync(OnlineOrderCreateRequest req)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            // Create order
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_online_order_insert(p_farmid=>@F::text,p_ordertype=>@a::text," +
                "p_tableid=>@b::int,p_tablenumber=>@c::text,p_customername=>@d::text,p_customerphone=>@e::text," +
                "p_covers=>@f::int,p_notes=>@g::text,p_onlinesource=>@h::text,p_deliveryaddress=>@i::text," +
                "p_deliveryfee=>@j::numeric,p_promocodeid=>@k::int,p_promocode=>@l::text,p_promodiscount=>@m::numeric)", conn);
            cmd.Parameters.AddWithValue("@F", req.FarmId);
            cmd.Parameters.AddWithValue("@a", req.OrderType);
            cmd.Parameters.AddWithValue("@b", (object?)req.TableId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@c", (object?)req.TableNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@d", (object?)req.CustomerName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@e", (object?)req.CustomerPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@f", req.Covers);
            cmd.Parameters.AddWithValue("@g", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@h", (object?)req.OnlineSource ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@i", (object?)req.DeliveryAddress ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@j", req.DeliveryFee);
            cmd.Parameters.AddWithValue("@k", (object?)req.PromoCodeId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@l", (object?)req.PromoCode ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@m", req.PromoDiscount);
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            var orderId = r.GetInt32(r.GetOrdinal("orderid"));
            var orderNum = r.GetString(r.GetOrdinal("ordernumber"));
            var token = r.GetString(r.GetOrdinal("trackingtoken"));
            await r.CloseAsync();

            // Add items
            if (req.Items != null)
            {
                foreach (var item in req.Items)
                {
                    using var icmd = new NpgsqlCommand(
                        "SELECT sprestaurant_orderitem_insert(p_farmid=>@F::text,p_orderid=>@O::int," +
                        "p_menuitemid=>@M::int,p_comboid=>@C::int,p_itemname=>@N::text," +
                        "p_quantity=>@Q::int,p_unitprice=>@P::numeric,p_notes=>@No::text," +
                        "p_seatnumber=>@S::int,p_kdsstation=>@K::text)", conn);
                    icmd.Parameters.AddWithValue("@F", req.FarmId);
                    icmd.Parameters.AddWithValue("@O", orderId);
                    icmd.Parameters.AddWithValue("@M", item.MenuItemId);
                    icmd.Parameters.AddWithValue("@C", DBNull.Value);
                    icmd.Parameters.AddWithValue("@N", item.ItemName);
                    icmd.Parameters.AddWithValue("@Q", item.Quantity);
                    icmd.Parameters.AddWithValue("@P", item.UnitPrice);
                    icmd.Parameters.AddWithValue("@No", (object?)item.Notes ?? DBNull.Value);
                    icmd.Parameters.AddWithValue("@S", DBNull.Value);
                    icmd.Parameters.AddWithValue("@K", DBNull.Value);
                    var itemId = Convert.ToInt32(await icmd.ExecuteScalarAsync());

                    if (item.Modifiers != null)
                    {
                        foreach (var mod in item.Modifiers)
                        {
                            using var mcmd = new NpgsqlCommand(
                                "SELECT sprestaurant_orderitemmod_insert(p_farmid=>@F::text,p_orderitemid=>@OI::int," +
                                "p_modifierid=>@MI::int,p_modifiername=>@MN::text,p_priceadjustment=>@PA::numeric,p_quantity=>@Q::int)", conn);
                            mcmd.Parameters.AddWithValue("@F", req.FarmId);
                            mcmd.Parameters.AddWithValue("@OI", itemId);
                            mcmd.Parameters.AddWithValue("@MI", (object?)mod.ModifierId ?? DBNull.Value);
                            mcmd.Parameters.AddWithValue("@MN", mod.ModifierName);
                            mcmd.Parameters.AddWithValue("@PA", mod.PriceAdjustment);
                            mcmd.Parameters.AddWithValue("@Q", mod.Quantity);
                            await mcmd.ExecuteScalarAsync();
                        }
                    }
                }
            }

            return (orderId, orderNum, token);
        }

        public async Task<OrderTrackingModel?> TrackOrderAsync(string trackingToken)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_order_track(p_token=>@T::text)", conn);
            cmd.Parameters.AddWithValue("@T", trackingToken);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new()
            {
                OrderId = r.GetInt32(r.GetOrdinal("orderid")),
                OrderNumber = r.GetString(r.GetOrdinal("ordernumber")),
                OrderType = r.GetString(r.GetOrdinal("ordertype")),
                Status = r.GetString(r.GetOrdinal("status")),
                TableNumber = r.IsDBNull(r.GetOrdinal("tablenumber")) ? null : r.GetString(r.GetOrdinal("tablenumber")),
                TotalAmount = r.GetDecimal(r.GetOrdinal("totalamount")),
                PaymentStatus = r.GetString(r.GetOrdinal("paymentstatus")),
                EstimatedReadyTime = r.IsDBNull(r.GetOrdinal("estimatedreadytime")) ? null : r.GetDateTime(r.GetOrdinal("estimatedreadytime")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            };
        }

        public async Task<ThrottleCheckResult> CheckThrottleAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_online_order_throttle_check(p_farmid=>@F::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlTypes.NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return new()
            {
                CanAccept = r.GetBoolean(r.GetOrdinal("can_accept")),
                CurrentCount = r.GetInt32(r.GetOrdinal("current_count")),
                MaxPerSlot = r.GetInt32(r.GetOrdinal("max_per_slot")),
                Message = r.GetString(r.GetOrdinal("message")),
            };
        }
    }
}
