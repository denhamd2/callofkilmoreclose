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
  { rect: [6.5, 120, 29, 160], surface: 'dirt' }, // provisional rear-access lane, empty (east) side of the lane stretch
  { rect: [6.5, 40, 29, 70], surface: 'dirt' }, // provisional rear-access lane, empty (east) side of the lane stretch
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

/** One house. `extra` carries only the playable-interior fields (3 houses). */
function house(id, x, z, w, d, streetSide, extra) {
  return {
    id,
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
 * Buildings. KW* = the single-sided lane + the west arm of the loop (22
 * houses, streetSide 1). KE* = the loop's east arm (4 houses, streetSide 3),
 * the only stretch of Kilmore Close with buildings on both sides.
 *
 * Real OSM footprints (w/d) and the real house order are preserved; the row is
 * re-spaced to a constant 3.0 m wall-to-wall gap. That gap is the mean of the
 * street's own original spacing, so the row still occupies the same stretch of
 * z and STREET.zMin/zMax, ROAD_ENDS and the cross-street ALLEYS all stay valid.
 * The provisional BG* background infill has been removed — one building type
 * only.
 */
export const BUILDINGS = [
  // --------------------------------------------- KW row (single lane + loop west arm) --
  house('KW1', -18.585, 197.505, 8.1, 9.73, 1), // osm way/644614598
  house('KW2', -21.245, 185.875, 13.4, 7.53, 1), // osm way/960176181 — irregular/larger footprint, kept as mapped
  house('KW3', -21.505, 174.06, 14, 10.1, 1), // osm way/644614600 — irregular/larger footprint (likely a mapped semi-D pair), kept as mapped
  house('KW4', -19.035, 163.31, 9, 5.4, 1), // osm way/960176180
  house('KW5', -18.835, 154.295, 8.6, 6.63, 1, { enterable: true, roofAccess: false, stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }], stairHoles: { '1': { x0: -19.625, x1: -18.425, z0: 152.555, z1: 155.355 } }, rooms: [{ walls: [[0.4, 0, 0.4, 0.55, 0.28]], furnish: [{ kind: 'living', x0: 0.4, z0: 0, x1: 1, z1: 1 }, { kind: 'storage', x0: 0, z0: 0, x1: 0.4, z1: 0.55 }, { kind: 'living', x0: 0, z0: 0.55, x1: 0.4, z1: 1 }] }, { walls: [[0.5, 0, 0.5, 1, 0.3]], furnish: [{ kind: 'living', x0: 0, z0: 0, x1: 0.5, z1: 1 }, { kind: 'living', x0: 0.5, z0: 0, x1: 1, z1: 1 }] }] }),
  house('KW6', -18.965, 145.565, 8.9, 4.83, 1), // osm way/960176179
  house('KW7', -20.795, 136.73, 12.5, 6.84, 1), // osm way/644614616 — irregular footprint, kept as mapped
  house('KW8', -19.105, 127.19, 9.2, 6.24, 1), // osm way/960176178
  house('KW9', -19.305, 117.81, 9.6, 6.52, 1), // osm way/644614617
  house('KW10', -19.305, 108.29, 9.6, 6.52, 1), // osm way/960176177
  house('KW11', -18.975, 98.87, 8.9, 6.32, 1), // osm way/644614618
  house('KW12', -18.975, 89.55, 8.9, 6.32, 1), // osm way/960176176
  house('KW13', -19.145, 79.53, 9.2, 7.72, 1, { enterable: true, roofAccess: false, stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }], stairHoles: { '1': { x0: -19.725, x1: -18.525, z0: 77.7, z1: 81.4 } }, rooms: [{ walls: [[0.4, 0, 0.4, 0.55, 0.28]], furnish: [{ kind: 'living', x0: 0.4, z0: 0, x1: 1, z1: 1 }, { kind: 'storage', x0: 0, z0: 0, x1: 0.4, z1: 0.55 }, { kind: 'living', x0: 0, z0: 0.55, x1: 0.4, z1: 1 }] }, { walls: [[0.5, 0, 0.5, 1, 0.3]], furnish: [{ kind: 'living', x0: 0, z0: 0, x1: 0.5, z1: 1 }, { kind: 'living', x0: 0.5, z0: 0, x1: 1, z1: 1 }] }] }),
  house('KW14', -19.145, 69.21, 9.2, 6.92, 1), // osm way/960176175
  house('KW15', -19.145, 59.09, 9.2, 7.32, 1), // osm way/644614614
  house('KW16', -19.145, 48.52, 9.2, 7.82, 1), // osm way/960176174
  house('KW17', -19.155, 38.43, 9.3, 6.36, 1), // osm way/644614624 — loop's west arm begins here
  house('KW18', -19.155, 28.92, 9.3, 6.66, 1), // osm way/960176171
  house('KW19', -18.865, 19.105, 8.7, 6.97, 1), // osm way/644614623 — porch centred on the doorBays{1:0} entrance (bay0 sits at along ~ -1.74)
  house('KW20', -18.865, 9.135, 8.7, 6.97, 1), // osm way/960176170
  house('KW21', -19.335, -1.285, 9.6, 7.87, 1), // osm way/644614622 — KW22 (roofAccess finale) excluded from this pattern, so KW21 gets a porch with no paired garage neighbour
  house('KW22', -19.335, -12.155, 9.6, 7.87, 1, { enterable: true, roofAccess: true, stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }], stairHoles: { '1': { x0: -19.925, x1: -18.725, z0: -13.955, z1: -10.355 } }, rooms: [{ walls: [[0.4, 0, 0.4, 0.55, 0.28]], furnish: [{ kind: 'living', x0: 0.4, z0: 0, x1: 1, z1: 1 }, { kind: 'storage', x0: 0, z0: 0, x1: 0.4, z1: 0.55 }, { kind: 'living', x0: 0, z0: 0.55, x1: 0.4, z1: 1 }] }, { walls: [[0.5, 0, 0.5, 1, 0.3]], furnish: [{ kind: 'living', x0: 0, z0: 0, x1: 0.5, z1: 1 }, { kind: 'living', x0: 0.5, z0: 0, x1: 1, z1: 1 }] }] }),

  // --------------------------------------------- KE row (loop's east arm — the only two-sided stretch) --
  house('KE1', 18.825, 34.395, 8.6, 7.76, 3), // osm way/644614620
  house('KE2', 18.825, 23.635, 8.6, 7.76, 3), // osm way/960176173
  house('KE3', 19.405, 13.235, 9.8, 7.04, 3), // osm way/644614621
  house('KE4', 19.405, 3.195, 9.8, 7.04, 3), // osm way/960176172
];

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
