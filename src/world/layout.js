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
 *  - Both ends are open, per the real connecting-road continuity above —
 *    see ROAD_ENDS below for the resolved OSM roads at each end. (An earlier
 *    pass closed the loop end with a fictional GATE arch and the lane end
 *    with a barricade; both were removed once this connectivity was pinned
 *    down to specific roads.)
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
  { rect: [-30, -36, 30, -30], surface: 'gravel' }, // provisional far cross street south end, reads as Beechlawn Avenue (ROAD_ENDS.south) crossing beyond the loop
  { rect: [-30, 203, 30, 209], surface: 'gravel' }, // provisional far cross street north end, reads as Kilmore Avenue (ROAD_ENDS.north) crossing beyond the lane — mirrors the south entry's offset from its street edge (zMin+4..zMin+10), so both real OSM road connections read the same way
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
/**
 * Painted-band scale-out (houses agent, approved sample KW19/KW20 -> wider
 * street): every 2-storey house with no roofAccess/setback/ruin and a single
 * main wallKey gets a bandKey per this fixed pairing rule, carrying forward
 * the judge's contrast note (plaster_wine read too flat against plaster_white
 * in the sample) —
 *   plaster_white  -> plaster_coral (kept off plaster_wine specifically)
 *   plaster_cream  -> plaster_wine
 *   plaster_sand   -> plaster_wine
 * KW22 is excluded (roofAccess, the one house whose roof is playable ground).
 * BG* background infill is excluded — it's loose distant massing, not part of
 * the individually-read house frontage set this pattern targets.
 */
