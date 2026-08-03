import * as THREE from 'three';
import { Rng } from '../core/rng.js';
import {
  facadeWall,
  windowUnit,
  windowState,
  doorUnit,
  shopfront,
  balcony,
  parapet,
  stairRun,
  awning,
  drainpipe,
  spallPatch,
  rubbleMound,
  BOX,
  BOX_SOFT,
  IDENT,
  LL,
  slab,
  worldOf,
} from './kit.js';
import { chamferBox, clothGeometry, fbm3, patchGeometry, polyPrism, runoffStreak } from './util.js';
import { furnishRoom } from './interiors.js';

/**
 * WORLD — building assembly.
 *
 * A building is a footprint, a floor count and a per-side facade programme. The
 * generator walks each side in ~3 m bays and picks a kit element per bay per
 * floor (shopfront, door, window, arched window, balcony door, blank), then
 * dresses it: plinth, string courses, sills, lintels, shutters, drainpipes,
 * spalled render, bullet damage, roof parapet and roof clutter anchors.
 *
 * Sides are indexed 0:-Z 1:+X 2:+Z 3:-X. Every side gets a panel matrix whose
 * local +Z points INTO the building, so kit elements can work in a single
 * consistent panel space (see kit.js).
 */

const SIDE = [
  { ry: 0, n: [0, 0, -1] },
  { ry: -Math.PI / 2, n: [1, 0, 0] },
  { ry: Math.PI, n: [0, 0, 1] },
  { ry: Math.PI / 2, n: [-1, 0, 0] },
];

const _pm = new THREE.Matrix4();
const _e = new THREE.Euler(0, 0, 0, 'YXZ');
const _q = new THREE.Quaternion();
const _p = new THREE.Vector3();
const _s = new THREE.Vector3(1, 1, 1);

function panelMatrix(spec, side, y) {
  const { x, z, w, d } = spec;
  const s = SIDE[side];
  let px = x;
  let pz = z;
  if (side === 0) pz = z - d / 2;
  else if (side === 2) pz = z + d / 2;
  else if (side === 1) px = x + w / 2;
  else px = x - w / 2;
  _e.set(0, s.ry, 0);
  _q.setFromEuler(_e);
  _p.set(px, y, pz);
  _s.set(1, 1, 1);
  return _pm.compose(_p, _q, _s);
}

/** Repair-render key per wall colour: close in value, different in mix. */
const PATCH_KEY = {
  plaster_cream: 'plaster_sand',
  plaster_sand: 'plaster_cream',
  // A white patch on a blue-grey wall is nearly a stop brighter than the wall and
  // reads as a sheet of paper taped to the building — a cement repair does not.
  plaster_blue: 'concrete',
  plaster_pink: 'plaster_sand',
  plaster_white: 'concrete',
};

const sideLen = (spec, side) => (side === 0 || side === 2 ? spec.w : spec.d);

/**
 * Per-floor footprint. `spec.setback = { from, depth, side? }` pulls every floor
 * at or above `from` back from one face, leaving a roof terrace over the floor
 * below — the standard Mediterranean/Levantine form, and the thing that lets
 * afternoon sun down onto the street instead of walling it into shade.
 */
function floorSpec(spec, f) {
  const sb = spec.setback;
  if (!sb || f < sb.from) return spec;
  const d = sb.depth;
  const side = sb.side ?? spec.streetSide ?? 0;
  const o = { ...spec };
  if (side === 1) {
    o.x = spec.x - d / 2;
    o.w = spec.w - d;
  } else if (side === 3) {
    o.x = spec.x + d / 2;
    o.w = spec.w - d;
  } else if (side === 0) {
    o.z = spec.z + d / 2;
    o.d = spec.d - d;
  } else {
    o.z = spec.z - d / 2;
    o.d = spec.d - d;
  }
  return o;
}

/** The strip of roof left exposed by a setback: slab, coping and a parapet. */
function terrace(A, rng, spec, y, t) {
  const sb = spec.setback;
  const side = sb.side ?? spec.streetSide ?? 0;
  const d = sb.depth;
  const horiz = side === 1 || side === 3;
  const sign = side === 1 || side === 2 ? 1 : -1;
  const cx = horiz ? spec.x + sign * (spec.w / 2 - d / 2) : spec.x;
  const cz = horiz ? spec.z : spec.z + sign * (spec.d / 2 - d / 2);
  const sx = horiz ? d : spec.w;
  const sz = horiz ? spec.d : d;
  A.add('roof_screed', BOX(A), LL(IDENT, cx, y - 0.13, cz, 0, sx + 0.08, 0.26, sz + 0.08), {
    masks: [0.45, 0.3, 0.15],
  });
  A.box('concrete', cx, y - 0.13, cz, sx + 0.08, 0.26, sz + 0.08);
  // parapet along the exposed edge, low enough to fight over from the terrace
  const ph = 0.92;
  const px = horiz ? spec.x + sign * (spec.w / 2 - 0.11) : spec.x;
  const pz = horiz ? spec.z : spec.z + sign * (spec.d / 2 - 0.11);
  A.add(spec.wallKey ?? 'plaster_cream', BOX(A), LL(IDENT, px, y + ph / 2, pz, 0, horiz ? 0.22 : spec.w + 0.1, ph, horiz ? spec.d + 0.1 : 0.22), {
    masks: [0.5, 0.5, 0.2],
  });
  A.add('concrete', BOX_SOFT(A), LL(IDENT, px, y + ph + 0.05, pz, 0, horiz ? 0.32 : spec.w + 0.2, 0.1, horiz ? spec.d + 0.2 : 0.32), {
    masks: [0.8, 0.35, 0.1],
  });
  A.box('concrete', px, y + ph / 2, pz, horiz ? 0.26 : spec.w + 0.1, ph + 0.1, horiz ? spec.d + 0.1 : 0.26);
  // the returns at each end of the terrace
  for (const s of [-1, 1]) {
    const ex = horiz ? cx : spec.x + s * (spec.w / 2 - 0.11);
    const ez = horiz ? spec.z + s * (spec.d / 2 - 0.11) : cz;
    A.add(spec.wallKey ?? 'plaster_cream', BOX(A), LL(IDENT, ex, y + ph / 2, ez, 0, horiz ? d : 0.22, ph, horiz ? 0.22 : d), {
      masks: [0.5, 0.5, 0.2],
    });
    A.box('concrete', ex, y + ph / 2, ez, horiz ? d : 0.26, ph, horiz ? 0.26 : d);
  }
  return { cx, cz, sx, sz, y };
}

