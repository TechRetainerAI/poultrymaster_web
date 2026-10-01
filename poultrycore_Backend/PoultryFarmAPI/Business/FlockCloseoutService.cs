using Npgsql;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public interface IFlockCloseoutService
    {
        Task<FlockCloseoutContext?> GetContextAsync(int flockId, string userId, string farmId);
        Task<FlockCloseoutResult> CloseAsync(int flockId, FlockCloseoutRequest request);
        Task<FlockReopenResult> ReopenAsync(int flockId, FlockReopenRequest request);
        Task<List<FlockCloseoutRecord>> GetHistoryAsync(int flockId, string farmId);
        Task<List<FlockLifetimeSummary>> GetLifetimeSummaryAsync(string farmId, int? flockId, bool closedOnly);
    }

    /// <summary>
    /// A closed business-rule refusal from the database (RAISE ... ERRCODE
    /// P0001/P0002). Its message is written for the person, so it is shown as is.
    /// </summary>
    public class FlockCloseoutRefusedException : Exception
    {
        public FlockCloseoutRefusedException(string message) : base(message) { }
    }

    /// <summary>
    /// End-of-flock closeout (migration 332).
    ///
    /// <para><b>Sales are the ordinary sales.</b> A spent-layer sale is created
    /// with <see cref="ISaleService.Insert"/> -- the method the Sales page calls --
    /// so it gets the same customer resolution, cash-account stamping, bird-ledger
    /// row and receivable as any other sale. Payments go through
    /// <see cref="IPoultryPaymentService.Record"/>, the Pay dialog's method. This
    /// class writes no sale or payment SQL of its own.</para>
    ///
    /// <para><b>Ordering.</b> SaleService owns its own connections, so the sales
    /// cannot share the closeout's transaction. The order is chosen so every
    /// failure leaves a clean state:</para>
    /// <list type="number">
    /// <item>validate everything (<see cref="FlockCloseoutValidator"/>) -- nothing written yet;</item>
    /// <item>create the sales UNPAID (the account is still stamped on the row);</item>
    /// <item>spflock_closeout links them and closes the flock in one transaction;
    ///   if it refuses, the unpaid sales are deleted through SaleService.Delete,
    ///   which reverses their stock -- there is no money to reverse yet;</item>
    /// <item>only then record the payments. A payment that fails leaves that sale
    ///   on credit and is reported as a warning: the flock IS closed, and the
    ///   payment can be taken on the Sales page.</item>
    /// </list>
    /// </summary>
    public class FlockCloseoutService : IFlockCloseoutService
    {
        private readonly string _connectionString;
        private readonly IBirdFlockService _flocks;
        private readonly IHouseService _houses;
        private readonly ISaleService _sales;
        private readonly IPoultryPaymentService _payments;

        public FlockCloseoutService(
            string connectionString,
            IBirdFlockService flocks,
            IHouseService houses,
            ISaleService sales,
            IPoultryPaymentService payments)
        {
            _connectionString = connectionString;
            _flocks = flocks;
            _houses = houses;
            _sales = sales;
            _payments = payments;
        }

        // ------------------------------------------------------------------ reads

        public async Task<FlockCloseoutContext?> GetContextAsync(int flockId, string userId, string farmId)
        {
            var flock = _flocks.GetFlockById(flockId, userId, farmId);
            if (flock == null) return null;

            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            var position = await ReadPositionAsync(conn, farmId, flockId)
                           ?? new FlockBirdPosition { FlockId = flockId };

            DateTime businessDate;
            using (var cmd = new NpgsqlCommand("SELECT fncompany_businessdate(p_farmid => @FarmId::text)", conn))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                businessDate = Convert.ToDateTime(await cmd.ExecuteScalarAsync());
            }

            string birdProduct = "Birds";
            using (var cmd = new NpgsqlCommand(
                "SELECT name FROM poultryproducts WHERE farmid = @FarmId AND isbirdproduct = TRUE ORDER BY poultryproductid LIMIT 1", conn))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                var name = await cmd.ExecuteScalarAsync() as string;
                // Only a name the stock side will recognise as birds; anything
                // else would be a sale the closeout then refuses to link.
                if (!string.IsNullOrWhiteSpace(name) && FlockCloseoutValidator.IsBirdSaleProduct(name))
                    birdProduct = name.Trim();
            }

            string? houseName = null;
            if (flock.HouseId.HasValue)
                houseName = _houses.GetAll(userId, farmId).FirstOrDefault(h => h.HouseId == flock.HouseId)?.HouseName;

            var earliest = flock.StartDate.Date;
            if (position.LastCountDate.HasValue && position.LastCountDate.Value.Date > earliest)
                earliest = position.LastCountDate.Value.Date;

            string? ineligible = null;
            if (!flock.HasArrived)
                ineligible = "This flock's birds have not arrived yet, so there is nothing to close out. Delete the flock instead if it was never placed.";

            return new FlockCloseoutContext
            {
                Flock = flock,
                Position = position,
                IsClosed = flock.ClosedDate.HasValue,
                IneligibleReason = ineligible,
                HouseName = houseName,
                BusinessDate = businessDate.Date,
                EarliestCloseDate = earliest,
                BirdProductName = birdProduct,
            };
        }

        public async Task<List<FlockCloseoutRecord>> GetHistoryAsync(int flockId, string farmId)
        {
            var list = new List<FlockCloseoutRecord>();
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM spflock_closeouthistory(p_farmid => @FarmId::text, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockId", flockId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var rec = new FlockCloseoutRecord
                {
                    CloseoutId = r.GetInt32(r.GetOrdinal("closeoutid")),
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    ClosedDate = r.GetDateTime(r.GetOrdinal("closeddate")),
                    Reason = r.GetString(r.GetOrdinal("reason")),
                    Notes = Str(r, "notes"),
                    ClosedBy = r.GetString(r.GetOrdinal("closedby")),
                    ClosedAt = r.GetDateTime(r.GetOrdinal("closedat")),
                    HouseId = Int(r, "houseid"),
                    HasOpeningPosition = r.GetBoolean(r.GetOrdinal("hasopeningposition")),
                    HistoryKnown = r.GetBoolean(r.GetOrdinal("historyknown")),
                    OriginallyPlaced = r.GetInt32(r.GetOrdinal("originallyplaced")),
                    OpeningMortality = r.GetInt32(r.GetOrdinal("openingmortality")),
                    OpeningSold = r.GetInt32(r.GetOrdinal("openingsold")),
                    OpeningCulled = r.GetInt32(r.GetOrdinal("openingculled")),
                    OpeningTransferred = r.GetInt32(r.GetOrdinal("openingtransferred")),
                    OpeningOther = r.GetInt32(r.GetOrdinal("openingother")),
                    OpeningLiveBirds = r.GetInt32(r.GetOrdinal("openinglivebirds")),
                    RecordedMortality = r.GetInt32(r.GetOrdinal("recordedmortality")),
                    Correction = r.GetInt32(r.GetOrdinal("correction")),
                    LastCountedBirds = r.GetInt32(r.GetOrdinal("lastcountedbirds")),
                    LastCountDate = Date(r, "lastcountdate"),
                    SoldBeforeCloseout = r.GetInt32(r.GetOrdinal("soldbeforecloseout")),
                    LiveBirdsAtCloseout = r.GetInt32(r.GetOrdinal("livebirdsatcloseout")),
                    DisposedSold = r.GetInt32(r.GetOrdinal("disposedsold")),
                    DisposedCulled = r.GetInt32(r.GetOrdinal("disposedculled")),
                    DisposedTransferred = r.GetInt32(r.GetOrdinal("disposedtransferred")),
                    ReopenedAt = Date(r, "reopenedat"),
                    ReopenedBy = Str(r, "reopenedby"),
                    ReopenReason = Str(r, "reopenreason"),
                };

                var json = Str(r, "dispositions");
                if (!string.IsNullOrWhiteSpace(json))
                {
                    rec.Dispositions = JsonSerializer.Deserialize<List<FlockCloseoutDisposition>>(
                        json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new();
                }
                list.Add(rec);
            }
            return list;
        }

        public async Task<List<FlockLifetimeSummary>> GetLifetimeSummaryAsync(string farmId, int? flockId, bool closedOnly)
        {
            var list = new List<FlockLifetimeSummary>();
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM fnflock_lifetimesummary(p_farmid => @FarmId::text, p_flockid => @FlockId::int, p_closedonly => @ClosedOnly::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockId", (object?)flockId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ClosedOnly", closedOnly);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new FlockLifetimeSummary
                {
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname") ?? string.Empty,
                    Breed = Str(r, "breed"),
                    Status = Str(r, "status") ?? string.Empty,
                    BatchId = Int(r, "batchid"),
                    BatchCode = Str(r, "batchcode"),
                    BatchName = Str(r, "batchname"),
                    SupplierId = Int(r, "supplierid"),
                    SupplierType = Str(r, "suppliertype"),
                    HouseId = Int(r, "houseid"),
                    HouseName = Str(r, "housename"),
                    StartDate = r.GetDateTime(r.GetOrdinal("startdate")),
                    ClosedDate = Date(r, "closeddate"),
                    DaysInProduction = r.GetInt32(r.GetOrdinal("daysinproduction")),
                    HasOpeningPosition = r.GetBoolean(r.GetOrdinal("hasopeningposition")),
                    HistoryKnown = r.GetBoolean(r.GetOrdinal("historyknown")),
                    OriginallyPlaced = r.GetInt32(r.GetOrdinal("originallyplaced")),
                    OpeningLiveBirds = r.GetInt32(r.GetOrdinal("openinglivebirds")),
                    OpeningMortality = r.GetInt32(r.GetOrdinal("openingmortality")),
                    RecordedMortality = r.GetInt32(r.GetOrdinal("recordedmortality")),
                    BirdsSold = r.GetInt32(r.GetOrdinal("birdssold")),
                    BirdsCulled = r.GetInt32(r.GetOrdinal("birdsculled")),
                    BirdsTransferred = r.GetInt32(r.GetOrdinal("birdstransferred")),
                    FinalBirds = r.GetInt32(r.GetOrdinal("finalbirds")),
                    TrackedMortalityRate = Dec(r, "trackedmortalityrate"),
                    LifetimeMortalityRate = Dec(r, "lifetimemortalityrate"),
                    TotalEggs = r.GetInt64(r.GetOrdinal("totaleggs")),
                    ProductionDays = r.GetInt32(r.GetOrdinal("productiondays")),
                    EggRevenue = Dec(r, "eggrevenue") ?? 0,
                    BirdSaleRevenue = Dec(r, "birdsalerevenue") ?? 0,
                    OtherRevenue = Dec(r, "otherrevenue") ?? 0,
                    TotalRevenue = Dec(r, "totalrevenue") ?? 0,
                    FeedConsumedKg = Dec(r, "feedconsumedkg") ?? 0,
                    FeedCost = Dec(r, "feedcost") ?? 0,
                    MedicationCost = Dec(r, "medicationcost") ?? 0,
                    BirdCost = Dec(r, "birdcost") ?? 0,
                    BirdCostRecorded = r.GetBoolean(r.GetOrdinal("birdcostrecorded")),
                    LaborCost = Dec(r, "laborcost") ?? 0,
                    OtherDirectCost = Dec(r, "otherdirectcost") ?? 0,
                    TotalCost = Dec(r, "totalcost") ?? 0,
                    Profit = Dec(r, "profit") ?? 0,
                    ProfitPerOriginalBird = Dec(r, "profitperoriginalbird"),
                    RevenuePerOriginalBird = Dec(r, "revenueperoriginalbird"),
                    FeedKgPerDozenEggs = Dec(r, "feedkgperdozeneggs"),
                });
            }
            return list;
        }

        // ------------------------------------------------------------------ close

        public async Task<FlockCloseoutResult> CloseAsync(int flockId, FlockCloseoutRequest request)
        {
            var context = await GetContextAsync(flockId, request.UserId, request.FarmId);
            if (context == null)
                return new FlockCloseoutResult { Success = false, Message = "Flock not found on this farm." };

            var errors = FlockCloseoutValidator.Validate(request, context);
            if (errors.Count > 0)
            {
                return new FlockCloseoutResult
                {
                    Success = false,
                    Errors = errors,
                    Message = errors.Count == 1 ? errors[0] : $"{errors.Count} things need attention before this flock can close.",
                };
            }

            var closedDate = request.ClosedDate.Date;
            var sales = request.Sales ?? new();
            var createdSaleIds = new List<int>();

            // 2. The sales, unpaid, through the ordinary sale workflow.
            try
            {
                foreach (var line in sales)
                {
                    var saleId = await _sales.Insert(new SaleModel
                    {
                        UserId = request.UserId,
                        FarmId = request.FarmId,
                        SaleDate = closedDate,
                        Product = context.BirdProductName,
                        Quantity = line.Quantity,
                        UnitPrice = line.UnitPrice,
                        TotalAmount = FlockCloseoutValidator.SaleTotal(line),
                        PaymentMethod = string.IsNullOrWhiteSpace(line.PaymentMethod) ? null : line.PaymentMethod!.Trim(),
                        CustomerId = line.CustomerId,
                        CustomerName = string.IsNullOrWhiteSpace(line.CustomerName) ? null : line.CustomerName!.Trim(),
                        FlockId = flockId,
                        SaleDescription = string.IsNullOrWhiteSpace(line.Description)
                            ? $"Flock closeout: {context.Flock.Name}"
                            : line.Description!.Trim(),
                        Paid = false,
                        PoultryCashAccountId = line.PoultryCashAccountId,
                    });
                    createdSaleIds.Add(saleId);
                }
            }
            catch (Exception ex)
            {
                await DeleteSalesAsync(createdSaleIds, request);
                return new FlockCloseoutResult
                {
                    Success = false,
                    Message = "The sale could not be recorded, so the flock was not closed. " + Unwrap(ex),
                };
            }

            // 3. Link and close, in one transaction.
            var dispositions = new List<object>();
            for (var i = 0; i < sales.Count; i++)
                dispositions.Add(new { disposition = "Sale", quantity = sales[i].Quantity, saleId = createdSaleIds[i] });
            foreach (var c in request.Culls ?? new())
                dispositions.Add(new { disposition = "Cull", quantity = c.Quantity, notes = c.Notes });
            foreach (var t in request.Transfers ?? new())
                dispositions.Add(new { disposition = "Transfer", quantity = t.Quantity, destination = t.Destination, notes = t.Notes });

            int closeoutId;
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                using var cmd = new NpgsqlCommand(
                    "SELECT spflock_closeout(p_farmid => @FarmId::text, p_flockid => @FlockId::int, p_closeddate => @ClosedDate::date, " +
                    "p_reason => @Reason::text, p_notes => @Notes::text, p_closedby => @ClosedBy::text, p_dispositions => @Dispositions::jsonb)", conn);
                cmd.Parameters.AddWithValue("@FarmId", request.FarmId);
                cmd.Parameters.AddWithValue("@FlockId", flockId);
                cmd.Parameters.AddWithValue("@ClosedDate", closedDate);
                cmd.Parameters.AddWithValue("@Reason", request.Reason.Trim());
                cmd.Parameters.AddWithValue("@Notes", (object?)request.Notes ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ClosedBy", request.UserId);
                // camelCase keys: the SQL reads them with quoted identifiers.
                cmd.Parameters.AddWithValue("@Dispositions", JsonSerializer.Serialize(dispositions));
                closeoutId = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            }
            catch (Exception ex)
            {
                await DeleteSalesAsync(createdSaleIds, request);
                return new FlockCloseoutResult
                {
                    Success = false,
                    Message = ex is PostgresException pg && pg.SqlState is "P0001" or "P0002"
                        ? pg.MessageText
                        : "The flock could not be closed. " + Unwrap(ex),
                };
            }

            // 4. The money, now that the closeout stands.
            var warnings = new List<string>();
            for (var i = 0; i < sales.Count; i++)
            {
                var line = sales[i];
                var terms = FlockCloseoutValidator.PaymentTerms.First(t =>
                    string.Equals(t, line.PaymentTerms, StringComparison.OrdinalIgnoreCase));
                if (terms == "Credit") continue;

                var amount = terms == "Paid" ? FlockCloseoutValidator.SaleTotal(line) : line.AmountPaid ?? 0;
                if (amount <= 0) continue;

                try
                {
                    await _payments.Record(new PoultryPaymentModel
                    {
                        FarmId = request.FarmId,
                        SaleId = createdSaleIds[i],
                        Amount = amount,
                        PaymentMethod = line.PaymentMethod,
                        PaymentDate = closedDate,
                        Note = terms == "Paid" ? "Paid at point of sale (flock closeout)" : "Part payment at flock closeout",
                        CreatedBy = request.UserId,
                    });
                }
                catch (Exception ex)
                {
                    warnings.Add($"Sale #{createdSaleIds[i]}: the payment of {amount:N2} could not be recorded, so the sale is on credit. Record it from the Sales page. ({Unwrap(ex)})");
                }
            }

            return new FlockCloseoutResult
            {
                Success = true,
                CloseoutId = closeoutId,
                SaleIds = createdSaleIds,
                ReleasedHouseId = context.Flock.HouseId,
                ReleasedHouseName = context.HouseName,
                Warnings = warnings,
                Message = context.HouseName != null
                    ? $"{context.Flock.Name} is closed and {context.HouseName} is free for a new flock."
                    : $"{context.Flock.Name} is closed.",
            };
        }

        // ----------------------------------------------------------------- reopen

        public async Task<FlockReopenResult> ReopenAsync(int flockId, FlockReopenRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.Reason))
                return new FlockReopenResult { Success = false, Message = "A reason is required to reopen a flock." };

            var flock = _flocks.GetFlockById(flockId, request.UserId, request.FarmId);
            if (flock == null) return new FlockReopenResult { Success = false, Message = "Flock not found on this farm." };
            if (!flock.ClosedDate.HasValue) return new FlockReopenResult { Success = false, Message = "This flock is not closed." };

            int closeoutId;
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                using var cmd = new NpgsqlCommand(
                    "SELECT spflock_reopen(p_farmid => @FarmId::text, p_flockid => @FlockId::int, p_reason => @Reason::text, p_reopenedby => @By::text, p_reversesales => @ReverseSales::boolean)", conn);
                cmd.Parameters.AddWithValue("@FarmId", request.FarmId);
                cmd.Parameters.AddWithValue("@FlockId", flockId);
                cmd.Parameters.AddWithValue("@Reason", request.Reason.Trim());
                cmd.Parameters.AddWithValue("@By", request.UserId);
                cmd.Parameters.AddWithValue("@ReverseSales", request.ReverseSales);
                var result = await cmd.ExecuteScalarAsync();
                closeoutId = result == null || result == DBNull.Value ? 0 : Convert.ToInt32(result);
            }
            catch (PostgresException pg) when (pg.SqlState is "P0001" or "P0002")
            {
                return new FlockReopenResult { Success = false, Message = pg.MessageText };
            }

            // The house may have been given to a new flock since. Capacity is a
            // planning figure (FarmSetupValidator's rule): it warns, never refuses
            // a fact -- these birds are already standing there.
            var warnings = new List<string>();
            if (flock.HouseId.HasValue)
            {
                var house = _houses.GetAll(request.UserId, request.FarmId).FirstOrDefault(h => h.HouseId == flock.HouseId);
                if (house?.Capacity is int capacity && capacity > 0)
                {
                    var occupied = _flocks.GetAllFlocks(request.UserId, request.FarmId)
                        .Where(f => f.Active && f.HouseId == flock.HouseId)
                        .Sum(f => f.Quantity);
                    if (occupied > capacity)
                        warnings.Add($"{house.HouseName} now holds {occupied:N0} birds' worth of flocks against a capacity of {capacity:N0}.");
                }
            }

            return new FlockReopenResult
            {
                Success = true,
                CloseoutId = closeoutId,
                Warnings = warnings,
                Message = request.ReverseSales
                    ? $"{flock.Name} is open again. Its closeout sales and their payments were reversed -- the money is back out of the cash account -- and its culls and transfers were undone."
                    : $"{flock.Name} is open again. Its culls and transfers were undone; its sales still stand and can now be edited on the Sales page.",
            };
        }

        // ---------------------------------------------------------------- helpers

        private static async Task<FlockBirdPosition?> ReadPositionAsync(NpgsqlConnection conn, string farmId, int flockId)
        {
            using var cmd = new NpgsqlCommand("SELECT * FROM fnflock_birdposition(p_farmid => @FarmId::text, p_flockid => @FlockId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockId", flockId);
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new FlockBirdPosition
            {
                FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                HasOpeningPosition = r.GetBoolean(r.GetOrdinal("hasopeningposition")),
                HistoryKnown = r.GetBoolean(r.GetOrdinal("historyknown")),
                OriginallyPlaced = r.GetInt32(r.GetOrdinal("originallyplaced")),
                OpeningMortality = r.GetInt32(r.GetOrdinal("openingmortality")),
                OpeningSold = r.GetInt32(r.GetOrdinal("openingsold")),
                OpeningCulled = r.GetInt32(r.GetOrdinal("openingculled")),
                OpeningTransferred = r.GetInt32(r.GetOrdinal("openingtransferred")),
                OpeningOther = r.GetInt32(r.GetOrdinal("openingother")),
                OpeningLiveBirds = r.GetInt32(r.GetOrdinal("openinglivebirds")),
                RecordedMortality = r.GetInt32(r.GetOrdinal("recordedmortality")),
                ProductionRecordCount = r.GetInt32(r.GetOrdinal("productionrecordcount")),
                LastCountedBirds = r.GetInt32(r.GetOrdinal("lastcountedbirds")),
                LastCountDate = Date(r, "lastcountdate"),
                Correction = r.GetInt32(r.GetOrdinal("correction")),
                BirdsSold = r.GetInt32(r.GetOrdinal("birdssold")),
                BirdsCulled = r.GetInt32(r.GetOrdinal("birdsculled")),
                BirdsTransferred = r.GetInt32(r.GetOrdinal("birdstransferred")),
                CurrentLiveBirds = r.GetInt32(r.GetOrdinal("currentlivebirds")),
            };
        }

        /// <summary>
        /// Undo sales created for a closeout that did not happen. They were created
        /// unpaid, so this reverses stock only -- the same Delete the Sales page uses.
        /// </summary>
        private async Task DeleteSalesAsync(List<int> saleIds, FlockCloseoutRequest request)
        {
            foreach (var id in saleIds)
            {
                try { await _sales.Delete(id, request.UserId, request.FarmId); }
                catch { /* best effort; the sale is still visible on the Sales page */ }
            }
        }

        private static string Unwrap(Exception ex)
        {
            var e = ex;
            while (e.InnerException != null) e = e.InnerException;
            return e is PostgresException pg ? pg.MessageText : e.Message;
        }

        private static string? Str(NpgsqlDataReader r, string c)
        {
            var o = r.GetOrdinal(c);
            return r.IsDBNull(o) ? null : Convert.ToString(r.GetValue(o));
        }

        private static int? Int(NpgsqlDataReader r, string c)
        {
            var o = r.GetOrdinal(c);
            return r.IsDBNull(o) ? null : Convert.ToInt32(r.GetValue(o));
        }

        private static decimal? Dec(NpgsqlDataReader r, string c)
        {
            var o = r.GetOrdinal(c);
            return r.IsDBNull(o) ? null : Convert.ToDecimal(r.GetValue(o));
        }

        private static DateTime? Date(NpgsqlDataReader r, string c)
        {
            var o = r.GetOrdinal(c);
            return r.IsDBNull(o) ? null : r.GetDateTime(o);
        }
    }
}
