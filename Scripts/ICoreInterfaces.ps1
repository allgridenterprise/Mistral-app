# Definer hovedkontraktene
@'
namespace MistralApp.Core.Interfaces
{
    public interface IDocumentProcessor
    {
        Task<ProcessingResult> ProcessAsync(string filePath, ProcessingOptions options);
        Task<ProcessingStatus> GetStatusAsync(string documentId);
    }

    public interface IWorkspaceManager
    {
        Task<string> CreateWorkspaceAsync(string name);
        Task<bool> ConfigureWorkspaceAsync(string workspaceId, WorkspaceConfig config);
        Task<WorkspaceStatus> GetStatusAsync(string workspaceId);
    }

    public interface IStorageProvider
    {
        Task<string> StoreAsync(Stream content, string path);
        Task<Stream> RetrieveAsync(string path);
        Task<bool> ExistsAsync(string path);
    }
}
'@ | Out-File -FilePath "src\Core\Interfaces\ICore.cs" -Encoding UTF8
