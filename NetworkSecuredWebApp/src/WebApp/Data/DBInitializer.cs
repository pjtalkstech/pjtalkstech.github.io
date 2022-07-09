using WebApp.Models;
using WebApp.Repository;

namespace WebApp.Data
{
    public static class DBInitializer
    {
        public static void Initialize(OrgDbContext context)
        {
            context.Database.EnsureCreated();

            if (context.Employees.Any())
            {
                return;
            }

            var emps = new Employee[]
            {
                new Employee{ FirstName ="Scott", LastName ="Hanselmann"},
                new Employee{ FirstName ="Scott", LastName ="Gu"},
                new Employee{ FirstName ="Bill", LastName ="Gates"}
            };

            foreach(var e in emps)
            {
                context.Employees.Add(e);
            }
            context.SaveChanges();
        }


    }
}
