namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelCashLedgerService
    {
        /// <summary>Posts a credit (income) or debit (expense) to the designated cash account and logs a transaction.</summary>
        Task PostAsync(string farmId, string purpose, string txnType, decimal amount, string description, string? reference, string sourceType, int sourceId, string? createdBy);
    }
}
