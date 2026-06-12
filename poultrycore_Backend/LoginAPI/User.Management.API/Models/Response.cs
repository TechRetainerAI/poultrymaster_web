namespace User.Management.API.Models
{
    public class Response
    {

        public string? Status { get; set; }
        public string? Message { get; set; }
        public bool IsSuccess { get; set; }
        public bool RequiresTwoFactor { get; set; }
        public string UserId { get; set; }
        public string Username { get; set; }
        public bool IsStaff { get; set; }
        public string FarmId { get; set; }
        public string? FarmName { get; set; }
    }
}
