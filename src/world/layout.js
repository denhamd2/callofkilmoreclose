/**
 * WORLD — the map.
 *
 * Kilmore Close (OSM way 37211091, Beaumont/Artane area, Dublin) replaces the
 * fictional Middle-Eastern market street. All coordinates are in LEVEL space;
 * the WorldSystem rotates the whole thing so the street runs down the
 * canonical hero-shot camera axis — real-world compass bearing is not
 * preserved, only the street's own internal shape.
 *
 * Sides: 0 = -Z, 1 = +X, 2 = +Z, 3 = -X.
 *
 * ==========================================================================
 * 2026-08 RE-SURVEY — supersedes parts of the OSM notes below. READ FIRST.
 * ==========================================================================
 * Re-derived from three Overpass GeoJSON exports of the area (checked in under
 * `src/world/osm/`). Three findings changed the table below; the older notes
 * are kept where still true and struck through in prose where not.
 *
 * 1. TWO HOUSES WERE MISSING. `way/644614599` and `way/960176182` are tagged
 *    `building=house` with NO `addr:street`, so the earlier
 *    `addr:street=Kilmore Close` query never saw them — but they sit squarely
 *    in the row line (along -102.4 / -93.0, perp +8.0 / +6.5). They exactly
 *    fill what the old notes called a real ~20 m `kilmoreGap` "between KW2 and
 *    KW3". That gap was a TAGGING HOLE, not a feature of the street.
 *    -> the row is 28 houses, not 26.
 *
 * 2. THE TWO LOOP ARMS WERE ON THE WRONG SIDES. Sorting all 28 by along-axis
 *    position and reading their perpendicular offset shows the lane ending at
 *    perp -14.2 and continuing smoothly into the FOUR-house arm
 *    (-15.5, -16.9, -18.8, -20.0), while the SIX-house arm sits at
 *    +16.1..+24.1 — about 40 m across the road. The previous table had it
 *    backwards: it welded the six-house arm onto the end of the long row and
 *    put the four-house arm opposite. That is precisely the reported
 *    "one long row, one short row" symptom, and it was a data error, not a
 *    dressing problem.
 *    -> near side (streetSide 1) = 18 lane + 4 continuation = 22 houses
 *    -> far  side (streetSide 3) = the six-house arm          =  6 houses
 *
 * 3. REAL OSM SPACING IS RESTORED. The previous pass replaced real
 *    house-to-house spacing with a constant 3.0 m wall-to-wall gap, which
 *    flattened the semi-detached rhythm into an evenly spaced terrace. Real
 *    along-axis spacing alternates ~6-7 m (within a joined semi pair) and
 *    ~11-13 m (between pairs); `z` is now that real position, 1:1, so the
 *    pairing reads again. Total along-axis extent 209.0 m, unchanged.
 *
 * OSM-vs-MEASUREMENT CONFLICTS, recorded rather than reconciled away:
 *  - Semi-pair width: the Google Earth reference measures a joined pair at
 *    16.55 m. Real OSM pair spans here run ~11.8-16.9 m (mean ~13). OSM
 *    per-house footprints are canonical per the brief, so `w`/`d` are left as
 *    mapped and 16.55 m is used only as a reference check. The likely cause is
 *    the party-wall double-counting already noted below.
 *  - Road length: Google Earth measures 304.69 m. The OSM along-axis extent of
 *    the 28 footprints is 209.0 m and the drawn ribbon runs 253 m
 *    (STREET.zMin..zMax) so the street does not stop dead at the end houses.
 *    No geometry is fabricated to reach 304.69 m.
 *  - HOUSE NUMBERS ARE NOT IN OSM AT ALL. Every one of the 32
 *    `addr:street=Kilmore Close` features carries zero `addr:housenumber`.
 *    (The only house numbers anywhere in the export belong to Beechlawn Close,
 *    odds 1-21 — which does confirm the local odd-one-side/even-the-other
 *    convention.) The `no` field below is therefore a DOCUMENTED CONVENTION,
 *    not an OSM fact. See HOUSE_NUMBERS.
 *
 * --------------------------------------------------------------------------
 * OSM-GROUNDED vs PROVISIONAL — read this before touching a number below.
 * --------------------------------------------------------------------------
 * OSM-GROUNDED (from three Overpass queries anchored on way 37211091):
 *  - The 26 building footprints tagged `addr:street=Kilmore Close` — their
 *    real footprint dimensions (from polygon geometry) and their real
 *    along-street ORDER. Their real along-street SPACING was OSM-grounded up
 *    to the uniform-row pass, which replaced it with a constant 3.0 m
 *    wall-to-wall gap (see BUILDINGS). The gap chosen is the mean of the real
 *    spacing, so the row still spans the same stretch of z — but individual
 *    house-to-house distances are no longer OSM facts. (A 27th–32nd match at addr:street=
 *    "Kilmore Close" belonged to an unrelated street of the same name
 *    ~190 km away and was excluded.)
 *  - Both-street-ends connectivity: three real highways (Beechlawn Avenue,
 *    Kilmore Avenue, and an unnamed way flagged `fixme=Kilmore Drive?`) share
 *    nodes with Kilmore Close, geographically bracketing one end — support
 *    for "neither end is a dead end" (decision, not a literal traced
 *    endpoint, since the raw way-37211091 linestring itself was not fetched).
 *  - The street's real shape: fitting a PCA axis through the 26 building
 *    centroids and projecting each one onto it shows a single-sided lane for
 *    ~154 m (one building per along-position, no pairing) that forks into a
 *    two-sided loop/bulb for the final ~47 m (two rows, six on one arm, four
 *    on the other). Real total along-axis length: ~209 m.
 *  - None of the 26 carry `building:levels`, `house=`, or `roof:shape` (the
 *    neighbouring Beechlawn Avenue/Close houses do — 2-storey semis — used
 *    only as circumstantial support for the provisional floor count below).
 *
 * PROVISIONAL (no OSM support — a barriers/hedges/footways/driveways query
 * around Kilmore Close came back with zero features):
 *  - Every front garden: a uniform 8.71 m gap between the kerb line
 *    (x = ±5.815) and each house's near face — calibrated to the Google
 *    Earth front-garden-depth measurement (8.71 m) on the reference street,
 *    with BUILDINGS' per-house `x` shifted by a constant ∓5.025 m (west/east)
 *    from the previous 3.0 m provisional gap so every house's real OSM width
 *    (`w`, left untouched — see below) keeps its own near-face position
 *    exactly 8.71 m back from the (also recalibrated, see STREET) kerb line.
 *    frontGardens() in dressing.js reads this off STREET.kerb + BUILDINGS
 *    directly, so the lawn/driveway/wall dressing follows automatically.
 *  - Front garden lawn/driveway/boundary-wall dressing is procedural (see
 *    dressing.js's `frontGardens`) — the "garden" reads as a bounded plot,
 *    not open ground.
 *  - floors (2), wall material, doorBays, roofProps, damage, and the window
 *    pattern — ordinary set-dressing choices, not claimed as OSM facts. These
 *    are no longer per-house: every building is one archetype (white
 *    pebbledash `dash_white` over a `plaster_coral` band, porch, garage, fixed
 *    window pattern), declared once above BUILDINGS. bandKey stays plaster_*,
 *    because the painted ground-floor band is a smooth render strip over the
 *    dash, not more aggregate. The earlier scheme cycled four dash colours for
 *    variety; the BG* background infill that stood for the neighbouring
 *    streets' rears has been removed outright — there is one building type.
 *  - The engine's road is a straight, constant-width ribbon (see
 *    ground.js:16-65) with no curve/fork support, so the real curving,
 *    forking street is flattened: real along-axis position/order/spacing is
 *    used for z (true 1:1 scale, ~209 m), but the real perpendicular
 *    OFFSET MAGNITUDE is not usable (it would put "mid-lane" houses almost
 *    on the kerb and loop-end houses ~20+ m out) — only its topology
 *    survives: one row for the 154 m lane, both rows for the 47 m loop end,
 *    each placed at a fixed, schema-consistent setback.
 *  - A handful of adjacent semi-detached pairs' raw OSM footprints overlap
 *    by ~0.5–2 m (party-wall thickness double-counted on both sides, a
 *    common mapping artifact) — trimmed by the overlap amount so pairs sit
 *    flush instead of interpenetrating; real z-spacing (positions) is
 *    untouched, only the depth ('d') of the two affected houses per pair.
 *  - Both ends are open, per the real connecting-road continuity above —
 *    see ROAD_ENDS below for the resolved OSM roads at each end. (An earlier
 *    pass closed the loop end with a fictional GATE arch and the lane end
 *    with a barricade; both were removed once this connectivity was pinned
 *    down to specific roads.)
 *  - SET_PIECES POSITIONS below are anchored to the houses. Each entry was
 *    placed against a particular frontage, and when the uniform-row pass
 *    re-spaced the street every entry moved with the house it sat outside,
 *    keeping its offset from that house's centre. They are therefore no longer
 *    a proportional rescale of the old market street (a factor of 2.375, which
 *    is where the retired "247 m" figure came from — it was an arithmetic
 *    product, never a street length). Three figures describe this street and
 *    they mean different things:
 *      ~209 m  real OSM along-axis extent of the 26 footprints (PCA fit)
 *       218.5 m modelled building span, KW22's near z to KW1's far z, at the
 *               uniform 3.0 m spacing
 *       253 m   STREET.zMin..zMax, the drawn road ribbon, which runs past the
 *               end houses at both ends so the street does not stop dead
 *    Anything added to SET_PIECES from here should be placed relative to a
 *    house, not typed as a bare z, or the next spacing change will strand it.
 *  - SET_PIECES CONTENT is rethemed for the residential setting — see the
 *    comment on the table itself. (This note previously claimed the content was
 *    still the old market-street set. That was stale from the moment the
 *    dressing pass landed, and it caused a later pass to misdiagnose correct
 *    residential dressing as leftover market dressing. Keep it in step.)
 *
 * Coordinate conversion: local tangent-plane approximation centred on the
 * centroid of the 26 building footprints (equirectangular: metres-per-degree
 * longitude scaled by cos(latitude), no further projection correction —
 * accurate to a few cm over this ~250 m span). PCA axis through the same 26
 * centroids gives the street's internal orientation; along-axis position
 * maps 1:1 to engine z, real footprint extents map to engine w (X extent)
 * and d (Z extent) per the existing convention.
 */

