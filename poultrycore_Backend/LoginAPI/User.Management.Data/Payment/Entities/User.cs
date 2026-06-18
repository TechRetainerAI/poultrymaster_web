using Microsoft.AspNetCore.Identity;

namespace User.Management.Data.Entities
{
    //public class User : IdentityUser
    //{
    //	public string CustomerId { get; set; }
    //}

    public class User : IdentityUser
    {
        public string FirstName { get; set; } = string.Empty;

        public string LastName { get; set; } = string.Empty;

        //public string PhoneNumber { get; set; }

        public string CustomerId { get; set; } = string.Empty;

    }

}