/**
 * @returns {object} anchors for the dressing pass:
 *   { facades:[{side, x, y, ry, wx, wz, nx, nz}], roof:{...}, doors:[], balconies:[] }
 */
export function buildBuilding(A, rng, spec) {
  const t = spec.t ?? 0.34;
  const floors = spec.floors ?? 3;
  // Storey heights for a 1950s Dublin Corporation two-storey semi: roughly 2.4 m
  // floor-to-ceiling plus joists. Were 3.45/3.05, which put the eaves at 6.56 m
  // and the ridge at 10.05 m — three-storey proportions on a two-storey house,
  // and the reason the street read as a row of blocks rather than semi-Ds.
  // These now give eaves ~5.35 m and a ridge ~9.0 m.
  //
  // Anything keyed off these adapts on its own: stairs derive from the
  // floor-to-floor climb (`steps = round(climb / 0.19)`), and interior ceilings
  // are `groundH - 0.13`. Window heights do NOT adapt and were retuned to match
  // — see the `window` bay case below.
  const groundH = spec.groundH ?? 2.7;
  const upperH = spec.upperH ?? 2.6;
  const wallKey = spec.wallKey ?? 'plaster_cream';
  const streetSide = spec.streetSide ?? 0;
  const info = {
    spec,
    floorY: [],
    doors: [],
    balconies: [],
    roofY: 0,
    windows: [],
    awnings: [],
    top: 0,
  };

  // ---------------------------------------------------------------- plinth --
  // A base course everywhere: catches the ground grime band and stops the walls
  // reading as slabs dropped on a plane.
  const plinthH = spec.plinthH ?? 0.42;
  A.add(
    spec.plinthKey ?? 'concrete',
    BOX(A),
    LL(IDENT, spec.x, plinthH / 2, spec.z, 0, spec.w + 0.14, plinthH, spec.d + 0.14),
    { masks: [0.55, 0.75, 0.45] }
  );
  A.box('concrete', spec.x, plinthH / 2, spec.z, spec.w + 0.14, plinthH, spec.d + 0.14);

  let y = 0;
  info.terraces = [];
  for (let f = 0; f < floors; f++) {
    const h = f === 0 ? groundH : upperH;
    const fs = floorSpec(spec, f);
    info.floorY.push(y);
    for (let side = 0; side < 4; side++) {
      if (spec.skipSides?.includes(side)) continue;
      buildFacade(A, rng, fs, info, { side, f, y, h, t, wallKey, streetSide, floors });
    }
    // ---- floor / ceiling slab of the NEXT level ----
    y += h;
    if (f < floors - 1) {
      interiorSlab(A, rng, floorSpec(spec, f + 1), y, t, f + 1);
      // the setback happens on top of this floor: dress the exposed strip
      if (spec.setback && f + 1 === spec.setback.from) {
        info.terraces.push(terrace(A, rng, spec, y, t));
      }
    }
  }
  info.roofY = y;
  info.top = y;

  // ------------------------------------------------------------------ roof --
  const ts = floorSpec(spec, floors - 1);
  interiorSlab(A, rng, ts, y, t, floors, true);
  // Roofs are playable ground ONLY where `roofAccess` opens a stair onto them
  // (one house on this street). Every other house keeps its flat slab as an
  // invisible ceiling and gets a real pitched, tiled roof over it — the flat
  // parapet-topped look is a fine finale vantage point but reads as a flat
  // industrial rooftop everywhere else, next to nothing like the pitched
  // suburban roofs in the Street View references.
  if (spec.roofAccess) {
    if (spec.parapet !== false) {
      parapet(A, spec.parapetKey ?? wallKey, ts.x, ts.z, ts.w + 0.1, ts.d + 0.1, y, rng, {
        h: spec.parapetH ?? 0.78,
        t: 0.22,
      });
    }
  } else if (!spec.setback && !spec.ruin) {
    // Setback/ruin buildings keep the old flat-roof treatment: a pitched cap
    // over a roof terrace or a collapsed top floor doesn't make sense, and
    // neither shape is used anywhere on Kilmore Close today.
    pitchedRoof(A, rng, ts, wallKey, y);
  } else if (spec.parapet !== false) {
    parapet(A, spec.parapetKey ?? wallKey, ts.x, ts.z, ts.w + 0.1, ts.d + 0.1, y, rng, {
      h: spec.parapetH ?? 0.78,
      t: 0.22,
    });
  }
  info.roofSpec = ts;
  info.pitchedRoof = !spec.roofAccess && !spec.setback && !spec.ruin;

  // ----------------------------------------------------------- interiors ---
  if (spec.enterable) {
    buildInterior(A, rng, spec, info, t, groundH, upperH, floors);
  } else {
    // Non-enterable: a dark core so windows read as depth, not as a hole into
    // a lit empty shell.
    // Sized off the SMALLEST floor plate so a setback never leaves the core
    // poking out through an upper wall.
    const top = floorSpec(spec, floors - 1);
    const inset = 2.0;
    const cw = Math.max(1.0, top.w - inset * 2);
    const cd = Math.max(1.0, top.d - inset * 2);
    // Stop the core short of the roof slab: coplanar faces z-fight, and a dark
    // core showing through the roof turns every rooftop into a grey blotch.
    const coreH = Math.max(0.5, y - 0.45);
    // `interior_shell`, not white plaster: seen through a doorway or a blown-out
    // hole a bright core reads as a sheet of paper taped behind the opening.
    A.add(
      'interior_shell',
      BOX(A),
      LL(IDENT, top.x, coreH / 2, top.z, 0, cw, coreH, cd),
      { masks: [0.1, 0.95, 0.9] }
    );
    A.box('concrete', top.x, coreH / 2, top.z, cw, coreH, cd);
    for (let f = 0; f <= floors; f++) {
      const fs = floorSpec(spec, Math.min(f, floors - 1));
      const fy = f === 0 ? 0.1 : info.floorY[f] ?? y;
      A.add(
        'floor_concrete',
        BOX(A),
        LL(IDENT, fs.x, fy - 0.06, fs.z, 0, fs.w - t * 2, 0.16, fs.d - t * 2),
        { masks: [0.2, 0.8, 0.6] }
      );
      if (f === 0) A.box('concrete', fs.x, fy - 0.06, fs.z, fs.w, 0.2, fs.d);
    }
  }

  // ------------------------------------------------------------- drainpipe --
  // A downpipe has to die into the wall it is clipped to. On a setback face the
  // wall STOPS at the terrace, so a pipe run to the main roof height carries on
  // three metres into open sky and reads as a floating mast — which is exactly
  // what it was doing. Clamp the top to the parapet of whatever surface is
  // actually above the pipe.
  const dpSide = streetSide;
  const pmD = panelMatrix(spec, dpSide, 0);
  const len = sideLen(spec, dpSide);
  const sbSide = spec.setback ? spec.setback.side ?? streetSide : -1;
  const dpTop =
    sbSide === dpSide
      ? (info.floorY[spec.setback.from] ?? info.roofY) + 0.55
      : info.roofY + 0.4;
  drainpipe(A, pmD.clone(), rng.range(-len / 2 + 0.4, -len / 2 + 1.0), dpTop, dpTop, rng);
  if (rng.float() < 0.6) {
    drainpipe(A, pmD.clone(), rng.range(len / 2 - 1.0, len / 2 - 0.4), dpTop, dpTop, rng);
  }

  // ---------------------------------------------------------- frontage add-ons --
  buildAttachments(A, rng, spec, wallKey, streetSide);

  return info;
}