export const BUILDINGS = [
  // --------------------------------------------- KW row (single lane + loop west arm) --
  { id: 'KW1', x: -18.585, z: 197.35, w: 8.1, d: 9.73, floors: 2, wallKey: 'plaster_sand', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'porch', along: -3.615, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614598
  { id: 'KW2', x: -21.245, z: 188.42, w: 13.4, d: 7.53, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'garage', along: 2.165, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176181 — irregular/larger footprint, kept as mapped
  { id: 'KW3', x: -21.505, z: 159.25, w: 14.0, d: 10.1, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 1, damage: 0.1, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'porch', along: -3.8, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614600 — irregular/larger footprint (likely a mapped semi-D pair), kept as mapped
  { id: 'KW4', x: -19.035, z: 151.2, w: 9.0, d: 5.4, floors: 2, wallKey: 'plaster_white', bandKey: 'plaster_coral', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1, attachments: [{ kind: 'garage', along: 1.1, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176180
  {
    id: 'KW5',
    x: -18.835,
    z: 140.34,
    w: 8.6,
    d: 6.63,
    floors: 2,
    wallKey: 'plaster_sand',
    bandKey: 'plaster_wine',
    streetSide: 1,
    damage: 0.05,
    balconies: 0,
    doorBays: { 1: 0 },
    enterable: true,
    roofAccess: false,
    roofProps: 2,
    attachments: [{ kind: 'porch', along: -2.065, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }],
    stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }],
    stairHoles: { 1: { x0: -19.625, x1: -18.425, z0: 138.6, z1: 141.4 } },
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
  { id: 'KW6', x: -18.965, z: 134.31, w: 8.9, d: 4.83, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1, attachments: [{ kind: 'garage', along: 0.815, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176179
  { id: 'KW7', x: -20.795, z: 123.95, w: 12.5, d: 6.84, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 1, damage: 0.1, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'porch', along: -2.17, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614616 — irregular footprint, kept as mapped
  { id: 'KW8', x: -19.105, z: 117.11, w: 9.2, d: 6.24, floors: 2, wallKey: 'plaster_white', bandKey: 'plaster_coral', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'garage', along: 1.52, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176178
  { id: 'KW9', x: -19.305, z: 104.9, w: 9.6, d: 6.52, floors: 2, wallKey: 'plaster_sand', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'porch', along: -2.01, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614617
  { id: 'KW10', x: -19.305, z: 98.08, w: 9.6, d: 6.52, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'garage', along: 1.66, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176177
  { id: 'KW11', x: -18.975, z: 86.19, w: 8.9, d: 6.32, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1, attachments: [{ kind: 'porch', along: -1.91, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614618
  { id: 'KW12', x: -18.975, z: 79.57, w: 8.9, d: 6.32, floors: 2, wallKey: 'plaster_white', bandKey: 'plaster_coral', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1, attachments: [{ kind: 'garage', along: 1.56, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176176
  {
    id: 'KW13',
    x: -19.145,
    z: 66.83,
    w: 9.2,
    d: 7.72,
    floors: 2,
    wallKey: 'plaster_sand',
    bandKey: 'plaster_wine',
    streetSide: 1,
    damage: 0.05,
    balconies: 0,
    doorBays: { 1: 0 },
    enterable: true,
    roofAccess: false,
    roofProps: 2,
    attachments: [{ kind: 'porch', along: -2.61, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }],
    stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }],
    stairHoles: { 1: { x0: -19.725, x1: -18.525, z0: 65.0, z1: 68.7 } },
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
  { id: 'KW14', x: -19.145, z: 58.81, w: 9.2, d: 6.92, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'garage', along: 1.86, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176175
  { id: 'KW15', x: -19.145, z: 50.8, w: 9.2, d: 7.32, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1, attachments: [{ kind: 'porch', along: -2.41, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614614
  { id: 'KW16', x: -19.145, z: 42.78, w: 9.2, d: 7.82, floors: 2, wallKey: 'plaster_white', bandKey: 'plaster_coral', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'garage', along: 2.31, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176174
  { id: 'KW17', x: -19.155, z: 34.62, w: 9.3, d: 6.36, floors: 2, wallKey: 'plaster_sand', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1, attachments: [{ kind: 'porch', along: -1.93, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614624 — loop's west arm begins here
  { id: 'KW18', x: -19.155, z: 27.81, w: 9.3, d: 6.66, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'garage', along: 1.73, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176171
  // SAMPLE PASS (houses agent) — mirrored-footprint pair used as the
  // representative paired frontage against screenshots 1 & 4, visible via the
  // `housesSample` capture shot (src/dev/shots.js). bandKey paints a ground-
  // floor spandrel band (see buildings.js buildFacade) so each half of the
  // pair reads as its own two-tone paint job instead of one flat wallKey.
  // Iteration 2: swapped KW20's wallKey/bandKey from plaster_sand/plaster_pink
  // (too close in value to each other and to KW19's plaster_white) to
  // plaster_butter/plaster_coral for real separation between the two houses.
  // PORCH/GARAGE SAMPLE PASS (porches agent) — same mirrored pair used for the
  // two-tone band sample, now carrying the paired attachment cluster from the
  // Street View references: a small glazed porch at KW19's boundary with
  // KW20, a flat-roofed garage at KW20's matching boundary — the two sit
  // ~0.3m apart, echoing the party-wall gap already trimmed in the OSM data.
  { id: 'KW19', x: -18.865, z: 15.95, w: 8.7, d: 6.97, floors: 2, wallKey: 'plaster_white', bandKey: 'plaster_wine', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 1, attachments: [{ kind: 'porch', along: -1.74, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614623 — porch centred on the doorBays{1:0} entrance (bay0 sits at along ~ -1.74)
  { id: 'KW20', x: -18.865, z: 8.68, w: 8.7, d: 6.97, floors: 2, wallKey: 'plaster_butter', bandKey: 'plaster_coral', streetSide: 1, damage: 0.05, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'garage', along: 1.9, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176170
  { id: 'KW21', x: -19.335, z: -3.83, w: 9.6, d: 7.87, floors: 2, wallKey: 'plaster_sand', bandKey: 'plaster_wine', streetSide: 1, damage: 0.1, balconies: 0, doorBays: { 1: 0 }, roofProps: 2, attachments: [{ kind: 'porch', along: -2.685, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614622 — KW22 (roofAccess finale) excluded from this pattern, so KW21 gets a porch with no paired garage neighbour
  {
    id: 'KW22',
    x: -19.335,
    z: -12.0,
    w: 9.6,
    d: 7.87,
    floors: 2,
    wallKey: 'plaster_cream',
    streetSide: 1,
    damage: 0.15,
    balconies: 0,
    doorBays: { 1: 0 },
    enterable: true,
    roofAccess: true,
    roofProps: 2,
    stairFlights: [{ floor: 0, x: 0.18, z: 0.3, ry: 0, w: 0.9, railing: 'right' }],
    stairHoles: { 1: { x0: -19.925, x1: -18.725, z0: -13.8, z1: -10.2 } },
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
  { id: 'KE1', x: 18.825, z: 32.24, w: 8.6, d: 7.76, floors: 2, wallKey: 'plaster_sand', bandKey: 'plaster_wine', streetSide: 3, damage: 0.05, balconies: 0, doorBays: { 3: 0 }, roofProps: 2, attachments: [{ kind: 'porch', along: -2.63, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614620
  { id: 'KE2', x: 18.825, z: 24.18, w: 8.6, d: 7.76, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 3, damage: 0.05, balconies: 0, doorBays: { 3: 0 }, roofProps: 1, attachments: [{ kind: 'garage', along: 2.28, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176173
  { id: 'KE3', x: 19.405, z: 12.69, w: 9.8, d: 7.04, floors: 2, wallKey: 'plaster_cream', bandKey: 'plaster_wine', streetSide: 3, damage: 0.05, balconies: 0, doorBays: { 3: 0 }, roofProps: 2, attachments: [{ kind: 'porch', along: -2.27, w: 1.9, depth: 1.5, h: 2.5, wallKey: 'plaster_wine' }] }, // osm way/644614621
  { id: 'KE4', x: 19.405, z: 5.35, w: 9.8, d: 7.04, floors: 2, wallKey: 'plaster_white', bandKey: 'plaster_coral', streetSide: 3, damage: 0.1, balconies: 0, doorBays: { 3: 0 }, roofProps: 1, attachments: [{ kind: 'garage', along: 1.92, w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' }] }, // osm way/960176172

  // --------------------------------------------- background / infill (fully provisional) --
  /**
   * The KW row is single-sided for its whole ~154 m lane stretch (an OSM
   * fact), so the east side of the lane is genuinely open in reality —
   * almost certainly the rear boundaries of Beechlawn Avenue/Close, per the
   * decision to keep neighbouring streets as loose background only. These
   * are generic distant masses, not individually OSM-placed.
   */
  { id: 'BGE1', x: 26, z: 172, w: 18, d: 22, floors: 2, wallKey: 'plaster_cream', streetSide: 3, damage: 0.1, skipSides: [3], roofProps: 2 },
  { id: 'BGE2', x: 27, z: 108, w: 18, d: 24, floors: 2, wallKey: 'plaster_cream', streetSide: 3, damage: 0.1, skipSides: [3], roofProps: 2 },
  { id: 'BGE3', x: 26, z: 52, w: 16, d: 18, floors: 2, wallKey: 'plaster_sand', streetSide: 3, damage: 0.1, skipSides: [3], roofProps: 2 },
  // Far skyline beyond the lane's open (north) end, toward Kilmore Avenue — "the street continues off-map", not a dead end.
  { id: 'BGN1', x: -18, z: 222, w: 20, d: 14, floors: 2, wallKey: 'plaster_cream', streetSide: 0, damage: 0.1, roofProps: 2 },
  { id: 'BGN2', x: 16, z: 226, w: 22, d: 16, floors: 2, wallKey: 'plaster_cream', streetSide: 0, damage: 0.1, roofProps: 2 },
  // Far skyline beyond the loop's open (south) end, toward Beechlawn Avenue — mirrors BGN1/BGN2, replaces the removed GATE backdrop (BGS1).
  { id: 'BGS1', x: -18, z: -52, w: 20, d: 14, floors: 2, wallKey: 'plaster_cream', streetSide: 2, damage: 0.1, roofProps: 2 },
  { id: 'BGS2', x: 16, z: -56, w: 22, d: 16, floors: 2, wallKey: 'plaster_cream', streetSide: 2, damage: 0.1, roofProps: 2 },
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
    [5.7, 118.95, 0.0, 4.3],
    [-5.7, 108.97, 0.0, 4.0],
    [5.7, 126.31, 0.0, 4.3],
    [-5.7, 113.25, 0.0, 4.1],
    [5.7, 109.93, 0.0, 4.0],
    [-5.7, 82.38, 0.0, 4.2],
    [5.7, 69.31, 0.0, 4.3],
    [-5.7, 56.25, 0.0, 4.0],
  ],
  /** A builder's skip outside the one house mid-renovation: [x, z, ry] */
  skips: [
    [5.7, 104.94, 0.42],
    [-5.7, 36.06, -0.3],
  ],
  /** Street/garden trees: [x, z, scale] */
  trees: [
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
  /** Overhead utility cable spans: [x0, y0, z0, x1, y1, z1, sag] */
  cables: [
    [-6.4, 7.2, 127.5, 6.4, 6.6, 133.44, 1.1],
    [-6.4, 8.4, 99.0, 6.4, 7.9, 102.56, 1.4],
    [-6.4, 6.2, 65.75, 6.4, 6.6, 69.31, 1.0],
    [-6.4, 7.6, 32.5, 6.4, 7.2, 37.25, 1.2],
    [-6.4, 5.4, 148.88, -6.4, 5.6, 161.94, 0.6],
    [6.4, 5.6, 108.5, 6.4, 5.4, 122.75, 0.7],
  ],
  /** Back-garden washing lines with hanging laundry: [x0, y0, z0, x1, y1, z1] */
  laundry: [
    [6.35, 3.6, 125.12, 6.35, 3.75, 137.47],
    [-6.35, 3.7, 106.12, -6.35, 3.6, 116.57],
    [-6.35, 6.6, 55.06, -6.35, 6.4, 66.94],
    [6.35, 6.5, 89.5, 6.35, 6.7, 101.38],
    [-6.35, 3.65, 39.62, -6.35, 3.8, 51.5],
    [6.4, 3.7, 153.62, 6.4, 3.6, 164.31],
  ],
  /** Doorstep planters / window boxes: [x, y, z, ry, w] */
  doorstepPlanters: [
    [-6.45, 0.02, 123.94, Math.PI / 2, 1.5],
    [-6.45, 0.02, 114.44, Math.PI / 2, 1.2],
    [6.45, 0.02, 118.0, -Math.PI / 2, 1.6],
    [6.45, 0.02, 83.56, -Math.PI / 2, 1.3],
    [-6.45, 0.02, 65.75, Math.PI / 2, 1.4],
  ],
  /** Kerbside bin stores: [x, z, radius, count] */
  binStores: [
    [-4.2, 55.06, 2.4, 34],
    [5.0, 69.31, 2.8, 40],
    [-1.5, 8.75, 2.0, 26],
    [7.6, 31.31, 2.2, 28],
    [-5.0, 165.5, 1.6, 18],
  ],
};
