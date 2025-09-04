using System.Collections.Generic;
using MistralApp.Core;

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