// ============================================================ attachments ====
/**
 * One-storey porch/garage additions tucked against the street face, opt-in
 * via `spec.attachments`. Every paired semi-D in the Street View references
 * has one of these at the shared boundary with its neighbour — a garage on
 * one half, a porch on the other — which is what actually breaks the
 * repeated two-storey block up before the eye reaches the roofline; the
 * pitched roof and wall banding above are untouched by this function.
 *
 * Positioned directly in level space (no panel matrix): `along` is an offset
 * along the wall's own run from the building's centreline (world x for a
 * north/south-facing wall, world z for an east/west-facing one — whichever
 * axis `streetSide` doesn't point down), `depth` is how far the box
 * protrudes outward from the wall face along `streetSide`'s normal. Kept
 * shallow (<=2.6m) to stay inside the fixed 3.0m front-garden gap
 * (layout.js) rather than reaching real driveway depth.
 */
function buildAttachments(A, rng, spec, wallKey, streetSide) {
  const list = spec.attachments;
  if (!list || !list.length) return;
  const n = SIDE[streetSide].n;
  const alongX = streetSide === 0 || streetSide === 2 ? 1 : 0;
  const alongZ = 1 - alongX;
  const faceX = spec.x + n[0] * (spec.w / 2);
  const faceZ = spec.z + n[2] * (spec.d / 2);

  for (const at of list) {
    const isGarage = at.kind === 'garage';
    const h = at.h ?? (isGarage ? 2.3 : 2.5);
    const depth = Math.min(at.depth ?? (isGarage ? 2.6 : 1.3), 2.6);
    const w = at.w ?? (isGarage ? 2.6 : 1.6);
    const along = at.along ?? 0;
    const cx = faceX + alongX * along + n[0] * (depth / 2);
    const cz = faceZ + alongZ * along + n[2] * (depth / 2);
    const boxW = alongX ? w : depth;
    const boxD = alongX ? depth : w;
    const key = at.wallKey ?? wallKey;

    A.add(key, BOX(A), LL(IDENT, cx, h / 2, cz, 0, boxW, h, boxD), { masks: [0.5, 0.5, 0.2] });
    A.box('concrete', cx, h / 2, cz, boxW, h, boxD);
    // flat capped roof, thin fascia overhang
    const capW = alongX ? w + 0.16 : depth + 0.16;
    const capD = alongX ? depth + 0.16 : w + 0.16;
    A.add('concrete', BOX_SOFT(A), LL(IDENT, cx, h + 0.05, cz, 0, capW, 0.1, capD), {
      masks: [0.6, 0.4, 0.15],
    });

    // door/garage leaf set into the outward face
    const leafW = isGarage ? w * 0.8 : 0.95;
    const leafH = isGarage ? h * 0.78 : 2.05;
    const leafKey = at.doorKey ?? 'wood_dark';
    const faceOff = depth / 2 + 0.03;
    const lx = cx + n[0] * faceOff;
    const lz = cz + n[2] * faceOff;
    const leafX = alongX ? leafW : 0.06;
    const leafZ = alongX ? 0.06 : leafW;
    A.add(leafKey, BOX(A), LL(IDENT, lx, leafH / 2 + 0.03, lz, 0, leafX, leafH, leafZ), {
      masks: [0.3, 0.3, 0.1],
    });

    // ---- a porch is GLAZED, a garage is not ------------------------------
    // The Street View reference calls for a small glazed porch, and this was
    // building it as a solid box with one opaque leaf — a windowless cupboard
    // bolted to the front of the house. Garages stay solid, which is correct.
    //
    // Glazing goes either side of the door leaf on the outward face, plus a
    // return panel down the exposed flank, which is what makes a porch read as
    // an add-on rather than as part of the wall.
    if (!isGarage) {
      const glazeH = leafH - 0.45;
      const glazeY = 0.42 + glazeH / 2;
      const sideW = Math.max(0.28, (w - leafW) / 2 - 0.09);
      // front glazing, one panel each side of the door
      for (const s of [-1, 1]) {
        const off = (leafW / 2 + 0.06 + sideW / 2) * s;
        A.add(
          'window_glass',
          BOX(A),
          LL(
            IDENT,
            lx + (alongX ? off : 0),
            glazeY,
            lz + (alongX ? 0 : off),
            0,
            alongX ? sideW : 0.05,
            glazeH,
            alongX ? 0.05 : sideW
          ),
          { masks: [0.15, 0.2, 0.05] }
        );
      }
      // return panel down the flank facing away from the party wall
      const flank = at.along >= 0 ? 1 : -1;
      const retOff = (w / 2 - 0.05) * flank;
      A.add(
        'window_glass',
        BOX(A),
        LL(
          IDENT,
          cx + (alongX ? retOff : n[0] * 0.02),
          glazeY,
          cz + (alongX ? n[2] * 0.02 : retOff),
          0,
          alongX ? 0.05 : depth - 0.3,
          glazeH,
          alongX ? depth - 0.3 : 0.05
        ),
        { masks: [0.15, 0.2, 0.05] }
      );
    }
  }
}

