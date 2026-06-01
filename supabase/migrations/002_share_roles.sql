-- Migracja 002: role 'editor' / 'viewer' dla profile_shares
--
-- Wklej do SQL Editor w Supabase i odpal (Run). Idempotentny — można
-- odpalać wielokrotnie, nie ruszy istniejących danych (w przeciwieństwie
-- do `schema.sql` które dropuje tabele).

-- ─────────────────────────────────────────────────────────────
-- 1. Kolumna `role` w profile_shares
-- ─────────────────────────────────────────────────────────────
alter table public.profile_shares
  add column if not exists role text not null default 'editor'
  check (role in ('editor', 'viewer'));

-- ─────────────────────────────────────────────────────────────
-- 2. Kolumna `role` w invites (rola z którą wygenerowany kod)
-- ─────────────────────────────────────────────────────────────
alter table public.invites
  add column if not exists role text not null default 'editor'
  check (role in ('editor', 'viewer'));

-- ─────────────────────────────────────────────────────────────
-- 3. Helper: czy user może EDYTOWAĆ profil (owner lub editor)
-- ─────────────────────────────────────────────────────────────
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
-- 4. Policies cycles: SELECT pozostaje (read = każdy z dostępem),
--    INSERT/UPDATE/DELETE wymagają edit (owner lub editor).
-- ─────────────────────────────────────────────────────────────
drop policy if exists cycles_insert on public.cycles;
create policy cycles_insert on public.cycles
  for insert with check (
    public.user_can_edit_profile(cycles.profile_id, auth.uid())
  );

drop policy if exists cycles_update on public.cycles;
create policy cycles_update on public.cycles
  for update using (
    public.user_can_edit_profile(cycles.profile_id, auth.uid())
  );

drop policy if exists cycles_delete on public.cycles;
create policy cycles_delete on public.cycles
  for delete using (
    public.user_can_edit_profile(cycles.profile_id, auth.uid())
  );

-- ─────────────────────────────────────────────────────────────
-- 5. Policy update na profile_shares: owner może zmienić rolę
-- ─────────────────────────────────────────────────────────────
drop policy if exists shares_update on public.profile_shares;
create policy shares_update on public.profile_shares
  for update using (
    public.is_profile_owner(profile_shares.profile_id, auth.uid())
  ) with check (
    public.is_profile_owner(profile_shares.profile_id, auth.uid())
  );
