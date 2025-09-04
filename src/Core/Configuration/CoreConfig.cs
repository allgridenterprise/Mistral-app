using System.Collections.Generic;

namespace MistralApp.Core.Configuration
{
    public class WorkspaceConfig
    {
        public required string RootPath { get; set; }
        public required string WorkingPath { get; set; }
        public required string OutputPath { get; set; }
        public Dictionary<string, string> Mappings { get; set; } = new();
        public ProcessingOptions ProcessingOptions { get; set; } = new();
    }

    public class ProcessingOptions
    {
        public bool ExtractMetadata { get; set; } = true;
        public bool PerformOcr { get; set; } = false;
        public bool EnableAiAnalysis { get; set; } = true;
        public int MaxConcurrentProcessing { get; set; } = 2;
        public List<string> SupportedFileTypes { get; set; } = new();
    }
}
