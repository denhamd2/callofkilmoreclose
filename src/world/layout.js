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
 * 2026-08 — THE LAYOUT IS DERIVED FROM THE MAP, NOT FROM OSM. READ THIS FIRST.
 * ==========================================================================
 * Kilmore Close is a STRAIGHT road with perpendicular roads at both ends and
 * THIRTEEN joined semi-detached pairs on each side. That is what the Google
 * Maps reference for 18 Kilmore Cl shows, and it is what this file builds.
 *
 * WHY OSM WAS SET ASIDE. Earlier passes built this table from the 26 building
 * footprints tagged `addr:street=Kilmore Close` (Overpass exports still checked
 * in under `src/world/osm/` for reference). Those footprints do NOT describe a
 * straight road. Searching every street bearing in 0.25 degree steps, the best
 * two-band split of the 26 is 18/8, and the larger band still spreads across
 * 29 m of perpendicular drift — a curve, not a straight row seen off a wrong
 * axis. Whatever those polygons are, they are not the two rows fronting this
 * road, so no amount of re-fitting makes them agree with the map. They are kept
 * on disk as evidence, and used for nothing.
 *
 * The measurements, by contrast, agree with each other and with the map:
 *
 *   16.55 m   one joined pair            -> 13 x 16.55 = 215.15 m of frontage
 *    3.00 m   gap between pairs          -> 12 gaps, where the garages stand
 *             housing run                =  251.15 m per side
 *  304.69 m   measured road length       -> ~26.8 m past the end houses at each
 *                                          end, reaching the cross roads
 *    7.63 m   carriageway, no footpaths  -> STREET.halfWidth 3.815
 *    8.71 m   front garden depth         -> STREET.setback
 *
 * The old OSM-derived street could never reconcile those: it had 209 m of
 * footprints against a 304.69 m measured road.
 *
 * WHAT IS AND IS NOT GROUNDED
 *   Grounded in the map:      straight road, 13 pairs a side, cross roads at
 *                             both ends.
 *   Grounded in measurement:  pair width, pair gap, carriageway, garden depth,
 *                             road length.
 *   Provisional (neither):    plot depth (HOUSE_D, 8.5 m), floors (2), wall
 *                             materials, roof props, and the house archetype
 *                             itself — white pebbledash, two upper windows, one
 *                             lower, glazed sliding porch, single-storey side
 *                             garage. These are set-dressing choices.
 *   NOT AVAILABLE ANYWHERE:   house numbers. Every one of the 32
 *                             `addr:street=Kilmore Close` features in OSM
 *                             carries zero `addr:housenumber`. The numbering
 *                             below is a documented convention — see
 *                             HOUSE_NUMBERS.
 *
 * Coordinates are in LEVEL space; WorldSystem rotates the whole thing so the
 * street runs down the canonical hero-shot camera axis. The street runs along
 * Z, the two rows sit either side of x = 0.
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
  // Road length. The Google Earth measurement is 304.69 m; the housing run is
  // 251.15 m (13 pairs a side), so the carriageway continues ~26.8 m past the
  // end houses at each end to reach the perpendicular cross roads. Was
  // -40..213, which came from the retired OSM-footprint layout.
  zMin: -26.8,
  zMax: 277.9,
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
  // The perpendicular roads closing each end of Kilmore Close, as the Google
  // Maps reference shows them. They sit just outside the housing run (which
  // spans z 0..251.15) and just inside the drawn carriageway, so the street
  // visibly runs INTO a junction at both ends rather than stopping dead.
  //
  // The two `dirt` "rear-access lane" rects that used to be here are gone for
  // good. They covered an open side that no longer exists — both sides now
  // carry 13 pairs each — and they were the densest junk source in the level,
  // because scatterDebris ran a per-alley crate/barrel/pallet/rubble pass over
  // every ALLEYS rect.
  { rect: [-34, -22.5, 34, -15.5], surface: 'gravel' }, // south cross road
  { rect: [-34, 266.5, 34, 273.5], surface: 'gravel' }, // north cross road
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

/* ---------------------------------------------------------------- metrics --
 * Everything below is derived from the four measured references. Change one of
 * these and the whole street regenerates consistently.
 */

