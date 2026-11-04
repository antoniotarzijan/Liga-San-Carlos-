/* ══════════════════════════════════════════════════════════════
   PLAYOFFS · reglas comunes a todas las páginas
   Los partidos de playoffs viven en las mismas tablas que la fase
   regular (games / games_segunda) con round 100 (cuartos), 101
   (semifinales) y 102 (final), y bracket_slot QF1..QF4, SF1, SF2, F1.
   Sus puntos NO suman a la nómina de la temporada (players).
   Debe coincidir con supabase/playoffs.sql.
══════════════════════════════════════════════════════════════ */
const PLAYOFF_ROUND = 100;
const PLAYOFF_ROUND_NAMES = { 100: 'Cuartos de final', 101: 'Semifinal', 102: 'Final' };
const PLAYOFF_ROUND_SHORT = { 100: 'CF', 101: 'SF', 102: 'F' };

// Cuartos: [puesto local, puesto visita, hora, cancha]. Ganadores de QF1-QF2 → SF1, QF3-QF4 → SF2.
const PLAYOFF_QF = {
  QF1: [1, 8, '19:30', 'Cancha 1'],
  QF2: [4, 5, '19:30', 'Cancha 2'],
  QF3: [2, 7, '20:30', 'Cancha 1'],
  QF4: [3, 6, '20:30', 'Cancha 2'],
};

const roundOf = g => typeof g === 'number' ? g : +(g?.round || 0);
const isPlayoff = g => roundOf(g) >= PLAYOFF_ROUND;
const roundName = g => isPlayoff(g) ? (PLAYOFF_ROUND_NAMES[roundOf(g)] || 'Playoffs') : `Jornada ${roundOf(g)}`;
const roundShort = g => isPlayoff(g) ? (PLAYOFF_ROUND_SHORT[roundOf(g)] || 'PO') : `J${roundOf(g)}`;
