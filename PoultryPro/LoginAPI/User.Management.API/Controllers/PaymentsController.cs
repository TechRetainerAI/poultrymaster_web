//using API.DAL;
//using API.Data.Entities;
//using API.Data.Repositories;
//using API.Models;
using User.Management.API.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Stripe;
using Stripe.Checkout;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using User.Management.Service.Services;
using User.Management.Data.Models;
using Microsoft.AspNetCore.Authentication;

// For more information on enabling Web API for empty projects, visit https://go.microsoft.com/fwlink/?LinkID=397860

namespace API.Controllers
{
	[Route("api/[controller]")]
	[ApiController]
	public class PaymentsController : ControllerBase
	{
		private readonly StripeSettings _stripeSettings;
		private readonly UserManager<ApplicationUser> _userManager;
		private readonly ISubscriptionService _subscriberService;
        private readonly IUserService _userService;

        public PaymentsController(IOptions<StripeSettings> stripeSettings, UserManager<ApplicationUser> userManager, ISubscriptionService subscriberRepository, IUserService userService)
		{
			_subscriberService = subscriberRepository;
            _userService = userService;
            _stripeSettings = stripeSettings.Value;
			_userManager = userManager;
		}

		[HttpGet("products")]
		public IActionResult Products()
		{
			if (string.IsNullOrWhiteSpace(_stripeSettings.PrivateKey))
				return BadRequest("Stripe private key is not configured. Set StripeSettings:PrivateKey (User Secrets or environment variable).");

			StripeConfiguration.ApiKey = _stripeSettings.PrivateKey;

			var options = new ProductListOptions { Limit = 3 };
			var service = new ProductService();
			StripeList<Product> products = service.List(options);

			return Ok(products);
		}

		[HttpPost("create-checkout-session")]
		public async Task<IActionResult> CreateCheckoutSession([FromBody] CreateCheckoutSessionRequest req)
		{
			var options = new SessionCreateOptions
			{
				//SuccessUrl = "http://localhost:5166/Subscription/PaymentSuccess",
				//CancelUrl = "http://localhost:5166/Subscription/PaymentFailure",
				SuccessUrl = req.SuccessUrl,
				CancelUrl = req.FailureUrl,
				PaymentMethodTypes = new List<string>
				{
					"card",
				},
				Mode = "subscription",
				LineItems = new List<SessionLineItemOptions>
				{
					new SessionLineItemOptions
					{
						Price = req.PriceId,
						Quantity = 1,
					},
				},
			};

			var service = new SessionService();
			service.Create(options);
			try
			{
				var session = await service.CreateAsync(options);
				return Ok(new CreateCheckoutSessionResponse
				{
					SessionId = session.Id,
					PublicKey = _stripeSettings.PublicKey
				});
			}
			catch (StripeException e)
			{
				Console.WriteLine(e.StripeError.Message);
				return BadRequest(new ErrorResponse
				{
					ErrorMessage = new ErrorMessage
					{
						Message = e.StripeError.Message,
					}
				});
			}
		}

