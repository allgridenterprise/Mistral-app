# Mistral Suite – Metadata og beviskjerne (automatisk generert)

## Hovedmodell:
- EvidenceEntry.cs: For alle dokumenttyper, samlet metadata, partlister, tema, dato, link, tekstutdrag og dynamiske felter.

## Juridiske og matching-krav:
- All matching, filtrering og statistikk refererer til EvidenceEntry og støtteklassene i Core/Stubs.cs
- Ingen andre hovedskjemaer for dokument/bevisdata!

## Videre utvikling:
- Utvid kun med én versjon av hver analyse/modul
- Slett gamle eksperimenter manuelt/automatisk hver uke
- Hold pipeline tydelig og ryddig – ingen spesialtilfeller utenfor hovedskjemaet
