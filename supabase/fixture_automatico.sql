-- ══════════════════════════════════════════════════════════════
--  FIXTURE AUTOMÁTICO · Liga San Carlos
--
--  Cómo instalar: Supabase → SQL Editor → pegar todo este archivo → Run.
--  Se puede correr más de una vez sin problema.
--
--  Qué hace:
--   1. Agrega a games / games_segunda las columnas game_date (fecha real),
--      slot_time (hora, ej '19:30') y rescheduled (jornada reprogramada).
--   2. Permite el estado 'scheduled' = partido del fixture aún no publicado
--      (el sitio solo muestra 'upcoming', 'live' y 'finished').
--   3. Crea lsc_publicar_jornada(): cuando la jornada en curso está
--      completamente jugada, a las 10:00 del día siguiente publica la
--      jornada que sigue, con fecha = próximo martes (Segunda) o jueves
--      (Primera), y actualiza la "jornada actual" del sitio.
--   4. Programa una tarea (pg_cron) que lo revisa cada hora.
-- ══════════════════════════════════════════════════════════════

-- 1. Columnas nuevas ------------------------------------------------
alter table public.games
  add column if not exists game_date   date,
  add column if not exists slot_time   text,
  add column if not exists rescheduled boolean not null default false;

alter table public.games_segunda
  add column if not exists game_date   date,
  add column if not exists slot_time   text,
  add column if not exists rescheduled boolean not null default false;

-- 2. Permitir type = 'scheduled' ------------------------------------
--    Si la columna type tiene un CHECK o es un enum, se le agrega el valor.
--    El CHECK se vuelve a crear con los mismos valores que ya tenía + 'scheduled'.
do $$
declare
  t       text;
  c       record;
  valores text;
  udt     text;
begin
  foreach t in array array['games', 'games_segunda'] loop
    select udt_name into udt from information_schema.columns
     where table_schema = 'public' and table_name = t
       and column_name = 'type' and data_type = 'USER-DEFINED';
    if udt is not null then
      execute format('alter type %I add value if not exists %L', udt, 'scheduled');
    end if;

    for c in
      select conname, pg_get_constraintdef(oid) as d from pg_constraint
       where conrelid = format('public.%I', t)::regclass
         and contype = 'c'
         and pg_get_constraintdef(oid) ilike '%upcoming%'
         and pg_get_constraintdef(oid) not ilike '%scheduled%'
    loop
      select string_agg(distinct quote_literal(m[1]), ', ') into valores
        from regexp_matches(c.d || ' ''scheduled''', '''([^'']+)''', 'g') as m;
      execute format('alter table public.%I drop constraint %I', t, c.conname);
      execute format('alter table public.%I add constraint %I check (type::text in (%s))', t, c.conname, valores);
    end loop;
  end loop;
end $$;

-- 3. Texto de fecha, ej: 'Martes 27 Oct · 19:30' --------------------
--    Debe coincidir con fechaTexto() en fixture.html.
create or replace function public.lsc_fecha_texto(d date, hora text)
returns text language sql immutable as $$
  select (array['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'])[extract(dow from d)::int + 1]
      || ' ' || extract(day from d)::int || ' '
      || (array['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'])[extract(month from d)::int]
      || coalesce(' · ' || nullif(hora, ''), '');
$$;

-- 4. Publicar la siguiente jornada de una división ------------------
--    Devuelve un texto explicando qué hizo (útil para revisar a mano:
--    select public.lsc_publicar_jornada('segunda');).
create or replace function public.lsc_publicar_jornada(division text)
returns text language plpgsql security definer set search_path = public as $$
declare
  tabla     text := case division when 'primera' then 'games' when 'segunda' then 'games_segunda' end;
  dia_juego int  := case division when 'primera' then 4 else 2 end;  -- 4 = jueves, 2 = martes
  ahora     timestamp := now() at time zone 'America/Santiago';
  hoy       date := (now() at time zone 'America/Santiago')::date;
  en_curso  int;
  siguiente int;
  ultima    date;
  nueva     date;
begin
  if tabla is null then
    raise exception 'División desconocida: %', division;
  end if;

  -- La jornada en curso no termina hasta que se jueguen todos sus partidos.
  execute format('select count(*) from %I where type in (''upcoming'', ''live'')', tabla) into en_curso;
  if en_curso > 0 then
    return 'Jornada en curso, nada que publicar';
  end if;

  execute format('select min(round) from %I where type = ''scheduled''', tabla) into siguiente;
  if siguiente is null then
    return 'No quedan jornadas por publicar';
  end if;

  -- Se publica a las 10:00 del día siguiente al último partido jugado.
  execute format('select max(game_date) from %I where type = ''finished''', tabla) into ultima;
  if ahora::time < time '10:00' then
    return 'Aún no son las 10:00';
  end if;
  if ultima is not null and hoy <= ultima then
    return 'Se publica mañana a las 10:00';
  end if;

  -- Próximo día de juego de la división, a partir de mañana.
  nueva := hoy + ((dia_juego - extract(dow from hoy)::int + 6) % 7 + 1);

  execute format(
    'update %I set type = ''upcoming'', game_date = $1, rescheduled = false,
            date = public.lsc_fecha_texto($1, slot_time)
      where type = ''scheduled'' and round = $2', tabla)
  using nueva, siguiente;

  insert into public.settings (key, value)
  values ('round_' || division, siguiente::text)
  on conflict (key) do update set value = excluded.value;

  return format('J%s publicada para el %s', siguiente, public.lsc_fecha_texto(nueva, null));
end $$;

create or replace function public.lsc_publicar_jornadas()
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.lsc_publicar_jornada('primera');
  perform public.lsc_publicar_jornada('segunda');
end $$;

-- Solo la tarea programada (y tú desde el SQL Editor) puede ejecutarlas.
revoke all on function public.lsc_publicar_jornada(text) from public, anon, authenticated;
revoke all on function public.lsc_publicar_jornadas()    from public, anon, authenticated;

-- 5. Tarea programada: cada hora, al minuto 5 ----------------------
--    Corre cada hora (y no solo a las 10:00) para no depender del horario
--    de verano/invierno de Chile; la función decide si ya corresponde.
create extension if not exists pg_cron;

select cron.schedule('lsc-publicar-jornadas', '5 * * * *', $$select public.lsc_publicar_jornadas()$$);

-- Para desactivarla:
--   select cron.unschedule('lsc-publicar-jornadas');
