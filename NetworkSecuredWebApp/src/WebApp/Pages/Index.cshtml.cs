using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using WebApp.Models;
using WebApp.Repository;

namespace WebApp.Pages
{
    public class IndexModel : PageModel
    {
        private readonly ILogger<IndexModel> _logger;
        private readonly OrgDbContext orgDbContext;
        [BindProperty]
        public List<Employee> Employees { get; set; }
        public IndexModel(ILogger<IndexModel> logger, OrgDbContext orgDbContext)
        {
            _logger = logger;
            this.orgDbContext = orgDbContext;
        }

        public void OnGet()
        {
            this.Employees = orgDbContext.Employees.ToList();
        }
    }
}