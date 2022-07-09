using Microsoft.EntityFrameworkCore;
using WebApp.Models;

namespace WebApp.Repository
{
    public class OrgDbContext : DbContext
    {
        public OrgDbContext(DbContextOptions<OrgDbContext> options) : base(options)
        {

        }

        public DbSet<Employee> Employees { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Employee>().ToTable("Employee").HasKey("Id");
            base.OnModelCreating(modelBuilder);
        }
    }
}
