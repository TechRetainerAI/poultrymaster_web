using Npgsql; using NpgsqlTypes; using PoultryFarmAPIWeb.Models;
namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Notification Service
    // =========================================================================
    public class RestaurantNotificationService : IRestaurantNotificationService
    {
        private readonly string _cs; public RestaurantNotificationService(string cs) => _cs = cs;
        static NpgsqlParameter TP(string n, string v) => new(n, System.Data.DbType.String) { Value = v };
        static NpgsqlParameter TPN(string n, string? v) => new(n, NpgsqlDbType.Text) { Value = (object?)v ?? DBNull.Value };

        public async Task<List<NotificationModel>> ListAsync(string farmId, bool unreadOnly = false) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_notification_list(p_farmid=>@F::text,p_unreadonly=>@U::boolean)",c); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@U",unreadOnly); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); var l=new List<NotificationModel>(); while(await r.ReadAsync()) l.Add(new(){NotificationId=r.GetInt32(0),FarmId=r.GetString(1),Type=r.GetString(2),Title=r.GetString(3),Message=r.GetString(4),Severity=r.GetString(5),IsRead=r.GetBoolean(6),TargetUserId=r.IsDBNull(7)?null:r.GetString(7),TargetRole=r.IsDBNull(8)?null:r.GetString(8),RelatedId=r.IsDBNull(9)?null:r.GetInt32(9),RelatedType=r.IsDBNull(10)?null:r.GetString(10),CreatedAt=r.GetDateTime(11)}); return l; }

        public async Task<int> CreateAsync(string farmId, string type, string title, string message, string severity, string? targetRole = null, int? relatedId = null, string? relatedType = null) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_notification_create(p_farmid=>@F::text,p_type=>@a::text,p_title=>@b::text,p_message=>@c::text,p_severity=>@d::text,p_targetrole=>@e::text,p_relatedid=>@f::int,p_relatedtype=>@g::text)",c); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@a",type); cmd.Parameters.AddWithValue("@b",title); cmd.Parameters.AddWithValue("@c",message); cmd.Parameters.AddWithValue("@d",severity); cmd.Parameters.AddWithValue("@e",(object?)targetRole??DBNull.Value); cmd.Parameters.AddWithValue("@f",(object?)relatedId??DBNull.Value); cmd.Parameters.AddWithValue("@g",(object?)relatedType??DBNull.Value); await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync()); }

        public async Task MarkReadAsync(int id, string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_notification_markread(p_id=>@I::int,p_farmid=>@F::text)",c); cmd.Parameters.AddWithValue("@I",id); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }

        public async Task MarkAllReadAsync(string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_notification_markallread(p_farmid=>@F::text)",c); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }

        public async Task<NotificationSettingsModel?> GetSettingsAsync(string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_notification_settings_get(p_farmid=>@F::text)",c); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); if(!await r.ReadAsync()) return null; return new(){NotificationSettingId=r.GetInt32(0),FarmId=r.GetString(1),EmailEnabled=r.GetBoolean(2),SmsEnabled=r.GetBoolean(3),PushEnabled=r.GetBoolean(4),LowStockAlerts=r.GetBoolean(5),NewOrderAlerts=r.GetBoolean(6),ReservationAlerts=r.GetBoolean(7),KpiAlerts=r.GetBoolean(8),ShiftReminders=r.GetBoolean(9),CreatedAt=r.GetDateTime(10),UpdatedAt=r.IsDBNull(11)?null:r.GetDateTime(11)}; }

        public async Task UpsertSettingsAsync(NotificationSettingsModel m) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("INSERT INTO restaurantnotificationsettings (farmid,emailenabled,smsenabled,pushenabled,lowstockalerts,neworderalerts,reservationalerts,kpialerts,shiftreminders) VALUES (@FarmId,@EmailOn,@SmsOn,@PushOn,@LowStk,@NewOrd,@ResAlrt,@KpiAlrt,@ShiftR) ON CONFLICT (farmid) DO UPDATE SET emailenabled=@EmailOn,smsenabled=@SmsOn,pushenabled=@PushOn,lowstockalerts=@LowStk,neworderalerts=@NewOrd,reservationalerts=@ResAlrt,kpialerts=@KpiAlrt,shiftreminders=@ShiftR,updatedat=NOW()",c); cmd.Parameters.AddWithValue("@FarmId",m.FarmId); cmd.Parameters.AddWithValue("@EmailOn",m.EmailEnabled); cmd.Parameters.AddWithValue("@SmsOn",m.SmsEnabled); cmd.Parameters.AddWithValue("@PushOn",m.PushEnabled); cmd.Parameters.AddWithValue("@LowStk",m.LowStockAlerts); cmd.Parameters.AddWithValue("@NewOrd",m.NewOrderAlerts); cmd.Parameters.AddWithValue("@ResAlrt",m.ReservationAlerts); cmd.Parameters.AddWithValue("@KpiAlrt",m.KpiAlerts); cmd.Parameters.AddWithValue("@ShiftR",m.ShiftReminders); await c.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }
    }

    // =========================================================================
    // Event Service
    // =========================================================================
    public class RestaurantEventService : IRestaurantEventService
    {
        private readonly string _cs; public RestaurantEventService(string cs) => _cs = cs;
        static NpgsqlParameter TP(string n, string v) => new(n, System.Data.DbType.String) { Value = v };

        public async Task<List<EventModel>> ListAsync(string farmId, string? status = null) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_event_list(p_farmid=>@F::text,p_status=>@S::text)",c); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.Add(new NpgsqlParameter("@S",NpgsqlDbType.Text){Value=(object?)status??DBNull.Value}); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); var l=new List<EventModel>(); while(await r.ReadAsync()) l.Add(new(){EventId=r.GetInt32(0),FarmId=r.GetString(1),EventNumber=r.IsDBNull(2)?null:r.GetString(2),Name=r.GetString(3),EventType=r.GetString(4),EventDate=r.GetDateTime(5),StartTime=r.IsDBNull(6)?null:r.GetString(6),EndTime=r.IsDBNull(7)?null:r.GetString(7),GuestCount=r.GetInt32(8),Venue=r.IsDBNull(9)?null:r.GetString(9),Status=r.GetString(10),ContactName=r.IsDBNull(11)?null:r.GetString(11),ContactPhone=r.IsDBNull(12)?null:r.GetString(12),ContactEmail=r.IsDBNull(13)?null:r.GetString(13),PackageName=r.IsDBNull(14)?null:r.GetString(14),PricePerHead=r.GetDecimal(15),TotalAmount=r.GetDecimal(16),DepositAmount=r.GetDecimal(17),DepositPaid=r.GetBoolean(18),BalanceDue=r.GetDecimal(19),SpecialRequests=r.IsDBNull(20)?null:r.GetString(20),DietaryNotes=r.IsDBNull(21)?null:r.GetString(21),Notes=r.IsDBNull(22)?null:r.GetString(22),CreatedBy=r.IsDBNull(23)?null:r.GetString(23),CreatedAt=r.GetDateTime(24),UpdatedAt=r.IsDBNull(25)?null:r.GetDateTime(25)}); return l; }

        public async Task<int> InsertAsync(EventModel m) {
            using var c=new NpgsqlConnection(_cs);
            var num = "EVT-" + m.EventDate.ToString("yyyyMMdd") + "-" + DateTime.UtcNow.Ticks.ToString().Substring(14);
            var total = m.PricePerHead * m.GuestCount;
            using var cmd=new NpgsqlCommand("INSERT INTO restaurantevents (farmid,eventnumber,name,eventtype,eventdate,starttime,endtime,guestcount,venue,contactname,contactphone,contactemail,packagename,priceperhead,totalamount,balancedue,specialrequests,dietarynotes,notes,createdby) VALUES (@FarmId,@EvNum,@EvName,@EvType,@EvDate,@StartT,@EndT,@Guests,@Venue,@CName,@CPhone,@CEmail,@PkgName,@PPH,@TotalAmt,@TotalAmt,@SpecReq,@DietNotes,@EvNotes,@CreatedBy) RETURNING eventid",c);
            cmd.Parameters.AddWithValue("@FarmId",m.FarmId); cmd.Parameters.AddWithValue("@EvNum",num);
            cmd.Parameters.AddWithValue("@EvName",m.Name); cmd.Parameters.AddWithValue("@EvType",m.EventType);
            cmd.Parameters.AddWithValue("@EvDate",m.EventDate); cmd.Parameters.AddWithValue("@StartT",(object?)m.StartTime??DBNull.Value);
            cmd.Parameters.AddWithValue("@EndT",(object?)m.EndTime??DBNull.Value); cmd.Parameters.AddWithValue("@Guests",m.GuestCount);
            cmd.Parameters.AddWithValue("@Venue",(object?)m.Venue??DBNull.Value); cmd.Parameters.AddWithValue("@CName",(object?)m.ContactName??DBNull.Value);
            cmd.Parameters.AddWithValue("@CPhone",(object?)m.ContactPhone??DBNull.Value); cmd.Parameters.AddWithValue("@CEmail",(object?)m.ContactEmail??DBNull.Value);
            cmd.Parameters.AddWithValue("@PkgName",(object?)m.PackageName??DBNull.Value); cmd.Parameters.AddWithValue("@PPH",m.PricePerHead);
            cmd.Parameters.AddWithValue("@TotalAmt",total);
            cmd.Parameters.AddWithValue("@SpecReq",(object?)m.SpecialRequests??DBNull.Value); cmd.Parameters.AddWithValue("@DietNotes",(object?)m.DietaryNotes??DBNull.Value);
            cmd.Parameters.AddWithValue("@EvNotes",(object?)m.Notes??DBNull.Value); cmd.Parameters.AddWithValue("@CreatedBy",(object?)m.CreatedBy??DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync()); }

        public async Task UpdateStatusAsync(int id, string farmId, string status) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_event_update_status(p_id=>@I::int,p_farmid=>@F::text,p_status=>@S::text)",c); cmd.Parameters.AddWithValue("@I",id); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@S",status); await c.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }

        public async Task DeleteAsync(int id, string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_event_delete(p_id=>@I::int,p_farmid=>@F::text)",c); cmd.Parameters.AddWithValue("@I",id); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }
    }

    // =========================================================================
    // Gift Card Service
    // =========================================================================
    public class RestaurantGiftCardService : IRestaurantGiftCardService
    {
        private readonly string _cs; public RestaurantGiftCardService(string cs) => _cs = cs;
        static NpgsqlParameter TP(string n, string v) => new(n, System.Data.DbType.String) { Value = v };

        public async Task<List<GiftCardModel>> ListAsync(string farmId, string? status = null) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_giftcard_list(p_farmid=>@F::text,p_status=>@S::text)",c); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.Add(new NpgsqlParameter("@S",NpgsqlDbType.Text){Value=(object?)status??DBNull.Value}); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); var l=new List<GiftCardModel>(); while(await r.ReadAsync()) l.Add(new(){GiftCardId=r.GetInt32(0),FarmId=r.GetString(1),CardNumber=r.GetString(2),CardType=r.GetString(3),InitialBalance=r.GetDecimal(4),CurrentBalance=r.GetDecimal(5),PurchaserName=r.IsDBNull(6)?null:r.GetString(6),PurchaserPhone=r.IsDBNull(7)?null:r.GetString(7),RecipientName=r.IsDBNull(8)?null:r.GetString(8),Status=r.GetString(9),ExpiryDate=r.IsDBNull(10)?null:r.GetDateTime(10),CreatedAt=r.GetDateTime(11)}); return l; }

        public async Task<(int id, string cardNumber)> CreateAsync(string farmId, string cardType, decimal amount, string? purchaserName, string? purchaserPhone, string? recipientName, string? recipientEmail, string? message, DateTime? expiryDate) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_giftcard_create(p_farmid=>@F::text,p_cardtype=>@a::text,p_amount=>@b::numeric,p_purchasername=>@c::text,p_purchaserphone=>@d::text,p_recipientname=>@e::text,p_recipientemail=>@f::text,p_message=>@g::text,p_expirydate=>@h::date)",c); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@a",cardType); cmd.Parameters.AddWithValue("@b",amount); cmd.Parameters.AddWithValue("@c",(object?)purchaserName??DBNull.Value); cmd.Parameters.AddWithValue("@d",(object?)purchaserPhone??DBNull.Value); cmd.Parameters.AddWithValue("@e",(object?)recipientName??DBNull.Value); cmd.Parameters.AddWithValue("@f",(object?)recipientEmail??DBNull.Value); cmd.Parameters.AddWithValue("@g",(object?)message??DBNull.Value); cmd.Parameters.AddWithValue("@h",(object?)expiryDate??DBNull.Value); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); await r.ReadAsync(); return(r.GetInt32(0),r.GetString(1)); }

        public async Task<GiftCardRedeemResult> RedeemAsync(string cardNumber, string farmId, decimal amount, int? orderId = null, string? processedBy = null) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_giftcard_redeem(p_cardnumber=>@N::text,p_farmid=>@F::text,p_amount=>@A::numeric,p_orderid=>@O::int,p_processedby=>@P::text)",c); cmd.Parameters.AddWithValue("@N",cardNumber); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@A",amount); cmd.Parameters.AddWithValue("@O",(object?)orderId??DBNull.Value); cmd.Parameters.AddWithValue("@P",(object?)processedBy??DBNull.Value); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); await r.ReadAsync(); return new(){Success=r.GetBoolean(0),NewBalance=r.GetDecimal(1),Message=r.GetString(2)}; }

        public async Task ReloadAsync(string cardNumber, string farmId, decimal amount, string? processedBy = null) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_giftcard_reload(p_cardnumber=>@N::text,p_farmid=>@F::text,p_amount=>@A::numeric,p_processedby=>@P::text)",c); cmd.Parameters.AddWithValue("@N",cardNumber); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@A",amount); cmd.Parameters.AddWithValue("@P",(object?)processedBy??DBNull.Value); await c.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }

        public async Task<GiftCardModel?> CheckBalanceAsync(string cardNumber) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_giftcard_balance(p_cardnumber=>@N::text)",c); cmd.Parameters.AddWithValue("@N",cardNumber); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); if(!await r.ReadAsync()) return null; return new(){CardNumber=r.GetString(0),CurrentBalance=r.GetDecimal(1),Status=r.GetString(2),ExpiryDate=r.IsDBNull(3)?null:r.GetDateTime(3)}; }

        public async Task<List<GiftCardTxModel>> GetTransactionsAsync(int giftCardId, string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_giftcard_transactions(p_giftcardid=>@G::int,p_farmid=>@F::text)",c); cmd.Parameters.AddWithValue("@G",giftCardId); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); var l=new List<GiftCardTxModel>(); while(await r.ReadAsync()) l.Add(new(){GiftCardTxId=r.GetInt32(0),TransactionType=r.GetString(1),Amount=r.GetDecimal(2),BalanceAfter=r.GetDecimal(3),OrderId=r.IsDBNull(4)?null:r.GetInt32(4),Notes=r.IsDBNull(5)?null:r.GetString(5),ProcessedBy=r.IsDBNull(6)?null:r.GetString(6),CreatedAt=r.GetDateTime(7)}); return l; }

        public async Task<GiftCardStatsModel> GetStatsAsync(string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_giftcard_stats(p_farmid=>@F::text)",c); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); if(await r.ReadAsync()) return new(){TotalCards=r.GetInt64(0),ActiveCards=r.GetInt64(1),TotalIssued=r.GetDecimal(2),TotalOutstanding=r.GetDecimal(3),TotalRedeemed=r.GetDecimal(4)}; return new(); }
    }

    // =========================================================================
    // Expense Service
    // =========================================================================
    public class RestaurantExpenseService : IRestaurantExpenseService
    {
        private readonly string _cs; public RestaurantExpenseService(string cs) => _cs = cs;
        static NpgsqlParameter TP(string n, string v) => new(n, System.Data.DbType.String) { Value = v };

        public async Task<List<ExpenseCategoryModel>> ListCategoriesAsync(string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_expensecategory_list(p_farmid=>@F::text)",c); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); var l=new List<ExpenseCategoryModel>(); while(await r.ReadAsync()) l.Add(new(){ExpenseCategoryId=r.GetInt32(0),FarmId=r.GetString(1),Name=r.GetString(2),IsActive=r.GetBoolean(3),SortOrder=r.GetInt32(4)}); return l; }

        public async Task<int> InsertCategoryAsync(string farmId, string name) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_expensecategory_insert(p_farmid=>@F::text,p_name=>@N::text)",c); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@N",name); await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync()); }

        public async Task DeleteCategoryAsync(int id, string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_expensecategory_delete(p_id=>@I::int,p_farmid=>@F::text)",c); cmd.Parameters.AddWithValue("@I",id); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }

        public async Task<List<RestaurantExpenseModel>> ListExpensesAsync(string farmId, DateTime? from = null, DateTime? to = null) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_expense_list(p_farmid=>@F::text,p_from=>@A::date,p_to=>@B::date)",c); cmd.Parameters.Add(TP("@F",farmId)); cmd.Parameters.AddWithValue("@A",(object?)from??DBNull.Value); cmd.Parameters.AddWithValue("@B",(object?)to??DBNull.Value); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); var l=new List<RestaurantExpenseModel>(); while(await r.ReadAsync()) l.Add(new(){ExpenseId=r.GetInt32(0),FarmId=r.GetString(1),ExpenseDate=r.GetDateTime(2),CategoryId=r.IsDBNull(3)?null:r.GetInt32(3),CategoryName=r.IsDBNull(4)?null:r.GetString(4),Description=r.GetString(5),Amount=r.GetDecimal(6),PaymentMethod=r.GetString(7),SupplierName=r.IsDBNull(8)?null:r.GetString(8),ReceiptRef=r.IsDBNull(9)?null:r.GetString(9),Status=r.GetString(10),CreatedBy=r.IsDBNull(11)?null:r.GetString(11),CreatedAt=r.GetDateTime(12)}); return l; }

        public async Task<int> InsertExpenseAsync(RestaurantExpenseModel m) {
            using var c=new NpgsqlConnection(_cs);
            using var cmd=new NpgsqlCommand(
                "INSERT INTO RestaurantExpenses (FarmId, ExpenseDate, CategoryId, CategoryName, Description, Amount, PaymentMethod, SupplierName, ReceiptRef, CreatedBy) " +
                "VALUES (@FarmId, @ExpenseDate, @CategoryId, @CategoryName, @Description, @Amount, @PaymentMethod, @SupplierName, @ReceiptRef, @CreatedBy) " +
                "RETURNING ExpenseId", c);
            cmd.Parameters.Add(TP("@FarmId",m.FarmId));
            cmd.Parameters.AddWithValue("@ExpenseDate",m.ExpenseDate);
            cmd.Parameters.AddWithValue("@CategoryId",(object?)m.CategoryId??DBNull.Value);
            cmd.Parameters.AddWithValue("@CategoryName",(object?)m.CategoryName??DBNull.Value);
            cmd.Parameters.AddWithValue("@Description",m.Description);
            cmd.Parameters.AddWithValue("@Amount",m.Amount);
            cmd.Parameters.AddWithValue("@PaymentMethod",m.PaymentMethod);
            cmd.Parameters.AddWithValue("@SupplierName",(object?)m.SupplierName??DBNull.Value);
            cmd.Parameters.AddWithValue("@ReceiptRef",(object?)m.ReceiptRef??DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy",(object?)m.CreatedBy??DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteExpenseAsync(int id, string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_expense_delete(p_id=>@I::int,p_farmid=>@F::text)",c); cmd.Parameters.AddWithValue("@I",id); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }

        public async Task<ReceiptTemplateModel?> GetReceiptTemplateAsync(string farmId) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT * FROM sprestaurant_receipttemplate_get(p_farmid=>@F::text)",c); cmd.Parameters.Add(TP("@F",farmId)); await c.OpenAsync(); using var r=await cmd.ExecuteReaderAsync(); if(!await r.ReadAsync()) return null; return new(){ReceiptTemplateId=r.GetInt32(0),FarmId=r.GetString(1),HeaderText=r.IsDBNull(2)?null:r.GetString(2),FooterText=r.IsDBNull(3)?null:r.GetString(3),ShowLogo=r.GetBoolean(4),ShowTaxDetails=r.GetBoolean(5),ShowServerNames=r.GetBoolean(6),ThanksMessage=r.GetString(7),CreatedAt=r.GetDateTime(8),UpdatedAt=r.IsDBNull(9)?null:r.GetDateTime(9)}; }

        public async Task UpsertReceiptTemplateAsync(ReceiptTemplateModel m) { using var c=new NpgsqlConnection(_cs); using var cmd=new NpgsqlCommand("SELECT sprestaurant_receipttemplate_upsert(p_farmid=>@F::text,p_headertext=>@a::text,p_footertext=>@b::text,p_showlogo=>@c::boolean,p_showtaxdetails=>@d::boolean,p_showservernames=>@e::boolean,p_thanksmessage=>@f::text)",c); cmd.Parameters.Add(TP("@F",m.FarmId)); cmd.Parameters.AddWithValue("@a",(object?)m.HeaderText??DBNull.Value); cmd.Parameters.AddWithValue("@b",(object?)m.FooterText??DBNull.Value); cmd.Parameters.AddWithValue("@c",m.ShowLogo); cmd.Parameters.AddWithValue("@d",m.ShowTaxDetails); cmd.Parameters.AddWithValue("@e",m.ShowServerNames); cmd.Parameters.AddWithValue("@f",m.ThanksMessage); await c.OpenAsync(); await cmd.ExecuteNonQueryAsync(); }
    }

    // =========================================================================
    // Restaurant Staff Service
    // =========================================================================
    public class RestaurantStaffService : IRestaurantStaffService
    {
        private readonly string _cs; public RestaurantStaffService(string cs) => _cs = cs;

        public async Task<List<RestaurantStaffModel>> ListAsync(string farmId, string? role = null)
        {
            var list = new List<RestaurantStaffModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_staff_getall(p_farmid => @FarmId::text, p_role => @Role::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Role", (object?)role ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadStaff(r));
            return list;
        }

        public async Task<RestaurantStaffModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_staff_getbyid(p_id => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadStaff(r) : null;
        }

        public async Task<int> InsertAsync(RestaurantStaffModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_staff_insert(p_farmid=>@FarmId::text,p_firstname=>@FirstName::text,p_lastname=>@LastName::text,p_phone=>@Phone::text,p_email=>@Email::text,p_role=>@Role::text,p_salarytype=>@SalaryType::text,p_basepay=>@BasePay::numeric,p_isactive=>@IsActive::boolean,p_notes=>@Notes::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName", m.LastName);
            cmd.Parameters.AddWithValue("@Phone", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Role", m.Role);
            cmd.Parameters.AddWithValue("@SalaryType", m.SalaryType);
            cmd.Parameters.AddWithValue("@BasePay", m.BasePay);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(RestaurantStaffModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_staff_update(p_id=>@Id::int,p_farmid=>@FarmId::text,p_firstname=>@FirstName::text,p_lastname=>@LastName::text,p_phone=>@Phone::text,p_email=>@Email::text,p_role=>@Role::text,p_salarytype=>@SalaryType::text,p_basepay=>@BasePay::numeric,p_isactive=>@IsActive::boolean,p_notes=>@Notes::text)", c);
            cmd.Parameters.AddWithValue("@Id", m.RestaurantStaffId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName", m.LastName);
            cmd.Parameters.AddWithValue("@Phone", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Role", m.Role);
            cmd.Parameters.AddWithValue("@SalaryType", m.SalaryType);
            cmd.Parameters.AddWithValue("@BasePay", m.BasePay);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_staff_delete(p_id=>@Id::int,p_farmid=>@FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static RestaurantStaffModel ReadStaff(NpgsqlDataReader r) => new()
        {
            RestaurantStaffId = r.GetInt32(0), FarmId = r.GetString(1),
            FirstName = r.GetString(2), LastName = r.IsDBNull(3) ? "" : r.GetString(3),
            Phone = r.IsDBNull(4) ? null : r.GetString(4), Email = r.IsDBNull(5) ? null : r.GetString(5),
            Role = r.GetString(6), SalaryType = r.GetString(7), BasePay = r.GetDecimal(8),
            IsActive = r.GetBoolean(9), Notes = r.IsDBNull(10) ? null : r.GetString(10),
            CreatedAt = r.GetDateTime(11), UpdatedAt = r.IsDBNull(12) ? null : r.GetDateTime(12),
        };
    }
}
