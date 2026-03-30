using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;

namespace PoultryWeb.Models;

// Add profile data for application users by adding properties to the AppUser class
public class AppUser : IdentityUser
{
    public string FarmId { get; set; }
    public string? FarmName { get; set; }
    public bool IsStaff { get; set; }


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
    public bool? IsSubscriber { get; set; }   //TODO - I MIGHT HAVE TO SAVE THIS IN THE DB. ADD A COLUMN AND MAINTAIN WHEN USER IS SUBSCRIBED

    public string? RefreshToken { get; set; }
    public DateTime? RefreshTokenExpiry { get; set; }
}

    