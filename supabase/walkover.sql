-- ══════════════════════════════════════════════════════════════
--  WALK OVER (W.O.) · Liga San Carlos
--
--  Cómo instalar: Supabase → SQL Editor → pegar → Run.
--  Se puede correr más de una vez sin problema.
--
--  walkover = id del equipo que NO se presentó (null en partidos normales).
--  El partido queda 'finished' 20-0 para el rival; el que no se presentó
--  recibe 0 puntos de tabla y el W.O. no cuenta para los récords.
-- ══════════════════════════════════════════════════════════════

alter table public.games         add column if not exists walkover text;
alter table public.games_segunda add column if not exists walkover text;
