using API.Data.Entities;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace API.DAL
{
    public interface IUserDataDAL
    {
        Task DeleteAsync(Subscriber subscription);
        Task<User> FindByEmailAsync(string email);
        Task<IEnumerable<Subscriber>> GetAsync();
        Task<Subscriber> GetSubscriberByCustomerId(string customerId);
        Task<Subscriber> GetSubscriberByCustomerIdAsync(string customerId); //I like this one better - tested
        Task<Subscriber> GetSubscriberByIdAsync(string subscriberId);  //tested
        Task SaveSubscriberAsync(Subscriber subscriber);  //tested
        Task<Subscriber> UpdateSubscriberAsync(Subscriber subscription); //tested
        Task<User> UpdateUserAsync(User user);
        Task<User> UpdateUserCustomerIdAsync(User user);  //tested
    }
}