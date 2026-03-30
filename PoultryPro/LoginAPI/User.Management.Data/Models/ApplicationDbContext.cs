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
                builder.Property(x => x.IsSubscriber).HasColumnType("BIT");
                builder.Property(x => x.IsAdmin).HasColumnType("BIT");
            }
        }
    }
}