// =================================================================== roof ====
/**
 * A pitched, tiled gable roof over the top floor's flat slab (which stays in
 * place underneath as an invisible ceiling — no other code path needs to know
 * the roof isn't walkable, which is what makes this a roof-only change).
 *
 * Ridge runs along Z (`ts.d`, the frontage-width axis, since Kilmore Close's
 * buildings are wired at right angles to the street) with two tile slopes
 * pitched down along X to eaves overhanging the walls, gable-end infill
 * closing the two triangular ends in the facade's own wall colour, a ridge
 * cap, fascia boards under both eaves, and one chimney stack — the single
 * most identifying silhouette feature in every Street View reference, not
 * "roof clutter" in the industrial sense the earlier dressing pass removed.
 */
function pitchedRoof(A, rng, ts, wallKey, y) {
  const w = ts.w;
  const d = ts.d;
  const PITCH = 0.64; // ~37 degrees — a typical concrete-tile Irish suburban pitch
  const overhangX = 0.34; // eave overhang beyond the wall face
  const overhangZ = 0.16; // verge overhang beyond the gable wall
  const run = w / 2 + overhangX;
  // A few footprints on this street are wide (merged semi-D pairs, background
  // infill blocks up to 22 m). Holding one fixed pitch angle across all of
  // them would put a church-spire-height ridge over the widest ones, so the
  // rise is capped and the pitch shallows out instead — real wide roofs do
  // exactly this (or break into multiple ridges), never just get taller.
  // Cap was 3.6, which held every house at or above 30 degrees only while the
  // footprints stayed narrow. The three merged-pair footprints (KW2 13.4 m,
  // KW3 14.0 m, KW7 12.5 m) hit it and shallowed to 26-29 degrees — under the
  // ~30 degree minimum concrete tiles are laid at, so they read as flat. 4.4
  // clears all 26 street houses; the wide BG* background infill still shallows
  // out, which is correct for distant generic massing.
  const rise = Math.min(run * Math.tan(PITCH), 4.4);
  const pitch = Math.atan2(rise, run);
  const slopeLen = Math.hypot(run, rise);
  const deckThick = 0.1;
  const deckLen = d + overhangZ * 2;
  const eaveY = y + 0.06;
  const ridgeY = eaveY + rise;

  // ---- two tile slopes, tilted about Z so the ridge runs along Z ----
  for (const side of [-1, 1]) {
    const cx = ts.x + side * (run / 2);
    const cy = eaveY + rise / 2;
    A.add(
      'roof_tile',
      BOX(A),
      LL(IDENT, cx, cy, ts.z, 0, slopeLen, deckThick, deckLen, 0, side > 0 ? -pitch : pitch),
      { masks: [0.4, 0.3, 0.18] }
    );
    // fascia board under the eave edge
    const fx = ts.x + side * (run + 0.02);
    A.add('wood_dark', BOX(A), LL(IDENT, fx, eaveY - 0.06, ts.z, 0, 0.1, 0.22, deckLen), {
      masks: [0.5, 0.4, 0.3],
    });
  }
  // one rough AABB for the whole roof volume — not walkable, so a tilt-accurate
  // collision mesh buys nothing; this just stops shots and the eye passing
  // straight through an empty rooftop.
  A.box('concrete', ts.x, (eaveY + ridgeY) / 2, ts.z, w + overhangX * 2, ridgeY - eaveY, deckLen);

  // ---- ridge cap ----
  A.add('roof_tile', BOX(A), LL(IDENT, ts.x, ridgeY - 0.02, ts.z, 0, 0.26, 0.14, deckLen + 0.06), {
    masks: [0.35, 0.35, 0.2],
  });

  // ---- gable-end infill, closing the triangle under the roof at each Z end ----
  const halfSpan = w / 2 + overhangX * 0.5;
  const pts = [
    [-halfSpan, 0],
    [halfSpan, 0],
    [0, rise + 0.05],
  ];
  for (const side of [0, 2]) {
    const g = polyPrism(pts, 0.22);
    g.rotateX(Math.PI / 2);
    const pm = panelMatrix(ts, side, eaveY);
    A.addOnce(wallKey, g, LL(pm, 0, 0, 0), { masks: [0.5, 0.45, 0.2] });
  }

  // ---- chimney stack: brick, capped, with a couple of pots ----
  // Offset toward one gable end and off the ridge centreline, the way a real
  // flue serving a fireplace below actually lands, not dead-centre.
  const cz = ts.z + (d / 2 - 0.9) * (rng.float() < 0.5 ? 1 : -1);
  const cx = ts.x + rng.range(-0.3, 0.3);
  const stackH = 0.85;
  const stackW = 0.55;
  const stackD = 0.34;
  A.add('brick_fine', BOX(A), LL(IDENT, cx, ridgeY + stackH / 2, cz, 0, stackW, stackH, stackD), {
    masks: [0.4, 0.35, 0.15],
  });
  A.box('concrete', cx, ridgeY + stackH / 2, cz, stackW, stackH, stackD);
  A.add('concrete', BOX_SOFT(A), LL(IDENT, cx, ridgeY + stackH + 0.04, cz, 0, stackW + 0.14, 0.09, stackD + 0.14), {
    masks: [0.6, 0.35, 0.15],
  });
  const pots = rng.int(1, 2);
  for (let i = 0; i < pots; i++) {
    const px = cx + (pots > 1 ? (i - 0.5) * stackW * 0.45 : 0);
    A.put('chimney_pot', px, ridgeY + stackH + 0.09, cz, rng.float() * 6.28, 1, null);
  }
}

