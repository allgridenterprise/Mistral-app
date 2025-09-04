# Opprett hovedmappestrukturen
$folders = @(
    "Core",
    "Core\Analysis",
    "Core\Analysis\EMD",
    "Core\Analysis\FactPattern",
    "Core\Analysis\Validation",
    "Core\Evidence",
    "Core\Processing"
)

foreach ($folder in $folders)
{
    $path = Join-Path "src" $folder
    New-Item -Path $path -ItemType Directory -Force
}

# Bekreft at mappene er opprettet
Write-Host "Mappestruktur opprettet. Fortsetter med filopprettelse..."

# Nå kan vi opprette filene i riktig struktur
# Først EMDStandards
$emdStandardsPath = Join-Path "src" "Core\Analysis\EMD\EMDStandards.cs"
@'
namespace MistralApp.Core.Analysis.EMD
{
    public static class EMDStandards
    {
        public static class ChildrensBest
        {
            public static readonly EMDPremise RightToFamilyLife = new(
                "ECHR-8",
                "Rett til familieliv",
                PremiseCategory.Fundamental
            );

            public static readonly EMDPremise ProportionalityPrinciple = new(
                "ECHR-PP",
                "Proporsjonalitetsprinsippet",
                PremiseCategory.Procedural
            );

            public static readonly List<ValidationRule> CoreValidations = new()
            {
                new ValidationRule(
                    "CBV-1",
                    "Proporsjonalitet i inngrep",
                    severity: 1.0
                ),
                new ValidationRule(
                    "CBV-2",
                    "Dokumentert vurdering av alternativer",
                    severity: 0.9
                )
            };
        }
    }
}
'@ | Out-File -FilePath $emdStandardsPath -Encoding UTF8

# Så FactualAnalyzer
$factAnalyzerPath = Join-Path "src" "Core\Analysis\FactPattern\FactualAnalyzer.cs"
@'
namespace MistralApp.Core.Analysis.FactPattern
{
    public class FactualAnalyzer
    {
        private readonly IPatternAnalyzer _patternAnalyzer;
        private readonly MistralApiClient _mistralClient;
        
        public class FactualEvidence
        {
            public required string EventId { get; init; }
            public DateTime Timestamp { get; init; }
            public EvidenceType Type { get; init; }
            public double VerificationScore { get; set; }
            public List<string> SupportingDocuments { get; set; } = new();
            public List<CrossReference> References { get; set; } = new();
        }

        public async Task<FactualAnalysis> AnalyzeFactsVsClaims(string caseId)
        {
            var analysis = new FactualAnalysis();
            
            // Ekstraher verifiserbare fakta
            var facts = await ExtractVerifiableEvents(caseId);
            
            // Analyser mot påstander
            foreach (var fact in facts)
            {
                if (await ValidateEvidence(fact))
                {
                    analysis.AddVerifiedFact(fact);
                }
            }
            
            return analysis;
        }
    }
}
'@ | Out-File -FilePath $factAnalyzerPath -Encoding UTF8

# Opprett basisklasser for evidens
$evidenceBasePath = Join-Path "src" "Core\Evidence\EvidenceBase.cs"
@'
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
'@ | Out-File -FilePath $evidenceBasePath -Encoding UTF8

Write-Host "Grunnleggende filstruktur er opprettet. Klar for videre implementasjon."
