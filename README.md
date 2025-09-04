# Mistral Suite
# Mistral Suite

AI‑drevet dokumentprosessering og orkestrering for prosjektets bevis- og metadataflyt.

## Innhold

- Arkitektur og flyt
- Konfigurasjon og hemmeligheter (env/appsettings/Bitwarden)
- Integrasjoner (Mistral, OpenAI, Airtable, Make, OneDrive)
- GUI-faner og arbeidsflater
- Scripts & Console
- Veikart / Neste steg

---

## Arkitektur og flyt

- Lokal GUI (WPF) som nav i en hybrid pipeline:
  - Lokal prosessering (mappebasert) + AI‑støttede arbeidssteg
  - Online orkestrering (Make) og toveis synk (OneDrive)
  - Datagrunnlag og køer i Airtable (prosjekt/forsider/utfallsmapper)
- Tjenestelag via DI:
  - IMistralClient (Mistral chat/completions)
  - IOpenAIClient (chat/completions)
  - IAirtableService (API, base og tabeller)
  - IMakeOrchestrator (webhook/trigger)
  - IOneDriveSyncService (speilsynk validering)
  - ISecretsProvider (env/appsettings/Bitwarden SSO)
- Konfig og hemmeligheter:
  - Miljøvariabler → appsettings.json → Bitwarden (BW_SESSION)
  - Secrets:Map brukes for å slå opp item‑navn i Bitwarden

## Konfigurasjon og hemmeligheter

- appsettings.json (kopieres til Output ved publish); eksempel:
  ```json
  {
    "Secrets": {
      "MISTRAL_API_KEY": "",
      "OPENAI_API_KEY": "",
      "AIRTABLE_API_KEY": "",
      "AIRTABLE_BASE_ID": "",
      "AIRTABLE_TABLE": "",
      "MAKE_WEBHOOK_URL": "",
      "Map": {
        "MISTRAL_API_KEY": "Mistral API Key",
        "OPENAI_API_KEY": "OpenAI API Key",
        "AIRTABLE_API_KEY": "Airtable API Key",
        "AIRTABLE_BASE_ID": "Airtable Base ID",
        "AIRTABLE_TABLE": "Airtable Table",
        "MAKE_WEBHOOK_URL": "Make Webhook URL"
      }
    }
  }
  ```
- Miljøvariabler (overstyrer):
  - MISTRAL_API_KEY, OPENAI_API_KEY, AIRTABLE_API_KEY, AIRTABLE_BASE_ID, AIRTABLE_TABLE, MAKE_WEBHOOK_URL
- Bitwarden SSO:
  - Krever BW_SESSION aktiv
  - Secrets:Map definerer hvilke Bitwarden items/felt som korresponderer

## Integrasjoner

- Mistral (chat/completions) – modell “mistral-large-latest”
- OpenAI (chat/completions) – modell “gpt-4o-mini”
- Airtable – ping av tabell (GET 1 record) for health
- Make – webhook POST for health/run
- OneDrive – enkel validering (prosess + katalog)

## GUI-faner

- Dashboard:
  - Hurtigprompt og basis handlinger (Start Processing, Test Connections, Refresh)
- Chat:
  - Samtale med Mistral/OpenAI, logg og respons
- Documents:
  - Velg Input/Output, test tilkoblinger, kjør pipeline (grunnmur)
- Metadata:
  - Import/valider/eksporter CSV (grunnmur)
- Integrations:
  - Sjekk nøkler/status, test integrasjoner
- Console:
  - AI‑genererte scripts og kjøring (PowerShell), logg/lagre/last skript

## Scripts & Console

- Generering av idempotente PowerShell‑scripts for:
  - Prosjektstruktur (Input/Output/Logs)
  - Rydding/normalisering (duplikat/metadata)
  - Batchprosesser (OCR/konvertering)
- Kjøring med -NoProfile og Bypass ExecutionPolicy, logg av stdout/stderr

## Veikart (neste steg)

1. Fullføre reelle API‑kall:
   - Mistral/OpenAI: prompts, system‑instruks, temperatur, osv.
   - Airtable: skjemalasting, validering, køstatus, oppdatering
   - Make: scenario‑ID, payloadskjema, status callbacks
2. OneDrive speilsynk:
   - Regler og overvåkning + håndtering av konflikter
3. Metadata‑motor:
   - Skjema (kolonner), valideringsregler, deduplisering og merging
   - CSV/Parquet eksport og snapshot versjonering
4. Dokumentprosess:
   - OCR/tekstuttrekk, splitting, nøkkelord/entiteter, sorteringslogikk
   - Automatisk mappestruktur og utfallsmapper
5. Visualisering:
   - Dashboards for tellinger, tidsserier, mønstre, relasjoner
6. Sikkerhet:
   - Audit‑logg, rolle/tilgang, nøkkelrotasjon

## Hurtigtaster og tips

- Help → Open Project README åpner denne filen
- Kjør bygg/publish/start via Scripts/Start-Mistral-Full.ps1

---
## Prosjektstruktur
- **src/**: Kildekode for applikasjonen
- **Scripts/**: PowerShell-script for bygging og deployment  
- **docs/**: Dokumentasjon
- **dist/**: Ferdig bygde installers
- **Setup/**: Inno Setup konfigurasjon

## Bygging og installasjon
Kjør \Complete-MistralSuite-Manager.ps1\ med følgende parametre:

- \-Action Clean\: Rydder kun opp i filer
- \-Action Build\: Bygger applikasjonen
- \-Action Install\: Oppretter installer
- \-Action Full\: Gjør alt (anbefalt)
- \-Action Analyze\: Analyserer prosjektstrukturen

### Eksempler
\\\powershell
# Full opprydding og bygging
.\Complete-MistralSuite-Manager.ps1 -Action Full

# Kun analysere prosjektet
.\Complete-MistralSuite-Manager.ps1 -Action Analyze -DryRun

# Rask opprydding uten å spørre om bekreftelse
.\Complete-MistralSuite-Manager.ps1 -Action Clean -Force
\\\

Sist oppdatert: 2025-08-21 00:20
