-- Kalendazyk — schemat Supabase
-- Wklej całość do SQL Editor w panelu projektu i odpal (Run).
-- Idempotentny (drop + create) — można odpalać wielokrotnie.

-- ─────────────────────────────────────────────────────────────
-- DROP (gdyby było coś od poprzedniej iteracji)
-- ─────────────────────────────────────────────────────────────
drop table if exists public.cycles cascade;
drop table if exists public.profile_shares cascade;
drop table if exists public.invites cascade;
drop table if exists public.profiles cascade;
drop table if exists public.users cascade;
drop function if exists public.is_profile_owner(uuid, uuid) cascade;
drop function if exists public.has_profile_share(uuid, uuid) cascade;
drop function if exists public.user_can_access_profile(uuid, uuid) cascade;

-- ─────────────────────────────────────────────────────────────
-- USERS (rozszerzenie auth.users o display_name i default_profile_id)
-- ─────────────────────────────────────────────────────────────
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  default_profile_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Trigger: auto-create row in public.users gdy nowy user w auth.users
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.users (id, display_name)
  values (new.id, '');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- PROFILES (jeden lub wiele profili per user; właściciel + share)
-- ─────────────────────────────────────────────────────────────
create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  name text not null,
  photo_url text,
  ovulation_uncertainty smallint not null default 1
    check (ovulation_uncertainty between 0 and 3),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profiles_owner_idx on public.profiles(owner_id);

-- ─────────────────────────────────────────────────────────────
-- PROFILE_SHARES (kto ma dostęp do udostępnionego profilu)
-- ─────────────────────────────────────────────────────────────
create table public.profile_shares (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'editor' check (role in ('editor', 'viewer')),
  granted_at timestamptz not null default now(),
  primary key (profile_id, user_id)
);

create index profile_shares_user_idx on public.profile_shares(user_id);

-- FK dla default_profile_id (po profiles)
alter table public.users
  add constraint users_default_profile_fk
  foreign key (default_profile_id) references public.profiles(id) on delete set null;

-- ─────────────────────────────────────────────────────────────
-- CYCLES (start cyklu, unikalna data per profil)
-- ─────────────────────────────────────────────────────────────
create table public.cycles (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  date date not null,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  unique (profile_id, date)
);

create index cycles_profile_idx on public.cycles(profile_id, date);

