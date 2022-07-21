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
        [BindProperty]
        public string PublicIP { get; set; }
        public IndexModel(ILogger<IndexModel> logger, OrgDbContext orgDbContext)
        {
            _logger = logger;
            this.orgDbContext = orgDbContext;
        }

        public void OnGet()
        {
            this.Employees = new List<Employee>();
            this.Employees = orgDbContext.Employees.ToList();

            HttpClient httpClient = new HttpClient();
            PublicIP =  httpClient.GetStringAsync("https://api.my-ip.io/ip").GetAwaiter().GetResult();
        }
    }
}