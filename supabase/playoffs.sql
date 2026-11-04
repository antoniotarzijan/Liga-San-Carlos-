-- ══════════════════════════════════════════════════════════════
--  PLAYOFFS · Liga San Carlos
--
--  Cómo instalar: Supabase → SQL Editor → pegar → Run (se puede repetir).
--  Requiere fixture_automatico.sql.
--
--  Los partidos de playoffs van en games / games_segunda:
--    round 100 = cuartos, 101 = semifinales, 102 = final
--    bracket_slot QF1..QF4, SF1, SF2, F1
--    home_seed / away_seed = puesto en la tabla final (local = mejor puesto)
--  Los cuartos se crean con "Confirmar cruces" en fixture.html.
--  Este trigger arma solo las semifinales y la final: cuando terminan los
--  dos partidos que alimentan un cruce, crea el siguiente (o lo corrige si
--  se edita un resultado, o lo borra si un resultado se deshace y el
--  cruce siguiente aún no se publica). La publicación la hace
--  lsc_publicar_jornada(), igual que las jornadas.
--  Debe coincidir con playoffs.js.
-- ══════════════════════════════════════════════════════════════

alter table public.games
  add column if not exists bracket_slot text,
  add column if not exists home_seed    int,
  add column if not exists away_seed    int;

alter table public.games_segunda
  add column if not exists bracket_slot text,
  add column if not exists home_seed    int,
  add column if not exists away_seed    int;

create or replace function public.lsc_avanzar_playoff()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  destino  text := case when new.bracket_slot in ('QF1','QF2') then 'SF1'
                        when new.bracket_slot in ('QF3','QF4') then 'SF2'
                        when new.bracket_slot in ('SF1','SF2') then 'F1' end;
  hermano  text := case new.bracket_slot when 'QF1' then 'QF2' when 'QF2' then 'QF1'
                                         when 'QF3' then 'QF4' when 'QF4' then 'QF3'
                                         when 'SF1' then 'SF2' when 'SF2' then 'SF1' end;
  id_dest  bigint;
  tipo_dest text;
  h_type   text; h_home text; h_away text; h_hs int; h_as int; h_hseed int; h_aseed int;
  w1 text; s1 int; w2 text; s2 int; tmp_t text; tmp_s int;
begin
  if destino is null then return new; end if;   -- la final no avanza a nada

  execute format('select id, type from %I where bracket_slot = $1', tg_table_name)
    into id_dest, tipo_dest using destino;
  execute format('select type, home, away, home_score, away_score, home_seed, away_seed from %I where bracket_slot = $1', tg_table_name)
    into h_type, h_home, h_away, h_hs, h_as, h_hseed, h_aseed using hermano;

  -- Falta un resultado: si el cruce siguiente existe y aún no se publica, se quita.
  if new.type <> 'finished' or h_type is distinct from 'finished' then
    if id_dest is not null and tipo_dest = 'scheduled' then
      execute format('delete from %I where id = $1', tg_table_name) using id_dest;
    end if;
    return new;
  end if;

  if new.home_score > new.away_score then w1 := new.home; s1 := new.home_seed;
  else w1 := new.away; s1 := new.away_seed; end if;
  if h_hs > h_as then w2 := h_home; s2 := h_hseed;
  else w2 := h_away; s2 := h_aseed; end if;
  if coalesce(s2, 99) < coalesce(s1, 99) then   -- local = mejor puesto (número menor)
    tmp_t := w1; w1 := w2; w2 := tmp_t;
    tmp_s := s1; s1 := s2; s2 := tmp_s;
  end if;

  if id_dest is null then
    execute format(
      'insert into %I (type, round, home, away, home_seed, away_seed, bracket_slot, slot_time, venue, date)
       values (''scheduled'', $1, $2, $3, $4, $5, $6, $7, ''Cancha 1 · Colegio Cumbres'', ''Por definir'')', tg_table_name)
    using new.round + 1, w1, w2, s1, s2, destino, case destino when 'SF1' then '19:30' else '20:30' end;
  elsif tipo_dest = 'scheduled' then
    execute format('update %I set home = $1, away = $2, home_seed = $3, away_seed = $4 where id = $5', tg_table_name)
    using w1, w2, s1, s2, id_dest;
  end if;
  return new;
end $$;

revoke all on function public.lsc_avanzar_playoff() from public, anon, authenticated;

drop trigger if exists lsc_avanzar_playoff on public.games;
create trigger lsc_avanzar_playoff after update of type, home_score, away_score, home, away on public.games
  for each row when (new.bracket_slot is not null and (new.type = 'finished' or old.type = 'finished'))
  execute function public.lsc_avanzar_playoff();

drop trigger if exists lsc_avanzar_playoff on public.games_segunda;
create trigger lsc_avanzar_playoff after update of type, home_score, away_score, home, away on public.games_segunda
  for each row when (new.bracket_slot is not null and (new.type = 'finished' or old.type = 'finished'))
  execute function public.lsc_avanzar_playoff();
