# Opprett modellklasse for chat-responser
@"
using System.Collections.Generic;
using Newtonsoft.Json;

namespace MistralApp.Models
{
    public class ChatMessage
    {
        public string Role { get; set; }
        public string Content { get; set; }
    }

    public class ChatCompletionChoice
    {
        public ChatMessage Message { get; set; }
        public string FinishReason { get; set; }
        public int Index { get; set; }
    }

    public class ChatCompletionResponse
    {
        public string Id { get; set; }
        public string Object { get; set; }
        public long Created { get; set; }
        public string Model { get; set; }
        public List<ChatCompletionChoice> Choices { get; set; }
        public Usage Usage { get; set; }
    }

    public class Usage
    {
        [JsonProperty("prompt_tokens")]
        public int PromptTokens { get; set; }
        
        [JsonProperty("completion_tokens")]
        public int CompletionTokens { get; set; }
        
        [JsonProperty("total_tokens")]
        public int TotalTokens { get; set; }
    }
}
"@ | Out-File -FilePath "Models\ChatModels.cs" -Encoding UTF8