export const STREET = {
  // Carriageway half-width, recalibrated so the full 2x carriageway reads as
  // 7.63 m — the Google Earth "road width excluding footpaths" measurement
  // on the reference street (no OSM width tag on this `highway=residential`
  // way to calibrate against directly). Was 4.5 (9.0 m full width).
  halfWidth: 3.815,
  // Kerb line: halfWidth + the same 2.0 m footpath/verge strip as before, so
  // narrowing the carriageway doesn't also narrow the footpath. Was 6.5.
  kerb: 5.815,
  // Front-garden depth: the Google Earth "front garden depth" measurement
  // (8.71 m) on the reference street. See the file-header PROVISIONAL note
  // for how this is applied to BUILDINGS' per-house x.
  setback: 8.71,
  // Kerb upstand. Was 0.145; standard kerb face is 100-125 mm, and 125 is what
  // a residential estate is laid to. Also what the dished driveway crossings in
  // dressing.js measure their drop-down from.
  walkH: 0.125,
  zMin: -40,
  zMax: 213,
};

/**
 * Alleys and open ground, as rects [x0, z0, x1, z1]. All provisional/fictional.
 *
 * The `kilmoreGap` entry that used to head this list — a real ~20 m clear gap
 * in the OSM building row between KW2 and KW3 — is gone with the move to a
 * uniform row: at a constant 3 m spacing that gap no longer exists, and the
 * rect would have laid bare dirt under KW3-KW5.
 */
