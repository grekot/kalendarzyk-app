-- Migracja 004: zmiana domyślnej wartości ovulation_uncertainty z 2 na 1.
-- Wklej do SQL Editor w Supabase Dashboard i odpal Run.
-- Idempotentne — można odpalać wielokrotnie.

-- Update istniejących wierszy które mają stary domyślny = 2 (nie były ręcznie
-- zmienione). Profile z 0, 1 lub 3 (świadomy wybór usera) zostawiamy bez zmian.
update public.profiles
  set ovulation_uncertainty = 1
  where ovulation_uncertainty = 2;

-- Zmień default dla przyszłych insertów.
alter table public.profiles
  alter column ovulation_uncertainty set default 1;
