using System;
using System.ComponentModel.DataAnnotations;
using User.Management.Data.Models;

namespace User.Management.Service.Models
{
    public class PlansDisplay
    {
        public int TransactionCount { get; set; }
        public List<Plan> MembershipPlans { get; set; }
    }


}