export const ALLEYS = [
  // The two `dirt` "rear-access lane" rects that used to sit at [6.5, 120, 29,
  // 160] and [6.5, 40, 29, 70] are gone. They covered the open (+X) side of the
  // lane stretch, where Kilmore Close genuinely has no houses — the re-survey
  // puts a neighbouring street's rear about 40 m across there — and laying bare
  // dirt over it is what made that side read as unfinished ground next to a
  // long row of houses. They were also the densest junk source in the level:
  // scatterDebris ran a per-alley crate/barrel/pallet/rubble pass over every
  // ALLEYS rect. `rearBoundary()` in dressing.js now closes that side properly
  // with a garden wall and hedge run.
  { rect: [-30, -36, 30, -30], surface: 'gravel' }, // provisional far cross street south end, reads as Beechlawn Avenue (ROAD_ENDS.south) crossing beyond the loop
  { rect: [-30, 203, 30, 209], surface: 'gravel' }, // provisional far cross street north end, reads as Kilmore Avenue (ROAD_ENDS.north) crossing beyond the lane — mirrors the south entry's offset from its street edge (zMin+4..zMin+10), so both real OSM road connections read the same way
];

/**
 * THE KILMORE CLOSE HOUSE ARCHETYPE.
 *
 * Every building on the map is one of these — there is no second building
 * type. The archetype is stated once, here, so it cannot drift house by
 * house: white pebbledash over a painted band, a front garden (STREET.setback),
 * a porch over the front door, a garage at the far end of the frontage, and a
 * fixed window pattern.
 *
 * `w` is the X extent (plot depth, perpendicular to the street) and `d` the Z
 * extent (the frontage the street actually sees) — `sideLen()` in
 * buildings.js reads `d` for streetSide 1/3, which is every house here. Real
 * OSM footprints are kept; only the spacing between them is regularised.
 */
