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
            
            // 1. Hent ut faktiske hendelser - dokumenterte, tidsstemplede, verifiserbare
            var facts = await ExtractVerifiableEvents(caseId);
            
            // 2. Hent ut påstander og argumenter
            var claims = await ExtractClaims(caseId);
            
            // 3. Bygg tidslinje med fakta som ankerpunkter
            var timeline = new FactBasedTimeline();
            foreach (var fact in facts.OrderBy(f => f.Timestamp))
            {
                var node = new TimelineNode(fact);
                
                // Finn relaterte påstander rundt dette faktum
                var relatedClaims = FindRelatedClaims(
                    claims, 
                    fact, 
                    TimeSpan.FromDays(30)
                );
                
                // Analyser avvik mellom fakta og påstander
                var discrepancies = await AnalyzeDiscrepancies(
                    fact,
                    relatedClaims
                );
                
                if (discrepancies.Any())
                {
                    foreach (var disc in discrepancies)
                    {
                        // Vektlegg særlig avvik som påvirker barnas beste
                        if (disc.ImpactsChildrensBest)
                        {
                            node.AddCriticalDiscrepancy(disc);
                        }
                        
                        // Marker systematiske avvik
                        if (disc.IsSystemic)
                        {
                            analysis.AddSystemicPattern(disc);
                        }
                    }
                }
                
                timeline.AddNode(node);
            }
            
            // 4. Verifiser konsistens i hendelseskjeden
            await VerifyEventChainConsistency(timeline);
            
            return analysis;
        }

        private async Task<List<FactualEvidence>> ExtractVerifiableEvents(string caseId)
        {
            var events = new List<FactualEvidence>();
            
            // Fokuser på konkrete, dokumenterbare hendelser
            var documentTypes = new[]
            {
                "court_decision",
                "official_record",
                "documented_meeting",
                "formal_complaint",
                "official_response",
                "medical_record",
                "school_record"
            };

            foreach (var docType in documentTypes)
            {
                var docs = await FindDocuments(caseId, docType);
                foreach (var doc in docs)
                {
                    // Ekstraher kun verifiserbare fakta
                    var facts = await ExtractVerifiableFacts(doc);
                    
                    foreach (var fact in facts)
                    {
                        // Valider at hendelsen er dokumentert
                        if (await ValidateEvidence(fact))
                        {
                            events.Add(new FactualEvidence
                            {
                                EventId = Guid.NewGuid().ToString(),
                                Timestamp = fact.Timestamp,
                                Type = fact.Type,
                                VerificationScore = await CalculateVerificationScore(fact),
                                SupportingDocuments = fact.Documents,
                                References = await BuildCrossReferences(fact)
                            });
                        }
                    }
                }
            }
            
            return events;
        }

        private async Task<double> CalculateVerificationScore(Evidence evidence)
        {
            double score = 0;
            
            // Vektlegging basert på bevistype
            var weights = new Dictionary<string, double>
            {
                {"official_document", 1.0},
                {"court_record", 1.0},
                {"timestamped_communication", 0.9},
                {"verified_meeting_minutes", 0.85},
                {"formal_complaint", 0.8},
                {"witness_statement", 0.7},
                {"informal_communication", 0.5}
            };

            // Beregn score basert på:
            // 1. Dokumenttype og vekt
            if (weights.TryGetValue(evidence.Type, out var weight))
            {
                score += weight;
            }

            // 2. Tidsmessig nærhet til hendelsen
            var timeProximity = CalculateTimeProximity(
                evidence.Timestamp, 
                evidence.DocumentationTimestamp
            );
            score *= timeProximity;

            // 3. Kryssreferanser til andre bevis
            var crossRefScore = await CalculateCrossReferenceScore(evidence);
            score *= (1 + crossRefScore) / 2;

            // 4. Konsistens med andre verifiserte fakta
            var consistencyScore = await CheckFactualConsistency(evidence);
            score *= consistencyScore;

            return Math.Min(score, 1.0);
        }

        private async Task<List<Discrepancy>> AnalyzeDiscrepancies(
            FactualEvidence fact, 
            IEnumerable<Claim> claims)
        {
            var discrepancies = new List<Discrepancy>();
            
            foreach (var claim in claims)
            {
                // Analyser avvik mellom påstand og faktum
                var conflict = await AnalyzeConflict(fact, claim);
                
                if (conflict.HasDiscrepancy)
                {
                    var impact = await AnalyzeImpact(
                        conflict,
                        EMDStandards.ChildrensBest.CoreValidations
                    );
                    
                    if (impact.IsSignificant)
                    {
                        discrepancies.Add(new Discrepancy
                        {
                            Type = conflict.Type,
                            Severity = impact.Severity,
                            Evidence = fact,
                            ConflictingClaim = claim,
                            ImpactsChildrensBest = impact.AffectsChildrensBest,
                            IsSystemic = await CheckIfSystemic(conflict)
                        });
                    }
                }
            }
            
            return discrepancies;
        }
    }
}
'@ | Out-File -FilePath "src\Core\Analysis\FactPattern\FactualAnalyzer.cs" -Encoding UTF8
