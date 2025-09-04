using System.IO;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using MistralApp.Core.Interfaces;

namespace MistralApp.Infrastructure.Storage
{
    public class LocalStorageProvider : IStorageProvider
    {
        private readonly string _rootPath;
        private readonly ILogger<LocalStorageProvider> _logger;

        public LocalStorageProvider(string rootPath, ILogger<LocalStorageProvider> logger)
        {
            _rootPath = rootPath;
            _logger = logger;
            
            Directory.CreateDirectory(_rootPath);
        }

        public async Task<string> StoreAsync(Stream content, string path)
        {
            var fullPath = Path.Combine(_rootPath, path);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            
            using var fileStream = File.Create(fullPath);
            await content.CopyToAsync(fileStream);
            
            return path;
        }

        public Task<Stream> RetrieveAsync(string path)
        {
            var fullPath = Path.Combine(_rootPath, path);
            return Task.FromResult<Stream>(File.OpenRead(fullPath));
        }

        public Task<bool> ExistsAsync(string path)
        {
            var fullPath = Path.Combine(_rootPath, path);
            return Task.FromResult(File.Exists(fullPath));
        }
    }
}