const ARCHETYPE = {
  floors: 2,
  wallKey: 'dash_white',
  bandKey: 'plaster_coral',
  damage: 0.05,
  balconies: 0,
  roofProps: 2,
};

/** Frontage bay count, matching buildings.js's own `round(len / 3.05)`. */
const bays = (d) => Math.max(1, Math.round(d / 3.05));

/** Bay centre offset along the street face, in the wall's local coords. */
const bayCentre = (d, b) => -d / 2 + (b + 0.5) * (d / bays(d));

/**
 * The fixed window pattern: ground floor is the front door in bay 0 and
 * windows across the rest, upper floor is windows all the way. Authored as
 * `bayKinds` so it overrides the per-bay dice roll in buildings.js (which gave
 * each bay a 72%/88% chance of a window and blank wall otherwise, and was why
 * no two frontages matched). Applies to whichever side faces the street, so a
 * 2-bay and a 3-bay frontage still read as the same house.
 */
function windows(streetSide, d) {
  const n = bays(d);
  const ground = [];
  const upper = [];
  for (let b = 0; b < n; b++) {
    ground.push(b === 0 ? 'door' : 'window');
    upper.push('window');
  }
  return { [streetSide]: [ground, upper] };
}

/**
 * Porch over the front door, garage at the opposite end of the frontage. Both
 * are clamped inside the wall run so neither overhangs a corner on the
 * narrowest (4.83 m) frontage; the generator asserts they never overlap.
 */
