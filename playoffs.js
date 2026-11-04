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

// Tabla de la fase regular. Misma regla que computeStandings() en index.html:
// 2 pts por victoria, 1 por derrota (0 si es por W.O.); desempate por diferencial,
// duelo directo y puntos anotados. `games`: filas de la BD (snake_case).
function regularStandings(games, teamIds) {
  const finished = games.filter(g => g.type === 'finished' && !isPlayoff(g));
  const rows = {};
  teamIds.forEach(id => {
    rows[id] = { teamId: id, gp: 0, w: 0, l: 0, diff: 0, pointsFor: 0, tablePoints: 0 };
  });
  finished.forEach(g => {
    if (!rows[g.home] || !rows[g.away]) return;
    const hs = +g.home_score, as = +g.away_score;
    const h = rows[g.home], a = rows[g.away];
    h.gp++; a.gp++;
    h.pointsFor += hs; a.pointsFor += as;
    h.diff += hs - as; a.diff += as - hs;
    const [win, loss] = hs > as ? [h, a] : [a, h];
    win.w++; win.tablePoints += 2;
    loss.l++; loss.tablePoints += g.walkover ? 0 : 1;
  });
  const headToHead = (idA, idB) => {
    let wA = 0, wB = 0;
    finished.forEach(g => {
      if (g.home === idA && g.away === idB) { if (+g.home_score > +g.away_score) wA++; else wB++; }
      else if (g.home === idB && g.away === idA) { if (+g.home_score > +g.away_score) wB++; else wA++; }
    });
    return wA > wB ? 1 : wB > wA ? -1 : 0;
  };
  return Object.values(rows).sort((a, b) => {
    const ap = a.gp > 0 ? 1 : 0, bp = b.gp > 0 ? 1 : 0;
    if (bp !== ap) return bp - ap;
    if (b.tablePoints !== a.tablePoints) return b.tablePoints - a.tablePoints;
    if (b.diff !== a.diff) return b.diff - a.diff;
    const h2h = headToHead(a.teamId, b.teamId);
    if (h2h !== 0) return -h2h;
    return b.pointsFor - a.pointsFor;
  });
}

// Cuartos según la tabla: [{ slot, hora, cancha, home, away, homeSeed, awaySeed }] (home/away = filas de la tabla).
function quarterFinalsFrom(table) {
  return Object.entries(PLAYOFF_QF).map(([slot, [hs, as, hora, cancha]]) => ({
    slot, hora, cancha, home: table[hs - 1], away: table[as - 1], homeSeed: hs, awaySeed: as,
  }));
}
