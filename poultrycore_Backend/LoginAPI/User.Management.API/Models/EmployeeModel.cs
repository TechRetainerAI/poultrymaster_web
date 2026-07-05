using System.ComponentModel.DataAnnotations;

namespace User.Management.API.Models
{
    public class EmployeeModel
    {
        public string Id { get; set; }
        
        [Required]
        [EmailAddress]
        public string Email { get; set; }
        
        [Required]
        public string FirstName { get; set; }
        
        [Required]
        public string LastName { get; set; }
        
        [Phone]
        public string PhoneNumber { get; set; }
        
        [Required]
        public string UserName { get; set; }
        
        public string FarmId { get; set; }
        public string FarmName { get; set; }
        public bool IsStaff { get; set; } = true;
        public bool IsAdmin { get; set; }
        public string? AdminTitle { get; set; }
        public Dictionary<string, bool>? Permissions { get; set; }
        public Dictionary<string, bool>? FeaturePermissions { get; set; }
        public bool EmailConfirmed { get; set; }
        public DateTime? CreatedDate { get; set; }
        public DateTime? LastLoginTime { get; set; }
    }

    public class CreateEmployeeRequest
    {
       
        [EmailAddress]
        public string Email { get; set; }
        
        [Required]
        public string FirstName { get; set; }
        
        [Required]
        public string LastName { get; set; }
        
        [Phone]
        public string PhoneNumber { get; set; }
        
        [Required]
        public string UserName { get; set; }
        
        [Required]
        [MinLength(4)]
        public string Password { get; set; }
        
        [Required]
        public string FarmId { get; set; }
        
        public string FarmName { get; set; }
        public bool IsAdmin { get; set; }
        [MaxLength(100)]
        public string? AdminTitle { get; set; }
        public Dictionary<string, bool>? Permissions { get; set; }
        public Dictionary<string, bool>? FeaturePermissions { get; set; }
    }

    // Doc 3 §6-7: a company an employee can access, with the role on that company.
    public class CompanyAccessModel
    {
        public string FarmId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Type { get; set; } = "Poultry";
        public string? Role { get; set; }
    }

    // Doc 3 §6: an organization-wide employee plus the companies they can access.
    public class OrganizationEmployeeModel : EmployeeModel
    {
        public List<CompanyAccessModel> Companies { get; set; } = new();
    }

    // Doc 3 §7: request body for granting an employee access to a company.
    public class CompanyAccessRequest
    {
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public string? Role { get; set; }
    }

    // Request body for setting the owner's organization code.
    public class SetOrgCodeRequest
    {
        [Required]
        public string Code { get; set; } = string.Empty;
    }

    public class UpdateEmployeeRequest
    {
        [Required]
        public string Id { get; set; }
        
        [Required]
        public string FirstName { get; set; }
        
        [Required]
        public string LastName { get; set; }
        
        [Phone]
        public string PhoneNumber { get; set; }
        
        [EmailAddress]
        public string Email { get; set; }

        public bool IsAdmin { get; set; }
        [MaxLength(100)]
        public string? AdminTitle { get; set; }
        public Dictionary<string, bool>? Permissions { get; set; }
        public Dictionary<string, bool>? FeaturePermissions { get; set; }
    }
}