function attachments(d) {
  const half = d / 2;
  return [
    { kind: 'porch', along: +Math.max(bayCentre(d, 0), -(half - 0.95)).toFixed(3), w: 1.9, depth: 1.5, h: 2.5 },
    { kind: 'garage', along: +Math.min(bayCentre(d, bays(d) - 1), half - 1.3).toFixed(3), w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' },
  ];
}

/**
 * One house. `no` is the Kilmore Close house number (see HOUSE_NUMBERS — a
 * documented convention, not an OSM fact). `extra` carries only the
 * playable-interior fields (3 houses).
 */
function house(id, no, x, z, w, d, streetSide, extra) {
  return {
    id,
    no,
    x,
    z,
    w,
    d,
    streetSide,
    ...ARCHETYPE,
    doorBays: { [streetSide]: 0 },
    bayKinds: windows(streetSide, d),
    attachments: attachments(d),
    ...extra,
  };
}

/**
 * Stair void for an enterable house, in world coords. Kept as a helper so the
 * three interiors stay consistent when a house moves: the previous table had
 * these typed as absolute literals, which silently desynced from `x`/`z` every
 * time the row was re-spaced.
 */
function stairHole(x, z) {
  return { 1: { x0: x - 0.79, x1: x + 0.41, z0: z - 1.74, z1: z + 1.06 } };
}

/** The two-floor plan shared by the three enterable houses. */
const ROOMS = [
  {
    walls: [[0.4, 0, 0.4, 0.55, 0.28]],
    furnish: [
      { kind: 'living', x0: 0.4, z0: 0, x1: 1, z1: 1 },
      { kind: 'storage', x0: 0, z0: 0, x1: 0.4, z1: 0.55 },
      { kind: 'living', x0: 0, z0: 0.55, x1: 0.4, z1: 1 },
    ],
  },
  {
    walls: [[0.5, 0, 0.5, 1, 0.3]],
    furnish: [
      { kind: 'living', x0: 0, z0: 0, x1: 0.5, z1: 1 },
      { kind: 'living', x0: 0.5, z0: 0, x1: 1, z1: 1 },
    ],
  },
];

/** Playable-interior payload for a house at (x, z). */
function interior(x, z) {
  return {
    enterable: true,
    // roofAccess stays false everywhere: buildings.js derives
    // `pitchedRoof = !roofAccess && ...`, so a roof-access house is the one
    // thing on the street that gets a FLAT roof — an archetype outlier.
    roofAccess: false,
    stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }],
    stairHoles: stairHole(x, z),
    rooms: ROOMS,
  };
}

/**
 * Buildings — 28 houses, from the 2026-08 re-survey (see the file header).
 *
 * KW* = the near side (streetSide 1): the 18-house single-sided lane plus the
 * 4-house arm that continues its line around the loop = 22 houses.
 * KE* = the far side (streetSide 3): the 6-house arm, ~40 m across. This is
 * the only stretch of Kilmore Close with houses facing each other, and it is
 * where the encounter is staged.
 *
 * `no` is the house number (HOUSE_NUMBERS convention, not OSM). `z` is the
 * real OSM along-axis position, 1:1 — the uniform 3.0 m re-spacing of the
 * previous pass is gone, so joined semi pairs sit ~6-7 m apart and the gap
 * between pairs reads ~11-13 m again. `x` places every near face exactly
 * STREET.setback (8.71 m) back from the kerb line, so `w` varying per house
 * does not vary the garden depth.
 *
 * Ordered north (the Kilmore Avenue end, high z) to south (the Beechlawn
 * Avenue end, low z). House numbers run the other way — from the south end
 * up — which is why KW22 is number 14 and KW1 is number 56.
 */
