// =============================================================================
// Phase 1 Acceptance Tests — Unified Generic Item Architecture (Migration 441)
//
// Tests marked [Trait("Category","Integration")] require a live PostgreSQL
// connection string in the GENERIC_ITEM_TEST_CONN environment variable.
// All other tests are pure unit / model tests.
// =============================================================================

using System.ComponentModel.DataAnnotations;
using Npgsql;
using PoultryFarmAPIWeb.Models;
using PoultryFarmAPIWeb.Business;
using Xunit;

namespace GenericItem.Tests
{
    // =========================================================================
    // 1–3. Model & capability tests (pure unit, no DB)
    // =========================================================================
    public class GenericProductModelTests
    {
        [Fact]
        public void Default_product_has_CanSell_true()
        {
            var m = new GenericProductModel();
            Assert.True(m.CanSell);
            Assert.False(m.CanUseInProduction);
            Assert.False(m.CanUseInternally);
            Assert.Equal("Product", m.ItemType);
        }

        [Fact]
        public void Item_can_have_single_purpose()
        {
            var m = new GenericProductModel { CanSell = true, CanUseInProduction = false, CanUseInternally = false };
            Assert.True(m.CanSell);
            Assert.False(m.CanUseInProduction);
            Assert.False(m.CanUseInternally);
        }

        [Fact]
        public void Item_can_have_multiple_purposes()
        {
            var m = new GenericProductModel
            {
                ProductName = "Packaging Bags",
                CanSell = true,
                CanUseInProduction = true,
                CanUseInternally = true
            };
            Assert.True(m.CanSell);
            Assert.True(m.CanUseInProduction);
            Assert.True(m.CanUseInternally);
        }

        [Fact]
        public void Maize_example_from_spec()
        {
            var m = new GenericProductModel
            {
                ProductName = "Maize",
                CanSell = true,
                CanUseInProduction = true,
                CanUseInternally = false
            };
            Assert.True(m.CanSell);
            Assert.True(m.CanUseInProduction);
            Assert.False(m.CanUseInternally);
        }

        [Fact]
        public void Rice_for_workers_example_from_spec()
        {
            var m = new GenericProductModel
            {
                ProductName = "Rice for Workers",
                CanSell = false,
                CanUseInProduction = false,
                CanUseInternally = true
            };
            Assert.False(m.CanSell);
            Assert.False(m.CanUseInProduction);
            Assert.True(m.CanUseInternally);
        }

        [Fact]
        public void Custom_category_association()
        {
            var m = new GenericProductModel
            {
                GenericProductCategoryId = 42,
                CategoryName = "Raw Materials"
            };
            Assert.Equal(42, m.GenericProductCategoryId);
            Assert.Equal("Raw Materials", m.CategoryName);
        }

        [Fact]
        public void Description_separate_from_notes()
        {
            var m = new GenericProductModel
            {
                Description = "High-grade maize flour suitable for production and resale.",
                Notes = "Reorder from Supplier X when stock < 100 bags."
            };
            Assert.NotEqual(m.Description, m.Notes);
            Assert.NotNull(m.Description);
        }

        [Fact]
        public void PurchaseUnit_and_SalesUnit_separate_from_base_unit()
        {
            var m = new GenericProductModel
            {
                UnitOfMeasure = "kg",
                PurchaseUnit = "bag",
                SalesUnit = "piece"
            };
            Assert.Equal("kg", m.UnitOfMeasure);
            Assert.Equal("bag", m.PurchaseUnit);
            Assert.Equal("piece", m.SalesUnit);
        }

        [Fact]
        public void ItemType_defaults_to_Product()
        {
            Assert.Equal("Product", new GenericProductModel().ItemType);
        }

        [Fact]
        public void SupplyItem_type_does_not_force_CanSell()
        {
            var m = new GenericProductModel
            {
                ItemType = "SupplyItem",
                CanSell = false,
                CanUseInternally = true
            };
            Assert.Equal("SupplyItem", m.ItemType);
            Assert.False(m.CanSell);
        }

        [Fact]
        public void Services_model_unaffected()
        {
            var svc = new GenericServiceModel
            {
                GenericServiceId = 1,
                ServiceName = "Consultation",
                DefaultPrice = 100m
            };
            // GenericServiceModel has no CanSell / CanUseInProduction / CanUseInternally
            var props = typeof(GenericServiceModel).GetProperties();
            Assert.DoesNotContain(props, p => p.Name == "CanSell");
            Assert.DoesNotContain(props, p => p.Name == "TrackInventory");
        }

