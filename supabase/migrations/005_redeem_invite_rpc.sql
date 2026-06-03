-- Migracja 005: RPC do realizacji kodu udostępnienia profilu.
-- Wklej do SQL Editor w Supabase Dashboard i odpal Run.
-- Idempotentne — można odpalać wielokrotnie (CREATE OR REPLACE).
--
-- Dlaczego: aktualna policy `shares_insert` wymaga `is_profile_owner` →
-- użytkownik realizujący kod (NIE owner) nie mógł wstawić wiersza do
-- profile_shares. Funkcja z SECURITY DEFINER bypassuje RLS i wykonuje
-- całą operację atomicznie (sprawdza expiry, insertuje share, kasuje invite).

create or replace function public.redeem_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_profile_id uuid;
  v_role text;
  v_expires timestamptz;
  v_cleaned text;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  v_cleaned := regexp_replace(upper(p_code), '\s+', '', 'g');

  select profile_id, role, expires_at
    into v_profile_id, v_role, v_expires
    from public.invites
    where code = v_cleaned;

  if v_profile_id is null then
    raise exception 'invalid_code' using errcode = 'P0001';
  end if;

  if v_expires < now() then
    -- Usuwamy wygasły kod przy okazji.
    delete from public.invites where code = v_cleaned;
    raise exception 'expired_code' using errcode = 'P0002';
  end if;

  -- Insert / upsert share z rolą z invite.
  insert into public.profile_shares (profile_id, user_id, role)
    values (v_profile_id, v_user, coalesce(v_role, 'editor'))
    on conflict (profile_id, user_id) do update set role = excluded.role;

  -- Skonsumowany kod od razu znika.
  delete from public.invites where code = v_cleaned;

  return v_profile_id;
end;
$$;

-- Pozwól wszystkim zalogowanym wywoływać tę funkcję (RLS i tak nie dotyczy
-- SECURITY DEFINER, ale grant na execute musi być).
grant execute on function public.redeem_invite(text) to authenticated;