// =============================================================== facades ====
function buildFacade(A, rng, spec, info, ctx) {
  const { side, f, y, h, t, wallKey, streetSide, floors } = ctx;
  const len = sideLen(spec, side);
  const pm = panelMatrix(spec, side, y).clone();
  const street = side === streetSide;
  const secondary = spec.secondarySide === side;
  const openFace = street || secondary;

  const bays = Math.max(1, Math.round(len / 3.05));
  const bw = len / bays;
  const openings = [];
  const deco = [];

  const ruinTop = spec.ruin && f === floors - 1;

  for (let b = 0; b < bays; b++) {
    const bx = -len / 2 + (b + 0.5) * bw;
    // edge bays keep more solid wall so corners stay strong
    const room = Math.min(bw - 1.0, 2.6);
    let kind = 'blank';
    if (f === 0) {
      if (openFace) {
        // Opt-IN, not opt-out: this was `spec.shops !== false`, which meant every
        // building on Kilmore Close (an ordinary residential close with no
        // BUILDINGS entry setting `shops: false`) had a 50%/25% chance per
        // ground-floor bay of getting a shopfront() roller shutter plus a
        // striped red/teal/cream market awning — the "hazard-striped facade"
        // that read industrial instead of residential. No house on this street
        // should ever roll a shop bay unless a future BUILDINGS entry opts in.
        const shopHere = spec.shops === true && room > 2.0 && rng.float() < (street ? 0.5 : 0.25);
        if (spec.doorBays?.[side] === b) kind = 'door';
        else if (shopHere) kind = 'shop';
        else if (rng.float() < 0.72) kind = 'window';
      } else if (rng.float() < 0.4) kind = 'window';
    } else {
      if (rng.float() < (openFace ? 0.88 : 0.6)) {
        kind = spec.arches && f === 1 ? 'arch' : 'window';
        if (openFace && f >= 1 && rng.float() < (spec.balconies ?? 0.35)) kind = 'balconyDoor';
      }
    }
    if (ruinTop && rng.float() < 0.5) kind = kind === 'blank' ? 'blank' : 'ragged';

    /**
     * Hand-authored override for the bays that carry a sightline the map
     * depends on (the shop the interior camera looks out of, the doorway that
     * connects an alley to a stairwell). A string names the kind; an object
     * additionally passes options to the kit element.
     */
    let forced = spec.bayKinds?.[side]?.[f]?.[b];
    if (typeof forced === 'string') forced = { kind: forced };
    if (forced) kind = forced.kind;

    switch (kind) {
      case 'door': {
        const o = { x: bx, y: 1.08, w: 1.12, h: 2.16, kind };
        openings.push(o);
        deco.push(() =>
          doorUnit(A, pm, o, rng, {
            t,
            open: rng.float() < 0.45 ? rng.range(0.5, 1.6) : 0,
            leafKey: rng.pick(['metal_green', 'metal_blue', 'wood_dark']),
          })
        );
        info.doors.push({ side, x: bx, pm, wp: worldOf(pm, bx, 0, 0).slice() });
        break;
      }
      case 'shop': {
        const sw = Math.min(bw - 0.75, 3.1);
        const o = { x: bx, y: 1.32, w: sw, h: 2.58, kind };
        openings.push(o);
        // Never fully shuttered: a market street with every shop closed is dead,
        // and a shutter over an interior sightline blocks the shot.
        const drop = forced?.drop ?? (rng.float() < 0.5 ? rng.range(0.1, 0.55) : 0);
        deco.push(() => shopfront(A, pm, o, rng, { t, drop }));
        if (rng.float() < 0.8) {
          const aw = sw + 0.5;
          deco.push(() =>
            awning(A, pm, bx, o.y + o.h / 2 + 0.55, aw, rng, {
              depth: rng.range(1.3, 1.9),
              key: rng.pick(['fabric_red', 'fabric_teal', 'fabric_cream']),
              legs: rng.float() < 0.4,
            })
          );
          info.awnings.push({ side, x: bx, y: o.y + o.h / 2 + 0.55, w: aw, pm });
        }
        break;
      }
      case 'window': {
        const ww = Math.min(room, rng.range(1.05, 1.3));
        // Retuned with the storey heights above. At the old 1.62/1.48 with sills
        // at 1.05/0.95 the heads sat at 2.67 m and 2.43 m, which clears a 3.45 m
        // storey but would leave 3 cm of wall under a 2.70 m one. These land the
        // heads at 2.20 m and 2.05 m — the usual head height for the type, with
        // a proper band of wall left under the ceiling.
        const wh = f === 0 ? 1.3 : 1.2;
        const o = { x: bx, y: (f === 0 ? 0.9 : 0.85) + wh / 2, w: ww, h: wh, kind };
        openings.push(o);
        // Kilmore Close's houses are occupied, not derelict: broken glass and
        // boarded panes are a war-zone/abandoned-building tell, and security
        // grilles + metal roller shutters read as a shopfront or a squat, not
        // a semi-D. Damage still scales a much rarer cracked pane; boarded is
        // switched off outright (see windowState's `allowBoarded`), and
        // grille/shutters are dropped for this map rather than rolled.
        const broken = rng.float() < (spec.damage ?? 0.15) * 0.35;
        // One window per bay is not the same window per bay: pick a state so the
        // facade carries open casements, curtains and the occasional lit room
        // instead of one repeated glazed panel.
        const st = broken
          ? 'open'
          : windowState(rng, f, spec.damage ?? 0.15, { allowLit: !openFace || f > 0, allowBoarded: false });
        deco.push(() =>
          windowUnit(A, pm, o, rng, {
            t,
            broken,
            state: st,
            back: !spec.enterable,
            grille: false,
            shutters: false,
            curtain: st === 'curtain' || (st === 'glazed' && rng.float() < 0.25),
          })
        );
        info.windows.push({ side, f, x: bx, y: o.y, w: ww, h: wh, pm, state: st });
        break;
      }
      case 'arch': {
        const ww = Math.min(room, 1.35);
        const o = { x: bx, y: 1.05 + 0.9, w: ww, h: 1.9, arch: 0.62, kind };
        openings.push(o);
        const st = windowState(rng, f, spec.damage ?? 0.15, { allowBoarded: false });
        deco.push(() =>
          windowUnit(A, pm, o, rng, {
            t,
            broken: rng.float() < 0.04,
            state: st,
            back: !spec.enterable,
            shutters: false,
            curtain: st === 'curtain' || rng.float() < 0.3,
            lintel: false,
          })
        );
        info.windows.push({ side, f, x: bx, y: o.y, w: ww, h: o.h, pm, state: st });
        break;
      }
      case 'balconyDoor': {
        const ww = Math.min(room, 1.15);
        const o = { x: bx, y: 1.12, w: ww, h: 2.24, kind };
        openings.push(o);
        const bwid = Math.min(bw - 0.35, 2.6);
        deco.push(() => {
          doorUnit(A, pm, o, rng, {
            t,
            open: rng.float() < 0.5 ? rng.range(0.6, 1.5) : 0,
            leafKey: 'wood_dark',
          });
          const balY = 0.02;
          const bal = balcony(A, pm, bx, balY, bwid, rng, {
            depth: rng.range(1.0, 1.35),
            railing: rng.float() < 0.45 ? 'concrete' : 'metal',
            key: spec.wallKey ?? 'plaster_cream',
          });
          // `y` here is PANEL-LOCAL, like info.windows/info.awnings: `pm`
          // already carries the floor height. Publishing the world floor `y`
          // made dressing place balcony clutter at 2*floorY (props and rugs
          // floating in mid-air above the street).
          info.balconies.push({ side, x: bx, y: balY, w: bal.w, d: bal.d, pm });
        });
        break;
      }
      case 'ragged': {
        const o = { x: bx, y: h * 0.55, w: Math.min(bw - 0.4, 2.2), h: h * 0.8, ragged: 0.22, kind };
        openings.push(o);
        break;
      }
      default:
        break;
    }
  }

  // ---- the wall itself ----
  const isTop = f === floors - 1;
  facadeWall(A, pm, {
    w: len,
    h: h + (isTop ? 0.02 : 0),
    t,
    key: wallKey,
    openings,
    rng,
    top: spec.ruin && isTop && (side === streetSide || side === spec.ruinSide) ? 'ragged' : 'flat',
    raggedAmp: 0.55,
    jag: isTop && !spec.ruin ? 0.03 : 0,
    warp: 0.02,
    paint: (x, wy, z, nx, ny, nz, out) => {
      // extra grime toward the base of the ground floor and under the eaves
      const base = f === 0 ? Math.max(0, 1 - wy / 1.4) : 0;
      const n = fbm3(x * 0.7, wy * 0.7, z * 0.7, 2);
      out[1] = Math.min(1, out[1] + base * base * 0.55 * (0.5 + n));
      out[2] = Math.min(1, out[2] + base * base * 0.4);
    },
  });

  for (const fn of deco) fn();

  // ---- painted ground-floor spandrel band ----------------------------------
  // A wine/coral accent strip under the front windows, the way the paired
  // semis in the Street View references read as two-tone paint rather than
  // one flat render colour. Street-facing ground floor only — the gable ends
  // and rear elevation in every reference stay a single colour.
  //
  // Iteration 2: the top edge stays pinned at the window sill (1.05) — raising
  // it further would push the band up into the glass opening itself. Instead
  // the band grows DOWN, over the plinth course, to 0.1 off the ground: at the
  // iteration-1 height (plinth-top to sill, 0.63 m) it read as a thin trim
  // line from street distance; starting it near ground level nearly doubles
  // the visible height without touching any opening.
  if (spec.bandKey && f === 0 && street) {
    const bandBottom = 0.1;
    const bandTop = 0.9; // ground-floor window sill height — do not raise past this
    const bandH = bandTop - bandBottom;
    // A touch more proud of the wall (was -0.017) so the band casts a hairline
    // shadow at its top edge instead of sitting perfectly flush — that edge
    // shadow is what reads as "painted strip" rather than "tinted patch" at
    // range.
    slab(A, spec.bandKey, pm, 0, bandBottom + bandH / 2, -0.022, len + 0.04, bandH, 0.035, {
      masks: [0.5, 0.4, 0.2],
    });
  }

  // ---- rain runoff below every opening and ledge --------------------------
  // The world knows where the water comes off: sills, shopfront heads, awning
  // bars and balcony slabs. A facade with no runs below its openings reads as
  // freshly painted, which is the one thing a street like this never is.
  //
  // Drawn from a stream keyed to this panel's identity rather than from `rng`, so
  // adding or tuning the weathering never re-rolls the level's layout.
  const wr = new Rng(
    (Math.round((spec.x + 512) * 977 + (spec.z + 512) * 7919) ^ (side * 131 + f * 1237)) >>> 0
  );
  for (const o of openings) {
    if (o.kind === 'ragged') continue;
    const sillY = o.y - o.h / 2;
    // Not every sill sheds the same amount, and a couple are bone dry.
    if (wr.float() < 0.22) continue;
    const run = Math.min(wr.range(0.7, 1.8), Math.max(0.25, sillY - 0.12));
    const g = runoffStreak(wr, o.w * wr.range(0.6, 1.0), run, {
      amount: wr.range(0.72, 1.0),
    });
    A.addOnce(wallKey, g, LL(pm, o.x + wr.range(-0.1, 0.1), sillY - 0.03, -0.012, 0, 1, 1, 1));
    // a second, narrower run off one corner of the sill: water finds a low spot
    if (wr.float() < 0.55) {
      const sgn = wr.float() < 0.5 ? -1 : 1;
      const run2 = Math.min(wr.range(0.5, 1.3), Math.max(0.2, sillY - 0.1));
      const g2 = runoffStreak(wr, wr.range(0.1, 0.22), run2, { amount: wr.range(0.8, 1.0), cols: 3 });
      A.addOnce(
        wallKey,
        g2,
        LL(pm, o.x + sgn * o.w * wr.range(0.32, 0.5), sillY - 0.02, -0.013, 0, 1, 1, 1)
      );
    }
  }
  // and one long run off the string course / cornice per open facade
  if (openFace && wr.float() < 0.8) {
    const g = runoffStreak(wr, wr.range(0.18, 0.4), wr.range(1.0, 1.8), {
      amount: wr.range(0.78, 1.0),
      cols: 4,
    });
    A.addOnce(
      wallKey,
      g,
      LL(pm, wr.range(-len / 2 + 0.4, len / 2 - 0.4), h - 0.16, -0.012, 0, 1, 1, 1)
    );
  }

  // ---- string course between floors ----
  if (f < ctx.floors - 1 && (openFace || rng.float() < 0.5)) {
    A.add(
      spec.trimKey ?? 'concrete',
      BOX_SOFT(A),
      LL(pm, 0, h - 0.09, -0.055, 0, len + 0.06, 0.13, 0.12),
      { masks: [0.7, 0.45, 0.2] }
    );
  }
  // ---- top cornice ----
  if (f === ctx.floors - 1 && !spec.ruin) {
    A.add(
      spec.trimKey ?? 'concrete',
      BOX_SOFT(A),
      LL(pm, 0, h - 0.14, -0.11, 0, len + 0.14, 0.22, 0.2),
      { masks: [0.75, 0.5, 0.25] }
    );
  }

  // ---- damage: spalled render exposing brick, bullet-pocked plaster ----
  const dmg = spec.damage ?? 0.2;
  const spalls = Math.round(dmg * 5 * (openFace ? 1.4 : 0.7));
  for (let i = 0; i < spalls; i++) {
    const sx = rng.range(-len / 2 + 0.5, len / 2 - 0.5);
    const sy = rng.range(0.4, h - 0.5);
    const g = spallPatch(rng, rng.range(0.35, 1.0), rng.range(0.3, 0.8), 0.03);
    A.addOnce('brick_fine', g, LL(pm, sx, sy, 0.01, 0, 1, 1, 1));
  }
  // patched render — a slightly different mix where somebody repaired it. Kept
  // in the same value family as the wall, or it reads as a paper poster.
  if (openFace && rng.float() < 0.5) {
    const px = rng.range(-len / 2 + 1, len / 2 - 1);
    const py = rng.range(0.5, h - 1.2);
    const g = spallPatch(rng, rng.range(0.6, 1.4), rng.range(0.5, 1.1), 0.02);
    // Same value family as the wall: a bright white patch on cream render reads
    // as a sheet of paper stuck to the building.
    A.addOnce(PATCH_KEY[wallKey] ?? 'plaster_sand', g, LL(pm, px, py, 0.013, 0, 1, 1, 1));
  }

  // ---- bullet pocks, clustered where somebody took cover ----
  // Combat damage, not weathering — every occupied Kilmore Close house has
  // `damage` in the 0.05-0.15 range, but this used to add a flat +2 bursts to
  // EVERY street-facing wall regardless of damage, so every house on the
  // close had bullet-hole clusters on its front. Gated on real damage now
  // (0.2+, above anything on this map) so nothing here rolls a burst; the
  // mechanic stays in place for any higher-damage set piece later.
  if (A.has('pock') && dmg >= 0.2) {
    const bursts = Math.round(dmg * 6) + (openFace ? 2 : 0);
    for (let i = 0; i < bursts; i++) {
      const cx = rng.range(-len / 2 + 0.4, len / 2 - 0.4);
      const cy = rng.range(0.5, Math.min(h - 0.4, 3.0));
      const n = rng.int(3, 9);
      for (let j = 0; j < n; j++) {
        const px = cx + rng.gauss() * 0.45;
        const py = cy + rng.gauss() * 0.32;
        if (Math.abs(px) > len / 2 - 0.15) continue;
        if (py < 0.15 || py > h - 0.15) continue;
        // skip pocks that would land inside an opening
        let inHole = false;
        for (const o of openings) {
          if (
            px > o.x - o.w / 2 - 0.05 &&
            px < o.x + o.w / 2 + 0.05 &&
            py > o.y - o.h / 2 - 0.05 &&
            py < o.y + o.h / 2 + 0.05
          ) {
            inHole = true;
            break;
          }
        }
        if (inHole) continue;
        // Just proud of the render. The pock is a raised-rim crater now, not a
        // solid cone, so burying the origin 4 mm inside the wall (which is what
        // hid the old cone's base) would sink the whole thing out of sight.
        const wp = worldOf(pm, px, py, 0.0015);
        const s = rng.range(0.55, 1.5);
        A.putS('pock', wp[0], wp[1], wp[2], SIDE[side].ry + Math.PI, s, s, rng.range(0.5, 1.2), [
          1,
          rng.range(0.7, 1.3),
          1,
        ]);
      }
    }
  }
}

