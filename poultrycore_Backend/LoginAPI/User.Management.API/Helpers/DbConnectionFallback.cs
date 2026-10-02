// DbConnectionFallback — pick a database connection string that actually works,
// once, at startup.
//
// KEEP IN SYNC: an identical copy lives in
//   PoultryFarmAPI/Helpers/DbConnectionFallback.cs  (and LoginAPI/User.Management.API/Helpers/)
// (each API's Docker build only sees its own folder, so the file can't be
// shared), and Tools/RunMigration compiles this copy directly.
//
// ORDER
//   1. MAIN      ConnectionStrings:<name>            — the normal setting (the
//                database's own address; what Cloud Run and teammates use).
//   2. FALLBACK  ConnectionStrings:<name>Fallback    — if set.
//                Otherwise, in Development only, the MAIN string with its host
//                and port swapped for a local Cloud SQL proxy:
//                  Host = Database:ProxyHost (default 127.0.0.1)
//                  Port = Database:ProxyPort (default 5433)
//                  SSL Mode = Prefer (the proxy usually doesn't offer SSL locally)
//                So anyone running the proxy gets it with no extra setting,
//                and anyone who isn't loses only a few seconds at startup.
//
// Each candidate is tried with a short timeout. If neither answers, the whole
// round is retried (Database:ConnectRounds, default 2, 2 s apart; each try Database:ConnectTimeoutSeconds, default 4) in case the
// proxy or the network is still starting. If nothing works the MAIN string is
// kept and the app starts anyway, so the error surfaces on the first query
// exactly as it did before this helper existed.
//
// Set Database:DisableFallback=true to skip all of this and use MAIN as-is.
// The chosen string is written back into configuration, so code that reads
// IConfiguration.GetConnectionString(<name>) later gets the same one.
// Passwords are never logged.

using System;
using System.Collections.Generic;
using System.Threading;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace PoultryCore.Db
{
    public static class DbConnectionFallback
    {
        public static string Resolve(IConfiguration config, string name, bool isDevelopment, Action<string>? log = null)
        {
            log ??= Console.WriteLine;
            var main = config.GetConnectionString(name);
            if (string.IsNullOrWhiteSpace(main)) return main ?? "";
            if (string.Equals(config["Database:DisableFallback"], "true", StringComparison.OrdinalIgnoreCase)) return main;

            var candidates = new List<(string Label, string Cs)> { ("main", main) };
            var fallback = config.GetConnectionString(name + "Fallback");
            if (string.IsNullOrWhiteSpace(fallback) && isDevelopment)
                fallback = DeriveProxy(main, config);
            if (!string.IsNullOrWhiteSpace(fallback) && !SameServer(main, fallback))
                candidates.Add(("fallback", fallback));

            if (candidates.Count == 1) return main; // nothing to fall back to: leave startup exactly as before

            var rounds = int.TryParse(config["Database:ConnectRounds"], out var r) && r > 0 ? r : 2;
            var timeout = int.TryParse(config["Database:ConnectTimeoutSeconds"], out var t) && t > 0 ? t : 4;

            for (var round = 1; round <= rounds; round++)
            {
                foreach (var (label, cs) in candidates)
                {
                    var error = TryConnect(cs, timeout);
                    if (error is null)
                    {
                        log($"[DB] {name}: using {label} connection {Describe(cs)}");
                        config[$"ConnectionStrings:{name}"] = cs;
                        return cs;
                    }
                    log($"[DB] {name}: {label} {Describe(cs)} failed (round {round}/{rounds}): {error}");
                }
                if (round < rounds) Thread.Sleep(2000);
            }
            log($"[DB] {name}: no connection answered; keeping main {Describe(main)}. " +
                "Start the Cloud SQL proxy on port 5433, or allow this PC's IP in Cloud SQL, then restart.");
            return main;
        }

        /// <summary>The main string pointed at the local proxy, same database and credentials.</summary>
        public static string? DeriveProxy(string main, IConfiguration config)
        {
            try
            {
                var b = new NpgsqlConnectionStringBuilder(main)
                {
                    Host = string.IsNullOrWhiteSpace(config["Database:ProxyHost"]) ? "127.0.0.1" : config["Database:ProxyHost"],
                    Port = int.TryParse(config["Database:ProxyPort"], out var p) ? p : 5433,
                    SslMode = SslMode.Prefer,
                };
                return b.ConnectionString;
            }
            catch { return null; } // not a PostgreSQL string: no derived fallback
        }

        static string? TryConnect(string cs, int timeoutSeconds)
        {
            try
            {
                var b = new NpgsqlConnectionStringBuilder(cs) { Timeout = timeoutSeconds, Pooling = false };
                using var c = new NpgsqlConnection(b.ConnectionString);
                c.Open();
                using var cmd = new NpgsqlCommand("SELECT 1", c);
                cmd.ExecuteScalar();
                return null;
            }
            catch (Exception ex) { return ex.GetBaseException().Message; }
        }

        static bool SameServer(string a, string b)
        {
            try
            {
                var x = new NpgsqlConnectionStringBuilder(a); var y = new NpgsqlConnectionStringBuilder(b);
                return string.Equals(x.Host, y.Host, StringComparison.OrdinalIgnoreCase) && x.Port == y.Port;
            }
            catch { return false; }
        }

        public static string Describe(string cs)
        {
            try { var b = new NpgsqlConnectionStringBuilder(cs); return $"{b.Host}:{b.Port}/{b.Database}"; }
            catch { return "(unparseable connection string)"; }
        }
    }
}
