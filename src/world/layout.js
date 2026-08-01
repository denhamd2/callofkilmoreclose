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
 * --------------------------------------------------------------------------
 * OSM-GROUNDED vs PROVISIONAL — read this before touching a number below.
 * --------------------------------------------------------------------------
 * OSM-GROUNDED (from three Overpass queries anchored on way 37211091):
 *  - The 26 building footprints tagged `addr:street=Kilmore Close` — their
 *    real positions, real footprint dimensions (from polygon geometry) and
 *    real along-street order/spacing. (A 27th–32nd match at addr:street=
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
 *  - Every front garden: a uniform, restrained 3.0 m gap between the kerb
 *    line (x = ±6.5) and each house's near face. No wall/hedge/fence mesh is
 *    added — that would need new geometry in dressing.js/kit.js beyond this
 *    data-only pass — so the "garden" reads as open ground, not a bounded
 *    plot. No per-house individual boundary detail is invented.
 *  - floors (2), wallKey materials (brick / brick_fine / plaster_cream /
 *    plaster_white, cycled for texture variety), doorBays, roofProps,
 *    damage — ordinary set-dressing choices, not claimed as OSM facts.
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
 *  - GATE is a fictional level-design vista-terminator only (not a real
 *    gate/wall at Kilmore Close) — placed at the loop end because that end's
 *    two-sided bulb reads naturally as an enclosed plaza; the lane's open end
 *    is treated as "the street continues past the map edge", consistent with
 *    neither end being a dead end.
 *  - SET_PIECES positions below are proportionally rescaled from the old
 *    ~104 m street to the new ~247 m one so nothing sits off the map; their
 *    CONTENT (market stalls, sandbag walls, palms, Jersey barriers…) is
 *    still the old market-street set and is deliberately NOT rethemed here —
 *    that belongs to the dressing/materials pass that follows this one.
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
  halfWidth: 4.5, // asphalt — no OSM width tag on a `highway=residential` way; kept from the previous pass
  kerb: 6.5,
  walkH: 0.145,
  zMin: -40,
  zMax: 213,
};

/**
 * Alleys and open ground, as rects [x0, z0, x1, z1].
 * kilmoreGap is the one OSM-grounded entry: a real ~20 m clear gap in the
 * Kilmore Close building row between KW2 and KW3 (the reason for the gap —
 * side lane, wider plot, mapping gap — is not confirmed by the data, only
 * the gap itself). The rest are fully provisional/fictional.
 */
export const ALLEYS = [
  { rect: [-27, 164.5, -6.5, 184.5], surface: 'dirt' }, // kilmoreGap — OSM-grounded gap, provisional surface/use
  { rect: [6.5, 120, 29, 160], surface: 'dirt' }, // provisional rear-access lane, empty (east) side of the lane stretch
  { rect: [6.5, 40, 29, 70], surface: 'dirt' }, // provisional rear-access lane, empty (east) side of the lane stretch
  { rect: [-30, -36, 30, -30], surface: 'gravel' }, // provisional far cross street, background depth beyond the gate
];

/**
 * Buildings. `w` is the X extent, `d` the Z extent.
 * KW* = the single-sided lane + the west arm of the loop (22 houses, all
 * streetSide 1). KE* = the loop's east arm (4 houses, streetSide 3) — the
 * only stretch of Kilmore Close with buildings on both sides. BG* = fully
 * provisional background infill (neighbouring streets' rears / far
 * skyline), per the "loose background/context only" decision — not
 * individually OSM-placed.
 */
