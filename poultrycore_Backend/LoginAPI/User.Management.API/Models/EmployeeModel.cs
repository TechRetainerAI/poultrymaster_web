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

