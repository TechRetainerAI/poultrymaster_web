//using System.Collections.Generic;
//using System.Net;
//using System.Net.Http;
//using System.Net.Http.Headers;
//using System.Text;
//using System.Threading.Tasks;
//using API.Data.Repositories;
//using Microsoft.AspNetCore.Identity;
//using Microsoft.Extensions.Configuration;
//using Newtonsoft.Json;
//using User.Management.Data;
//using User.Management.Data.Models;
//using User.Management.Service.Models;

//namespace User.Management.Service.Services
//{
//    public class SubscriptionService111 : ISubscriptionService
//    {
//        private readonly IConfiguration _configuration;
//        //private readonly ISubscriptionRepository _subscriptionRepository;
//        private readonly ISubscriptionDAL _subscriptionDal;
//        private readonly UserManager<ApplicationUser> _userManager;
//        private readonly IHttpClientFactory _httpClientFactory;

//        public SubscriptionService(IConfiguration configuration, ISubscriptionRepository subscriptionRepository, ISubscriptionDAL subscriptionDal, UserManager<ApplicationUser> userManager, IHttpClientFactory httpClientFactory)
//        {
//            _configuration = configuration;
//            //_subscriptionRepository = subscriptionRepository;
//            _subscriptionDal = subscriptionDal;
//            _userManager = userManager;
//            _httpClientFactory = httpClientFactory;
//        }

//        // New repository-based methods

//        public async Task<Subscriber> CreateSubscriptionAsync(Subscriber subscription)
//        {
//            return await _subscriptionRepository.CreateAsync(subscription);
//        }

//        public async Task DeleteSubscriptionAsync(string id)
//        {
//            var subscription = await _subscriptionRepository.GetByIdAsync(id);
//            if (subscription != null)
//            {
//                await _subscriptionRepository.DeleteAsync(subscription);
//            }
//        }

//        public async Task<IEnumerable<Subscriber>> GetAllSubscriptionsAsync()
//        {
//            return await _subscriptionRepository.GetAsync();
//        }

//        public async Task<Subscriber> GetSubscriptionByCustomerIdAsync(string customerId)
//        {
//            return await _subscriptionRepository.GetByCustomerIdAsync(customerId);
//        }

//        public async Task<Subscriber> GetSubscriptionByIdAsync(string id)
//        {
//            return await _subscriptionRepository.GetByIdAsync(id);
//        }

//        public async Task<Subscriber> UpdateSubscriptionAsync(Subscriber subscription)
//        {
//            return await _subscriptionRepository.UpdateAsync(subscription);
//        }

//        // User-related methods from repository

//        public async Task<ApplicationUser> FindUserByEmailAsync(string email)
//        {
//            return await _subscriptionRepository.FindByEmailAsync(email);
//        }

//        public async Task<ApplicationUser> UpdateUserAsync(ApplicationUser user)
//        {
//            return await _subscriptionRepository.UpdateUserAsync(user);
//        }

//        // Existing methods from the original service

//        public PlansDisplay GetPlans(string userId)
//        {
//            var result = new PlansDisplay();
//            // Existing logic to populate PlansDisplay
//            return result;
//        }

//        //If this works, it is simplier
//        //public Subscriber GetSubscriberByCustomerId(string customerId)
//        //{
//        //    var result = _subscriptionRepository.GetByCustomerIdAsync(customerId).Result;
//        //    return result;
//        //}

//        public Subscriber GetSubscriberByCustomerId(string customerId)
//        {
//            var result = _subscriptionDal.GetSubscriberByCustomerId(customerId);

//            return result;
//        }

//        public Session RequestMemberSession(string priceId)
//        {
//            try
//            {
//                var req = new
//                {
//                    priceId = priceId,
//                    successUrl = _configuration["successUrl"],
//                    failureUrl = _configuration["failureUrl"]
//                };

//                var json = JsonConvert.SerializeObject(req);
//                var data = new StringContent(json, Encoding.UTF8, "application/json");

//                var client = _httpClientFactory.CreateClient();
//                var url = _configuration["paymentApi"];
//                client.BaseAddress = new Uri(url);
//                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

//                HttpResponseMessage response = client.PostAsync("api/payments/create-checkout-session", data).Result;

//                if (response.IsSuccessStatusCode)
//                {
//                    string content = response.Content.ReadAsStringAsync().Result;
//                    Session session = JsonConvert.DeserializeObject<Session>(content);
//                    return session;
//                }
//            }
//            catch (Exception ex)
//            {
//                Console.WriteLine($"An error occurred: {ex.Message}");
//            }

//            return null;
//        }

//        public Session RequestCustomerPortalSession(string customerId, string accessToken)
//        {
//            try
//            {
//                var req = new
//                {
//                    CustomerId = customerId,
//                    ReturnUrl = _configuration["homeUrl"]
//                };

//                var json = JsonConvert.SerializeObject(req);
//                var data = new StringContent(json, Encoding.UTF8, "application/json");

//                var client = _httpClientFactory.CreateClient();
//                var url = _configuration["paymentApi"];
//                client.BaseAddress = new Uri(url);
//                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

//                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

//                HttpResponseMessage response = client.PostAsync("api/payments/customer-portal", data).Result;

//                if (response.IsSuccessStatusCode)
//                {
//                    string content = response.Content.ReadAsStringAsync().Result;
//                    Session session = JsonConvert.DeserializeObject<Session>(content);
//                    return session;
//                }
//            }
//            catch (Exception ex)
//            {
//                Console.WriteLine($"An error occurred: {ex.Message}");
//            }

//            return null;
//        }
//    }
//}