// ================================================================= slabs ====
/** Floor slab for one level, with the stairwell void left open. */
function interiorSlab(A, rng, spec, y, t, level, roof = false) {
  const iw = spec.w - t * 2;
  const id = spec.d - t * 2;
  const key = roof ? 'roof_screed' : 'floor_concrete';
  const hole = spec.enterable ? (spec.stairHoles?.[level] ?? null) : null;
  const thick = roof ? 0.26 : 0.2;
  if (!hole) {
    A.add(key, BOX(A), LL(IDENT, spec.x, y - thick / 2, spec.z, 0, iw, thick, id), {
      masks: roof ? [0.45, 0.25, 0.12] : [0.3, 0.55, 0.35],
    });
    A.box('concrete', spec.x, y - thick / 2, spec.z, iw, thick, id);
  } else {
    // picture-frame decomposition around the void
    const x0 = spec.x - iw / 2;
    const x1 = spec.x + iw / 2;
    const z0 = spec.z - id / 2;
    const z1 = spec.z + id / 2;
    const hx0 = hole.x0;
    const hx1 = hole.x1;
    const hz0 = hole.z0;
    const hz1 = hole.z1;
    const parts = [
      [x0, z0, x1, hz0],
      [x0, hz1, x1, z1],
      [x0, hz0, hx0, hz1],
      [hx1, hz0, x1, hz1],
    ];
    for (const [ax, az, bx, bz] of parts) {
      const w = bx - ax;
      const d = bz - az;
      if (w < 0.05 || d < 0.05) continue;
      A.add(key, BOX(A), LL(IDENT, (ax + bx) / 2, y - thick / 2, (az + bz) / 2, 0, w, thick, d), {
        masks: roof ? [0.45, 0.25, 0.12] : [0.3, 0.55, 0.35],
      });
      A.box('concrete', (ax + bx) / 2, y - thick / 2, (az + bz) / 2, w, thick, d);
    }
  }
  // exposed ceiling beams / joists under the slab, seen from inside
  if (!roof && spec.enterable) {
    const n = Math.max(2, Math.round(id / 1.5));
    for (let i = 0; i < n; i++) {
      const bz = spec.z - id / 2 + ((i + 0.5) / n) * id;
      A.add('wood_dark', BOX(A), LL(IDENT, spec.x, y - thick - 0.08, bz, 0, iw, 0.16, 0.13), {
        masks: [0.4, 0.6, 0.5],
      });
    }
  }
}

