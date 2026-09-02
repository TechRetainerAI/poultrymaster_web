using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantMenuService : IRestaurantMenuService
    {
        private readonly string _cs;
        public RestaurantMenuService(string cs) => _cs = cs;

        // =====================================================================
        // MENU CATEGORIES
        // =====================================================================

        public async Task<List<RestaurantMenuCategoryModel>> ListCategoriesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_menucategory_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantMenuCategoryModel>();
            while (await r.ReadAsync()) list.Add(ReadCategory(r));
            return list;
        }

        public async Task<RestaurantMenuCategoryModel?> GetCategoryAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_menucategory_get(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadCategory(r) : null;
        }

        public async Task<int> InsertCategoryAsync(RestaurantMenuCategoryModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menucategory_insert(p_farmid => @FarmId::text, p_parentcategoryid => @ParentCategoryId::int, " +
                "p_name => @Name::text, p_description => @Description::text, p_imageurl => @ImageUrl::text, " +
                "p_sortorder => @SortOrder::int, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ParentCategoryId", (object?)m.ParentCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ImageUrl", (object?)m.ImageUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateCategoryAsync(RestaurantMenuCategoryModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menucategory_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_parentcategoryid => @ParentCategoryId::int, p_name => @Name::text, " +
                "p_description => @Description::text, p_imageurl => @ImageUrl::text, " +
                "p_sortorder => @SortOrder::int, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", m.MenuCategoryId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ParentCategoryId", (object?)m.ParentCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ImageUrl", (object?)m.ImageUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteCategoryAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_menucategory_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static RestaurantMenuCategoryModel ReadCategory(NpgsqlDataReader r) => new()
        {
            MenuCategoryId   = r.GetInt32(r.GetOrdinal("menucategoryid")),
            FarmId           = r.GetString(r.GetOrdinal("farmid")),
            ParentCategoryId = r.IsDBNull(r.GetOrdinal("parentcategoryid")) ? null : r.GetInt32(r.GetOrdinal("parentcategoryid")),
            Name             = r.GetString(r.GetOrdinal("name")),
            Description      = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
            ImageUrl         = r.IsDBNull(r.GetOrdinal("imageurl")) ? null : r.GetString(r.GetOrdinal("imageurl")),
            SortOrder        = r.GetInt32(r.GetOrdinal("sortorder")),
            IsActive         = r.GetBoolean(r.GetOrdinal("isactive")),
            CreatedAt        = r.GetDateTime(r.GetOrdinal("createdat")),
            UpdatedAt        = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
        };

        // =====================================================================
        // MENU ITEMS
        // =====================================================================

        public async Task<List<RestaurantMenuItemModel>> ListItemsAsync(string farmId, int? categoryId = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_menuitem_list(p_farmid => @FarmId::text, p_categoryid => @CategoryId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CategoryId", (object?)categoryId ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantMenuItemModel>();
            while (await r.ReadAsync()) list.Add(ReadItem(r));
            return list;
        }

        public async Task<RestaurantMenuItemModel?> GetItemAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_menuitem_get(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadItem(r) : null;
        }

        public async Task<int> InsertItemAsync(RestaurantMenuItemModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menuitem_insert(p_farmid => @FarmId::text, p_menucategoryid => @MenuCategoryId::int, " +
                "p_name => @Name::text, p_description => @Description::text, p_price => @Price::numeric, " +
                "p_costprice => @CostPrice::numeric, p_imageurl => @ImageUrl::text, p_preptime => @PrepTime::int, " +
                "p_calories => @Calories::int, p_allergens => @Allergens::text, p_spicylevel => @SpicyLevel::int, " +
                "p_isvegetarian => @IsVegetarian::boolean, p_isvegan => @IsVegan::boolean, " +
                "p_isglutenfree => @IsGlutenFree::boolean, p_ishalal => @IsHalal::boolean, " +
                "p_iskosher => @IsKosher::boolean, p_isavailable => @IsAvailable::boolean, " +
                "p_isactive => @IsActive::boolean, p_sortorder => @SortOrder::int, " +
                "p_sku => @Sku::text, p_barcode => @Barcode::text)", conn);
            AddItemParams(cmd, m);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateItemAsync(RestaurantMenuItemModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menuitem_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_menucategoryid => @MenuCategoryId::int, p_name => @Name::text, p_description => @Description::text, " +
                "p_price => @Price::numeric, p_costprice => @CostPrice::numeric, p_imageurl => @ImageUrl::text, " +
                "p_preptime => @PrepTime::int, p_calories => @Calories::int, p_allergens => @Allergens::text, " +
                "p_spicylevel => @SpicyLevel::int, p_isvegetarian => @IsVegetarian::boolean, " +
                "p_isvegan => @IsVegan::boolean, p_isglutenfree => @IsGlutenFree::boolean, " +
                "p_ishalal => @IsHalal::boolean, p_iskosher => @IsKosher::boolean, " +
                "p_isavailable => @IsAvailable::boolean, p_isactive => @IsActive::boolean, " +
                "p_sortorder => @SortOrder::int, p_sku => @Sku::text, p_barcode => @Barcode::text)", conn);
            cmd.Parameters.AddWithValue("@Id", m.MenuItemId);
            AddItemParams(cmd, m);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteItemAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_menuitem_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ToggleItemAvailabilityAsync(int id, string farmId, bool isAvailable)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menuitem_toggle_available(p_id => @Id::int, p_farmid => @FarmId::text, p_isavailable => @IsAvailable::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@IsAvailable", isAvailable);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static void AddItemParams(NpgsqlCommand cmd, RestaurantMenuItemModel m)
        {
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@MenuCategoryId", (object?)m.MenuCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Price", m.Price);
            cmd.Parameters.AddWithValue("@CostPrice", m.CostPrice);
            cmd.Parameters.AddWithValue("@ImageUrl", (object?)m.ImageUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PrepTime", m.PrepTime);
            cmd.Parameters.AddWithValue("@Calories", (object?)m.Calories ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Allergens", (object?)m.Allergens ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SpicyLevel", m.SpicyLevel);
            cmd.Parameters.AddWithValue("@IsVegetarian", m.IsVegetarian);
            cmd.Parameters.AddWithValue("@IsVegan", m.IsVegan);
            cmd.Parameters.AddWithValue("@IsGlutenFree", m.IsGlutenFree);
            cmd.Parameters.AddWithValue("@IsHalal", m.IsHalal);
            cmd.Parameters.AddWithValue("@IsKosher", m.IsKosher);
            cmd.Parameters.AddWithValue("@IsAvailable", m.IsAvailable);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            cmd.Parameters.AddWithValue("@Sku", (object?)m.Sku ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Barcode", (object?)m.Barcode ?? DBNull.Value);
        }

        private static RestaurantMenuItemModel ReadItem(NpgsqlDataReader r) => new()
        {
            MenuItemId     = r.GetInt32(r.GetOrdinal("menuitemid")),
            FarmId         = r.GetString(r.GetOrdinal("farmid")),
            MenuCategoryId = r.IsDBNull(r.GetOrdinal("menucategoryid")) ? null : r.GetInt32(r.GetOrdinal("menucategoryid")),
            CategoryName   = r.IsDBNull(r.GetOrdinal("categoryname")) ? null : r.GetString(r.GetOrdinal("categoryname")),
            Name           = r.GetString(r.GetOrdinal("name")),
            Description    = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
            Price          = r.GetDecimal(r.GetOrdinal("price")),
            CostPrice      = r.GetDecimal(r.GetOrdinal("costprice")),
            ImageUrl       = r.IsDBNull(r.GetOrdinal("imageurl")) ? null : r.GetString(r.GetOrdinal("imageurl")),
            PrepTime       = r.GetInt32(r.GetOrdinal("preptime")),
            Calories       = r.IsDBNull(r.GetOrdinal("calories")) ? null : r.GetInt32(r.GetOrdinal("calories")),
            Allergens      = r.IsDBNull(r.GetOrdinal("allergens")) ? null : r.GetString(r.GetOrdinal("allergens")),
            SpicyLevel     = r.GetInt32(r.GetOrdinal("spicylevel")),
            IsVegetarian   = r.GetBoolean(r.GetOrdinal("isvegetarian")),
            IsVegan        = r.GetBoolean(r.GetOrdinal("isvegan")),
            IsGlutenFree   = r.GetBoolean(r.GetOrdinal("isglutenfree")),
            IsHalal        = r.GetBoolean(r.GetOrdinal("ishalal")),
            IsKosher       = r.GetBoolean(r.GetOrdinal("iskosher")),
            IsAvailable    = r.GetBoolean(r.GetOrdinal("isavailable")),
            IsActive       = r.GetBoolean(r.GetOrdinal("isactive")),
            SortOrder      = r.GetInt32(r.GetOrdinal("sortorder")),
            Sku            = r.IsDBNull(r.GetOrdinal("sku")) ? null : r.GetString(r.GetOrdinal("sku")),
            Barcode        = r.IsDBNull(r.GetOrdinal("barcode")) ? null : r.GetString(r.GetOrdinal("barcode")),
            CreatedAt      = r.GetDateTime(r.GetOrdinal("createdat")),
            UpdatedAt      = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
        };

        // =====================================================================
        // MODIFIER GROUPS
        // =====================================================================

        public async Task<List<RestaurantModifierGroupModel>> ListModifierGroupsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_modifiergroup_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantModifierGroupModel>();
            while (await r.ReadAsync()) list.Add(ReadModifierGroup(r));
            return list;
        }

        public async Task<int> InsertModifierGroupAsync(RestaurantModifierGroupModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_modifiergroup_insert(p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_description => @Description::text, p_isrequired => @IsRequired::boolean, " +
                "p_minselections => @MinSelections::int, p_maxselections => @MaxSelections::int, " +
                "p_sortorder => @SortOrder::int, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsRequired", m.IsRequired);
            cmd.Parameters.AddWithValue("@MinSelections", m.MinSelections);
            cmd.Parameters.AddWithValue("@MaxSelections", m.MaxSelections);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateModifierGroupAsync(RestaurantModifierGroupModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_modifiergroup_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_name => @Name::text, p_description => @Description::text, p_isrequired => @IsRequired::boolean, " +
                "p_minselections => @MinSelections::int, p_maxselections => @MaxSelections::int, " +
                "p_sortorder => @SortOrder::int, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", m.ModifierGroupId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsRequired", m.IsRequired);
            cmd.Parameters.AddWithValue("@MinSelections", m.MinSelections);
            cmd.Parameters.AddWithValue("@MaxSelections", m.MaxSelections);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteModifierGroupAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_modifiergroup_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static RestaurantModifierGroupModel ReadModifierGroup(NpgsqlDataReader r) => new()
        {
            ModifierGroupId = r.GetInt32(r.GetOrdinal("modifiergroupid")),
            FarmId          = r.GetString(r.GetOrdinal("farmid")),
            Name            = r.GetString(r.GetOrdinal("name")),
            Description     = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
            IsRequired      = r.GetBoolean(r.GetOrdinal("isrequired")),
            MinSelections   = r.GetInt32(r.GetOrdinal("minselections")),
            MaxSelections   = r.GetInt32(r.GetOrdinal("maxselections")),
            SortOrder       = r.GetInt32(r.GetOrdinal("sortorder")),
            IsActive        = r.GetBoolean(r.GetOrdinal("isactive")),
            CreatedAt       = r.GetDateTime(r.GetOrdinal("createdat")),
            UpdatedAt       = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
        };

        // =====================================================================
        // MODIFIERS
        // =====================================================================

        public async Task<List<RestaurantModifierModel>> ListModifiersAsync(string farmId, int? groupId = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_modifier_list(p_farmid => @FarmId::text, p_groupid => @GroupId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@GroupId", (object?)groupId ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantModifierModel>();
            while (await r.ReadAsync()) list.Add(ReadModifier(r));
            return list;
        }

        public async Task<int> InsertModifierAsync(RestaurantModifierModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_modifier_insert(p_farmid => @FarmId::text, p_modifiergroupid => @ModifierGroupId::int, " +
                "p_name => @Name::text, p_priceadjustment => @PriceAdjustment::numeric, " +
                "p_isdefault => @IsDefault::boolean, p_isavailable => @IsAvailable::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ModifierGroupId", m.ModifierGroupId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@PriceAdjustment", m.PriceAdjustment);
            cmd.Parameters.AddWithValue("@IsDefault", m.IsDefault);
            cmd.Parameters.AddWithValue("@IsAvailable", m.IsAvailable);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateModifierAsync(RestaurantModifierModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_modifier_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_modifiergroupid => @ModifierGroupId::int, p_name => @Name::text, " +
                "p_priceadjustment => @PriceAdjustment::numeric, p_isdefault => @IsDefault::boolean, " +
                "p_isavailable => @IsAvailable::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@Id", m.ModifierId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ModifierGroupId", m.ModifierGroupId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@PriceAdjustment", m.PriceAdjustment);
            cmd.Parameters.AddWithValue("@IsDefault", m.IsDefault);
            cmd.Parameters.AddWithValue("@IsAvailable", m.IsAvailable);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteModifierAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_modifier_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static RestaurantModifierModel ReadModifier(NpgsqlDataReader r) => new()
        {
            ModifierId      = r.GetInt32(r.GetOrdinal("modifierid")),
            FarmId          = r.GetString(r.GetOrdinal("farmid")),
            ModifierGroupId = r.GetInt32(r.GetOrdinal("modifiergroupid")),
            GroupName       = r.IsDBNull(r.GetOrdinal("groupname")) ? null : r.GetString(r.GetOrdinal("groupname")),
            Name            = r.GetString(r.GetOrdinal("name")),
            PriceAdjustment = r.GetDecimal(r.GetOrdinal("priceadjustment")),
            IsDefault       = r.GetBoolean(r.GetOrdinal("isdefault")),
            IsAvailable     = r.GetBoolean(r.GetOrdinal("isavailable")),
            SortOrder       = r.GetInt32(r.GetOrdinal("sortorder")),
            CreatedAt       = r.GetDateTime(r.GetOrdinal("createdat")),
            UpdatedAt       = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
        };

        // =====================================================================
        // MENU ITEM <-> MODIFIER GROUP ASSIGNMENTS
        // =====================================================================

        public async Task<List<RestaurantMenuItemModifierGroupModel>> ListItemModifierGroupsAsync(int menuItemId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_menuitem_modifiergroups_list(p_menuitemid => @MenuItemId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@MenuItemId", menuItemId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantMenuItemModifierGroupModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                MenuItemModifierGroupId = r.GetInt32(r.GetOrdinal("menuitemmodifiergroupid")),
                FarmId          = r.GetString(r.GetOrdinal("farmid")),
                MenuItemId      = r.GetInt32(r.GetOrdinal("menuitemid")),
                ModifierGroupId = r.GetInt32(r.GetOrdinal("modifiergroupid")),
                GroupName       = r.IsDBNull(r.GetOrdinal("groupname")) ? null : r.GetString(r.GetOrdinal("groupname")),
                IsRequired      = r.GetBoolean(r.GetOrdinal("isrequired")),
                MinSelections   = r.GetInt32(r.GetOrdinal("minselections")),
                MaxSelections   = r.GetInt32(r.GetOrdinal("maxselections")),
                SortOrder       = r.GetInt32(r.GetOrdinal("sortorder")),
            });
            return list;
        }

        public async Task<int> AssignModifierGroupToItemAsync(string farmId, int menuItemId, int modifierGroupId, int sortOrder)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menuitem_modifiergroup_assign(p_farmid => @FarmId::text, " +
                "p_menuitemid => @MenuItemId::int, p_modifiergroupid => @ModifierGroupId::int, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@MenuItemId", menuItemId);
            cmd.Parameters.AddWithValue("@ModifierGroupId", modifierGroupId);
            cmd.Parameters.AddWithValue("@SortOrder", sortOrder);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UnassignModifierGroupFromItemAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menuitem_modifiergroup_unassign(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // COMBOS
        // =====================================================================

        public async Task<List<RestaurantComboModel>> ListCombosAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_combo_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantComboModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                ComboId     = r.GetInt32(r.GetOrdinal("comboid")),
                FarmId      = r.GetString(r.GetOrdinal("farmid")),
                Name        = r.GetString(r.GetOrdinal("name")),
                Description = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
                Price       = r.GetDecimal(r.GetOrdinal("price")),
                ImageUrl    = r.IsDBNull(r.GetOrdinal("imageurl")) ? null : r.GetString(r.GetOrdinal("imageurl")),
                IsActive    = r.GetBoolean(r.GetOrdinal("isactive")),
                SortOrder   = r.GetInt32(r.GetOrdinal("sortorder")),
                CreatedAt   = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt   = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            });
            return list;
        }

        public async Task<int> InsertComboAsync(RestaurantComboModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_combo_insert(p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_description => @Description::text, p_price => @Price::numeric, p_imageurl => @ImageUrl::text, " +
                "p_isactive => @IsActive::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Price", m.Price);
            cmd.Parameters.AddWithValue("@ImageUrl", (object?)m.ImageUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateComboAsync(RestaurantComboModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_combo_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_name => @Name::text, p_description => @Description::text, p_price => @Price::numeric, " +
                "p_imageurl => @ImageUrl::text, p_isactive => @IsActive::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@Id", m.ComboId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Price", m.Price);
            cmd.Parameters.AddWithValue("@ImageUrl", (object?)m.ImageUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteComboAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_combo_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ---- Combo Items ----

        public async Task<List<RestaurantComboItemModel>> ListComboItemsAsync(int comboId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_comboitem_list(p_comboid => @ComboId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@ComboId", comboId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantComboItemModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                ComboItemId    = r.GetInt32(r.GetOrdinal("comboitemid")),
                FarmId         = r.GetString(r.GetOrdinal("farmid")),
                ComboId        = r.GetInt32(r.GetOrdinal("comboid")),
                MenuItemId     = r.IsDBNull(r.GetOrdinal("menuitemid")) ? null : r.GetInt32(r.GetOrdinal("menuitemid")),
                MenuItemName   = r.IsDBNull(r.GetOrdinal("menuitemname")) ? null : r.GetString(r.GetOrdinal("menuitemname")),
                MenuCategoryId = r.IsDBNull(r.GetOrdinal("menucategoryid")) ? null : r.GetInt32(r.GetOrdinal("menucategoryid")),
                CategoryName   = r.IsDBNull(r.GetOrdinal("categoryname")) ? null : r.GetString(r.GetOrdinal("categoryname")),
                Quantity       = r.GetInt32(r.GetOrdinal("quantity")),
                SortOrder      = r.GetInt32(r.GetOrdinal("sortorder")),
            });
            return list;
        }

        public async Task<int> InsertComboItemAsync(RestaurantComboItemModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_comboitem_insert(p_farmid => @FarmId::text, p_comboid => @ComboId::int, " +
                "p_menuitemid => @MenuItemId::int, p_menucategoryid => @MenuCategoryId::int, " +
                "p_quantity => @Quantity::int, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ComboId", m.ComboId);
            cmd.Parameters.AddWithValue("@MenuItemId", (object?)m.MenuItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MenuCategoryId", (object?)m.MenuCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteComboItemAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_comboitem_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // MENU SCHEDULES
        // =====================================================================

        public async Task<List<RestaurantMenuScheduleModel>> ListSchedulesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_menuschedule_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantMenuScheduleModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                MenuScheduleId = r.GetInt32(r.GetOrdinal("menuscheduleid")),
                FarmId         = r.GetString(r.GetOrdinal("farmid")),
                Name           = r.GetString(r.GetOrdinal("name")),
                StartTime      = r.GetString(r.GetOrdinal("starttime")),
                EndTime        = r.GetString(r.GetOrdinal("endtime")),
                DaysOfWeek     = r.IsDBNull(r.GetOrdinal("daysofweek")) ? null : r.GetString(r.GetOrdinal("daysofweek")),
                IsActive       = r.GetBoolean(r.GetOrdinal("isactive")),
                CreatedAt      = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt      = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            });
            return list;
        }

        public async Task<int> InsertScheduleAsync(RestaurantMenuScheduleModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menuschedule_insert(p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_starttime => @StartTime::text, p_endtime => @EndTime::text, " +
                "p_daysofweek => @DaysOfWeek::text, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@StartTime", m.StartTime);
            cmd.Parameters.AddWithValue("@EndTime", m.EndTime);
            cmd.Parameters.AddWithValue("@DaysOfWeek", (object?)m.DaysOfWeek ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateScheduleAsync(RestaurantMenuScheduleModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menuschedule_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_name => @Name::text, p_starttime => @StartTime::text, p_endtime => @EndTime::text, " +
                "p_daysofweek => @DaysOfWeek::text, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", m.MenuScheduleId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@StartTime", m.StartTime);
            cmd.Parameters.AddWithValue("@EndTime", m.EndTime);
            cmd.Parameters.AddWithValue("@DaysOfWeek", (object?)m.DaysOfWeek ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteScheduleAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_menuschedule_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ---- Schedule Items ----

        public async Task<List<RestaurantMenuScheduleItemModel>> ListScheduleItemsAsync(int scheduleId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_menuscheduleitem_list(p_scheduleid => @ScheduleId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@ScheduleId", scheduleId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantMenuScheduleItemModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                MenuScheduleItemId = r.GetInt32(r.GetOrdinal("menuscheduleitemid")),
                FarmId             = r.GetString(r.GetOrdinal("farmid")),
                MenuScheduleId     = r.GetInt32(r.GetOrdinal("menuscheduleid")),
                MenuItemId         = r.GetInt32(r.GetOrdinal("menuitemid")),
                MenuItemName       = r.IsDBNull(r.GetOrdinal("menuitemname")) ? null : r.GetString(r.GetOrdinal("menuitemname")),
                OverridePrice      = r.IsDBNull(r.GetOrdinal("overrideprice")) ? null : r.GetDecimal(r.GetOrdinal("overrideprice")),
            });
            return list;
        }

        public async Task<int> AssignItemToScheduleAsync(string farmId, int scheduleId, int menuItemId, decimal? overridePrice)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menuscheduleitem_assign(p_farmid => @FarmId::text, " +
                "p_menuscheduleid => @ScheduleId::int, p_menuitemid => @MenuItemId::int, p_overrideprice => @OverridePrice::numeric)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ScheduleId", scheduleId);
            cmd.Parameters.AddWithValue("@MenuItemId", menuItemId);
            cmd.Parameters.AddWithValue("@OverridePrice", (object?)overridePrice ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UnassignItemFromScheduleAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_menuscheduleitem_unassign(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // ITEM TAGS
        // =====================================================================

        public async Task<List<RestaurantItemTagModel>> ListItemTagsAsync(int menuItemId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_itemtag_list(p_menuitemid => @MenuItemId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@MenuItemId", menuItemId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantItemTagModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                ItemTagId  = r.GetInt32(r.GetOrdinal("itemtagid")),
                FarmId     = r.GetString(r.GetOrdinal("farmid")),
                MenuItemId = r.GetInt32(r.GetOrdinal("menuitemid")),
                Tag        = r.GetString(r.GetOrdinal("tag")),
            });
            return list;
        }

        public async Task<int> AddItemTagAsync(string farmId, int menuItemId, string tag)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_itemtag_add(p_farmid => @FarmId::text, p_menuitemid => @MenuItemId::int, p_tag => @Tag::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@MenuItemId", menuItemId);
            cmd.Parameters.AddWithValue("@Tag", tag);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task RemoveItemTagAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_itemtag_remove(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
