namespace MistralApp.Core.Events
{
    public class DocumentEvent
    {
        public string DocumentId { get; set; } = string.Empty;
        public DocumentEventType EventType { get; set; }
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
        public Dictionary<string, object> Metadata { get; set; } = new();
    }

    public enum DocumentEventType
    {
        Created,
        Processing,
        Analyzed,
        MetadataExtracted,
        Completed,
        Failed
    }

    public interface IEventBus
    {
        Task PublishAsync<T>(T @event) where T : class;
        Task SubscribeAsync<T>(Func<T, Task> handler) where T : class;
    }
}