/** Measured width of one joined semi-detached PAIR. */
const PAIR_W = 16.55;
/** One dwelling's frontage — half a pair, since the two are joined. */
const HOUSE_W = PAIR_W / 2;
/** Gap between adjacent pairs. This is where the side garages stand. */
const PAIR_GAP = 3.0;
/** Pair-to-pair pitch along the street. */
const PITCH = PAIR_W + PAIR_GAP;
/** Pairs per side, from the Google Maps reference. */
const PAIRS_PER_SIDE = 13;
/** Plot depth, perpendicular to the street. Provisional — not measured. */
const HOUSE_D = 8.5;
/** Total housing run: 12 gaps + 13 pair widths. */
export const HOUSING_RUN = (PAIRS_PER_SIDE - 1) * PITCH + PAIR_W;

/** Frontage bay count, matching buildings.js's own `round(len / 3.05)`. */
const bays = (d) => Math.max(1, Math.round(d / 3.05));

/**
 * The fixed window pattern: EXACTLY two windows upstairs and one downstairs
 * beside the front door, on every house, whatever its frontage.
 *
 * Authored as `bayKinds` so it overrides the per-bay dice roll in buildings.js
 * (which gave each bay a 72%/88% chance of a window and blank wall otherwise,
 * and was why no two frontages matched).
 *
 * `mirror` hands the pattern for the left-hand dwelling of a pair: its door and
 * windows sit at the high-z end of its frontage rather than the low-z end, so
 * the two halves of a semi-D face each other the way a real pair does. Without
 * this every house on the street points the same way and 13 pairs read as one
 * long terrace.
 */
function windows(streetSide, d, mirror) {
  const n = bays(d);
  const ground = [];
  const upper = [];
  for (let b = 0; b < n; b++) {
    // Distance from the door end of the frontage.
    const i = mirror ? n - 1 - b : b;
    ground.push(i === 0 ? 'door' : i === 1 ? 'window' : 'blank');
    upper.push(i < 2 ? 'window' : 'blank');
  }
  return { [streetSide]: [ground, upper] };
}

/** Bay centre offset along the street face, in the wall's local coords. */
const bayCentre = (d, b) => -d / 2 + (b + 0.5) * (d / bays(d));

/**
 * Porch over the front door, garage at the opposite end of the frontage.
 *
 * `mirror` swaps which end each sits at, so within a pair the two garages land
 * on the OUTER ends — standing in the PAIR_GAP between pairs, which is exactly
 * where a side garage goes on this kind of estate — and the two front doors sit
 * side by side at the party wall.
 *
 * Both are clamped inside the wall run so neither overhangs a corner, and the
 * generator asserts they never overlap.
 */
function attachments(d, mirror) {
  const half = d / 2;
  const n = bays(d);
  const doorEnd = mirror ? n - 1 : 0;
  const farEnd = mirror ? 0 : n - 1;
  const porchAt = mirror
    ? Math.min(bayCentre(d, doorEnd), half - 0.95)
    : Math.max(bayCentre(d, doorEnd), -(half - 0.95));
  const garageAt = mirror
    ? Math.max(bayCentre(d, farEnd), -(half - 1.3))
    : Math.min(bayCentre(d, farEnd), half - 1.3);
  return [
    { kind: 'porch', along: +porchAt.toFixed(3), w: 1.9, depth: 1.5, h: 2.5, doorKey: 'window_glass' },
    { kind: 'garage', along: +garageAt.toFixed(3), w: 2.6, depth: 2.5, h: 2.3, doorKey: 'wood_prop' },
  ];
}

/**
 * Stair void for an enterable house, in world coords. Kept as a helper so the
 * interiors stay consistent when a house moves: these used to be typed as
 * absolute literals, which silently desynced from `x`/`z` every time the row
 * was re-spaced.
 */
function stairHole(x, z) {
  return { 1: { x0: x - 0.79, x1: x + 0.41, z0: z - 1.74, z1: z + 1.06 } };
}

/** The two-floor plan shared by the enterable houses. */
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

/** Houses with a playable interior, by house number. */
const ENTERABLE = new Set([14, 18, 27]);

/**
 * BUILDINGS — 52 dwellings: 13 joined semi-detached pairs on each side of a
 * straight road.
 *
 * GENERATED, not hand-typed. The previous table was 28 hand-edited literals
 * derived from OSM footprints, and hand-editing is how the row drifted out of
 * rhythm in the first place. A generated row cannot.
 *
 * Geometry, all from the measured references:
 *   - a pair is 16.55 m wide, so a dwelling frontage `d` is 8.275 m
 *   - pairs sit PAIR_GAP (3.0 m) apart, giving a 19.55 m pitch
 *   - 13 pairs -> a 251.15 m housing run per side
 *   - `x` puts every front face exactly STREET.setback (8.71 m) back from the
 *     kerb line, so plot depth never eats into the garden
 *
 * Sides and numbering — evens one side, odds the other, which is the local
 * convention (neighbouring Beechlawn Close is mapped odds 1-21). Both sides are
 * numbered from the same end, so `n` faces `n + 1` across the road:
 *   near side (streetSide 1, -X): evens  2..52
 *   far  side (streetSide 3, +X): odds   1..51
 */
