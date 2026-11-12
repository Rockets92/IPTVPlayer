-- B&B IPTV Player: account e sincronizzazione (fase 0/1).
-- Da eseguire una volta in Supabase: SQL Editor -> New query -> incolla -> Run.
-- Si può rieseguire: non cancella dati esistenti.

-- Dispositivi collegati all'account (TV, PC, telefono...).
create table if not exists public.devices (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null,
  kind        text not null check (kind in ('tv', 'phone', 'tablet', 'desktop')),
  platform    text not null,
  app_version text,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);
create index if not exists devices_user_idx on public.devices (user_id);

-- Dati sincronizzati: promemoria, "continua a guardare", preferenze.
-- Una riga per oggetto; "data" è lo stesso JSON salvato sul dispositivo.
create table if not exists public.sync_rows (
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  table_name text not null check (table_name in ('reminders', 'vodProgress', 'prefs')),
  id         text not null,
  data       jsonb,
  deleted    boolean not null default false,
  -- Ultima modifica secondo il dispositivo (ms epoch): vince la più recente.
  updated_at bigint not null,
  -- Orologio del server: cursore per scaricare solo le novità.
  server_at  timestamptz not null default clock_timestamp(),
  primary key (user_id, table_name, id)
);
create index if not exists sync_rows_cursor_idx on public.sync_rows (user_id, server_at);

-- Vince la modifica più recente: un dispositivo rimasto offline non
-- sovrascrive dati più nuovi.
create or replace function public.sync_rows_keep_newest()
returns trigger language plpgsql as $$
begin
  if new.updated_at < old.updated_at then
    return null; -- si tiene la riga esistente
  end if;
  new.server_at := clock_timestamp();
  return new;
end $$;

drop trigger if exists sync_rows_keep_newest on public.sync_rows;
create trigger sync_rows_keep_newest
  before update on public.sync_rows
  for each row execute function public.sync_rows_keep_newest();

-- Ognuno vede e modifica solo le proprie righe.
alter table public.devices   enable row level security;
alter table public.sync_rows enable row level security;

drop policy if exists "devices: solo i propri" on public.devices;
create policy "devices: solo i propri" on public.devices
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "sync_rows: solo le proprie" on public.sync_rows;
create policy "sync_rows: solo le proprie" on public.sync_rows
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Lapidi più vecchie di 60 giorni: si possono togliere (chiamata dall'app).
create or replace function public.sync_rows_prune()
returns void language sql security invoker as $$
  delete from public.sync_rows
  where user_id = auth.uid() and deleted and server_at < now() - interval '60 days';
$$;

-- Aggiornamenti in tempo reale verso gli altri dispositivi.
do $$
begin
  alter publication supabase_realtime add table public.sync_rows;
exception when duplicate_object then null;
end $$;
