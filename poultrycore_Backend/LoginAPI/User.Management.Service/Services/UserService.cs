using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using User.Management.Data;
using User.Management.Data.Models;

namespace User.Management.Service.Services
{
    public class UserService : IUserService
    {
        private readonly IUserDataDAL _userDataDal;

        public UserService(IUserDataDAL userDataDal)
        {
            _userDataDal = userDataDal;
        }

        public async Task SaveSubscriberAsync(Subscriber subscriber)
        {
            await _userDataDal.SaveSubscriberAsync(subscriber);
        }

        public async Task DeleteSubscriberAsync(Subscriber subscriber)
        {
            await _userDataDal.DeleteAsync(subscriber);
        }

        public async Task<IEnumerable<Subscriber>> GetAllSubscribersAsync()
        {
            return await _userDataDal.GetAsync();
        }

        public async Task<Subscriber> GetSubscriberByCustomerIdAsync(string customerId)
        {
            return await _userDataDal.GetSubscriberByCustomerIdAsync(customerId);
        }

        public async Task<Subscriber> GetSubscriberByIdAsync(string subscriberId)
        {
            return await _userDataDal.GetSubscriberByIdAsync(subscriberId);
        }

        public async Task<Subscriber> UpdateSubscriberAsync(Subscriber subscriber)
        {
            return await _userDataDal.UpdateSubscriberAsync(subscriber);
        }

        public async Task<ApplicationUser> FindByEmailAsync(string email)
        {
            return await _userDataDal.FindByEmailAsync(email);
        }

        public async Task<ApplicationUser> UpdateUserAsync(ApplicationUser user)
        {
            return await _userDataDal.UpdateUserAsync(user);
        }

        public async Task<ApplicationUser> UpdateUserCustomerIdAsync(ApplicationUser user)
        {
            return await _userDataDal.UpdateUserCustomerIdAsync(user);
        }
    }
}
