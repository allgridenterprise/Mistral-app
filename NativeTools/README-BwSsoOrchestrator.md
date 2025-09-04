# BwSsoOrchestrator

Et lite C++-verktøy som automatiserer:
- Bitwarden SSO-innlogging (Azure AD / Microsoft Entra) via Bitwarden CLI
- Opplåsing av hvelv (interaktivt i nytt konsollvindu)
- Henting av Mistral API-nøkkel fra Bitwarden (passordfeltet i et element)
- Setting av MISTRAL_API_KEY som bruker-miljøvariabel og skriving til lokal, skjult fil

Forutsetninger:
- Windows 10/11
- Bitwarden CLI (`bw`) installert og i PATH: https://bitwarden.com/help/cli/
- Mistral API-nøkkelen lagret som passordfelt i et Bitwarden-element (standard navn: "Mistral API Key")

Bygg (MSVC):
