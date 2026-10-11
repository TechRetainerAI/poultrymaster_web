using System;
using System.Collections.Generic;
using System.Linq;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using Xunit;

namespace PlatformActivity.Tests
{
    public class TimelineBuilderTests
    {
        private static TimelineEventDto Ev(int daysAgo, string kind = "Note") => new()
        {
            AtUtc = new DateTime(2026, 10, 11, 12, 0, 0, DateTimeKind.Utc).AddDays(-daysAgo),
            Kind = kind,
            Title = $"{kind} {daysAgo}",
        };

        [Fact]
        public void Merge_SortsNewestFirst_AcrossSources()
        {
            var merged = TimelineBuilder.Merge(100,
                new[] { Ev(5), Ev(1) },
                new[] { Ev(3), Ev(10) });
            Assert.Equal(new[] { "Note 1", "Note 3", "Note 5", "Note 10" },
                merged.Select(e => e.Title).ToArray());
        }

        [Fact]
        public void Merge_RespectsLimit()
        {
            var merged = TimelineBuilder.Merge(2, new[] { Ev(1), Ev(2), Ev(3) });
            Assert.Equal(2, merged.Count);
            Assert.Equal("Note 1", merged[0].Title);
        }

        [Fact]
        public void HealthTransitions_EmitOnlyChanges()
        {
            var baseAt = new DateTime(2026, 9, 1, 0, 0, 0, DateTimeKind.Utc);
            var rows = new List<(DateTime, string, string?, string?)>
            {
                (baseAt, "Healthy", "Farm A", "a"),
                (baseAt.AddDays(1), "Healthy", "Farm A", "a"),     // no change: suppressed
                (baseAt.AddDays(2), "At Risk", "Farm A", "a"),     // change: emitted
                (baseAt.AddDays(3), "Healthy", "Farm B", "b"),     // separate subject
            };
            var events = TimelineBuilder.HealthTransitions(rows);
            Assert.Equal(3, events.Count);
            Assert.Contains(events, e => e.Title.Contains("changed to At Risk") && e.CompanyId == "a");
            Assert.Contains(events, e => e.Title.Contains("recorded as Healthy") && e.CompanyId == "b");
        }

        [Fact]
        public void HealthTransitions_KeepSubjectsIndependent()
        {
            var baseAt = new DateTime(2026, 9, 1, 0, 0, 0, DateTimeKind.Utc);
            var rows = new List<(DateTime, string, string?, string?)>
            {
                (baseAt, "Healthy", "A", "a"),
                (baseAt.AddDays(1), "Healthy", "B", "b"),   // same level, DIFFERENT subject: emitted
            };
            Assert.Equal(2, TimelineBuilder.HealthTransitions(rows).Count);
        }
    }

    public class VerticalSummaryRegistryTests
    {
        [Fact]
        public void EveryFamily_HasAnAdapter()
        {
            foreach (var family in new[] { "Poultry", "Water", "Hotel", "Restaurant", "Generic" })
                Assert.Contains(family, CustomerCrmService.SupportedSummaryFamilies);
        }

        [Fact]
        public void UnknownFamily_HasNoAdapter_SummaryStaysEmpty()
        {
            Assert.DoesNotContain("System", CustomerCrmService.SupportedSummaryFamilies);
            Assert.DoesNotContain("Pharmacy", CustomerCrmService.SupportedSummaryFamilies);
        }
    }
}
