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
  "preferredSources": ["hermes +", "hermes"],
  "dynamicGroups": [
    { "name": "Eventi", "startNumber": 800, "keywords": ["dazn", "eventi", "event"] },
    { "name": "Vetrina", "startNumber": 870, "keywords": ["vetrina"] }
  ],
  "unmappedChannels": { "show": false, "startNumber": 1000 },
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
| `aliases` | Altri nomi con cui il canale compare nella lista del provider. Con `*` si indica una parte variabile, utile per i canali che cambiano nome a tema: `"Sky Cinema * Collection"` abbina anche "Sky Cinema Oscar Collection". |
| `streamId` | Facoltativo: forza uno stream Xtream preciso (anche lista, per il failover). |
| `hidden` | Nasconde il canale senza toglierlo dal file. |
| `epgSources` | Guide XMLTV esterne (anche `.gz`), lette in ordine. |
| `preferredSources` | Etichette di fonte da usare come principali, in ordine (predefinito `["hermes +", "hermes"]`). |
| `dynamicGroups` | Categorie automatiche per i canali che cambiano spesso: tutti gli stream del provider (non già in lista) con una parola che inizia con una delle `keywords` ("event" prende "Eventi" ma non "Benevento"), numerati da `startNumber`. Prima tutti quelli della prima parola chiave, poi della seconda; le copie dello stesso evento diventano fonti. Predefinito: "Eventi" dall'800 con `dazn`, poi `eventi` e `event`; "Vetrina" dall'870 con `vetrina`. Se un gruppo arriva al numero di partenza del successivo, quest'ultimo prosegue dal primo numero libero. |
| `unmappedChannels` | Con `show: true` mostra anche gli altri canali del provider (senza doppioni) a partire da `startNumber`. Predefinito: spento, si vede solo la lista. |

## Come avviene l'abbinamento

1. Se c'è `streamId`, vince quello.
2. Altrimenti si confrontano nome e alias con i nomi del provider dopo una
   normalizzazione che ignora prefissi (`IT:`, `|IT|`, `[ITA]`), qualità
   (`HD`, `FHD`, `4K`, `HEVC`…) e simboli: `IT: Sky Uno +1 FHD` → `skyunoplus1`.
3. L'etichetta finale tra parentesi (`Sky Cinema Uno FHD ( sat-stella )`) viene
   sempre considerata una fonte. Si riconoscono anche le copie con un'etichetta di fonte prima o dopo il
   nome (`HERMES + SKY UNO`, `SKY UNO | BACKUP`). Un'etichetta conta come
   fonte se è in `preferredSources` oppure accompagna almeno 3 canali diversi;
   le etichette con numeri non contano, così `Sky Uno +1` resta un canale a sé.
4. Ogni canale compare **una sola volta**: tutti gli stream trovati diventano
   fonti dello stesso canale. Prima quelle con un'etichetta di
   `preferredSources`, poi le altre per qualità. Nel profilo light si
   preferisce l'HD al Full HD e si evita il 4K.
5. Con il tasto **S** (o il pulsante ⇄ nel banner) si sceglie la fonte del
   canale in visione; la scelta viene ricordata per quel canale. Se la fonte
   cade, il player passa da solo alle altre.
6. I canali della lista che il provider non ha non vengono mostrati: lo
   zapping non incontra canali vuoti.

## Guida TV

Per ogni canale vale la prima fonte che lo copre, in quest'ordine:
`epgSources` della lista → fonti aggiuntive dalle impostazioni → XMLTV del
provider (`xmltv.php`). Un canale viene associato alla guida tramite `epgId`
oppure, se manca, tramite il `display-name` della guida. Per i canali
ancora scoperti si usa `get_short_epg` del provider al momento dello zapping.