// ============================================================= interiors ====
function buildInterior(A, rng, spec, info, t, groundH, upperH, floors) {
  const it = 0.16; // partition thickness
  const g0 = floorSpec(spec, 0);

  // ground slab, a step up from the street
  A.add('floor_concrete', BOX(A), LL(IDENT, g0.x, 0.06, g0.z, 0, g0.w - t * 2, 0.14, g0.d - t * 2), {
    masks: [0.3, 0.6, 0.4],
  });
  A.box('concrete', g0.x, 0.06, g0.z, g0.w - t * 2, 0.16, g0.d - t * 2);

  const rooms = spec.rooms ?? [];
  for (let f = 0; f < floors; f++) {
    // Room plans are normalised, so they follow a setback automatically.
    const fs = floorSpec(spec, f);
    const iw = fs.w - t * 2;
    const id = fs.d - t * 2;
    const x0 = fs.x - iw / 2;
    const z0 = fs.z - id / 2;
    const fy = info.floorY[f] + (f === 0 ? 0.13 : 0.0);
    const fh = f === 0 ? groundH - 0.13 : upperH;
    // partitions for this floor
    const plan = rooms[f] ?? rooms[rooms.length - 1] ?? null;
    if (plan) {
      for (const wall of plan.walls) {
        const [ax, az, bx, bz, doorAt] = wall;
        const wx0 = x0 + ax * iw;
        const wz0 = z0 + az * id;
        const wx1 = x0 + bx * iw;
        const wz1 = z0 + bz * id;
        const len = Math.hypot(wx1 - wx0, wz1 - wz0);
        const ry = Math.atan2(wx1 - wx0, wz1 - wz0) - Math.PI / 2;
        _e.set(0, ry, 0);
        _q.setFromEuler(_e);
        _p.set((wx0 + wx1) / 2 - Math.sin(ry) * (it / 2), fy, (wz0 + wz1) / 2 - Math.cos(ry) * (it / 2));
        _s.set(1, 1, 1);
        const pm = new THREE.Matrix4().compose(_p, _q, _s);
        const holes = [];
        if (doorAt !== undefined && doorAt !== null) {
          holes.push({ x: -len / 2 + doorAt * len, y: 1.06, w: 1.05, h: 2.12 });
        }
        facadeWall(A, pm, {
          w: len,
          h: fh,
          t: it,
          key: 'plaster_white',
          openings: holes,
          rng,
          warp: 0.012,
          bevel: 0.012,
          paint: (px, py, pz, nx, ny, nz, out) => {
            const base = Math.max(0, 1 - py / 1.1);
            out[1] = Math.min(1, out[1] + base * base * 0.5);
            out[2] = Math.min(1, out[2] + base * base * 0.35);
          },
        });
        for (const hole of holes) {
          doorUnit(A, pm, hole, rng, { t: it, leaf: rng.float() < 0.4, open: 1.4, leafKey: 'wood_dark' });
        }
      }
    }

    // ---- stairs rising out of this floor ----
    for (const fl of spec.stairFlights ?? []) {
      if (fl.floor !== f) continue;
      const base = info.floorY[f] + (f === 0 ? 0.13 : 0);
      const climb = (info.floorY[f + 1] ?? info.roofY) - base;
      const steps = Math.max(6, Math.round(climb / 0.19));
      const rise = climb / steps;
      const run = fl.run ?? 0.275;
      const sw = fl.w ?? 1.2;
      _e.set(0, fl.ry ?? 0, 0);
      _q.setFromEuler(_e);
      _p.set(x0 + fl.x * iw, base, z0 + fl.z * id);
      _s.set(1, 1, 1);
      const pm = new THREE.Matrix4().compose(_p, _q, _s);
      stairRun(A, pm, 0, 0, 0, sw, steps, rise, run, {
        key: 'concrete_dark',
        railing: fl.railing ?? 'right',
      });
      const D = steps * run;
      const H = steps * rise;
      A.add('concrete_dark', BOX(A), LL(pm, 0, H - 0.1, D + 0.55, 0, sw + 0.1, 0.2, 1.1), {
        masks: [0.4, 0.5, 0.3],
      });
      const wp = worldOf(pm, 0, H - 0.1, D + 0.55);
      A.box('concrete', wp[0], wp[1], wp[2], sw + 0.1, 0.2, 1.1, fl.ry ?? 0);
    }

    // furnishing
    if (plan?.furnish) {
      for (const r of plan.furnish) {
        furnishRoom(A, rng, {
          kind: r.kind,
          // so furnishing never stacks a shelf across a shopfront opening
          street: spec.streetSide,
          x0: x0 + r.x0 * iw,
          z0: z0 + r.z0 * id,
          x1: x0 + r.x1 * iw,
          z1: z0 + r.z1 * id,
          y: fy,
          h: fh,
          spec,
        });
      }
    }
  }

  // roof access: a stair penthouse box with an open doorway
  if (spec.roofAccess) {
    const rs = floorSpec(spec, floors - 1);
    const riw = rs.w - t * 2;
    const rid = rs.d - t * 2;
    const st = spec.stairFlights?.[spec.stairFlights.length - 1];
    const px = rs.x - riw / 2 + (st?.x ?? 0.5) * riw;
    const pz = rs.z - rid / 2 + (st?.z ?? 0.5) * rid + 3.6;
    const y = info.roofY;
    for (let side = 0; side < 4; side++) {
      const pm = panelMatrix({ x: px, z: pz, w: 2.4, d: 2.6 }, side, y).clone();
      const holes = side === 2 ? [{ x: 0, y: 1.08, w: 1.05, h: 2.16 }] : [];
      facadeWall(A, pm, {
        w: side === 0 || side === 2 ? 2.4 : 2.6,
        h: 2.5,
        t: 0.22,
        key: spec.wallKey ?? 'plaster_cream',
        openings: holes,
        rng,
        warp: 0.015,
      });
    }
    A.add('concrete', BOX(A), LL(IDENT, px, y + 2.6, pz, 0, 2.7, 0.2, 2.9), {
      masks: [0.5, 0.45, 0.2],
    });
    A.box('concrete', px, y + 2.6, pz, 2.7, 0.2, 2.9);
  }
}

/** A hole in the roof slab and a matching heap of rubble on the floor below. */
export function collapseRoof(A, rng, spec, info, hole) {
  rubbleMound(A, rng, hole.x, info.floorY[info.floorY.length - 1] + 0.15, hole.z, 2.1, 26, {
    key: 'concrete',
  });
}
