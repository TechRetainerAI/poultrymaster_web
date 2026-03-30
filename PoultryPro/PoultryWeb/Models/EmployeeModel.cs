using System.ComponentModel.DataAnnotations;

namespace PoultryWeb.Models
{
    public class EmployeeModel
    {
        public string Id { get; set; }
        
        [Required(ErrorMessage = "Email is required")]
        [EmailAddress(ErrorMessage = "Invalid email address")]
        [Display(Name = "Email")]
        public string Email { get; set; }
        
        [Required(ErrorMessage = "First name is required")]
        [Display(Name = "First Name")]
        public string FirstName { get; set; }
        
        [Required(ErrorMessage = "Last name is required")]
        [Display(Name = "Last Name")]
        public string LastName { get; set; }
        
        [Phone(ErrorMessage = "Invalid phone number")]
        [Display(Name = "Phone Number")]
        public string PhoneNumber { get; set; }
        
        [Required(ErrorMessage = "Username is required")]
        [Display(Name = "Username")]
        public string UserName { get; set; }
        
        public string FarmId { get; set; }
        
        [Display(Name = "Farm Name")]
        public string FarmName { get; set; }
        
        [Display(Name = "Is Staff")]
        public bool IsStaff { get; set; } = true;
        
        [Display(Name = "Email Confirmed")]
        public bool EmailConfirmed { get; set; }
        
        [Display(Name = "Created Date")]
        public DateTime? CreatedDate { get; set; }

        // For create only
        [DataType(DataType.Password)]
        [Display(Name = "Password")]
        public string Password { get; set; }

        [DataType(DataType.Password)]
        [Display(Name = "Confirm Password")]
        [Compare("Password", ErrorMessage = "Passwords do not match")]
        public string ConfirmPassword { get; set; }
    }

    public class CreateEmployeeRequest
    {
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
        
        [Required]
        [MinLength(6)]
        public string Password { get; set; }
        
        [Required]
        public string FarmId { get; set; }
        
        public string FarmName { get; set; }
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
    }
}

