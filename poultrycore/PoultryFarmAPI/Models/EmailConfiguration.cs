namespace PoultryFarmAPIWeb.Models
{
    public class EmailConfiguration
    {
        public string From { get; set; } = string.Empty;
        public string SmtpServer { get; set; } = string.Empty;
        public int Port { get; set; }
        public string UserName { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
        // True for implicit TLS (port 465). False for STARTTLS (587).
        public bool UseSsl { get; set; } = true;
    }

    public class EmailAttachment
    {
        public string FileName { get; set; } = string.Empty;
        public string ContentType { get; set; } = "application/octet-stream";
        public byte[] Content { get; set; } = System.Array.Empty<byte>();
    }
}
