# Lista canali (JSON)

La lista decide **ordine, numerazione, nomi, loghi e guida** dei canali. Il
player prende gli stream dal provider Xtream e li associa a questa lista.

La lista integrata è `assets/channels/sky_italia.json` (numerazione ispirata
a Sky Italia, per i test). Dalle impostazioni (**M → Sorgente lista**) si può
indicare un URL `https://…` o un percorso di file locale con la stessa
struttura: l'ultima versione valida resta in cache e l'app parte anche offline.
In build si può impostare un URL predefinito con
`--dart-define=MAPPING_URL=https://server/canali.json`.

## Struttura

```json
{
  "schemaVersion": 1,
  "id": "sky-italia",
  "name": "Ordine Sky Italia",
  "revision": "2026-11-01",
  "logoBaseUrl": "https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/italy/",
  "epgSources": [
    { "id": "epgshare-it", "name": "EPGShare Italia", "url": "https://…/epg_IT.xml.gz" }
  ],
  "unmappedChannels": { "show": true, "startNumber": 1000 },
  "channels": [
    {
      "number": 101,
      "name": "Rai 1",
      "group": "Intrattenimento",
      "logo": "rai-1-it.png",
      "epgId": "Rai.1.it",
      "aliases": ["Rai Uno", "Rai1"],
      "streamId": 12345,
      "hidden": false
    }
  ]
}
```

| Campo | Significato |
|---|---|
| `number` | Numero canale (unico). Obbligatorio. |
| `name` | Nome mostrato. Obbligatorio. Serve anche per trovare lo stream. |
| `group` | Categoria per i filtri della lista canali. |
| `logo` | URL assoluto, oppure nome file relativo a `logoBaseUrl`. Se manca si usa il logo del provider. |
| `epgId` | Id `<channel id="…">` della guida XMLTV (anche lista di id). |
| `aliases` | Altri nomi con cui il canale compare nella lista del provider. |
| `streamId` | Facoltativo: forza uno stream Xtream preciso (anche lista, per il failover). |
| `hidden` | Nasconde il canale senza toglierlo dal file. |
| `epgSources` | Guide XMLTV esterne (anche `.gz`), lette in ordine. |
| `unmappedChannels` | Mostra gli altri canali del provider a partire da `startNumber`. |

## Come avviene l'abbinamento

1. Se c'è `streamId`, vince quello.
2. Altrimenti si confrontano nome e alias con i nomi del provider dopo una
   normalizzazione che ignora prefissi (`IT:`, `|IT|`, `[ITA]`), qualità
   (`HD`, `FHD`, `4K`, `HEVC`…) e simboli: `IT: Sky Uno +1 FHD` → `skyunoplus1`.
3. Se più stream corrispondono, sono tutti tenuti come sorgenti alternative
   (failover automatico), ordinati per qualità. Nel profilo light si
   preferisce l'HD al Full HD e si evita il 4K.
4. I canali della lista che il provider non ha non vengono mostrati: lo
   zapping non incontra canali vuoti.

## Guida TV

Per ogni canale vale la prima fonte che lo copre, in quest'ordine:
`epgSources` della lista → fonti aggiuntive dalle impostazioni → XMLTV del
provider (`xmltv.php`). Un canale viene associato alla guida tramite `epgId`
oppure, se manca, tramite il `display-name` della guida. Per i canali
ancora scoperti si usa `get_short_epg` del provider al momento dello zapping.
