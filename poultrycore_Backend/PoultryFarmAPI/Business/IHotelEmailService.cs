namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelEmailService
    {
        Task SendBookingConfirmationAsync(string farmId, int bookingId);
        Task SendCheckInConfirmationAsync(string farmId, int bookingId);
        Task SendCheckOutReceiptAsync(string farmId, int bookingId, decimal totalBill, decimal totalPaid);
        Task SendPaymentReceiptAsync(string farmId, int bookingId, decimal amount, string paymentMethod, string reference);
    }
}
