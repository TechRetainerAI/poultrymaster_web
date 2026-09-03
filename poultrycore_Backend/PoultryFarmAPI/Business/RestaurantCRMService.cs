using Npgsql; using NpgsqlTypes; using PoultryFarmAPIWeb.Models;
namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantCRMService : IRestaurantCRMService
    {
        private readonly string _cs;
        public RestaurantCRMService(string cs) => _cs = cs;
        static NpgsqlParameter TP(string n, string v) => new(n, System.Data.DbType.String) { Value = v };
        static NpgsqlParameter TPN(string n, string? v) => new(n, System.Data.DbType.String) { Value = (object?)v ?? DBNull.Value };

        public async Task<List<RestaurantCustomerModel>> ListCustomersAsync(string farmId, string? segment = null, string? search = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_customer_list(p_farmid=>@F::text,p_segment=>@S::text,p_search=>@Q::text)", conn);
            cmd.Parameters.Add(TP("@F", farmId)); cmd.Parameters.Add(TPN("@S", segment)); cmd.Parameters.Add(TPN("@Q", search));
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<RestaurantCustomerModel>();
            while (await r.ReadAsync()) l.Add(new() {
                CustomerId=r.GetInt32(0),FarmId=r.GetString(1),Name=r.GetString(2),
                Phone=r.IsDBNull(3)?null:r.GetString(3),Email=r.IsDBNull(4)?null:r.GetString(4),
                DateOfBirth=r.IsDBNull(5)?null:r.GetDateTime(5),Anniversary=r.IsDBNull(6)?null:r.GetDateTime(6),
                DietaryPreferences=r.IsDBNull(7)?null:r.GetString(7),Allergies=r.IsDBNull(8)?null:r.GetString(8),
                FavouriteItems=r.IsDBNull(9)?null:r.GetString(9),Segment=r.GetString(10),
                TotalVisits=r.GetInt32(11),TotalSpent=r.GetDecimal(12),AvgTicket=r.GetDecimal(13),
                LastVisit=r.IsDBNull(14)?null:r.GetDateTime(14),Notes=r.IsDBNull(15)?null:r.GetString(15),
                IsActive=r.GetBoolean(16),CreatedAt=r.GetDateTime(17),UpdatedAt=r.IsDBNull(18)?null:r.GetDateTime(18),
            }); return l;
        }

        public async Task<int> InsertCustomerAsync(RestaurantCustomerModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "INSERT INTO RestaurantCustomers (FarmId, Name, Phone, Email, DateOfBirth, Anniversary, DietaryPreferences, Allergies, FavouriteItems, Segment, Notes) " +
                "VALUES (@FarmId, @Name, @Phone, @Email, @DateOfBirth, @Anniversary, @DietaryPreferences, @Allergies, @FavouriteItems, @Segment, @Notes) " +
                "RETURNING CustomerId", conn);
            cmd.Parameters.Add(TP("@FarmId",m.FarmId)); cmd.Parameters.AddWithValue("@Name",m.Name);
            cmd.Parameters.AddWithValue("@Phone",(object?)m.Phone??DBNull.Value); cmd.Parameters.AddWithValue("@Email",(object?)m.Email??DBNull.Value);
            cmd.Parameters.AddWithValue("@DateOfBirth",(object?)m.DateOfBirth??DBNull.Value); cmd.Parameters.AddWithValue("@Anniversary",(object?)m.Anniversary??DBNull.Value);
            cmd.Parameters.AddWithValue("@DietaryPreferences",(object?)m.DietaryPreferences??DBNull.Value); cmd.Parameters.AddWithValue("@Allergies",(object?)m.Allergies??DBNull.Value);
            cmd.Parameters.AddWithValue("@FavouriteItems",(object?)m.FavouriteItems??DBNull.Value); cmd.Parameters.AddWithValue("@Segment",(object?)m.Segment??DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",(object?)m.Notes??DBNull.Value);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateCustomerAsync(RestaurantCustomerModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "UPDATE RestaurantCustomers SET Name=@Name, Phone=@Phone, Email=@Email, DateOfBirth=@DateOfBirth, " +
                "Anniversary=@Anniversary, DietaryPreferences=@DietaryPreferences, Allergies=@Allergies, " +
                "FavouriteItems=@FavouriteItems, Segment=@Segment, Notes=@Notes, IsActive=@IsActive, UpdatedAt=NOW() " +
                "WHERE CustomerId=@CustomerId AND FarmId=@FarmId", conn);
            cmd.Parameters.AddWithValue("@CustomerId",m.CustomerId); cmd.Parameters.Add(TP("@FarmId",m.FarmId));
            cmd.Parameters.AddWithValue("@Name",m.Name); cmd.Parameters.AddWithValue("@Phone",(object?)m.Phone??DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",(object?)m.Email??DBNull.Value); cmd.Parameters.AddWithValue("@DateOfBirth",(object?)m.DateOfBirth??DBNull.Value);
            cmd.Parameters.AddWithValue("@Anniversary",(object?)m.Anniversary??DBNull.Value); cmd.Parameters.AddWithValue("@DietaryPreferences",(object?)m.DietaryPreferences??DBNull.Value);
            cmd.Parameters.AddWithValue("@Allergies",(object?)m.Allergies??DBNull.Value); cmd.Parameters.AddWithValue("@FavouriteItems",(object?)m.FavouriteItems??DBNull.Value);
            cmd.Parameters.AddWithValue("@Segment",(object?)m.Segment??DBNull.Value); cmd.Parameters.AddWithValue("@Notes",(object?)m.Notes??DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive",m.IsActive);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteCustomerAsync(int id, string farmId) { using var conn = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT sprestaurant_customer_delete(p_id=>@I::int,p_farmid=>@F::text)", conn); cmd.Parameters.AddWithValue("@I",id); cmd.Parameters.Add(TP("@F",farmId)); await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }

        public async Task RecordVisitAsync(int id, string farmId, decimal orderAmount) { using var conn = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT sprestaurant_customer_record_visit(p_id=>@I::int,p_farmid=>@F::text,p_orderamount=>@A::numeric)", conn); cmd.Parameters.AddWithValue("@I",id); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@A",orderAmount); await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }

        public async Task<CustomerStatsModel> GetCustomerStatsAsync(string farmId) { using var conn = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_customer_stats(p_farmid=>@F::text)", conn); cmd.Parameters.Add(TP("@F",farmId)); await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync(); if (await r.ReadAsync()) return new() { TotalCustomers=r.GetInt64(0),NewCount=r.GetInt64(1),RegularCount=r.GetInt64(2),VipCount=r.GetInt64(3),LapsedCount=r.GetInt64(4),TotalLifetimeValue=r.GetDecimal(5) }; return new(); }

        public async Task<List<RestaurantFeedbackModel>> ListFeedbackAsync(string farmId, string? status = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_feedback_list(p_farmid=>@F::text,p_status=>@S::text)", conn);
            cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.Add(TPN("@S",status));
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<RestaurantFeedbackModel>();
            while (await r.ReadAsync()) l.Add(new() {
                FeedbackId=r.GetInt32(0),FarmId=r.GetString(1),CustomerId=r.IsDBNull(2)?null:r.GetInt32(2),
                CustomerName=r.IsDBNull(3)?null:r.GetString(3),OrderId=r.IsDBNull(4)?null:r.GetInt32(4),
                Rating=r.GetInt32(5),FoodRating=r.IsDBNull(6)?null:r.GetInt32(6),
                ServiceRating=r.IsDBNull(7)?null:r.GetInt32(7),AmbienceRating=r.IsDBNull(8)?null:r.GetInt32(8),
                Comment=r.IsDBNull(9)?null:r.GetString(9),Source=r.GetString(10),Status=r.GetString(11),
                Response=r.IsDBNull(12)?null:r.GetString(12),RespondedBy=r.IsDBNull(13)?null:r.GetString(13),
                CreatedAt=r.GetDateTime(14),UpdatedAt=r.IsDBNull(15)?null:r.GetDateTime(15),
            }); return l;
        }

        public async Task<int> InsertFeedbackAsync(RestaurantFeedbackModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("INSERT INTO restaurantcustomerfeedback (farmid,customerid,customername,orderid,rating,foodrating,servicerating,ambiencerating,comment,source) VALUES (@FarmId,@CustId,@CustName,@OrdId,@Rating,@FoodR,@ServR,@AmbR,@Comment,@Source) RETURNING feedbackid", conn);
            cmd.Parameters.AddWithValue("@FarmId",m.FarmId); cmd.Parameters.AddWithValue("@CustId",(object?)m.CustomerId??DBNull.Value);
            cmd.Parameters.AddWithValue("@CustName",(object?)m.CustomerName??DBNull.Value); cmd.Parameters.AddWithValue("@OrdId",(object?)m.OrderId??DBNull.Value);
            cmd.Parameters.AddWithValue("@Rating",m.Rating); cmd.Parameters.AddWithValue("@FoodR",(object?)m.FoodRating??DBNull.Value);
            cmd.Parameters.AddWithValue("@ServR",(object?)m.ServiceRating??DBNull.Value); cmd.Parameters.AddWithValue("@AmbR",(object?)m.AmbienceRating??DBNull.Value);
            cmd.Parameters.AddWithValue("@Comment",(object?)m.Comment??DBNull.Value); cmd.Parameters.AddWithValue("@Source",m.Source);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task RespondToFeedbackAsync(int id, string farmId, string response, string respondedBy) { using var conn = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT sprestaurant_feedback_respond(p_id=>@I::int,p_farmid=>@F::text,p_response=>@R::text,p_respondedby=>@B::text)", conn); cmd.Parameters.AddWithValue("@I",id); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@R",response); cmd.Parameters.AddWithValue("@B",respondedBy); await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }

        public async Task<FeedbackStatsModel> GetFeedbackStatsAsync(string farmId) { using var conn = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_feedback_stats(p_farmid=>@F::text)", conn); cmd.Parameters.Add(TP("@F",farmId)); await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync(); if (await r.ReadAsync()) return new() { TotalFeedback=r.GetInt64(0),AvgRating=r.IsDBNull(1)?null:r.GetDouble(1),AvgFood=r.IsDBNull(2)?null:r.GetDouble(2),AvgService=r.IsDBNull(3)?null:r.GetDouble(3),AvgAmbience=r.IsDBNull(4)?null:r.GetDouble(4),NewCount=r.GetInt64(5) }; return new(); }

        public async Task<List<RestaurantCampaignModel>> ListCampaignsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_campaign_list(p_farmid=>@F::text)", conn);
            cmd.Parameters.Add(TP("@F",farmId));
            await conn.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var l = new List<RestaurantCampaignModel>();
            while (await r.ReadAsync()) l.Add(new() {
                CampaignId=r.GetInt32(0),FarmId=r.GetString(1),Name=r.GetString(2),CampaignType=r.GetString(3),
                TargetSegment=r.IsDBNull(4)?null:r.GetString(4),Subject=r.IsDBNull(5)?null:r.GetString(5),
                Message=r.IsDBNull(6)?null:r.GetString(6),Channel=r.GetString(7),Status=r.GetString(8),
                ScheduledAt=r.IsDBNull(9)?null:r.GetDateTime(9),SentAt=r.IsDBNull(10)?null:r.GetDateTime(10),
                RecipientCount=r.GetInt32(11),OpenCount=r.GetInt32(12),CreatedAt=r.GetDateTime(13),
            }); return l;
        }

        public async Task<int> InsertCampaignAsync(RestaurantCampaignModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_campaign_insert(p_farmid=>@F::text,p_name=>@a::text,p_campaigntype=>@b::text,p_targetsegment=>@c::text,p_subject=>@d::text,p_message=>@e::text,p_channel=>@f::text)", conn);
            cmd.Parameters.Add(TP("@F",m.FarmId)); cmd.Parameters.AddWithValue("@a",m.Name); cmd.Parameters.AddWithValue("@b",m.CampaignType);
            cmd.Parameters.AddWithValue("@c",(object?)m.TargetSegment??DBNull.Value); cmd.Parameters.AddWithValue("@d",(object?)m.Subject??DBNull.Value);
            cmd.Parameters.AddWithValue("@e",(object?)m.Message??DBNull.Value); cmd.Parameters.AddWithValue("@f",m.Channel);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteCampaignAsync(int id, string farmId) { using var conn = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT sprestaurant_campaign_delete(p_id=>@I::int,p_farmid=>@F::text)", conn); cmd.Parameters.AddWithValue("@I",id); cmd.Parameters.Add(TP("@F",farmId)); await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }
    }
}
