using System.Diagnostics.CodeAnalysis;

namespace MistralApp.Core
{
    // Juridisk og dokumentasjonsnøktern støtte, minimum for funksjonalitet
    public class VerificationContext {}
    public class PremiseViolation {}
    public class SystemicPattern {}
    public class TimelineAnalysis {}

    [SuppressMessage("Style", "IDE1006:Naming Styles", Justification = "Stubs")]
    public class EMDPremise {
        public EMDPremise(string code, string desc, PremiseCategory category) {}
    }

    [SuppressMessage("Style", "IDE1006:Naming Styles", Justification = "Stubs")]
    public class ValidationRule {
        public ValidationRule(string code, string desc, double severity) {}
    }

    public class FactualAnalysis {}
    public class EvidenceType {}
    public class CrossReference {}
    public class WorkspaceConfig 
    {
        public string? RootPath { get; set; }
    }
    public class WorkspaceStatus {}
    public class ProcessingOptions {}
    public class ProcessingResult {}
    public enum ProcessingStatus { Draft, Final, Error }
    public enum PremiseCategory { Fundamental, Procedural }
}
namespace MistralApp.Core.Analysis.EMD { public class MistralApiClient {} }
