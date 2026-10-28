using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // School-specific models (migration 366).

    public class GenericClassModel
    {
        public int GenericClassId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(100)]
        public string ClassName { get; set; } = string.Empty;
        public int? ClassLevel { get; set; }
        [StringLength(200)]
        public string? ClassTeacher { get; set; }
        public int? Capacity { get; set; }
        [StringLength(500)]
        public string? Description { get; set; }
        public bool IsActive { get; set; } = true;
        public long StudentCount { get; set; }
    }

    public class GenericAcademicTermModel
    {
        public int GenericAcademicTermId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(100)]
        public string TermName { get; set; } = string.Empty;
        [Required]
        public DateTime StartDate { get; set; }
        [Required]
        public DateTime EndDate { get; set; }
        public bool IsCurrent { get; set; }
        public bool IsActive { get; set; } = true;
    }

    // Customer/student attendance (migration 367)
    public class GenericCustomerAttendanceModel
    {
        public int GenericCustomerAttendanceId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public string? ClassOrGrade { get; set; }
        [Required]
        public DateTime AttendanceDate { get; set; }
        [Required] [StringLength(20)]
        public string Status { get; set; } = "Present";
        public int? GenericClassId { get; set; }
        public int? GenericAcademicTermId { get; set; }
        [StringLength(500)]
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }
}
