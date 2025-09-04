@'
using Microsoft.Extensions.DependencyInjection;

namespace MistralApp.Core
{
    public static class CoreServiceConfiguration
    {
        public static IServiceCollection AddCoreServices(
            this IServiceCollection services,
            WorkspaceConfig config)
        {
            // Core services
            services.AddSingleton<IWorkspaceManager, WorkspaceManager>();
            services.AddSingleton<IDocumentProcessor, DocumentProcessor>();
            services.AddSingleton<IEventBus, InMemoryEventBus>();
            
            // Infrastructure
            services.AddSingleton<IStorageProvider>(
                new LocalStorageProvider(config.RootPath)
            );
            
            // Configuration
            services.AddSingleton(config);
            
            return services;
        }
    }
}
'@ | Out-File -FilePath "src\Core\CoreServiceConfiguration.cs" -Encoding UTF8
