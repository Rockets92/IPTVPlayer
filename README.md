# IPTV Player

Player IPTV per liste **Xtream Codes** con interfaccia in vetro e
interazione da decoder: si accende, riparte dall'ultimo canale, si cambia
canale con su/giù o digitando il numero.

Flutter, una sola base di codice per **Windows** (obiettivo principale),
Linux, macOS, Android/Android TV e iOS, più un profilo **light** per
proiettori e box Android da 1 GB di RAM.

## Cosa fa

- **Primo avvio**: server, utente e password Xtream (si può incollare anche
  il link M3U completo). Le credenziali vengono verificate e lo stato
  dell'abbonamento mostrato.
- **Zapping da decoder**: banner con numero, logo, nome, programma in onda
  con avanzamento e successivo, orologio; inserimento numerico diretto;
  canale precedente; cambio canale istantaneo nell'interfaccia con
  sintonizzazione posticipata durante lo zapping rapido.
- **Lista canali personalizzabile via JSON**: ordine, numeri, loghi, id EPG
  (vedi [docs/lista-canali.md](docs/lista-canali.md)). Integrata la
  numerazione Sky Italia per i test, leggibile in futuro da un server.
- **Guida TV** da fonti XMLTV esterne (anche `.gz`), con riempimento dalla
  guida del provider. Parsing in streaming in un isolate, cache su disco.
- **Affidabilità**: più stream per canale con failover automatico, nuovi
  tentativi con attesa crescente, rilevamento di segnale bloccato, avvio
  istantaneo dalla lista in cache con aggiornamento in background.
- **Profilo light**: niente blur in tempo reale, animazioni più brevi,
  finestra EPG ridotta, buffer video e cache immagini contenuti, texture
  video limitata a 720p, preferenza per stream HD. Si attiva con la build
  light, dalle impostazioni o in automatico su Android sotto 1,8 GB di RAM.

## Comandi

| Tasto | Azione |
|---|---|
| ↑ ↓ · CH+ CH− · PagSu PagGiù | Canale successivo / precedente |
| 0–9 | Vai al numero |
| OK / Invio | Informazioni sul canale in visione; di nuovo OK apre l'elenco canali |
| ← → | Sfoglia gli altri canali nel banner senza cambiare il video; OK per passarci |
| ← → (con le informazioni aperte) | Programmi precedenti e successivi del canale |
| L | Elenco canali (←→ cambia categoria) |
| G / Guida | Guida TV |
| + / tasto rosso | Versione +1 del canale, se il provider la offre (di nuovo per tornare in diretta) |
| S / tasto verde | Scegli la fonte del canale (se il provider ne ha più di una) |
| I / Info | Mostra/nasconde le informazioni |
| ⌫ / P | Canale precedente |
| M / Menu | Impostazioni |
| F / F11 · doppio clic | Schermo intero (desktop) |
| K / Muto | Audio on/off |

Con mouse e tocco: tocco = informazioni, scorrimento verticale = zapping,
pressione lunga = elenco canali, pulsanti rapidi nel banner.

## Build

Richiede Flutter 3.47 (stable).

```bash
flutter pub get
flutter run -d windows                 # sviluppo
flutter build windows --release        # Windows
flutter build apk --release            # Android completa
flutter build apk --release --split-per-abi --dart-define=FLAVOR=light   # Android light
flutter build linux --release          # Linux (serve libmpv-dev, libgtk-3-dev)
```

Su Windows la build scarica automaticamente libmpv. Ogni push e ogni pull
request producono gli eseguibili Windows e gli APK (completa e light) come
artefatti della GitHub Action **Build**.

## Struttura

```
lib/
  core/        profilo prestazioni, tema e tipografia, brand
  data/        client Xtream, lista canali JSON, EPG XMLTV, impostazioni
  domain/      modello canale, normalizzazione nomi, abbinamento stream
  player/      motore video (media_kit / libmpv)
  state/       stato app e logica di zapping
  ui/          setup, player, banner, lista, guida, impostazioni, widget vetro
assets/channels/sky_italia.json   lista canali integrata
```

Loghi dalla raccolta [tv-logo/tv-logos](https://github.com/tv-logo/tv-logos).
Font Inter (SIL Open Font License, `assets/fonts/OFL-Inter.txt`).
