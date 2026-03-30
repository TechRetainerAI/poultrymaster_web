using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace User.Management.Data.Models
{
    public class Farm
    {
        public string FarmId { get; set; }                // Unique identifier (GUID)
        public string Name { get; set; }              // Name of the farm
        public string Email { get; set; }             // Contact email
        public string Type { get; set; }              // Type
        public string PhoneNumber { get; set; }       // Optional phone number
        public DateTime CreatedAt { get; set; }       // Timestamp of registration
    }

}