		//The goal of this API is to return us a session, this session has a session URL. We are going to use that later on from the UI
		//to redirect the User to the billing portal. It needs the customerId to be able to create the billing session.it has to be securely so it does not
		//create a session for the wrong person. We will get it from our database. We will not pass it
		[Authorize]
		[HttpPost("customer-portal")]
		public async Task<IActionResult> CustomerPortal([FromBody] CustomerPortalRequest req)
		{

			try
			{

				//IMPORTANT COMMENT:
				//For security reasons, we do not pass the customer id. We get it directly from the db.
				//The way this works is that, when the user logs in, we create an access_token and save it in the browser.
				//we save useful user information there with the token such as email, userid etc called Claims.
				//Now when they call this function, because of the authorize, those values become available. So we use what we need to make the db call
				ClaimsPrincipal principal = HttpContext.User as ClaimsPrincipal;
				var claim = principal.Claims.FirstOrDefault(c => c.Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"); //gives the Email
				//var claim = principal.Claims.FirstOrDefault(c => c.Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname");  //gives the Username

				var userFromDb = await _userService.FindByEmailAsync(claim.Value);
				
				if (userFromDb == null)
				{
					return BadRequest();
				}

                if (userFromDb.CustomerId != null)
                {
				    var options = new Stripe.BillingPortal.SessionCreateOptions
				    {
				    	Customer = userFromDb.CustomerId,     //"cus_PXlxI8CSV8uibo",//req.CustomerId (No longer passing it)
				    	ReturnUrl = req.ReturnUrl,
				    };

				    var service = new Stripe.BillingPortal.SessionService();
				    var session = await service.CreateAsync(options);

				    return Ok(new
				    {
				    	url = session.Url
				    });
                }
                else
                {
                    return BadRequest(new ErrorResponse
                    {
                        ErrorMessage = new ErrorMessage
                        {
                            Message = "User must be a subscriber First"
                        }
                    }); ;
                }
            }
			catch (StripeException e)
			{
				Console.WriteLine(e.StripeError.Message);
				return BadRequest(new ErrorResponse
				{
					ErrorMessage = new ErrorMessage
					{
						Message = e.StripeError.Message,
					}
				});
			}

		}

		//Note we are NOTE able to add Authorize here. We have to make it public. The reason is that stripe is not going to be able to login 
		//and send us a JWT Token everytime they wanna use this API.
		//So we secure it by adding the WHSecret to the stripeEvent to make sure only stripe is using it.
		//POST api/<PaymentsController>/webhook
		[HttpPost("webhook")]
		public async Task<IActionResult> WebHook()
		{
			var json = await new StreamReader(HttpContext.Request.Body).ReadToEndAsync();

			try
			{
				var stripeEvent = EventUtility.ConstructEvent(
				 json,
				 Request.Headers["Stripe-Signature"],
				 _stripeSettings.WHSecret,
				  throwOnApiVersionMismatch: false // Disable exception for API version mismatch
			   );

				// Handle the event
				if (stripeEvent.Type == Events.CustomerSubscriptionCreated)
				{
					var subscription = stripeEvent.Data.Object as Subscription;
					//Do stuff
					await addSubscriptionToDb(subscription);
				}
				else if (stripeEvent.Type == Events.CustomerSubscriptionUpdated)
				{
					var session = stripeEvent.Data.Object as Stripe.Subscription;

					// Update Subsription
					await updateSubscription(session);
				}
				else if (stripeEvent.Type == Events.CustomerCreated)
				{
					var customer = stripeEvent.Data.Object as Customer;
					//Do Stuff
					await addCustomerIdToUser(customer);
				}
				// ... handle other event types
				else
				{
					// Unexpected event type
					Console.WriteLine("Unhandled event type: {0}", stripeEvent.Type);
				}
				return Ok();  //We must always try to send a response back to stripe else it will keep trying to call the endpoint endlessly
			}
			catch (StripeException e)
			{
				Console.WriteLine(e.StripeError.Message);
				return BadRequest();
			}
		}

		private async Task updateSubscription(Subscription subscription)
		{
			try
			{
				var subscriptionFromDb = await _userService.GetSubscriberByIdAsync(subscription.Id);
				//var subscriptionFromDb = await _subscriberService.GetByIdAsync(subscription.Id);
				if (subscriptionFromDb != null)
				{
					subscriptionFromDb.Status = subscription.Status;
					subscriptionFromDb.CurrentPeriodStart = subscription.CurrentPeriodStart;
					subscriptionFromDb.CurrentPeriodEnd = subscription.CurrentPeriodEnd;
					subscriptionFromDb.CanceledAt = subscription.CanceledAt;
					subscriptionFromDb.Created = subscription.Created;
					subscriptionFromDb.EndedAt = subscription.EndedAt;
					subscriptionFromDb.LatestInvoiceId = subscription.LatestInvoiceId;
					subscriptionFromDb.StartDate = subscription.StartDate;
					subscriptionFromDb.TrialEnd = subscription.TrialEnd;
					subscriptionFromDb.TrialStart = subscription.TrialStart;

					await _userService.UpdateSubscriberAsync(subscriptionFromDb);
					//await _subscriberService.UpdateAsync(subscriptionFromDb);
					Console.WriteLine("Subscription Updated");
				}

			}
			catch (System.Exception ex)
			{
				Console.WriteLine(ex.Message);

				Console.WriteLine("Unable to update subscription");

			}

		}

		private async Task addCustomerIdToUser(Customer customer)
		{
			try
			{
				//It is very important that the stripe email is something that we have in our db. else we will have trouble here.
				//See how you can prevent them from editting that field.. then pass the email yourself and prevent editting.
				//Instead of getting it this way, go to the db directly and get it.
				//var userFromDb = await _userManager.FindByEmailAsync(customer.Email);
				var userFromDb = await _userService.FindByEmailAsync(customer.Email);
				//var userFromDb = await _subscriberService.FindByEmailAsync(customer.Email);

				if (userFromDb != null)
				{
					userFromDb.CustomerId = customer.Id;
                    userFromDb.IsSubscriber = true;
                    //await _userManager.UpdateAsync(userFromDb);
                    await _userService.UpdateUserCustomerIdAsync(userFromDb);  //Only saving the one field alone - safer and lowers chance of error
                                                                               //await _subscriberService.UpdateUserAsync(userFromDb);

                    // Update the user's session -- ONLY UPDATING THE IsSubscriber field for now
                    await UpdateUserSession(userFromDb);


                    Console.WriteLine("Customer Id added to user ");
				}

			}
			catch (System.Exception ex)
			{
				Console.WriteLine("Unable to add customer id to user");
				Console.WriteLine(ex);
			}
		}

		private async Task addSubscriptionToDb(Subscription subscription)
		{
			try
			{
				var subscriber = new Subscriber
				{
					SubscriberId = subscription.Id,
					CustomerId = subscription.CustomerId,
					Status = "active",
					CurrentPeriodEnd = subscription.CurrentPeriodEnd,
					CurrentPeriodStart = subscription.CurrentPeriodStart,
					CanceledAt = subscription.CanceledAt,
					Created = subscription.Created,
					EndedAt = subscription.EndedAt,
					LatestInvoiceId = subscription.LatestInvoiceId,
					StartDate = subscription.StartDate,
					TrialEnd = subscription.TrialEnd,
					TrialStart = subscription.TrialStart
				};
				await _userService.SaveSubscriberAsync(subscriber);
				//await _subscriberService.CreateAsync(subscriber);

				//IMPORTANT
				//You can send the new subscriber an email welcoming the new subscriber
			}
			catch (System.Exception ex)
			{
				Console.WriteLine("Unable to add new subscriber to Database");
				Console.WriteLine(ex.Message);
			}
		}

        //Currently not workng as expected.
        private async Task UpdateUserSession(ApplicationUser user)
        {
            // Get the current claims principal
            var currentPrincipal = HttpContext.User as ClaimsPrincipal;
            var currentClaims = currentPrincipal?.Claims.ToList() ?? new List<Claim>();

            // Remove the old subscriber claim if it exists
            var subscriberClaim = currentClaims.FirstOrDefault(c => c.Type == "IsSubscriber");
            if (subscriberClaim != null)
            {
                currentClaims.Remove(subscriberClaim);
            }

            // Add the new subscriber claim
            currentClaims.Add(new Claim("IsSubscriber", "True"));

            // Create a new claims identity and principal
            var claimsIdentity = new ClaimsIdentity(currentClaims, "PoultryFarmSoftwareCookieScheme");
            var claimsPrincipal = new ClaimsPrincipal(claimsIdentity);

            // Sign in the user with the updated principal
            await HttpContext.SignInAsync("PoultryFarmSoftwareCookieScheme", claimsPrincipal, new AuthenticationProperties
            {
                IsPersistent = true,
                ExpiresUtc = DateTime.UtcNow.AddDays(14)
            });

            // Update session and cookies
            HttpContext.Session.SetString("IsSubscriber", "True");
            Response.Cookies.Append("IsSubscriber", "True", new CookieOptions
            {
                //HttpOnly = true,
                Secure = true,
                Expires = DateTime.UtcNow.AddDays(14)
            });
        }

    }
}