export const BUILDINGS = [
  // ------------------------------------------- KW: near side, 22 houses --
  house('KW1', 56, -18.266, 197.509, 7.48, 11.73, 1), // osm way/644614598
  house('KW2', 54, -20.685, 188.341, 12.32, 8.19, 1), // osm way/960176181 — larger footprint, kept as mapped
  house('KW3', 52, -18.461, 177.767, 7.87, 11.55, 1), // osm way/644614599 — RESTORED: building=house, no addr:street
  house('KW4', 50, -18.467, 168.355, 7.88, 7.96, 1), // osm way/960176182 — RESTORED: building=house, no addr:street
  house('KW5', 48, -21.186, 160.815, 13.32, 10.79, 1), // osm way/644614600 — likely a mapped semi-D pair, kept as mapped
  house('KW6', 46, -18.604, 151.789, 8.16, 6.72, 1), // osm way/960176180
  house('KW7', 44, -18.324, 140.934, 7.6, 6.83, 1), // osm way/644614615
  house('KW8', 42, -18.595, 135.08, 8.14, 5.13, 1), // osm way/960176179
  house('KW9', 40, -20.562, 124.759, 12.07, 6.82, 1), // osm way/644614616 — larger footprint, kept as mapped
  house('KW10', 38, -18.596, 117.709, 8.14, 6.82, 1), // osm way/960176178
  house('KW11', 36, -18.795, 105.497, 8.54, 6.91, 1), // osm way/644614617
  house('KW12', 34, -18.796, 98.678, 8.54, 6.91, 1), // osm way/960176177
  house('KW13', 32, -18.477, 86.8, 7.9, 6.71, 1), // osm way/644614618
  house('KW14', 30, -18.477, 80.183, 7.9, 6.71, 1), // osm way/960176176
  house('KW15', 28, -18.534, 67.303, 8.02, 8.13, 1), // osm way/644614619
  house('KW16', 26, -18.534, 59.285, 8.02, 8.13, 1, interior(-18.534, 59.285)), // osm way/960176175 — 26: Oysters
  house('KW17', 24, -18.534, 51.267, 8.02, 8.13, 1), // osm way/644614614
  house('KW18', 22, -18.534, 43.249, 8.02, 8.13, 1), // osm way/960176174
  // --- the loop's near arm: the only stretch with houses opposite ---
  house('KW19', 20, -18.203, 32.699, 7.36, 8.18, 1), // osm way/644614620
  house('KW20', 18, -18.203, 24.631, 7.36, 8.19, 1, interior(-18.203, 24.631)), // osm way/960176173 — 18: David
  house('KW21', 16, -18.853, 13.24, 8.66, 7.44, 1), // osm way/644614621
  house('KW22', 14, -18.848, 5.899, 8.65, 7.44, 1, interior(-18.848, 5.899)), // osm way/960176172 — 14: the McCabes

  // ------------------------------------------- KE: far side, 6 houses ----
  house('KE1', 31, 18.644, 35.212, 8.24, 6.9, 3), // osm way/644614624 — 31: Paddy Mason
  house('KE2', 29, 18.644, 28.406, 8.24, 6.9, 3), // osm way/960176171
  house('KE3', 27, 18.317, 16.49, 7.58, 7.37, 3), // osm way/644614623 — 27: Angela, across from 18
  house('KE4', 25, 18.312, 9.219, 7.57, 7.38, 3), // osm way/960176170
  house('KE5', 23, 18.71, -3.374, 8.37, 8.28, 3), // osm way/644614622
  house('KE6', 21, 18.711, -11.54, 8.37, 8.28, 3), // osm way/960176169
];

/**
 * HOUSE NUMBERS — a documented convention, NOT an OSM fact.
 *
 * OSM carries zero `addr:housenumber` for Kilmore Close (all 32 matching
 * features), so nothing here can be reconciled against it. What IS supported:
 * neighbouring Beechlawn Close is mapped with odds 1-21, confirming the local
 * odd-one-side / even-the-other convention. That convention is applied here:
 *
 *   near side (streetSide 1, 22 houses) -> EVENS, 14..56, from the south end up
 *   far  side (streetSide 3,  6 houses) -> ODDS,  21..31, from the south end up
 *
 * The sides start at 14 and 21 rather than 2 and 1 because the numbered stretch
 * of the close nearest Beechlawn Avenue is not in the OSM extract; the low
 * numbers are assumed to live there. This is the assumption that makes the
 * brief's five addresses land on real, correctly-sided houses:
 *
 *   14 KW22  z   5.9  near   the McCabes — two doors from 18 (14 -> 16 -> 18)
 *   18 KW20  z  24.6  near   David
 *   26 KW16  z  59.3  near   Oysters
 *   27 KE3   z  16.5  far    Angela — across the road, 8.1 m off David's frontage
 *   31 KE1   z  35.2  far    Paddy Mason
 *
 * Documented residual: 27 is genuinely across the road from 18 but not exactly
 * opposite it — the two rows are offset by roughly one house width. Kilmore
 * Close is only two-sided for its last ~47 m, so this is as close as the real
 * geometry allows without moving a house off its OSM position.
 */
