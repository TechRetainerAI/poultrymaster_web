using Microsoft.AspNetCore.Identity;

namespace User.Management.Data.Entities
{
    //public class User : IdentityUser
    //{
    //	public string CustomerId { get; set; }
    //}

    public class User : IdentityUser
    {
        public string FirstName { get; set; }

        public string LastName { get; set; }

        //public string PhoneNumber { get; set; }

        public string CustomerId { get; set; }

    }

}