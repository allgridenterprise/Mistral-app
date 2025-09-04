# Opprett WorkspaceManager som kobler sammen dokumenthåndtering med resten av systemet
@'
using System;
using System.IO;
using System.Threading.Tasks;
using System.Collections.Generic;
using MistralApp.Models;

namespace MistralApp.Services
{
    public class WorkspaceManager
    {
        private readonly string _rootPath;
        private readonly DocumentService _documentService;
        private readonly MistralApiClient _mistralClient;
        private readonly Dictionary<string, string> _workspaceFolders;

        public WorkspaceManager(
            string rootPath,
            DocumentService documentService,
            MistralApiClient mistralClient)
        {
            _rootPath = rootPath;
            _documentService = documentService;
            _mistralClient = mistralClient;
            _workspaceFolders = new Dictionary<string, string>();
            
            InitializeWorkspace();
        }

        private void InitializeWorkspace()
        {
            // Definerer standard mappehierarki
            var folders = new[]
            {
                "input",
                "working",
                "output",
                "temp",
                "processed",
                "failed"
            };

            foreach (var folder in folders)
            {
                var path = Path.Combine(_rootPath, folder);
                Directory.CreateDirectory(path);
                _workspaceFolders[folder] = path;
            }
        }

        public async Task<DocumentModel> ProcessNewDocumentAsync(string inputFile)
        {
            try
            {
                // Initialiser dokument
                var doc = await _documentService.InitializeDocumentAsync(inputFile);
                
                // Analyser med Mistral AI
                var analysisPrompt = $"Analyser følgende dokument: {Path.GetFileName(inputFile)}";
                var analysis = await _mistralClient.CompleteChatAsync("mistral-small-latest", analysisPrompt);
                
                // Oppdater metadata
                doc.Metadata["analysis"] = analysis;
                doc.Metadata["processedDate"] = DateTime.Now;
                
                // Flytt til prosessert-mappe
                var processedPath = Path.Combine(
                    _workspaceFolders["processed"], 
                    Path.GetFileName(inputFile)
                );
                File.Move(doc.FilePath, processedPath);
                doc.FilePath = processedPath;
                doc.Status = ProcessingStatus.Completed;
                
                return doc;
            }
            catch (Exception ex)
            {
                // Håndter feil - flytt til failed-mappe
                var failedPath = Path.Combine(
                    _workspaceFolders["failed"], 
                    Path.GetFileName(inputFile)
                );
                if (File.Exists(inputFile))
                {
                    File.Move(inputFile, failedPath);
                }
                
                throw new WorkspaceException($"Feil ved prosessering av dokument: {ex.Message}", ex);
            }
        }

        public string GetFolderPath(string folderType)
        {
            return _workspaceFolders.TryGetValue(folderType, out var path)
                ? path
                : throw new KeyNotFoundException($"Mappe ikke funnet: {folderType}");
        }
    }

    public class WorkspaceException : Exception
    {
        public WorkspaceException(string message, Exception innerException) 
            : base(message, innerException)
        {
        }
    }
}
'@ | Out-File -FilePath "Services\WorkspaceManager.cs" -Encoding UTF8