export const HOUSE_NUMBERS = Object.freeze(
  BUILDINGS.reduce((m, b) => {
    m[b.no] = b.id;
    return m;
  }, {}),
);

/** Look a house up by its Kilmore Close number. Returns undefined if absent. */
export function houseByNumber(no) {
  return BUILDINGS.find((b) => b.no === no);
}

/**
 * Real OSM road continuity at each end of the map. Replaces the removed
 * fictional GATE arch (which used to close the vista at the loop/south end)
 * and the removed perimeter end-of-street barricades (`buildPerimeter`'s old
 * `blocks` in dressing.js, which used to close the lane/north end) — both
 * ends are now left open, reading as "the street continues into the real
 * road network" rather than a dead end.
 *
 * Resolved by node-level Overpass queries on way 37211091's two endpoint
 * nodes (sharper than the "bracketing one end" connectivity noted in the
 * file-header OSM survey above, which didn't distinguish which node was
 * which):
 *   - node 291661838 (53.39073, -6.21343) -> Kilmore Avenue (way 27814285),
 *     plus an unnamed residential stub (way 28698421, `fixme=Kilmore Drive?`)
 *   - node 291661825 (53.39015, -6.20872) -> Beechlawn Avenue (way 26595749)
 *
 * `end` maps these nodes to engine ends using the existing z convention:
 * KW1 sits at z=197.35 near the documented "lane's open (north) end"
 * (BGN1/BGN2, z=222-226), and KW21 sits at the documented "loop end"
 * (z=-24..-40, BGS1/BGS2) — so the Kilmore Avenue node is the north/lane
 * end, the Beechlawn Avenue node the south/loop end. This inference (not a
 * literal traced bearing) should get a quick sanity check before it drives
 * further road-continuation geometry.
 */
export const ROAD_ENDS = {
  north: {
    end: 'lane', // the single-sided lane's open end, z near STREET.zMax
    osmNode: 291661838,
    roads: [
      { way: 27814285, name: 'Kilmore Avenue' },
      { way: 28698421, name: null, fixme: 'Kilmore Drive?' },
    ],
  },
  south: {
    end: 'loop', // the two-sided loop/bulb end, z near STREET.zMin
    osmNode: 291661825,
    roads: [{ way: 26595749, name: 'Beechlawn Avenue' }],
  },
};

/**
 * Hand-placed set pieces. Positions are carried over from the previous
 * market-street pass (chosen to clear the named shot cameras — see
 * `SHOT_CLEAR` in dressing.js — and to sit inside the real building line),
 * but every category's CONTENT is rethemed here for a lived-in Dublin
 * residential close: parked cars in place of market stalls, low garden walls
 * in place of jersey barriers, clipped hedges in place of sandbag walls, a
 * single builder's skip in place of the burnt-out wrecks, ordinary deciduous
 * trees in place of palms, and kerbside bin stores in place of the war-rubble
 * piles and tyre stacks. Lamps, overhead cables and washing lines read fine
 * unchanged for an older Irish estate and are kept as-is.
 */