export const BUILDINGS = (() => {
  const out = [];
  const faceX = STREET.kerb + STREET.setback; // 14.525
  const cx = faceX + HOUSE_D / 2; // 18.775
  for (const side of [1, 3]) {
    const sgn = side === 1 ? -1 : 1;
    const prefix = side === 1 ? 'KW' : 'KE';
    for (let p = 0; p < PAIRS_PER_SIDE; p++) {
      for (let k = 0; k < 2; k++) {
        const i = p * 2 + k;
        const no = (side === 1 ? 2 : 1) + i * 2;
        const z = p * PITCH + k * HOUSE_W + HOUSE_W / 2;
        // The low-z half of each pair is the mirrored one, so its garage lands
        // in the gap below the pair and both front doors meet at the party wall.
        //
        // TWO handings, not one. Attachments are positioned in WORLD z —
        // buildings.js sets `alongZ = 1` for both streetSides — but bay kinds
        // are positioned in PANEL-LOCAL x, and panelMatrix maps local +x to
        // world +Z on side 1 and world -Z on side 3. Using one flag for both
        // put the solid garage box directly over the front-door opening on all
        // 26 far-side houses.
        const attachMirror = k === 0;
        const bayMirror = side === 1 ? k === 0 : k === 1;
        const x = sgn * cx;
        out.push({
          id: `${prefix}${i + 1}`,
          no,
          x,
          z: +z.toFixed(3),
          w: HOUSE_D,
          d: HOUSE_W,
          streetSide: side,
          pair: p,
          mirror: attachMirror,
          ...ARCHETYPE,
          doorBays: { [side]: bayMirror ? bays(HOUSE_W) - 1 : 0 },
          bayKinds: windows(side, HOUSE_W, bayMirror),
          attachments: attachments(HOUSE_W, attachMirror),
          ...(ENTERABLE.has(no) ? interior(x, +z.toFixed(3)) : null),
        });
      }
    }
  }
  return out;
})();

/**
 * HOUSE NUMBERS — a documented convention, NOT an OSM fact.
 *
 * OSM carries zero `addr:housenumber` for Kilmore Close (all 32 matching
 * features), so nothing here can be reconciled against it. The convention above
 * lands the five addresses the encounter needs:
 *
 *   14  near  the McCabes — two doors from 18 (14 -> 16 -> 18)
 *   18  near  David
 *   26  near  Oysters
 *   27  far   Angela — across the road
 *   31  far   Paddy Mason
 *
 * Documented residual: 27 is across the road from 18 but not directly opposite
 * it — 18 is the 9th dwelling on its side, 27 the 14th on the other, so they sit
 * about 47 m apart along the street. Forcing them face to face would mean
 * offsetting one side's numbering to start at 11, which is a fabrication; the
 * offset is recorded here instead.
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
 * The roads at each end of the street.
 *
 * This used to resolve two specific OSM endpoint nodes (291661838 -> Kilmore
 * Avenue, 291661825 -> Beechlawn Avenue) for the curving lane-and-loop shape
 * the previous layout modelled. That shape is gone (see the file header), so
 * the node-level detail no longer describes anything this file builds. What
 * survives is the fact both ends are open junctions, which is what the map
 * shows and what the ALLEYS rects above draw.
 */
export const ROAD_ENDS = {
  south: { end: 'south', z: -19, roads: [{ way: 26595749, name: 'Beechlawn Avenue' }] },
  north: { end: 'north', z: 270, roads: [{ way: 27814285, name: 'Kilmore Avenue' }] },
};

/**
 * Hand-placed set pieces, re-spread across the 251 m housing run.
 *
 * Every position here was previously anchored to the retired OSM-derived house
 * positions and clustered into z 0..180, leaving the top third of the street
 * bare. They are re-laid along the new run. Content is unchanged and stays
 * residential: parked cars at the kerb, clipped hedges, ordinary deciduous
 * trees, kerbside bin stores, one builder's skip outside the house being done
 * up, lamps and overhead cables.
 *
 * Kerbside x is +/-5.7, just inside STREET.kerb (5.815). Anything at |x| > 5.815
 * is standing in a front garden, which runs out to 14.525.
 */
