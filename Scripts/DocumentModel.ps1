# Oppdater DocumentModel.cs med required modifiers
@'
using System;
using System.Collections.Generic;

namespace MistralApp.Models
{
    public class DocumentModel
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public required string FilePath { get; set; }
        public required string DocumentType { get; set; }
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
'@ | Out-File -FilePath "Models\DocumentModel.cs" -Encoding UTF8 -Force