        [Fact]
        public void UpdatedBy_audit_field_exists()
        {
            var m = new GenericProductModel { UpdatedBy = "admin@acme.com" };
            Assert.Equal("admin@acme.com", m.UpdatedBy);
        }

        [Fact]
        public void TrackInventory_toggle_preserved()
        {
            var tracked = new GenericProductModel { TrackInventory = true };
            var untracked = new GenericProductModel { TrackInventory = false };
            Assert.True(tracked.TrackInventory);
            Assert.False(untracked.TrackInventory);
        }

        [Fact]
        public void ExpiryDate_and_TrackExpiry_preserved()
        {
            var m = new GenericProductModel
            {
                ExpiryDate = new DateTime(2027, 6, 30),
                TrackExpiry = true
            };
            Assert.Equal(new DateTime(2027, 6, 30), m.ExpiryDate);
            Assert.True(m.TrackExpiry);
        }
    }

    // =========================================================================
    // 4–5. Company isolation and SKU uniqueness model validation
    // =========================================================================
    public class CompanyIsolationTests
    {
        [Fact]
        public void Items_from_different_companies_have_different_FarmId()
        {
            var item1 = new GenericProductModel { FarmId = "company-A", ProductName = "Widget" };
            var item2 = new GenericProductModel { FarmId = "company-B", ProductName = "Widget" };
            Assert.NotEqual(item1.FarmId, item2.FarmId);
        }

        [Fact]
        public void Same_name_different_companies_are_distinct()
        {
            var item1 = new GenericProductModel { FarmId = "co-1", ProductName = "Nails", GenericProductId = 1 };
            var item2 = new GenericProductModel { FarmId = "co-2", ProductName = "Nails", GenericProductId = 2 };
            Assert.Equal(item1.ProductName, item2.ProductName);
            Assert.NotEqual(item1.GenericProductId, item2.GenericProductId);
        }
    }

    // =========================================================================
    // 6–12. Migration & Integration tests (require live DB)
    // =========================================================================
    [Trait("Category", "Integration")]
    public class GenericItemIntegrationTests : IAsyncLifetime
    {
        private readonly string? _connectionString;
        private string _farmId = null!;
        private IGenericProductService _service = null!;

        public GenericItemIntegrationTests()
        {
            _connectionString = Environment.GetEnvironmentVariable("GENERIC_ITEM_TEST_CONN");
        }

        public async Task InitializeAsync()
        {
            if (_connectionString is null) return;

            _farmId = $"test-farm-{Guid.NewGuid():N}";
            _service = new GenericProductService(_connectionString);

            // Ensure migration 441 columns exist (migration must have been applied)
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                SELECT column_name FROM information_schema.columns
                WHERE table_name = 'genericproducts' AND column_name IN ('cansell','canuseinproduction','canuseinternally')";
            var cols = new List<string>();
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) cols.Add(r.GetString(0));
            Assert.Contains("cansell", cols);
            Assert.Contains("canuseinproduction", cols);
            Assert.Contains("canuseinternally", cols);
        }

        public async Task DisposeAsync()
        {
            if (_connectionString is null) return;
            // Cleanup test data
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                DELETE FROM genericstockmovements WHERE farmid = @fid;
                DELETE FROM genericproducts WHERE farmid = @fid;
                DELETE FROM genericproductcategories WHERE farmid = @fid;";
            cmd.Parameters.AddWithValue("fid", _farmId);
            await cmd.ExecuteNonQueryAsync();
        }

        private void SkipIfNoDb()
        {
            if (_connectionString is null) Skip.If(true, "GENERIC_ITEM_TEST_CONN not set");
        }

