using System.Collections.Generic;
using System.Data;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Newtonsoft.Json;
using User.Management.Data;
using User.Management.Data.Models;
using User.Management.Service.Models;

namespace User.Management.Service.Services
{
    public class SubscriptionService : ISubscriptionService
    {
        private readonly IConfiguration _configuration;
        private readonly ISubscriptionDAL _subscriptionDal;
        private readonly UserManager<ApplicationUser> _userManager;
        private readonly IHttpClientFactory _httpClientFactory;

        public SubscriptionService(IConfiguration configuration, ISubscriptionDAL subscriptionDal, UserManager<ApplicationUser> userManager, IHttpClientFactory httpClientFactory)
        {
            _configuration = configuration;
            _subscriptionDal = subscriptionDal;
            _userManager = userManager;
            _httpClientFactory = httpClientFactory;
        }

        // New repository-based methods

        
        // Existing methods from the original service

        public PlansDisplay GetPlans(string userId)
        {
            var result = new PlansDisplay();
            // Existing logic to populate PlansDisplay
            return result;
        }

        
        public Subscriber GetSubscriberByCustomerId(string customerId)
        {
            var result = _subscriptionDal.GetSubscriberByCustomerId(customerId);

            return result;
        }

        public Session RequestMemberSession(string priceId)
        {
            try
            {
                var req = new
                {
                    priceId = priceId,
                    successUrl = _configuration["successUrl"],
                    failureUrl = _configuration["failureUrl"]
                };

                var json = JsonConvert.SerializeObject(req);
                var data = new StringContent(json, Encoding.UTF8, "application/json");

                var client = _httpClientFactory.CreateClient();
                var url = _configuration["paymentApi"];
                client.BaseAddress = new Uri(url);
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

                HttpResponseMessage response = client.PostAsync("api/payments/create-checkout-session", data).Result;

                if (response.IsSuccessStatusCode)
                {
                    string content = response.Content.ReadAsStringAsync().Result;
                    Session session = JsonConvert.DeserializeObject<Session>(content);
                    return session;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"An error occurred: {ex.Message}");
            }

            return null;
        }

        public Session RequestCustomerPortalSession(string customerId, string accessToken)
        {
            try
            {
                var req = new
                {
                    CustomerId = customerId,
                    ReturnUrl = _configuration["homeUrl"]
                };

                var json = JsonConvert.SerializeObject(req);
                var data = new StringContent(json, Encoding.UTF8, "application/json");

                var client = _httpClientFactory.CreateClient();
                var url = _configuration["paymentApi"];
                client.BaseAddress = new Uri(url);
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

                HttpResponseMessage response = client.PostAsync("api/payments/customer-portal", data).Result;

                if (response.IsSuccessStatusCode)
                {
                    string content = response.Content.ReadAsStringAsync().Result;
                    Session session = JsonConvert.DeserializeObject<Session>(content);
                    return session;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"An error occurred: {ex.Message}");
            }

            return null;
        }

        //uses this during registering
        public async Task<bool> CreateFarmAsync(Farm farm)
        {
            return await _subscriptionDal.CreateFarmAsync(farm);
        }

    }
}
