using System;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.DependencyInjection;
using MistralApp.Core.Configuration;
using MistralApp.Core.Interfaces;
using MistralApp.Core.Events;
using MistralApp.Infrastructure.Storage;

namespace MistralApp.Core
{
    // Stubs for manglende klasser for å la prosjektet bygge
    public class WorkspaceManager : IWorkspaceManager {
        public Task<string> CreateWorkspaceAsync(string name) => Task.FromResult("");
        public Task<bool> ConfigureWorkspaceAsync(string workspaceId, WorkspaceConfig config) => Task.FromResult(true);
        public Task<WorkspaceStatus> GetStatusAsync(string workspaceId) => Task.FromResult(new WorkspaceStatus());
    }
    public class DocumentProcessor : IDocumentProcessor {
        public Task<ProcessingResult> ProcessAsync(string filePath, ProcessingOptions options) => Task.FromResult(new ProcessingResult());
        public Task<ProcessingStatus> GetStatusAsync(string documentId) => Task.FromResult(ProcessingStatus.Draft);
    }
    public class InMemoryEventBus : IEventBus {
        public Task PublishAsync<T>(T @event) where T : class => Task.CompletedTask;
        public Task SubscribeAsync<T>(Func<T, Task> handler) where T : class => Task.CompletedTask;
    }


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
            services.AddSingleton<IStorageProvider>(provider => 
                new LocalStorageProvider(config.RootPath ?? "", provider.GetRequiredService<Microsoft.Extensions.Logging.ILogger<LocalStorageProvider>>())
            );
            
            // Configuration
            services.AddSingleton(config);
            
            return services;
        }
    }
}

