using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Newtonsoft.Json;
//using RestSharp;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text;
using User.Management.Data;
using User.Management.Data.Models;
using User.Management.Service.Models;

namespace User.Management.Service.Services
{

    public class SubscriptionServiceOldVersion : ISubscriptionServiceOldVersion
    {
        private readonly IConfiguration _configuration;
        private readonly ISubscriptionDAL _subscriptionDal;
        //private readonly ITransactionBLL _transactionBll;
        private readonly UserManager<ApplicationUser> _userManager;
        private readonly IHttpClientFactory _httpClientFactory;

        public SubscriptionServiceOldVersion(IConfiguration configuration, ISubscriptionDAL subscriptionDal, UserManager<ApplicationUser> userManager, IHttpClientFactory httpClientFactory)
        {
            _subscriptionDal = subscriptionDal;
            _userManager = userManager;
            //_transactionBll = transactionBll;
            _httpClientFactory = httpClientFactory;
            _configuration = configuration;
        }

        public PlansDisplay GetPlans(string userId)
        {
            var result = new PlansDisplay();
            //result.TransactionCount = _transactionBll.TransactionsCount(userId);
            //result.MembershipPlans = _subscriptionDal.GetPlans();
            //
            //foreach (var plan in result.MembershipPlans)
            //{
            //    if (plan.TransactionLimit >= result.TransactionCount)
            //        plan.isEnabled = true;
            //}
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
                // Construct the request body
                var req = new
                {
                    priceId = priceId,
                    successUrl = _configuration["successUrl"],
                    failureUrl = _configuration["failureUrl"]
                };

                var json = JsonConvert.SerializeObject(req);
                var data = new StringContent(json, Encoding.UTF8, "application/json");

                // Create HttpClient instance using HttpClientFactory
                var client = _httpClientFactory.CreateClient();

                // Set the base address
                var url = _configuration["paymentApi"];
                client.BaseAddress = new Uri("url");
                //client.BaseAddress = new Uri("https://localhost:44353/");

                // Set security protocol
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

                // Post request and get response synchronously
                HttpResponseMessage response = client.PostAsync("api/payments/create-checkout-session", data).Result;

                // Check if the response status code is OK (200)
                if (response.IsSuccessStatusCode)
                {
                    // Read response content as string
                    string content = response.Content.ReadAsStringAsync().Result;

                    // Deserialize JSON response into Session object
                    Session session = JsonConvert.DeserializeObject<Session>(content);
                    return session;
                }
            }
            catch (Exception ex)
            {
                // Log the exception
                Console.WriteLine($"An error occurred: {ex.Message}");
            }

            return null;
        }

        public Session RequestCustomerPortalSession(string customerId, string accessToken)
        {
            try
            {
                // Construct the request body
                var req = new
                {
                    CustomerId = customerId,
                    ReturnUrl = _configuration["homeUrl"]
                };

                var json = JsonConvert.SerializeObject(req);
                var data = new StringContent(json, Encoding.UTF8, "application/json");

                // Create HttpClient instance using HttpClientFactory
                var client = _httpClientFactory.CreateClient();

                // Set the base address
                var url = _configuration["paymentApi"];
                client.BaseAddress = new Uri(url);
                //client.BaseAddress = new Uri("https://localhost:44353/");

                // Set security protocol
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

                // Add bearer token to the request headers
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

                // Post request and get response synchronously
                HttpResponseMessage response = client.PostAsync("api/payments/customer-portal", data).Result;

                // Check if the response status code is OK (200)
                if (response.IsSuccessStatusCode)
                {
                    // Read response content as string
                    string content = response.Content.ReadAsStringAsync().Result;

                    // Deserialize JSON response into Session object
                    Session session = JsonConvert.DeserializeObject<Session>(content);
                    return session;
                }
            }
            catch (Exception ex)
            {
                // Log the exception
                Console.WriteLine($"An error occurred: {ex.Message}");
            }

            return null;
        }

    }
}
