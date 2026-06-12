
using User.Management.Data.Models;
//using User.Management.Data.Entities;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace User.Management.Data
{
    public interface IUserDataDAL
    {
        Task DeleteAsync(Subscriber subscription);
        Task<ApplicationUser> FindByEmailAsync(string email);
        Task<IEnumerable<Subscriber>> GetAsync();
        Task<Subscriber> GetSubscriberByCustomerId(string customerId);
        Task<Subscriber> GetSubscriberByCustomerIdAsync(string customerId); //I like this one better - tested
        Task<Subscriber> GetSubscriberByIdAsync(string subscriberId);  //tested
        Task SaveSubscriberAsync(Subscriber subscriber);  //tested
        Task<Subscriber> UpdateSubscriberAsync(Subscriber subscription); //tested
        Task<ApplicationUser> UpdateUserAsync(ApplicationUser user);
        Task<ApplicationUser> UpdateUserCustomerIdAsync(ApplicationUser user);  //tested
    }
}