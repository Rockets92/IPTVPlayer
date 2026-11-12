-- B&B IPTV Player: telecomando unico, preferiti, ultimo canale, record dei giochi.
-- Da eseguire una volta in Supabase: SQL Editor -> New query -> incolla -> Run.
-- Si può rieseguire: non cancella dati.

-- Record dei giochi: nuova categoria di righe sincronizzate.
-- (Preferiti e ultimo canale viaggiano già come preferenze, niente da fare.)
alter table public.sync_rows drop constraint if exists sync_rows_table_name_check;
alter table public.sync_rows add constraint sync_rows_table_name_check
  check (table_name in ('reminders', 'vodProgress', 'prefs', 'games'));

-- Telecomando unico: canali privati "remote:<utente>..." su Realtime.
-- Ognuno può ascoltare e scrivere solo sui canali del proprio account.
drop policy if exists "telecomando: ascolto dei propri canali" on realtime.messages;
create policy "telecomando: ascolto dei propri canali" on realtime.messages
  for select to authenticated
  using ((select realtime.topic()) like 'remote:' || (select auth.uid())::text || '%');

drop policy if exists "telecomando: invio sui propri canali" on realtime.messages;
create policy "telecomando: invio sui propri canali" on realtime.messages
  for insert to authenticated
  with check ((select realtime.topic()) like 'remote:' || (select auth.uid())::text || '%');