export const SET_PIECES = {
  /** Parked cars along the kerb: [x, z, ry, length] */
  cars: [
    [5.7, 34.2, 0.0, 4.3],
    [-5.7, 47.9, 0.0, 4.0],
    [5.7, 72.6, 0.0, 4.1],
    [-5.7, 96.3, 0.0, 4.3],
    [5.7, 118.8, 0.0, 4.0],
    [-5.7, 141.5, 0.0, 4.2],
    [5.7, 166.1, 0.0, 4.3],
    [-5.7, 189.4, 0.0, 4.0],
    [5.7, 212.7, 0.0, 4.1],
    [-5.7, 236.0, 0.0, 4.2],
  ],
  /** A builder's skip outside the one house mid-renovation: [x, z, ry] */
  skips: [
    [5.7, 104.4, 0.42],
    [-5.7, 198.3, -0.3],
  ],
  /** Street/garden trees: [x, z, scale] */
  trees: [
    [-5.4, 28.7, 1.0],
    [5.5, 61.4, 1.1],
    [-5.5, 88.2, 0.92],
    [5.6, 130.6, 1.05],
    [-5.5, 158.9, 1.0],
    [5.5, 184.3, 0.95],
    [-5.4, 221.7, 1.08],
    [8.5, 110.2, 0.85],
    [-9.0, 176.4, 0.9],
    [8.8, 243.1, 0.88],
  ],
  /** Street lamps: [x, z, ry] — ry points the arm across the street. */
  lamps: [
    [-5.9, 22.4, -Math.PI / 2],
    [5.9, 64.8, Math.PI / 2],
    [-5.9, 107.3, -Math.PI / 2],
    [5.9, 149.7, Math.PI / 2],
    [-5.9, 192.1, -Math.PI / 2],
    [5.9, 234.6, Math.PI / 2],
  ],
  /**
   * Overhead utility cable spans: [x0, y0, z0, x1, y1, z1, sag]
   *
   * Clearances are ESB-plausible minima measured at MID-SPAN (mean of the two
   * endpoint heights, less the sag), which is where a span is actually lowest:
   * spans CROSSING the carriageway need ~5.8 m, spans running ALONG the street
   * over the footpath need ~5.2 m. Every span below clears its own minimum.
   */
  cables: [
    [-6.4, 7.6, 40.2, 6.4, 7.0, 46.1, 1.1], // crossing: 6.20 mid
    [-6.4, 8.4, 96.5, 6.4, 7.9, 100.1, 1.4], // crossing: 6.75 mid
    [-6.4, 7.0, 152.8, 6.4, 7.4, 156.4, 1.0], // crossing: 6.20 mid
    [-6.4, 7.6, 209.1, 6.4, 7.2, 213.9, 1.2], // crossing: 6.20 mid
    [-6.4, 5.9, 60.3, -6.4, 6.1, 73.4, 0.6], // along street: 5.40 mid
    [6.4, 6.1, 178.2, 6.4, 5.9, 192.5, 0.7], // along street: 5.30 mid
  ],
  /**
   * Washing lines: REMOVED, deliberately and permanently. These sat at
   * x = +/-6.35, inside the FRONT garden facing the street. Nobody hangs
   * washing there; the correct home is the rear garden, which this map does not
   * build. The array is kept, empty, because overheadLines() iterates it and an
   * empty run is the cheapest correct way to say "no washing lines".
   */
  laundry: [],
  /** Doorstep planters / window boxes: [x, y, z, ry, w] */
  doorstepPlanters: [
    [-6.45, 0.02, 51.3, Math.PI / 2, 1.5],
    [-6.45, 0.02, 121.4, Math.PI / 2, 1.2],
    [6.45, 0.02, 90.1, -Math.PI / 2, 1.6],
    [6.45, 0.02, 168.7, -Math.PI / 2, 1.3],
    [-6.45, 0.02, 207.6, Math.PI / 2, 1.4],
  ],
  /** Kerbside bin stores: [x, z, radius, count] */
  binStores: [
    [-4.2, 43.1, 2.4, 34],
    [5.0, 82.5, 2.8, 40],
    [-1.5, 136.9, 2.0, 26],
    [7.6, 174.2, 2.2, 28],
    [-5.0, 228.4, 1.6, 18],
  ],
};