        [SkippableFact]
        public async Task Insert_product_with_single_purpose()
        {
            SkipIfNoDb();
            var id = await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId,
                ProductName = "TestProd-Single",
                CostPrice = 10, SellingPrice = 15,
                CanSell = true, CanUseInProduction = false, CanUseInternally = false,
                TrackInventory = false
            });
            var item = await _service.GetByIdAsync(id, _farmId);
            Assert.NotNull(item);
            Assert.True(item!.CanSell);
            Assert.False(item.CanUseInProduction);
            Assert.False(item.CanUseInternally);
        }

        [SkippableFact]
        public async Task Insert_product_with_all_purposes()
        {
            SkipIfNoDb();
            var id = await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId,
                ProductName = "TestProd-AllPurpose",
                CostPrice = 5, SellingPrice = 12,
                CanSell = true, CanUseInProduction = true, CanUseInternally = true,
                TrackInventory = false
            });
            var item = await _service.GetByIdAsync(id, _farmId);
            Assert.NotNull(item);
            Assert.True(item!.CanSell);
            Assert.True(item.CanUseInProduction);
            Assert.True(item.CanUseInternally);
        }

        [SkippableFact]
        public async Task Category_association_roundtrips()
        {
            SkipIfNoDb();
            var catId = await _service.InsertCategoryAsync(new GenericProductCategoryModel
            {
                FarmId = _farmId, Name = "Test-Category-441"
            });
            var prodId = await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId, ProductName = "CatTest",
                GenericProductCategoryId = catId,
                TrackInventory = false
            });
            var item = await _service.GetByIdAsync(prodId, _farmId);
            Assert.NotNull(item);
            Assert.Equal(catId, item!.GenericProductCategoryId);
            Assert.Equal("Test-Category-441", item.CategoryName);
        }

        [SkippableFact]
        public async Task Same_name_items_not_merged()
        {
            SkipIfNoDb();
            var id1 = await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId, ProductName = "Duplicate-Name-Test",
                CostPrice = 1, SellingPrice = 2, TrackInventory = false
            });
            var id2 = await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId, ProductName = "Duplicate-Name-Test",
                CostPrice = 3, SellingPrice = 4, TrackInventory = false
            });
            Assert.NotEqual(id1, id2);
            var item1 = await _service.GetByIdAsync(id1, _farmId);
            var item2 = await _service.GetByIdAsync(id2, _farmId);
            Assert.Equal(1m, item1!.CostPrice);
            Assert.Equal(3m, item2!.CostPrice);
        }

        [SkippableFact]
        public async Task Opening_stock_creates_movement_and_matches()
        {
            SkipIfNoDb();
            var id = await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId, ProductName = "StockTest",
                CostPrice = 10, SellingPrice = 20,
                OpeningStock = 50, TrackInventory = true
            });
            var item = await _service.GetByIdAsync(id, _farmId);
            Assert.Equal(50m, item!.CurrentStock);

            // Verify movement ledger matches
            await _service.ReconcileStockAsync(_farmId);
            var reconciled = await _service.GetByIdAsync(id, _farmId);
            Assert.Equal(50m, reconciled!.CurrentStock);
        }

        [SkippableFact]
        public async Task Update_preserves_capabilities()
        {
            SkipIfNoDb();
            var id = await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId, ProductName = "UpdateTest",
                CanSell = true, CanUseInProduction = true, CanUseInternally = false,
                TrackInventory = false
            });
            var item = await _service.GetByIdAsync(id, _farmId);
            item!.CanUseInternally = true;
            item.Description = "Updated description";
            item.PurchaseUnit = "carton";
            await _service.UpdateAsync(item);

            var updated = await _service.GetByIdAsync(id, _farmId);
            Assert.True(updated!.CanSell);
            Assert.True(updated.CanUseInProduction);
            Assert.True(updated.CanUseInternally);
            Assert.Equal("Updated description", updated.Description);
            Assert.Equal("carton", updated.PurchaseUnit);
        }

        [SkippableFact]
        public async Task Filtered_queries_return_correct_subsets()
        {
            SkipIfNoDb();
            await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId, ProductName = "SellOnly",
                CanSell = true, CanUseInProduction = false, CanUseInternally = false,
                TrackInventory = false
            });
            await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId, ProductName = "ProdOnly",
                CanSell = false, CanUseInProduction = true, CanUseInternally = false,
                TrackInventory = false
            });
            await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId, ProductName = "InternalOnly",
                CanSell = false, CanUseInProduction = false, CanUseInternally = true,
                TrackInventory = false
            });

            var sellable = await _service.GetSellableAsync(_farmId);
            var production = await _service.GetProductionItemsAsync(_farmId);
            var internalUse = await _service.GetInternalUseItemsAsync(_farmId);

            Assert.Contains(sellable, i => i.ProductName == "SellOnly");
            Assert.DoesNotContain(sellable, i => i.ProductName == "ProdOnly");
            Assert.Contains(production, i => i.ProductName == "ProdOnly");
            Assert.DoesNotContain(production, i => i.ProductName == "SellOnly");
            Assert.Contains(internalUse, i => i.ProductName == "InternalOnly");
            Assert.DoesNotContain(internalUse, i => i.ProductName == "SellOnly");
        }

        [SkippableFact]
        public async Task Company_isolation_enforced()
        {
            SkipIfNoDb();
            var otherFarm = $"other-farm-{Guid.NewGuid():N}";
            await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId, ProductName = "FarmA-Item", TrackInventory = false
            });
            await _service.InsertAsync(new GenericProductModel
            {
                FarmId = otherFarm, ProductName = "FarmB-Item", TrackInventory = false
            });

            var farmAItems = await _service.GetAllAsync(_farmId);
            Assert.DoesNotContain(farmAItems, i => i.ProductName == "FarmB-Item");
            Assert.Contains(farmAItems, i => i.ProductName == "FarmA-Item");

            // Cleanup other farm
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "DELETE FROM genericproducts WHERE farmid = @fid";
            cmd.Parameters.AddWithValue("fid", otherFarm);
            await cmd.ExecuteNonQueryAsync();
        }

        [SkippableFact]
        public async Task Legacy_API_backward_compatible()
        {
            SkipIfNoDb();
            // Insert without specifying new fields — defaults should apply
            var id = await _service.InsertAsync(new GenericProductModel
            {
                FarmId = _farmId,
                ProductName = "LegacyItem",
                CostPrice = 100,
                SellingPrice = 150,
                TrackInventory = false
            });
            var item = await _service.GetByIdAsync(id, _farmId);
            Assert.NotNull(item);
            Assert.True(item!.CanSell);              // default
            Assert.False(item.CanUseInProduction);    // default
            Assert.False(item.CanUseInternally);      // default
            Assert.Equal("Product", item.ItemType);   // default
            Assert.Null(item.Description);
            Assert.Null(item.PurchaseUnit);
            Assert.Null(item.SalesUnit);
        }
    }

    // =========================================================================
    // SQL migration idempotency test
    // =========================================================================
    [Trait("Category", "Integration")]
    public class MigrationIdempotencyTests
    {
        [SkippableFact]
        public async Task Migration_441_is_idempotent()
        {
            var cs = Environment.GetEnvironmentVariable("GENERIC_ITEM_TEST_CONN");
            Skip.If(cs is null, "GENERIC_ITEM_TEST_CONN not set");

            // Read the migration SQL
            var migrationPath = Path.Combine(
                AppContext.BaseDirectory, "..", "..", "..", "..", "..",
                "PoultryFarmAPI", "Migrations",
                "441_GenericUnifiedItemArchitecture.postgres.sql");

            if (!File.Exists(migrationPath))
            {
                // Try alternative path resolution
                migrationPath = Path.GetFullPath(Path.Combine(
                    Directory.GetCurrentDirectory(), "..", "..", "..", "..", "..",
                    "PoultryFarmAPI", "Migrations",
                    "441_GenericUnifiedItemArchitecture.postgres.sql"));
            }

            Skip.If(!File.Exists(migrationPath), $"Migration file not found at {migrationPath}");
            var sql = await File.ReadAllTextAsync(migrationPath);

            await using var conn = new NpgsqlConnection(cs);
            await conn.OpenAsync();

            // Run twice — should not throw
            await using (var cmd1 = new NpgsqlCommand(sql, conn))
                await cmd1.ExecuteNonQueryAsync();
            await using (var cmd2 = new NpgsqlCommand(sql, conn))
                await cmd2.ExecuteNonQueryAsync();
        }
    }

    // =========================================================================
    // Stock movement type coverage test
    // =========================================================================
    public class StockMovementTypesTests
    {
        [Theory]
        [InlineData("OpeningStock")]
        [InlineData("PurchaseIn")]
        [InlineData("SaleOut")]
        [InlineData("ReturnIn")]
        [InlineData("DamageOut")]
        [InlineData("ExpiredOut")]
        [InlineData("InternalUseOut")]
        [InlineData("AdjustmentIn")]
        [InlineData("AdjustmentOut")]
        [InlineData("TransferIn")]
        [InlineData("TransferOut")]
        public void All_stock_movement_types_defined(string type)
        {
            var field = typeof(GenericStockMovementTypes).GetField(type);
            Assert.NotNull(field);
            Assert.Equal(type, field!.GetValue(null));
        }

        [Fact]
        public void Stock_movement_references_product_id()
        {
            var m = new GenericStockMovementModel
            {
                GenericProductId = 42,
                MovementType = GenericStockMovementTypes.PurchaseIn,
                Quantity = 100
            };
            Assert.Equal(42, m.GenericProductId);
            Assert.Equal(100m, m.Quantity);
        }
    }
}