export const BUILDINGS = [
  // --------------------------------------------- KW row (single lane + loop west arm) --
  { id: 'KW1', x: -13.56, z: 197.35, w: 8.1, d: 9.73, floors: 2, wallKey: 'brick', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/644614598
  { id: 'KW2', x: -16.22, z: 188.42, w: 13.4, d: 7.53, floors: 2, wallKey: 'brick_fine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/960176181 — irregular/larger footprint, kept as mapped
  { id: 'KW3', x: -16.48, z: 159.25, w: 14.0, d: 10.1, floors: 2, wallKey: 'plaster_cream', streetSide: 1, damage: 0.1, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/644614600 — irregular/larger footprint (likely a mapped semi-D pair), kept as mapped
  { id: 'KW4', x: -14.01, z: 151.2, w: 9.0, d: 5.4, floors: 2, wallKey: 'plaster_white', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1 }, // osm way/960176180
  {
    id: 'KW5',
    x: -13.81,
    z: 140.34,
    w: 8.6,
    d: 6.63,
    floors: 2,
    wallKey: 'brick',
    streetSide: 1,
    damage: 0.05,
    balconies: 0,
    doorBays: { 1: 0 },
    enterable: true,
    roofAccess: false,
    roofProps: 2,
    stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }],
    stairHoles: { 1: { x0: -14.6, x1: -13.4, z0: 138.6, z1: 141.4 } },
    rooms: [
      {
        // ground floor: hall, living room, kitchen — an ordinary small semi
        walls: [[0.4, 0.0, 0.4, 0.55, 0.28]],
        furnish: [
          { kind: 'living', x0: 0.4, z0: 0.0, x1: 1.0, z1: 1.0 },
          { kind: 'storage', x0: 0.0, z0: 0.0, x1: 0.4, z1: 0.55 },
          { kind: 'living', x0: 0.0, z0: 0.55, x1: 0.4, z1: 1.0 },
        ],
      },
      {
        // first floor: two bedrooms
        walls: [[0.5, 0.0, 0.5, 1.0, 0.3]],
        furnish: [
          { kind: 'living', x0: 0.0, z0: 0.0, x1: 0.5, z1: 1.0 },
          { kind: 'living', x0: 0.5, z0: 0.0, x1: 1.0, z1: 1.0 },
        ],
      },
    ],
  },
  { id: 'KW6', x: -13.94, z: 134.31, w: 8.9, d: 4.83, floors: 2, wallKey: 'brick_fine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1 }, // osm way/960176179
  { id: 'KW7', x: -15.77, z: 123.95, w: 12.5, d: 6.84, floors: 2, wallKey: 'plaster_cream', streetSide: 1, damage: 0.1, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/644614616 — irregular footprint, kept as mapped
  { id: 'KW8', x: -14.08, z: 117.11, w: 9.2, d: 6.24, floors: 2, wallKey: 'plaster_white', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/960176178
  { id: 'KW9', x: -14.28, z: 104.9, w: 9.6, d: 6.52, floors: 2, wallKey: 'brick', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/644614617
  { id: 'KW10', x: -14.28, z: 98.08, w: 9.6, d: 6.52, floors: 2, wallKey: 'brick_fine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/960176177
  { id: 'KW11', x: -13.95, z: 86.19, w: 8.9, d: 6.32, floors: 2, wallKey: 'plaster_cream', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1 }, // osm way/644614618
  { id: 'KW12', x: -13.95, z: 79.57, w: 8.9, d: 6.32, floors: 2, wallKey: 'plaster_white', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1 }, // osm way/960176176
  {
    id: 'KW13',
    x: -14.12,
    z: 66.83,
    w: 9.2,
    d: 7.72,
    floors: 2,
    wallKey: 'brick',
    streetSide: 1,
    damage: 0.05,
    balconies: 0,
    doorBays: { 1: 0 },
    enterable: true,
    roofAccess: false,
    roofProps: 2,
    stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }],
    stairHoles: { 1: { x0: -14.7, x1: -13.5, z0: 65.0, z1: 68.7 } },
    rooms: [
      {
        walls: [[0.4, 0.0, 0.4, 0.55, 0.28]],
        furnish: [
          { kind: 'living', x0: 0.4, z0: 0.0, x1: 1.0, z1: 1.0 },
          { kind: 'storage', x0: 0.0, z0: 0.0, x1: 0.4, z1: 0.55 },
          { kind: 'living', x0: 0.0, z0: 0.55, x1: 0.4, z1: 1.0 },
        ],
      },
      {
        walls: [[0.5, 0.0, 0.5, 1.0, 0.3]],
        furnish: [
          { kind: 'living', x0: 0.0, z0: 0.0, x1: 0.5, z1: 1.0 },
          { kind: 'living', x0: 0.5, z0: 0.0, x1: 1.0, z1: 1.0 },
        ],
      },
    ],
  },
  { id: 'KW14', x: -14.12, z: 58.81, w: 9.2, d: 6.92, floors: 2, wallKey: 'brick_fine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/960176175
  { id: 'KW15', x: -14.12, z: 50.8, w: 9.2, d: 7.32, floors: 2, wallKey: 'plaster_cream', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1 }, // osm way/644614614
  { id: 'KW16', x: -14.12, z: 42.78, w: 9.2, d: 7.82, floors: 2, wallKey: 'plaster_white', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/960176174
  { id: 'KW17', x: -14.13, z: 34.62, w: 9.3, d: 6.36, floors: 2, wallKey: 'brick', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1 }, // osm way/644614624 — loop's west arm begins here
  { id: 'KW18', x: -14.13, z: 27.81, w: 9.3, d: 6.66, floors: 2, wallKey: 'brick_fine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/960176171
  { id: 'KW19', x: -13.84, z: 15.95, w: 8.7, d: 6.97, floors: 2, wallKey: 'plaster_cream', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1 }, // osm way/644614623
  { id: 'KW20', x: -13.84, z: 8.68, w: 8.7, d: 6.97, floors: 2, wallKey: 'plaster_white', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/960176170
  { id: 'KW21', x: -14.31, z: -3.83, w: 9.6, d: 7.87, floors: 2, wallKey: 'brick', streetSide: 1, damage: 0.1, balconies: 0, doorBays: { 1: 0 }, roofProps: 2 }, // osm way/644614622
  {
    id: 'KW22',
    x: -14.31,
    z: -12.0,
    w: 9.6,
    d: 7.87,
    floors: 2,
    wallKey: 'brick_fine',
    streetSide: 1,
    damage: 0.15,
    balconies: 0,
    doorBays: { 1: 0 },
    enterable: true,
    roofAccess: true,
    roofProps: 2,
    stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }],
    stairHoles: { 1: { x0: -14.9, x1: -13.7, z0: -13.8, z1: -10.2 } },
    rooms: [
      {
        walls: [[0.4, 0.0, 0.4, 0.55, 0.28]],
        furnish: [
          { kind: 'living', x0: 0.4, z0: 0.0, x1: 1.0, z1: 1.0 },
          { kind: 'storage', x0: 0.0, z0: 0.0, x1: 0.4, z1: 0.55 },
          { kind: 'living', x0: 0.0, z0: 0.55, x1: 0.4, z1: 1.0 },
        ],
      },
      {
        // last house before the gate — roofAccess makes its roof the level's finale vantage point
        walls: [[0.5, 0.0, 0.5, 1.0, 0.3]],
        furnish: [
          { kind: 'living', x0: 0.0, z0: 0.0, x1: 0.5, z1: 1.0 },
          { kind: 'living', x0: 0.5, z0: 0.0, x1: 1.0, z1: 1.0 },
        ],
      },
    ],
  },

  // --------------------------------------------- KE row (loop's east arm — the only two-sided stretch) --
  { id: 'KE1', x: 13.8, z: 32.24, w: 8.6, d: 7.76, floors: 2, wallKey: 'brick', streetSide: 3, damage: 0.05, balconies: 0, doorBays: { 3: 0 }, roofProps: 2 }, // osm way/644614620
  { id: 'KE2', x: 13.8, z: 24.18, w: 8.6, d: 7.76, floors: 2, wallKey: 'brick_fine', streetSide: 3, damage: 0.05, balconies: 0, doorBays: { 3: 0 }, roofProps: 1 }, // osm way/960176173
  { id: 'KE3', x: 14.38, z: 12.69, w: 9.8, d: 7.04, floors: 2, wallKey: 'plaster_cream', streetSide: 3, damage: 0.05, balconies: 0, doorBays: { 3: 0 }, roofProps: 2 }, // osm way/644614621
  { id: 'KE4', x: 14.38, z: 5.35, w: 9.8, d: 7.04, floors: 2, wallKey: 'plaster_white', streetSide: 3, damage: 0.1, balconies: 0, doorBays: { 3: 0 }, roofProps: 1 }, // osm way/960176172

  // --------------------------------------------- background / infill (fully provisional) --
  /**
   * The KW row is single-sided for its whole ~154 m lane stretch (an OSM
   * fact), so the east side of the lane is genuinely open in reality —
   * almost certainly the rear boundaries of Beechlawn Avenue/Close, per the
   * decision to keep neighbouring streets as loose background only. These
   * are generic distant masses, not individually OSM-placed.
   */
  { id: 'BGE1', x: 26, z: 172, w: 18, d: 22, floors: 2, wallKey: 'brick_fine', streetSide: 3, damage: 0.1, skipSides: [3], roofProps: 2 },
  { id: 'BGE2', x: 27, z: 108, w: 18, d: 24, floors: 2, wallKey: 'plaster_cream', streetSide: 3, damage: 0.1, skipSides: [3], roofProps: 2 },
  { id: 'BGE3', x: 26, z: 52, w: 16, d: 18, floors: 2, wallKey: 'brick', streetSide: 3, damage: 0.1, skipSides: [3], roofProps: 2 },
  // Far skyline beyond the lane's open (north) end — "the street continues off-map", not a dead end.
  { id: 'BGN1', x: -18, z: 222, w: 20, d: 14, floors: 2, wallKey: 'plaster_cream', streetSide: 0, damage: 0.1, roofProps: 2 },
  { id: 'BGN2', x: 16, z: 226, w: 22, d: 16, floors: 2, wallKey: 'brick_fine', streetSide: 0, damage: 0.1, roofProps: 2 },
  // The mass behind the fictional GATE — third plane of depth beyond the arch, same role BS3 played before.
  { id: 'BGS1', x: 2, z: -50, w: 10, d: 8, floors: 3, wallKey: 'plaster_white', streetSide: 2, damage: 0.15, roofProps: 2 },
];

/**
 * The street terminator closing the vista at the loop end of the map.
 *
 * Fully fictional per decision — Kilmore Close has no real gate. Kept as a
 * level-design device (vista terminator / plaza backdrop) rather than a
 * claimed real feature; internal proportions carried over unchanged from
 * the previous pass, only repositioned to sit beyond the new KW22/KE4
 * building line.
 *
 *   xL0..xL1  the left (west) gatehouse block, lowest of the four
 *   xR0..xR1  the right (east) block
 *   xT0..xT1  the tower/bastion, tallest and standing PROUD in +Z
 */
export const GATE = {
  z: -24,
  depth: 3.2,
  span: 5.6,
  height: 4.9,
  outerW: 17,
  bodyH: 6.7,
  xL0: -8.6,
  xL1: -2.8,
  hL: 7.9,
  xR0: 2.8,
  xR1: 6.1,
  hR: 9.5,
  eastProud: 0.55,
  xT0: 6.1,
  xT1: 9.4,
  hT: 12.4,
  towerProud: 1.5,
};

/**
 * Hand-placed set pieces, proportionally rescaled from the old ~104 m street
 * (zMin -58/zMax 46) to the new ~247 m one (zMin -40/zMax 213) so nothing
 * sits off the map. Categories/content are UNCHANGED from the previous
 * market-street pass and deliberately not rethemed here — retargeting these
 * for a residential Dublin close (bins, garden walls, parked cars…) is the
 * job of the dressing/materials pass that follows this one.
 */
export const SET_PIECES = {
  /** Market stalls: [x, z, ry, width] */
  stalls: [
    [-3.2, 118.95, 0.08, 2.4],
    [-3.0, 108.97, -0.05, 2.2],
    [3.1, 126.31, 3.2, 2.4],
    [3.4, 113.25, 3.05, 2.6],
    [-0.4, 109.93, 1.62, 2.3],
    [3.0, 82.38, 3.25, 2.2],
    [-3.3, 69.31, 0.12, 2.4],
    [2.9, 56.25, 3.0, 2.3],
  ],
  /** Jersey barriers: [x, z, ry] */
  jerseys: [
    [-2.6, 145.31, 0.12],
    [-0.4, 142.22, 1.5],
    [2.9, 132.25, -0.1],
    [1.6, 97.81, 1.62],
    [-2.4, 89.5, 0.05],
    [3.2, 65.75, 0.1],
    [-1.0, 46.75, 1.55],
    [1.2, 32.5, 0.2],
    [-3.0, 23.0, 0.0],
  ],
  /** Sandbag emplacements: [x, z, ry, length] */
  sandbagWalls: [
    [-3.6, 129.88, 0.0, 3.0],
    [3.6, 99.0, 0.0, 2.6],
    [-1.6, 59.81, 1.57, 2.4],
    [3.4, 39.62, 0.0, 3.2],
  ],
  /** Burnt-out vehicles: [x, z, ry, rollDeg] */
  wrecks: [
    [2.5, 104.94, 0.42, 0],
    [-2.8, 36.06, -2.6, 4],
    [4.9, 160.75, 1.5, 0],
  ],
  /** Palm trees: [x, z, scale] */
  palms: [
    [-5.4, 151.25, 1.0],
    [5.5, 119.19, 1.1],
    [-5.5, 93.06, 0.92],
    [5.6, 55.06, 1.05],
    [-5.5, 27.75, 1.0],
    [8.5, 115.62, 0.85],
    [-9.0, 79.52, 0.9],
  ],
  /** Street lamps: [x, z, ry] — ry points the arm across the street. */
  lamps: [
    [-5.9, 139.38, -Math.PI / 2],
    [5.9, 110.88, Math.PI / 2],
    [-5.9, 77.62, -Math.PI / 2],
    [5.9, 46.75, Math.PI / 2],
    [-5.9, 18.25, -Math.PI / 2],
  ],
  /** Overhead cable spans: [x0, y0, z0, x1, y1, z1, sag] */
  cables: [
    [-6.4, 7.2, 127.5, 6.4, 6.6, 133.44, 1.1],
    [-6.4, 8.4, 99.0, 6.4, 7.9, 102.56, 1.4],
    [-6.4, 6.2, 65.75, 6.4, 6.6, 69.31, 1.0],
    [-6.4, 7.6, 32.5, 6.4, 7.2, 37.25, 1.2],
    [-6.4, 5.4, 148.88, -6.4, 5.6, 161.94, 0.6],
    [6.4, 5.6, 108.5, 6.4, 5.4, 122.75, 0.7],
  ],
  /** Laundry lines with hanging cloth: [x0, y0, z0, x1, y1, z1] */
  laundry: [
    [6.35, 3.6, 125.12, 6.35, 3.75, 137.47],
    [-6.35, 3.7, 106.12, -6.35, 3.6, 116.57],
    [-6.35, 6.6, 55.06, -6.35, 6.4, 66.94],
    [6.35, 6.5, 89.5, 6.35, 6.7, 101.38],
    [-6.35, 3.65, 39.62, -6.35, 3.8, 51.5],
    [6.4, 3.7, 153.62, 6.4, 3.6, 164.31],
  ],
  /** Hanging rugs / cloth on facades: [x, y, z, ry, w, h] */
  hangings: [
    [-6.45, 2.6, 123.94, Math.PI / 2, 1.5, 2.1],
    [-6.45, 2.4, 114.44, Math.PI / 2, 1.2, 1.7],
    [6.45, 2.7, 118.0, -Math.PI / 2, 1.6, 2.2],
    [6.45, 2.5, 83.56, -Math.PI / 2, 1.3, 1.9],
    [-6.45, 2.5, 65.75, Math.PI / 2, 1.4, 2.0],
  ],
  /** Rubble piles: [x, z, radius, count] */
  rubble: [
    [-4.2, 55.06, 2.4, 34],
    [5.0, 69.31, 2.8, 40],
    [-1.5, 8.75, 2.0, 26],
    [7.6, 31.31, 2.2, 28],
    [-5.0, 165.5, 1.6, 18],
  ],
  /** Tyre stacks: [x, z, n] */
  tyres: [
    [-5.2, 133.44, 4],
    [5.3, 89.5, 3],
    [6.2, 110.88, 5],
    [-5.4, 37.25, 3],
  ],
};
