using Microsoft.AspNetCore.Identity;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.ComponentModel.DataAnnotations.Schema;
//using Microsoft.AspNetCore.Identity;

namespace PoultryWeb.Models
{
    public class ApplicationUser: IdentityUser
    {
        public string FarmId { get; set; }
        public string? FarmName { get; set; }
        public bool IsStaff { get; set; }


        public bool? isSubscriber { get; set; }
        public string? RefreshToken { get; set; }
        public DateTime? RefreshTokenExpiry { get; set; }

        [PersonalData]
        [Column(TypeName = "nvarchar(255)")]
        public string FirstName { get; set; }

        [PersonalData]
        [Column(TypeName = "nvarchar(255)")]
        public string LastName { get; set; }

        //Commented out because it was hiding the PhoneNumber field in Identity class itself
        //[PersonalData]
        //[Column(TypeName = "nvarchar(255)")]
        //public string PhoneNumber { get; set; }

        [Column(TypeName = "nvarchar(255)")]
        public string? CustomerId { get; set; }

    }
}
