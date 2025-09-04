# Opprett Models-mappe og DocumentModel
mkdir -p Models
@'
using System;

namespace MistralApp.Models
{
    public class DocumentModel
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string FilePath { get; set; }
        public string DocumentType { get; set; }
        public DateTime Created { get; set; } = DateTime.Now;
        public Dictionary<string, object> Metadata { get; set; } = new();
        public ProcessingStatus Status { get; set; }
    }

    public enum ProcessingStatus
    {
        New,
        Processing,
        ReadyForSync,
        Syncing,
        Completed,
        Error
    }
}
'@ | Out-File -FilePath "Models\DocumentModel.cs" -Encoding UTF8

# Opprett Services-mappe og DocumentService
mkdir -p Services
@'
using System.IO;
using MistralApp.Models;

namespace MistralApp.Services
{
    public class DocumentService
    {
        private readonly string _workingFolder;
        private readonly string _outputFolder;

        public DocumentService(string workingFolder, string outputFolder)
        {
            _workingFolder = workingFolder;
            _outputFolder = outputFolder;
            
            // Opprett mappene hvis de ikke eksisterer
            Directory.CreateDirectory(_workingFolder);
            Directory.CreateDirectory(_outputFolder);
        }

        public async Task<DocumentModel> InitializeDocumentAsync(string filePath)
        {
            var doc = new DocumentModel
            {
                FilePath = filePath,
                DocumentType = DetermineDocumentType(filePath),
                Status = ProcessingStatus.New
            };

            // Kopier til arbeidsmappen
            var workingPath = Path.Combine(_workingFolder, Path.GetFileName(filePath));
            File.Copy(filePath, workingPath, true);
            
            return doc;
        }

        private string DetermineDocumentType(string filePath)
        {
            // Enkel dokumenttype-bestemmelse basert på filnavn/innhold
            return Path.GetExtension(filePath).ToLower() switch
            {
                ".pdf" => "PDF",
                ".doc" or ".docx" => "Word",
                ".txt" => "Text",
                _ => "Unknown"
            };
        }
    }
}
'@ | Out-File -FilePath "Services\DocumentService.cs" -Encoding UTF8