-- ─────────────────────────────────────────────────────────────
-- INVITES (6-cyfrowy kod do udostępnienia profilu)
-- ─────────────────────────────────────────────────────────────
create table public.invites (
  code text primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_by uuid not null references public.users(id),
  role text not null default 'editor' check (role in ('editor', 'viewer')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────
-- HELPER FUNCTIONS (SECURITY DEFINER — bypassują RLS,
-- używane przez policies żeby uniknąć nieskończonej rekurencji).
-- ─────────────────────────────────────────────────────────────
create or replace function public.is_profile_owner(p_profile uuid, p_user uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = p_profile and owner_id = p_user
  );
$$;

create or replace function public.has_profile_share(p_profile uuid, p_user uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from public.profile_shares
    where profile_id = p_profile and user_id = p_user
  );
$$;

create or replace function public.user_can_access_profile(p_profile uuid, p_user uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.is_profile_owner(p_profile, p_user)
      or public.has_profile_share(p_profile, p_user);
$$;

create or replace function public.user_can_edit_profile(p_profile uuid, p_user uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = p_profile and owner_id = p_user
  ) or exists(
    select 1 from public.profile_shares
    where profile_id = p_profile and user_id = p_user and role = 'editor'
  );
$$;

-- ─────────────────────────────────────────────────────────────
-- ROW-LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────
alter table public.users enable row level security;
alter table public.profiles enable row level security;
alter table public.profile_shares enable row level security;
alter table public.cycles enable row level security;
alter table public.invites enable row level security;

-- USERS: user widzi swój wiersz; widzi też displayName tych userów którym coś
-- udostępnia / którzy coś mu udostępniają (do "udostępnione przez X" w UI).
-- Subquery na profile_shares i profiles są bezpieczne — ich RLS używa
-- SECURITY DEFINER helpers, więc nie ma rekurencji.
create policy users_select_self on public.users
  for select using (
    auth.uid() = id
    or exists (
      select 1 from public.profile_shares ps
      join public.profiles p on p.id = ps.profile_id
      where (p.owner_id = auth.uid() and ps.user_id = users.id)
         or (ps.user_id = auth.uid() and p.owner_id = users.id)
    )
  );

create policy users_insert_self on public.users
  for insert with check (auth.uid() = id);

create policy users_update_self on public.users
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- PROFILES: select jeśli jestem ownerem lub mam share (przez helper)
create policy profiles_select on public.profiles
  for select using (
    owner_id = auth.uid()
    or public.has_profile_share(profiles.id, auth.uid())
  );

create policy profiles_insert on public.profiles
  for insert with check (owner_id = auth.uid());

create policy profiles_update on public.profiles
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy profiles_delete on public.profiles
  for delete using (owner_id = auth.uid());

-- PROFILE_SHARES: select jeśli jestem ownerem profilu (przez helper) lub odbiorcą
create policy shares_select on public.profile_shares
  for select using (
    user_id = auth.uid()
    or public.is_profile_owner(profile_shares.profile_id, auth.uid())
  );

create policy shares_insert on public.profile_shares
  for insert with check (
    public.is_profile_owner(profile_shares.profile_id, auth.uid())
  );

create policy shares_update on public.profile_shares
  for update using (
    public.is_profile_owner(profile_shares.profile_id, auth.uid())
  ) with check (
    public.is_profile_owner(profile_shares.profile_id, auth.uid())
  );

create policy shares_delete on public.profile_shares
  for delete using (
    public.is_profile_owner(profile_shares.profile_id, auth.uid())
    or user_id = auth.uid()
  );

-- CYCLES: pełny dostęp przez user_can_access_profile (helper)
create policy cycles_select on public.cycles
  for select using (public.user_can_access_profile(cycles.profile_id, auth.uid()));

create policy cycles_insert on public.cycles
  for insert with check (public.user_can_edit_profile(cycles.profile_id, auth.uid()));

create policy cycles_update on public.cycles
  for update using (public.user_can_edit_profile(cycles.profile_id, auth.uid()));

create policy cycles_delete on public.cycles
  for delete using (public.user_can_edit_profile(cycles.profile_id, auth.uid()));

-- INVITES: czyta każdy zalogowany (potrzebne do realizacji kodu); tworzy owner
-- profilu; kasuje owner lub gdy wygasł.
create policy invites_select on public.invites
  for select using (auth.uid() is not null);

create policy invites_insert on public.invites
  for insert with check (
    created_by = auth.uid()
    and public.is_profile_owner(invites.profile_id, auth.uid())
  );

create policy invites_delete on public.invites
  for delete using (
    created_by = auth.uid()
    or expires_at < now()
  );

-- ─────────────────────────────────────────────────────────────
-- REALTIME — włącz publikację dla naszych tabel
-- ─────────────────────────────────────────────────────────────
-- Idempotentne: usuń z publikacji jeśli już dodane (przy ponownym odpaleniu),
-- potem dodaj na nowo.
do $$
declare
  t text;
begin
  for t in select unnest(array['profiles', 'profile_shares', 'cycles', 'users'])
  loop
    begin
      execute format('alter publication supabase_realtime drop table public.%I', t);
    exception when others then null; -- nie było w publikacji — ok
    end;
    execute format('alter publication supabase_realtime add table public.%I', t);
  end loop;
end$$;

-- ─────────────────────────────────────────────────────────────
-- STORAGE: bucket na zdjęcia profili
-- ─────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
  values ('profile_photos', 'profile_photos', true)
  on conflict (id) do nothing;

-- Storage RLS: upload tylko właścicieli profili (path = <profile_id>/<file>).
-- Used SECURITY DEFINER helper żeby uniknąć rekurencji.
drop policy if exists "profile_photos_upload" on storage.objects;
create policy "profile_photos_upload" on storage.objects
  for insert with check (
    bucket_id = 'profile_photos'
    and auth.uid() is not null
    and public.is_profile_owner(
      split_part(name, '/', 1)::uuid,
      auth.uid()
    )
  );

drop policy if exists "profile_photos_update" on storage.objects;
create policy "profile_photos_update" on storage.objects
  for update using (
    bucket_id = 'profile_photos'
    and public.is_profile_owner(
      split_part(name, '/', 1)::uuid,
      auth.uid()
    )
  );

drop policy if exists "profile_photos_delete" on storage.objects;
create policy "profile_photos_delete" on storage.objects
  for delete using (
    bucket_id = 'profile_photos'
    and public.is_profile_owner(
      split_part(name, '/', 1)::uuid,
      auth.uid()
    )
  );

-- ─────────────────────────────────────────────────────────────
-- BACKFILL: wstaw wiersze public.users dla istniejących auth.users
-- które jeszcze ich nie mają (np. zalogowali się anonimowo przed
-- utworzeniem triggera handle_new_user).
-- Idempotentne — przy ponownym Run nic nie zrobi.
-- ─────────────────────────────────────────────────────────────
insert into public.users (id, display_name)
select au.id, ''
from auth.users au
where not exists (select 1 from public.users u where u.id = au.id);
