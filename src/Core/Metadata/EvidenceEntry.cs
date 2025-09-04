namespace MistralApp.Core.Metadata
{
    // Felles hovedskjema for ALLE dokumenttyper
    public class EvidenceEntry
    {
        public required string Id { get; init; }                // Unik ID
        public required string SourceType { get; init; }        // f.eks. "journal", "sms", "e-post", "dom"
        public required DateTime Date { get; init; }
        public List<string> Parties { get; set; } = new();      // Parter/aktører
        public List<string> Topics { get; set; } = new();       // Emner/tema
        public string OriginalDocumentLink { get; set; } = "";  // Path/URI
        public string MainText { get; set; } = "";              // Selve tekstinnholdet / utdrag
        public Dictionary<string, object> ExtraFields { get; set; } = new();
        // F.eks. "court_reference", "case_number", "emojiFlags", "ruleRefs", "commentary" mm.
    }
}