export const SET_PIECES = {
  /** Parked cars along the kerb: [x, z, ry, length] */
  cars: [
    [5.7, 129.03, 0.0, 4.3],
    [-5.7, 121.88, 0.0, 4.0],
    [5.7, 139.09, 0.0, 4.3],
    [-5.7, 123.33, 0.0, 4.1],
    [5.7, 122.84, 0.0, 4.0],
    [-5.7, 92.36, 0.0, 4.2],
    [5.7, 71.47, 0.0, 4.3],
    [-5.7, 66.65, 0.0, 4.0],
  ],
  /** A builder's skip outside the one house mid-renovation: [x, z, ry] */
  skips: [
    [5.7, 117.85, 0.42],
    [-5.7, 39.87, -0.3],
  ],
  /** Street/garden trees: [x, z, scale] */
  trees: [
    [-5.4, 163.36, 1.0],
    [5.5, 129.27, 1.1],
    [-5.5, 103.27, 0.92],
    [5.6, 57.22, 1.05],
    [-5.5, 28.86, 1.0],
    [8.5, 125.7, 0.85],
    [-9.0, 89.5, 0.9],
  ],
  /** Street lamps: [x, z, ry] — ry points the arm across the street. */
  lamps: [
    [-5.9, 153.33, -Math.PI / 2],
    [5.9, 123.79, Math.PI / 2],
    [-5.9, 87.6, -Math.PI / 2],
    [5.9, 48.91, Math.PI / 2],
    [-5.9, 21.41, -Math.PI / 2],
  ],
  /**
   * Overhead utility cable spans: [x0, y0, z0, x1, y1, z1, sag]
   *
   * Clearances raised to ESB-plausible minima, measured at MID-SPAN (mean of
   * the two endpoint heights, less the sag) rather than at the poles, which is
   * where a span is actually lowest:
   *   - spans that CROSS the carriageway need ~5.8 m. Two were fine (6.75,
   *     6.20), one was exactly on the line (5.80) and one was under it (5.40).
   *   - spans that run ALONG the street over the footpath need ~5.2 m. Both
   *     were under, at 4.90 and 4.80.
   * Endpoints raised so every span now clears its own minimum with margin.
   */
  cables: [
    [-6.4, 7.6, 138.75, 6.4, 7.0, 144.69, 1.1], // crossing: 6.20 mid
    [-6.4, 8.4, 109.21, 6.4, 7.9, 112.77, 1.4], // crossing: 6.75 mid — unchanged
    [-6.4, 7.0, 78.45, 6.4, 7.4, 82.01, 1.0], // crossing: 6.20 mid (was 5.40)
    [-6.4, 7.6, 36.31, 6.4, 7.2, 41.06, 1.2], // crossing: 6.20 mid — unchanged
    [-6.4, 5.9, 163.69, -6.4, 6.1, 176.75, 0.6], // along street: 5.40 mid (was 4.90)
    [6.4, 6.1, 118.58, 6.4, 5.9, 132.83, 0.7], // along street: 5.30 mid (was 4.80)
  ],
  /**
   * Washing lines: REMOVED, deliberately and permanently.
   *
   * These sat at x = +/-6.35, which is inside the FRONT garden (kerb 5.815 ->
   * house face 14.515). Nobody hangs washing in the front garden facing the
   * street. Their correct home is the rear garden, and there isn't one — the
   * flat terrain band ends at |x| = 15.13 while a rear garden would start
   * around |x| = 23.7, i.e. 8.6 m out onto undulating background terrain.
   *
   * The array is kept, empty, rather than deleted: overheadLines() iterates it,
   * and an empty run is the cheapest correct way to say "no washing lines"
   * without a second code path. If rear gardens are ever built, this is where
   * they go back — at ~1.8 m, behind the houses.
   *
   * NOTE this emptied the shared placement rng of every per-line and
   * per-garment draw the loop used to make, so all props placed after
   * overheadLines() in dressStreet have moved. That is expected here.
   */
  laundry: [],
  /** Doorstep planters / window boxes: [x, y, z, ry, w] */
  doorstepPlanters: [
    [-6.45, 0.02, 136.72, Math.PI / 2, 1.5],
    [-6.45, 0.02, 124.52, Math.PI / 2, 1.2],
    [6.45, 0.02, 128.08, -Math.PI / 2, 1.6],
    [6.45, 0.02, 96.24, -Math.PI / 2, 1.3],
    [-6.45, 0.02, 78.45, Math.PI / 2, 1.4],
  ],
  /** Kerbside bin stores: [x, z, radius, count] */
  binStores: [
    [-4.2, 65.46, 2.4, 34],
    [5.0, 71.47, 2.8, 40],
    [-1.5, 9.21, 2.0, 26],
    [7.6, 33.47, 2.2, 28],
    [-5.0, 180.31, 1.6, 18],
  ],
};
