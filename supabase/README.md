# Account e sincronizzazione (Supabase)

Progetto: `https://yrgdckgyiodyeqfarsye.supabase.co` (chiave pubblica nell'app).

## Configurazione, una volta sola

1. **SQL Editor → New query**: incolla `migrations/0001_account_sync.sql` e premi **Run**.
   Crea le tabelle `devices` e `sync_rows` con le regole di accesso (ognuno vede solo i propri dati).
2. **Authentication → Emails → SMTP Settings**: servizio email proprio (es. Gmail con password per le app,
   `smtp.gmail.com:587`). Senza, Supabase non lascia modificare i template.
3. **Authentication → Emails → Templates**: in "Magic Link" e "Confirm signup" mettere il codice
   `{{ .Token }}` al posto del link, così l'app riceve un codice di 6 cifre.

Non mettere mai nel repo la chiave `service_role`/secret né la password SMTP.

## Cosa si sincronizza

| Dato | Tabella logica | Id |
| --- | --- | --- |
| Promemoria | `reminders` | `Reminder.id` (canale@orario della prima prenotazione) |
| Continua a guardare | `vodProgress` | `m:<id>` film, `s:<id>` serie |
| Preferenze personali | `prefs` | chiave in `SettingsStore.syncedKeys` |

Vince la modifica più recente (`updated_at`, impostato dal dispositivo); le cancellazioni restano come
righe `deleted` per 60 giorni. Le novità si scaricano con il cursore `server_at` (orologio del server).
Credenziali della lista, scala dell'interfaccia, profilo light e ultimo canale restano sul dispositivo.
