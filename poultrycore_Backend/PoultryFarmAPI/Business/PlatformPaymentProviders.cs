// The payment-provider seam (spec Part 12). The billing domain speaks only in
// these neutral shapes — checkout URL, verified charge, webhook event — so a
// second provider is a new class and a billingmarkets.provider value, not a
// rewrite. Paystack is the first implementation, not the definition.

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PoultryFarmAPIWeb.Business
{
    public sealed record ProviderCheckout(bool Ok, string? CheckoutUrl, string? Message);

    public sealed record ProviderCharge(
        bool Ok, string? ExternalPaymentId, string Reference, long AmountMinor,
        string Currency, DateTime PaidAtUtc, string? MethodSummary, string? Message);

    public sealed record ProviderWebhookEvent(
        bool SignatureValid, string EventType, string? Reference, string? ExternalPaymentId,
        long AmountMinor, string Currency, DateTime PaidAtUtc, string? MethodSummary, string? FailureMessage);

    public interface IPlatformPaymentProvider
    {
        /// <summary>billingmarkets.provider value this implementation serves.</summary>
        string Name { get; }
        bool IsConfigured { get; }

        Task<ProviderCheckout> CreateCheckoutAsync(
            string email, long amountMinor, string currency, string reference,
            string successUrl, string cancelUrl, string invoiceNumber, long accountId);

        /// <summary>Authoritative verification of one charge by our reference.</summary>
        Task<ProviderCharge> VerifyAsync(string reference);

        /// <summary>Signature check + neutral parse of a raw webhook body.</summary>
        ProviderWebhookEvent ParseWebhook(string payload, string signatureHeader);
    }

    public sealed class PaystackPlatformProvider : IPlatformPaymentProvider
    {
        private readonly string _secret;
        private readonly IHttpClientFactory _httpFactory;

        public PaystackPlatformProvider(string secretKey, IHttpClientFactory httpFactory)
        {
            _secret = secretKey ?? "";
            _httpFactory = httpFactory;
        }

        public string Name => "paystack";
        public bool IsConfigured => !string.IsNullOrWhiteSpace(_secret);

        private HttpClient Client()
        {
            var http = _httpFactory.CreateClient();
            http.DefaultRequestHeaders.Authorization =
                new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _secret);
            return http;
        }

        public async Task<ProviderCheckout> CreateCheckoutAsync(
            string email, long amountMinor, string currency, string reference,
            string successUrl, string cancelUrl, string invoiceNumber, long accountId)
        {
            var payload = JsonSerializer.Serialize(new
            {
                email,
                amount = amountMinor,
                currency = currency.ToUpperInvariant(),
                reference,
                callback_url = successUrl,
                metadata = new { invoiceNumber, accountId, cancelUrl },
            });
            using var content = new StringContent(payload, Encoding.UTF8, "application/json");
            var resp = await Client().PostAsync("https://api.paystack.co/transaction/initialize", content);
            var text = await resp.Content.ReadAsStringAsync();
            if (!resp.IsSuccessStatusCode)
                return new ProviderCheckout(false, null, $"Paystack initialize failed: {text}");

            using var doc = JsonDocument.Parse(text);
            var url = doc.RootElement.TryGetProperty("data", out var data)
                      && data.TryGetProperty("authorization_url", out var au)
                ? au.GetString() : null;
            return string.IsNullOrWhiteSpace(url)
                ? new ProviderCheckout(false, null, "Paystack did not return a checkout URL.")
                : new ProviderCheckout(true, url, null);
        }

        public async Task<ProviderCharge> VerifyAsync(string reference)
        {
            var resp = await Client().GetAsync(
                $"https://api.paystack.co/transaction/verify/{Uri.EscapeDataString(reference)}");
            var text = await resp.Content.ReadAsStringAsync();
            if (!resp.IsSuccessStatusCode)
                return new ProviderCharge(false, null, reference, 0, "", DateTime.UtcNow, null,
                    $"Paystack verify failed: {text}");

            using var doc = JsonDocument.Parse(text);
            var data = doc.RootElement.GetProperty("data");
            var status = data.TryGetProperty("status", out var st) ? st.GetString() : null;
            if (!string.Equals(status, "success", StringComparison.OrdinalIgnoreCase))
                return new ProviderCharge(false, null, reference, 0, "", DateTime.UtcNow, null,
                    $"Payment is not successful yet (status: {status}).");

            return new ProviderCharge(
                true,
                data.TryGetProperty("id", out var pid) ? pid.GetRawText() : null,
                reference,
                data.TryGetProperty("amount", out var am) ? am.GetInt64() : 0,
                data.TryGetProperty("currency", out var cu) ? cu.GetString() ?? "" : "",
                data.TryGetProperty("paid_at", out var pa) && pa.ValueKind == JsonValueKind.String
                    && DateTime.TryParse(pa.GetString(), null,
                        System.Globalization.DateTimeStyles.AdjustToUniversal, out var dt) ? dt : DateTime.UtcNow,
                data.TryGetProperty("channel", out var ch) ? ch.GetString() : null,
                null);
        }

        public ProviderWebhookEvent ParseWebhook(string payload, string signatureHeader)
        {
            var computed = Convert.ToHexString(
                new HMACSHA512(Encoding.UTF8.GetBytes(_secret))
                    .ComputeHash(Encoding.UTF8.GetBytes(payload))).ToLowerInvariant();
            var valid = IsConfigured
                        && string.Equals(computed, signatureHeader?.Trim(), StringComparison.OrdinalIgnoreCase);

            string eventType = "unknown"; string? reference = null, extId = null, channel = null, failure = null;
            long amountMinor = 0; string currency = ""; var paidAt = DateTime.UtcNow;
            try
            {
                using var doc = JsonDocument.Parse(payload);
                eventType = doc.RootElement.TryGetProperty("event", out var ev)
                    ? ev.GetString() ?? "unknown" : "unknown";
                if (doc.RootElement.TryGetProperty("data", out var data))
                {
                    reference = data.TryGetProperty("reference", out var rf) ? rf.GetString() : null;
                    extId = data.TryGetProperty("id", out var idp) ? idp.GetRawText() : null;
                    amountMinor = data.TryGetProperty("amount", out var am) ? am.GetInt64() : 0;
                    currency = data.TryGetProperty("currency", out var cu) ? cu.GetString() ?? "" : "";
                    channel = data.TryGetProperty("channel", out var chp) ? chp.GetString() : null;
                    failure = data.TryGetProperty("gateway_response", out var gr) ? gr.GetString() : null;
                    if (data.TryGetProperty("paid_at", out var pa) && pa.ValueKind == JsonValueKind.String)
                        DateTime.TryParse(pa.GetString(), null,
                            System.Globalization.DateTimeStyles.AdjustToUniversal, out paidAt);
                }
            }
            catch { /* unparseable body: reported to the caller as-is, never a 500 at the provider */ }

            return new ProviderWebhookEvent(valid, eventType, reference, extId, amountMinor, currency, paidAt, channel, failure);
        }
    }
}
