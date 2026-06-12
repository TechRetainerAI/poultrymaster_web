using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using User.Management.Data.Models;

namespace User.Management.Service.Services
{
    public interface IUserService
    {
        Task SaveSubscriberAsync(Subscriber subscriber);
        Task DeleteSubscriberAsync(Subscriber subscriber);
        Task<IEnumerable<Subscriber>> GetAllSubscribersAsync();
        Task<Subscriber> GetSubscriberByCustomerIdAsync(string customerId);
        Task<Subscriber> GetSubscriberByIdAsync(string subscriberId);
        Task<Subscriber> UpdateSubscriberAsync(Subscriber subscriber);
        Task<ApplicationUser> FindByEmailAsync(string email);
        Task<ApplicationUser> UpdateUserAsync(ApplicationUser user);
        Task<ApplicationUser> UpdateUserCustomerIdAsync(ApplicationUser user);


        ////new
        //Task<IdentityResult> CreateUserAsync(ApplicationUser user);
        //Task<IdentityResult> DeleteUserAsync(string userId);
        //Task<ApplicationUser> FindByIdAsync(string userId);
        //Task<ApplicationUser> FindByNameAsync(string normalizedUserName);
        //Task<string> GetPasswordHashAsync(string userId);
        //Task<bool> HasPasswordAsync(string userId);
        //Task<bool> SetPasswordHashAsync(string userId, string hash);
    }
}
