-- Migracja 003: per-profil margines błędu owulacji (±N dni, N = 0..3).
-- Wklej do SQL Editor w Supabase Dashboard i odpal Run.
-- Idempotentne — można odpalać wielokrotnie.

-- Dodaj kolumnę z domyślną wartością 2 (obecnie hardcoded w aplikacji).
alter table public.profiles
  add column if not exists ovulation_uncertainty smallint not null default 2;

-- Constraint zakresu 0..3.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_ovulation_uncertainty_range'
  ) then
    alter table public.profiles
      add constraint profiles_ovulation_uncertainty_range
      check (ovulation_uncertainty between 0 and 3);
  end if;
end$$;
