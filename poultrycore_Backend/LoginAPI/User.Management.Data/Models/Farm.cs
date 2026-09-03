using System;

namespace User.Management.Data.Models
{
    public class Farm
    {
        public string FarmId { get; set; } = string.Empty;   // Unique identifier (GUID or string)
        public string Name { get; set; } = string.Empty;     // Name of the farm / company
        public string Email { get; set; } = string.Empty;    // Contact email
        public string Type { get; set; } = string.Empty;     // 'Poultry' | 'Water' | future types
        public string PhoneNumber { get; set; } = string.Empty; // Optional phone number
        public string? OwnerUserId { get; set; }          // AspNetUsers.Id of the admin who created it
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class UserFarm
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public string Role { get; set; } = "Admin";      // 'Admin' | 'Staff'
        public DateTime CreatedAt { get; set; }
    }

    // Read-side projection returned by GET /api/Companies/mine and POST /api/Companies
    public class CompanyResponse
    {
        public string FarmId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Type { get; set; } = "Poultry";
        public string? Email { get; set; }
        public string? PhoneNumber { get; set; }
        public string? OwnerUserId { get; set; }
        public string Role { get; set; } = "Admin";      // role of the requesting user in this company
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class CreateCompanyRequest
    {
        [System.ComponentModel.DataAnnotations.Required(ErrorMessage = "Name is required.")]
        public string Name { get; set; } = string.Empty;

        // Type must be an explicit, valid value. A default of "Poultry" used to hide
        // wire bugs (stale frontends or missing field would silently create Poultry farms).
        [System.ComponentModel.DataAnnotations.Required(ErrorMessage = "Type is required (Poultry, Water, Generic, Hotel, or Restaurant).")]
        [System.ComponentModel.DataAnnotations.RegularExpression("^(Poultry|Water|Generic|Hotel|Restaurant)$",
            ErrorMessage = "Type must be Poultry, Water, Generic, Hotel, or Restaurant.")]
        public string Type { get; set; } = string.Empty;

        public string? Email { get; set; }
        public string? PhoneNumber { get; set; }
    }

    // Editing a company changes only its name/contact — Type is immutable and the
    // update stored proc never touches it. A dedicated model (no required Type)
    // avoids the automatic 400 "Type is required" that CreateCompanyRequest forces
    // on the PUT /Companies/{id} endpoint.
    public class UpdateCompanyRequest
    {
        [System.ComponentModel.DataAnnotations.Required(ErrorMessage = "Name is required.")]
        public string Name { get; set; } = string.Empty;

        public string? Email { get; set; }
        public string? PhoneNumber { get; set; }
    }

    public class SwitchFarmRequest
    {
        public string FarmId { get; set; } = string.Empty;
    }
}
