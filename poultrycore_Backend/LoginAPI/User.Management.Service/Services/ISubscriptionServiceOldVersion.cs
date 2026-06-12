

using User.Management.Data.Models;
using User.Management.Service.Models;

namespace User.Management.Service.Services
{
    public interface ISubscriptionServiceOldVersion
    {
        //TaxSetting GetTaxSettings(string userId);
        //void SaveTaxSettings(TaxSetting taxSettings);
        //string Calculate(string userId);
        //string CalculateSpecificWallet(string userId, string walletCode);
        PlansDisplay GetPlans(string userId);
        Session RequestMemberSession(string PriceId);
        Session RequestCustomerPortalSession(string customerId, string accessToken);
        //Task<Session> RequestMemberSession(string priceId);
        Subscriber GetSubscriberByCustomerId(string customerId);

    }
}
