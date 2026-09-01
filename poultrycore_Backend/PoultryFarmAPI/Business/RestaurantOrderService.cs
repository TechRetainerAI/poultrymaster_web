using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantOrderService : IRestaurantOrderService
    {
        private readonly string _cs;
        public RestaurantOrderService(string cs) => _cs = cs;

        // =====================================================================
        // ORDERS
        // =====================================================================

        public async Task<(int orderId, string orderNumber)> CreateOrderAsync(RestaurantOrderCreateRequest req)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_order_insert(" +
                "p_farmid => @FarmId::text, p_ordertype => @OrderType::text, p_tableid => @TableId::int, " +
                "p_tablenumber => @TableNumber::text, p_customerid => @CustomerId::int, " +
                "p_customername => @CustomerName::text, p_customerphone => @CustomerPhone::text, " +
                "p_covers => @Covers::int, p_notes => @Notes::text, " +
                "p_createdby => @CreatedBy::text, p_servedby => @ServedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@OrderType", req.OrderType);
            cmd.Parameters.AddWithValue("@TableId", (object?)req.TableId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TableNumber", (object?)req.TableNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CustomerId", (object?)req.CustomerId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CustomerName", (object?)req.CustomerName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CustomerPhone", (object?)req.CustomerPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Covers", req.Covers);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ServedBy", (object?)req.ServedBy ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return (r.GetInt32(r.GetOrdinal("orderid")), r.GetString(r.GetOrdinal("ordernumber")));
        }

        public async Task<List<RestaurantOrderModel>> ListOrdersAsync(string farmId, string? status = null, string? orderType = null, DateTime? fromDate = null, DateTime? toDate = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_order_list(p_farmid => @FarmId::text, p_status => @Status::text, " +
                "p_ordertype => @OrderType::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OrderType", (object?)orderType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantOrderModel>();
            while (await r.ReadAsync()) list.Add(ReadOrder(r, hasItemCount: true));
            return list;
        }

        public async Task<RestaurantOrderModel?> GetOrderAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_order_get(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadOrder(r, hasItemCount: false) : null;
        }

        public async Task UpdateOrderStatusAsync(int id, string farmId, string status, string? reason = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_order_update_status(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_status => @Status::text, p_reason => @Reason::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", status);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RecalcOrderAsync(int orderId, string farmId, decimal taxRate, decimal serviceChargeRate)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_order_recalc(p_orderid => @OrderId::int, p_farmid => @FarmId::text, " +
                "p_taxrate => @TaxRate::numeric, p_servicechargerate => @ServiceChargeRate::numeric)", conn);
            cmd.Parameters.AddWithValue("@OrderId", orderId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@TaxRate", taxRate);
            cmd.Parameters.AddWithValue("@ServiceChargeRate", serviceChargeRate);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static RestaurantOrderModel ReadOrder(NpgsqlDataReader r, bool hasItemCount) => new()
        {
            OrderId             = r.GetInt32(r.GetOrdinal("orderid")),
            FarmId              = r.GetString(r.GetOrdinal("farmid")),
            OrderNumber         = r.GetString(r.GetOrdinal("ordernumber")),
            OrderType           = r.GetString(r.GetOrdinal("ordertype")),
            Status              = r.GetString(r.GetOrdinal("status")),
            TableId             = r.IsDBNull(r.GetOrdinal("tableid")) ? null : r.GetInt32(r.GetOrdinal("tableid")),
            TableNumber         = r.IsDBNull(r.GetOrdinal("tablenumber")) ? null : r.GetString(r.GetOrdinal("tablenumber")),
            CustomerId          = r.IsDBNull(r.GetOrdinal("customerid")) ? null : r.GetInt32(r.GetOrdinal("customerid")),
            CustomerName        = r.IsDBNull(r.GetOrdinal("customername")) ? null : r.GetString(r.GetOrdinal("customername")),
            CustomerPhone       = r.IsDBNull(r.GetOrdinal("customerphone")) ? null : r.GetString(r.GetOrdinal("customerphone")),
            Covers              = r.GetInt32(r.GetOrdinal("covers")),
            Subtotal            = r.GetDecimal(r.GetOrdinal("subtotal")),
            DiscountAmount      = r.GetDecimal(r.GetOrdinal("discountamount")),
            TaxAmount           = r.GetDecimal(r.GetOrdinal("taxamount")),
            ServiceChargeAmount = r.GetDecimal(r.GetOrdinal("servicechargeamount")),
            TotalAmount         = r.GetDecimal(r.GetOrdinal("totalamount")),
            PaidAmount          = r.GetDecimal(r.GetOrdinal("paidamount")),
            PaymentStatus       = r.GetString(r.GetOrdinal("paymentstatus")),
            Notes               = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
            CreatedBy           = r.IsDBNull(r.GetOrdinal("createdby")) ? null : r.GetString(r.GetOrdinal("createdby")),
            ServedBy            = r.IsDBNull(r.GetOrdinal("servedby")) ? null : r.GetString(r.GetOrdinal("servedby")),
            CancelReason        = r.IsDBNull(r.GetOrdinal("cancelreason")) ? null : r.GetString(r.GetOrdinal("cancelreason")),
            RefundReason        = r.IsDBNull(r.GetOrdinal("refundreason")) ? null : r.GetString(r.GetOrdinal("refundreason")),
            CreatedAt           = r.GetDateTime(r.GetOrdinal("createdat")),
            UpdatedAt           = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            CompletedAt         = r.IsDBNull(r.GetOrdinal("completedat")) ? null : r.GetDateTime(r.GetOrdinal("completedat")),
            ItemCount           = hasItemCount ? r.GetInt64(r.GetOrdinal("itemcount")) : 0,
        };

        // =====================================================================
        // ORDER ITEMS
        // =====================================================================

        public async Task<int> AddOrderItemAsync(RestaurantOrderItemCreateRequest req)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            // Insert item
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_orderitem_insert(p_farmid => @FarmId::text, p_orderid => @OrderId::int, " +
                "p_menuitemid => @MenuItemId::int, p_comboid => @ComboId::int, p_itemname => @ItemName::text, " +
                "p_quantity => @Quantity::int, p_unitprice => @UnitPrice::numeric, " +
                "p_notes => @Notes::text, p_seatnumber => @SeatNumber::int, p_kdsstation => @KdsStation::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@OrderId", req.OrderId);
            cmd.Parameters.AddWithValue("@MenuItemId", (object?)req.MenuItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ComboId", (object?)req.ComboId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemName", req.ItemName);
            cmd.Parameters.AddWithValue("@Quantity", req.Quantity);
            cmd.Parameters.AddWithValue("@UnitPrice", req.UnitPrice);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SeatNumber", (object?)req.SeatNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@KdsStation", (object?)req.KdsStation ?? DBNull.Value);
            var itemId = Convert.ToInt32(await cmd.ExecuteScalarAsync());

            // Insert modifiers if any
            if (req.Modifiers != null)
            {
                foreach (var mod in req.Modifiers)
                {
                    using var mcmd = new NpgsqlCommand(
                        "SELECT sprestaurant_orderitemmod_insert(p_farmid => @FarmId::text, p_orderitemid => @OrderItemId::int, " +
                        "p_modifierid => @ModifierId::int, p_modifiername => @ModifierName::text, " +
                        "p_priceadjustment => @PriceAdjustment::numeric, p_quantity => @Quantity::int)", conn);
                    mcmd.Parameters.AddWithValue("@FarmId", req.FarmId);
                    mcmd.Parameters.AddWithValue("@OrderItemId", itemId);
                    mcmd.Parameters.AddWithValue("@ModifierId", (object?)mod.ModifierId ?? DBNull.Value);
                    mcmd.Parameters.AddWithValue("@ModifierName", mod.ModifierName);
                    mcmd.Parameters.AddWithValue("@PriceAdjustment", mod.PriceAdjustment);
                    mcmd.Parameters.AddWithValue("@Quantity", mod.Quantity);
                    await mcmd.ExecuteScalarAsync();
                }
            }

            return itemId;
        }

        public async Task<List<RestaurantOrderItemModel>> ListOrderItemsAsync(int orderId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_orderitem_list(p_orderid => @OrderId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@OrderId", orderId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantOrderItemModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                OrderItemId    = r.GetInt32(r.GetOrdinal("orderitemid")),
                FarmId         = r.GetString(r.GetOrdinal("farmid")),
                OrderId        = r.GetInt32(r.GetOrdinal("orderid")),
                MenuItemId     = r.IsDBNull(r.GetOrdinal("menuitemid")) ? null : r.GetInt32(r.GetOrdinal("menuitemid")),
                ComboId        = r.IsDBNull(r.GetOrdinal("comboid")) ? null : r.GetInt32(r.GetOrdinal("comboid")),
                ItemName       = r.GetString(r.GetOrdinal("itemname")),
                Quantity       = r.GetInt32(r.GetOrdinal("quantity")),
                UnitPrice      = r.GetDecimal(r.GetOrdinal("unitprice")),
                ModifierTotal  = r.GetDecimal(r.GetOrdinal("modifiertotal")),
                LineTotal      = r.GetDecimal(r.GetOrdinal("linetotal")),
                Notes          = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                Status         = r.GetString(r.GetOrdinal("status")),
                SeatNumber     = r.IsDBNull(r.GetOrdinal("seatnumber")) ? null : r.GetInt32(r.GetOrdinal("seatnumber")),
                KdsStation     = r.IsDBNull(r.GetOrdinal("kdsstation")) ? null : r.GetString(r.GetOrdinal("kdsstation")),
                SentToKitchenAt = r.IsDBNull(r.GetOrdinal("senttoktchenat")) ? null : r.GetDateTime(r.GetOrdinal("senttoktchenat")),
                PrepStartedAt  = r.IsDBNull(r.GetOrdinal("prepstartedat")) ? null : r.GetDateTime(r.GetOrdinal("prepstartedat")),
                ReadyAt        = r.IsDBNull(r.GetOrdinal("readyat")) ? null : r.GetDateTime(r.GetOrdinal("readyat")),
                CreatedAt      = r.GetDateTime(r.GetOrdinal("createdat")),
            });
            return list;
        }

        public async Task UpdateOrderItemStatusAsync(int id, string farmId, string status)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_orderitem_update_status(p_id => @Id::int, p_farmid => @FarmId::text, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", status);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelOrderItemAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_orderitem_cancel(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // ORDER ITEM MODIFIERS
        // =====================================================================

        public async Task<List<RestaurantOrderItemModifierModel>> ListOrderItemModifiersAsync(int orderItemId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_orderitemmod_list(p_orderitemid => @OrderItemId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@OrderItemId", orderItemId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantOrderItemModifierModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                OrderItemModifierId = r.GetInt32(r.GetOrdinal("orderitemmodifierid")),
                FarmId              = r.GetString(r.GetOrdinal("farmid")),
                OrderItemId         = r.GetInt32(r.GetOrdinal("orderitemid")),
                ModifierId          = r.IsDBNull(r.GetOrdinal("modifierid")) ? null : r.GetInt32(r.GetOrdinal("modifierid")),
                ModifierName        = r.GetString(r.GetOrdinal("modifiername")),
                PriceAdjustment     = r.GetDecimal(r.GetOrdinal("priceadjustment")),
                Quantity            = r.GetInt32(r.GetOrdinal("quantity")),
            });
            return list;
        }

        // =====================================================================
        // ORDER PAYMENTS
        // =====================================================================

        public async Task<int> AddPaymentAsync(string farmId, int orderId, string paymentMethod, decimal amount, decimal tipAmount, string? reference, string? processedBy)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_orderpayment_insert(p_farmid => @FarmId::text, p_orderid => @OrderId::int, " +
                "p_paymentmethod => @PaymentMethod::text, p_amount => @Amount::numeric, " +
                "p_tipamount => @TipAmount::numeric, p_reference => @Reference::text, p_processedby => @ProcessedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@OrderId", orderId);
            cmd.Parameters.AddWithValue("@PaymentMethod", paymentMethod);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@TipAmount", tipAmount);
            cmd.Parameters.AddWithValue("@Reference", (object?)reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProcessedBy", (object?)processedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<RestaurantOrderPaymentModel>> ListPaymentsAsync(int orderId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_orderpayment_list(p_orderid => @OrderId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@OrderId", orderId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantOrderPaymentModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                OrderPaymentId = r.GetInt32(r.GetOrdinal("orderpaymentid")),
                FarmId         = r.GetString(r.GetOrdinal("farmid")),
                OrderId        = r.GetInt32(r.GetOrdinal("orderid")),
                PaymentMethod  = r.GetString(r.GetOrdinal("paymentmethod")),
                Amount         = r.GetDecimal(r.GetOrdinal("amount")),
                TipAmount      = r.GetDecimal(r.GetOrdinal("tipamount")),
                Reference      = r.IsDBNull(r.GetOrdinal("reference")) ? null : r.GetString(r.GetOrdinal("reference")),
                Status         = r.GetString(r.GetOrdinal("status")),
                ProcessedBy    = r.IsDBNull(r.GetOrdinal("processedby")) ? null : r.GetString(r.GetOrdinal("processedby")),
                CreatedAt      = r.GetDateTime(r.GetOrdinal("createdat")),
            });
            return list;
        }

        // =====================================================================
        // DISCOUNTS
        // =====================================================================

        public async Task<List<RestaurantDiscountModel>> ListDiscountsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_discount_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantDiscountModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                DiscountId       = r.GetInt32(r.GetOrdinal("discountid")),
                FarmId           = r.GetString(r.GetOrdinal("farmid")),
                Name             = r.GetString(r.GetOrdinal("name")),
                DiscountType     = r.GetString(r.GetOrdinal("discounttype")),
                Value            = r.GetDecimal(r.GetOrdinal("value")),
                CouponCode       = r.IsDBNull(r.GetOrdinal("couponcode")) ? null : r.GetString(r.GetOrdinal("couponcode")),
                IsAutoApply      = r.GetBoolean(r.GetOrdinal("isautoapply")),
                MinOrderAmount   = r.GetDecimal(r.GetOrdinal("minorderamount")),
                MaxDiscountAmount = r.IsDBNull(r.GetOrdinal("maxdiscountamount")) ? null : r.GetDecimal(r.GetOrdinal("maxdiscountamount")),
                StartDate        = r.IsDBNull(r.GetOrdinal("startdate")) ? null : r.GetDateTime(r.GetOrdinal("startdate")),
                EndDate          = r.IsDBNull(r.GetOrdinal("enddate")) ? null : r.GetDateTime(r.GetOrdinal("enddate")),
                IsActive         = r.GetBoolean(r.GetOrdinal("isactive")),
                CreatedAt        = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt        = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            });
            return list;
        }

        public async Task<int> InsertDiscountAsync(RestaurantDiscountModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_discount_insert(p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_discounttype => @DiscountType::text, p_value => @Value::numeric, p_couponcode => @CouponCode::text, " +
                "p_isautoapply => @IsAutoApply::boolean, p_minorderamount => @MinOrderAmount::numeric, " +
                "p_maxdiscountamount => @MaxDiscountAmount::numeric, p_startdate => @StartDate::timestamp, " +
                "p_enddate => @EndDate::timestamp, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@DiscountType", m.DiscountType);
            cmd.Parameters.AddWithValue("@Value", m.Value);
            cmd.Parameters.AddWithValue("@CouponCode", (object?)m.CouponCode ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsAutoApply", m.IsAutoApply);
            cmd.Parameters.AddWithValue("@MinOrderAmount", m.MinOrderAmount);
            cmd.Parameters.AddWithValue("@MaxDiscountAmount", (object?)m.MaxDiscountAmount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StartDate", (object?)m.StartDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EndDate", (object?)m.EndDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateDiscountAsync(RestaurantDiscountModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_discount_update(p_id => @Id::int, p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_discounttype => @DiscountType::text, p_value => @Value::numeric, p_couponcode => @CouponCode::text, " +
                "p_isautoapply => @IsAutoApply::boolean, p_minorderamount => @MinOrderAmount::numeric, " +
                "p_maxdiscountamount => @MaxDiscountAmount::numeric, p_startdate => @StartDate::timestamp, " +
                "p_enddate => @EndDate::timestamp, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", m.DiscountId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@DiscountType", m.DiscountType);
            cmd.Parameters.AddWithValue("@Value", m.Value);
            cmd.Parameters.AddWithValue("@CouponCode", (object?)m.CouponCode ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsAutoApply", m.IsAutoApply);
            cmd.Parameters.AddWithValue("@MinOrderAmount", m.MinOrderAmount);
            cmd.Parameters.AddWithValue("@MaxDiscountAmount", (object?)m.MaxDiscountAmount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StartDate", (object?)m.StartDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EndDate", (object?)m.EndDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteDiscountAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_discount_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ---- Order Discounts ----

        public async Task<int> ApplyDiscountToOrderAsync(string farmId, int orderId, int? discountId, string discountName, string discountType, decimal value, decimal appliedAmount)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_orderdiscount_apply(p_farmid => @FarmId::text, p_orderid => @OrderId::int, " +
                "p_discountid => @DiscountId::int, p_discountname => @DiscountName::text, " +
                "p_discounttype => @DiscountType::text, p_value => @Value::numeric, p_appliedamount => @AppliedAmount::numeric)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@OrderId", orderId);
            cmd.Parameters.AddWithValue("@DiscountId", (object?)discountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DiscountName", discountName);
            cmd.Parameters.AddWithValue("@DiscountType", discountType);
            cmd.Parameters.AddWithValue("@Value", value);
            cmd.Parameters.AddWithValue("@AppliedAmount", appliedAmount);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task RemoveDiscountFromOrderAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_orderdiscount_remove(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<RestaurantOrderDiscountModel>> ListOrderDiscountsAsync(int orderId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_orderdiscount_list(p_orderid => @OrderId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@OrderId", orderId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantOrderDiscountModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                OrderDiscountId = r.GetInt32(r.GetOrdinal("orderdiscountid")),
                FarmId          = r.GetString(r.GetOrdinal("farmid")),
                OrderId         = r.GetInt32(r.GetOrdinal("orderid")),
                DiscountId      = r.IsDBNull(r.GetOrdinal("discountid")) ? null : r.GetInt32(r.GetOrdinal("discountid")),
                DiscountName    = r.GetString(r.GetOrdinal("discountname")),
                DiscountType    = r.GetString(r.GetOrdinal("discounttype")),
                Value           = r.GetDecimal(r.GetOrdinal("value")),
                AppliedAmount   = r.GetDecimal(r.GetOrdinal("appliedamount")),
                CreatedAt       = r.GetDateTime(r.GetOrdinal("createdat")),
            });
            return list;
        }
    }
}
