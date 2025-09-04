namespace MistralApp.Core.Evidence
{
    public class Evidence
    {
        public required string Id { get; init; }
        public required DateTime Timestamp { get; init; }
        public required string Source { get; init; }
        public required EvidenceType Type { get; init; }
        public double Reliability { get; set; }
        public List<string> References { get; set; } = new();
    }

    public enum EvidenceType
    {
        Document,
        Meeting,
        Communication,
        Decision,
        Action,
        Observation
    }
}
