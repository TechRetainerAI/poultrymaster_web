using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace User.Management.Data.Models
{
    public class ApplicationDbContext : IdentityDbContext<ApplicationUser>
    {
        public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options)
        {
        }
        protected override void OnModelCreating(ModelBuilder builder)
        {
            base.OnModelCreating(builder);
            SeedRoles(builder);

            builder.ApplyConfiguration(new ApplicationUserEntityConfiguration());

            // The migrated PostgreSQL schema uses unquoted (therefore lowercase)
            // identifiers: aspnetusers, normalizedusername, and so on. EF always
            // quotes the names it is given, so anything left in CamelCase would
            // produce relation "AspNetUsers" does not exist. IdentityDbContext
            // pins its table names with ToTable("AspNetUsers"), which a naming
            // convention will not override — hence this explicit pass, applied
            // last so it wins over both Identity and our own configuration.
            foreach (var entity in builder.Model.GetEntityTypes())
            {
                var table = entity.GetTableName();
                if (table is not null)
                    entity.SetTableName(table.ToLowerInvariant());

                foreach (var property in entity.GetProperties())
                {
                    var column = property.GetColumnName();
                    if (column is not null)
                        property.SetColumnName(column.ToLowerInvariant());
                }

                foreach (var key in entity.GetKeys())
                    key.SetName(key.GetName()?.ToLowerInvariant());

                foreach (var fk in entity.GetForeignKeys())
                    fk.SetConstraintName(fk.GetConstraintName()?.ToLowerInvariant());

                foreach (var index in entity.GetIndexes())
                    index.SetDatabaseName(index.GetDatabaseName()?.ToLowerInvariant());
            }
        }

        private static void SeedRoles(ModelBuilder builder)
        {
            builder.Entity<IdentityRole>().HasData
                (
                new IdentityRole() { Name = "Admin", ConcurrencyStamp = "1", NormalizedName = "Admin" },
                new IdentityRole() { Name = "User", ConcurrencyStamp = "2", NormalizedName = "User" },
                 new IdentityRole() { Name = "HR", ConcurrencyStamp = "3", NormalizedName = "HR" }
                );
        }


        public class ApplicationUserEntityConfiguration : IEntityTypeConfiguration<ApplicationUser>
        {
            public void Configure(EntityTypeBuilder<ApplicationUser> builder)
            {
                builder.Property(x => x.FirstName).HasMaxLength(255);
                builder.Property(x => x.LastName).HasMaxLength(255);
                builder.Property(x => x.PhoneNumber).HasMaxLength(255);
                builder.Property(x => x.CustomerId).HasMaxLength(255);
                builder.Property(x => x.AdminTitle).HasMaxLength(100);
                // bool maps to PostgreSQL boolean natively (was HasColumnType("BIT") on SQL Server)
                builder.Property(x => x.IsSubscriber);
                builder.Property(x => x.IsAdmin);
            }
        }
    }
}
