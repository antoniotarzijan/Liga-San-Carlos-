-- ══════════════════════════════════════════════════════════════
--  PRONÓSTICOS DE PLAYOFFS ("la polla") · Liga San Carlos
--
--  Cada celular (un código anónimo guardado en el navegador) vota una
--  vez por partido de playoffs y puede cambiar su voto hasta que el
--  partido empiece. La tabla no se lee ni se escribe directo desde el
--  sitio: solo a través de las dos funciones de abajo.
--  Se puede correr más de una vez sin problema.
-- ══════════════════════════════════════════════════════════════

create table if not exists public.playoff_votes (
  id         bigserial primary key,
  division   text not null check (division in ('primera', 'segunda')),
  game_id    bigint not null,
  device_id  uuid not null,
  team       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (division, game_id, device_id)
);

-- RLS activo y sin políticas: nadie accede a la tabla directamente.
alter table public.playoff_votes enable row level security;
revoke all on public.playoff_votes from anon, authenticated;

-- Votar (o cambiar el voto). Solo partidos de playoffs que aún no empiezan
-- y solo por uno de los dos equipos del partido.
create or replace function public.lsc_votar(p_division text, p_game_id bigint, p_device uuid, p_team text)
returns text language plpgsql security definer set search_path = public as $$
declare
  tabla text := case p_division when 'primera' then 'games' when 'segunda' then 'games_segunda' end;
  g record;
begin
  if tabla is null or p_device is null then
    raise exception 'Datos no válidos';
  end if;
  execute format('select type, round, home, away from %I where id = $1', tabla) into g using p_game_id;
  if g is null or g.round < 100 then
    raise exception 'Partido no válido';
  end if;
  if g.type not in ('scheduled', 'upcoming') then
    raise exception 'La votación de este partido ya cerró';
  end if;
  if p_team is distinct from g.home and p_team is distinct from g.away then
    raise exception 'Equipo no válido';
  end if;
  insert into public.playoff_votes (division, game_id, device_id, team)
  values (p_division, p_game_id, p_device, p_team)
  on conflict (division, game_id, device_id)
  do update set team = excluded.team, updated_at = now();
  return 'ok';
end $$;

-- Conteo de votos por partido y equipo de una división (sin códigos de celular).
create or replace function public.lsc_votos(p_division text)
returns table (game_id bigint, team text, votos bigint)
language sql security definer set search_path = public stable as $$
  select game_id, team, count(*) from public.playoff_votes
   where division = p_division group by game_id, team;
$$;

revoke all on function public.lsc_votar(text, bigint, uuid, text) from public;
revoke all on function public.lsc_votos(text) from public;
grant execute on function public.lsc_votar(text, bigint, uuid, text) to anon, authenticated;
grant execute on function public.lsc_votos(text) to anon, authenticated;

-- Resumen para el admin (página del fixture): personas que votaron, votos,
-- votos de hoy y conteo por partido. Solo lo pueden ver las cuentas admin.
-- Las cuentas deben coincidir con ADMIN_UIDS de fixture.html.
create or replace function public.lsc_votos_admin(p_division text)
returns json language plpgsql security definer set search_path = public stable as $$
declare
  hoy date := (now() at time zone 'America/Santiago')::date;
begin
  if auth.uid() is null or auth.uid() not in (
       'b4a8b65e-c365-4ae4-9a85-0624e8c7cd9c'::uuid,
       '272f8ea8-a576-46cc-97ae-7c292424a858'::uuid) then
    raise exception 'Solo para administradores';
  end if;
  return json_build_object(
    'personas',     (select count(distinct device_id) from playoff_votes where division = p_division),
    'votos',        (select count(*) from playoff_votes where division = p_division),
    'personas_hoy', (select count(distinct device_id) from playoff_votes
                      where division = p_division and (updated_at at time zone 'America/Santiago')::date = hoy),
    'votos_hoy',    (select count(*) from playoff_votes
                      where division = p_division and (updated_at at time zone 'America/Santiago')::date = hoy),
    'partidos',     (select coalesce(json_agg(x), '[]'::json) from (
                       select game_id, team, count(*) as votos from playoff_votes
                        where division = p_division group by game_id, team) x)
  );
end $$;

revoke all on function public.lsc_votos_admin(text) from public, anon;
grant execute on function public.lsc_votos_admin(text) to authenticated;
