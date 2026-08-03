import * as THREE from 'three';
import { Rng } from '../core/rng.js';
import {
  BOX,
  BOX_FINE,
  BOX_SOFT,
  BOX_THIN,
  IDENT,
  LL,
  worldOf,
  ryOf,
  rubbleMound,
  mergeSimple,
  stripedCloth,
  spallPatch,
} from './kit.js';
import { burntCar } from './props.js';
import {
  clothGeometry,
  catenaryTube,
  patchGeometry,
  driftBerm,
  chamferBox,
  fillMasks,
  paintMasks,
  rockGeometry,
  tubeY,
  fbm3,
} from './util.js';
import { STREET, ALLEYS, BUILDINGS, SET_PIECES } from './layout.js';

/**
 * WORLD — set dressing.
 *
 * Geometry makes a level; dressing makes it a *place*. This pass adds the
 * hundreds of instanced props that turn a street of boxes into a Dublin
 * close people evidently live in: cars parked along the kerb, low garden
 * walls and clipped hedges, wheelie bins out for collection, ordinary
 * deciduous trees, lamps, overhead cables and washing lines strung out the
 * back, roof clutter, and the litter and damp grime that collects against
 * every wall base. Both street ends are left open, continuing toward the
 * real connecting roads per `ROAD_ENDS` in layout.js.
 *
 * Everything is placed in LEVEL space and instanced through the Assembler, so
 * the cost of another two hundred props is a few kilobytes of matrices.
 */

const _m = new THREE.Matrix4();
const _v = new THREE.Vector3();

// --------------------------------------------------------------- occupancy --
/** True inside (or within `m` of) any building footprint. */
export function inBuilding(x, z, m = 0.3) {
  for (let i = 0; i < BUILDINGS.length; i++) {
    const b = BUILDINGS[i];
    if (
      x > b.x - b.w / 2 - m &&
      x < b.x + b.w / 2 + m &&
      z > b.z - b.d / 2 - m &&
      z < b.z + b.d / 2 + m
    )
      return true;
  }
  return false;
}

/** True on the street, a pavement or an alley — i.e. somewhere props can sit. */
export function isOpen(x, z, m = 0.3) {
  if (inBuilding(x, z, m)) return false;
  if (Math.abs(x) < STREET.kerb - 0.1 && z > STREET.zMin && z < STREET.zMax) return true;
  for (const a of ALLEYS) {
    const [x0, z0, x1, z1] = a.rect;
    if (x > x0 + m && x < x1 - m && z > z0 + m && z < z1 - m) return true;
  }
  return false;
}

/** Ground height for a prop: pavement slabs sit a kerb above the road. */
export function groundY(x, z) {
  // The road is cambered; props placed at y=0 sink into the crown by 5 cm.
  if (Math.abs(x) < STREET.halfWidth)
    return (1 - (x / STREET.halfWidth) ** 2) * 0.055 + 0.004;
  if (Math.abs(x) < STREET.kerb && z > STREET.zMin && z < STREET.zMax) return STREET.walkH;
  return 0.03;
}

/**
 * A dirt/rubble skirt at the base of a heavy prop.
 *
 * Nothing in the real world meets the ground on a clean line: there is a dust
 * halo where it was dragged into place, grit swept up against it, and a few
 * pebbles that got kicked out. Without this every crate, drum and barrier reads
 * as a decal pasted onto the deck — the single cheapest grounding cue there is.
 */
export function groundSkirt(A, rng, x, y, z, radius, opts = {}) {
  const r = radius * rng.range(1.15, 1.55);
  const g = patchGeometry(rng, r, { lobes: 11, wobble: 0.5 });
  A.addOnce(
    opts.key ?? 'dirt',
    g,
    LL(IDENT, x, y + 0.011 + rng.range(0, 0.005), z, rng.float() * 6.28, 1, 1, rng.range(0.7, 1.0)),
    { masks: [0.08, opts.grime ?? 0.85, opts.ao ?? 0.55] }
  );
  // a second, tighter and darker ring right at the contact line
  const g2 = patchGeometry(rng, radius * rng.range(0.75, 1.0), { lobes: 9, wobble: 0.35 });
  A.addOnce('dirt', g2, LL(IDENT, x, y + 0.018 + rng.range(0, 0.004), z, rng.float() * 6.28, 1, 1, 0.85), {
    masks: [0.05, 1.0, 0.8],
  });
  const n = opts.pebbles ?? rng.int(4, 8);
  for (let i = 0; i < n; i++) {
    const a = rng.float() * 6.28;
    const rr = radius * rng.range(0.75, 1.5);
    const px = x + Math.cos(a) * rr;
    const pz = z + Math.sin(a) * rr;
    if (!isOpen(px, pz, 0.05)) continue;
    A.put(
      rng.pick(['rock_b', 'rock_b', 'brick_b', 'cinder', 'rock_a', 'litter']),
      px,
      groundY(px, pz) + 0.012,
      pz,
      rng.float() * 6.28,
      rng.range(0.45, 0.95),
      [1, rng.range(1.1, 1.5), 1],
      rng.range(-0.3, 0.3),
      rng.range(-0.3, 0.3)
    );
  }
}

/** Distance to the nearest building wall, and the outward normal, in level space. */
function nearestWall(x, z) {
  let best = 1e9;
  let nx = 0;
  let nz = 0;
  for (const b of BUILDINGS) {
    const dx = Math.abs(x - b.x) - b.w / 2;
    const dz = Math.abs(z - b.z) - b.d / 2;
    const d = Math.max(dx, dz);
    if (d < best) {
      best = d;
      if (dx > dz) {
        nx = Math.sign(x - b.x);
        nz = 0;
      } else {
        nx = 0;
        nz = Math.sign(z - b.z);
      }
    }
  }
  return { d: best, nx, nz };
}

// =============================================================== prototypes ==
/** Props that only the dressing pass uses. */
export function registerDressingProps(A, rng) {
  const P = (id, key, geo, opts = {}) => A.proto(id, { geo, key, ...opts });

  P('wreck', 'metal_dark', burntCar(rng), { chunk: false });

  // A wheel still on the hub of a wreck — flat tyre, exposed rim.
  P(
    'wheel_flat',
    'rubber',
    (() => {
      const g = new THREE.TorusGeometry(0.24, 0.11, 10, 16);
      g.rotateY(Math.PI / 2);
      const pa = g.getAttribute('position');
      for (let i = 0; i < pa.count; i++) {
        const y = pa.getY(i);
        pa.setY(i, y * 0.82);
      }
      g.computeVertexNormals();
      fillMasks(g, 0.3, 0.6, 0.2);
      return g;
    })()
  );

  // Broken glass fan under a blown-out window.
  P(
    'glass_shards',
    'glass',
    (() => {
      const list = [];
      for (let i = 0; i < 9; i++) {
        const s = 0.03 + rng.float() * 0.06;
        const g = chamferBox(s, 0.004, s * rng.range(0.5, 1.6), 0.001);
        g.applyMatrix4(
          _m.makeRotationY(rng.float() * 6.28).setPosition(
            rng.range(-0.5, 0.5),
            0.003,
            rng.range(-0.4, 0.4)
          )
        );
        fillMasks(g, 0.6, 0.2, 0);
        list.push(g);
      }
      const g = mergeSimple(list);
      for (const p of list) p.dispose();
      return g;
    })(),
    { maxDist: 40, castShadow: false }
  );

  // Cinder blocks — offcuts from garden walls and boundary repairs.
  P(
    'cinder',
    'concrete_prop',
    (() => {
      const g = chamferBox(0.44, 0.21, 0.21, 0.012);
      paintMasks(g, (x, y, z, nx, ny, nz, out) => {
        out[0] = 0.7;
        out[1] = 0.3 + Math.max(0, -ny) * 0.5;
        out[2] = Math.max(0, -ny) * 0.4;
      });
      g.translate(0, 0.105, 0);
      return g;
    })()
  );

  // A stack of flat bread crates / produce trays for the stalls.
  P(
    'tray',
    'wood_prop',
    (() => {
      const list = [];
      const add = (sx, sy, sz, x, y, z) => {
        const g = chamferBox(sx, sy, sz, 0.005);
        g.translate(x, y, z);
        list.push(g);
      };
      add(0.6, 0.02, 0.42, 0, 0.01, 0);
      for (const s of [-1, 1]) {
        add(0.6, 0.09, 0.02, 0, 0.055, s * 0.2);
        add(0.02, 0.09, 0.42, s * 0.29, 0.055, 0);
      }
      const g = mergeSimple(list);
      for (const p of list) p.dispose();
      paintMasks(g, (x, y, z, nx, ny, nz, out) => {
        out[0] = 0.8;
        out[1] = 0.35;
      });
      return g;
    })()
  );

  // Produce heap: a lumpy mound that sits in a tray.
  P(
    'produce',
    'burlap',
    (() => {
      const list = [];
      for (let i = 0; i < 7; i++) {
        const g = rockGeometry(rng, rng.range(0.055, 0.1), 0, 0.8);
        g.translate(rng.range(-0.22, 0.22), 0.035 + rng.range(0, 0.04), rng.range(-0.14, 0.14));
        list.push(g);
      }
      const g = mergeSimple(list);
      for (const p of list) p.dispose();
      fillMasks(g, 0.15, 0.2, 0.1);
      return g;
    })(),
    { maxDist: 60 }
  );

  // Wall conduit box — small, but it is what makes a facade look serviced.
  P(
    'conduit_box',
    'metal_dark',
    (() => {
      const list = [];
      const b = chamferBox(0.2, 0.26, 0.11, 0.008);
      list.push(b);
      const lid = chamferBox(0.17, 0.22, 0.02, 0.004);
      lid.translate(0, 0, 0.065);
      list.push(lid);
      const g = mergeSimple(list);
      for (const p of list) p.dispose();
      paintMasks(g, (x, y, z, nx, ny, nz, out) => {
        out[0] = 0.85;
        out[1] = 0.45;
      });
      return g;
    })(),
    { maxDist: 55 }
  );

  // Cheap plastic chair — one is on every roof and outside every shop.
  P(
    'stool',
    'wood_prop',
    (() => {
      const list = [];
      const top = chamferBox(0.34, 0.04, 0.34, 0.01);
      top.translate(0, 0.42, 0);
      list.push(top);
      for (const sx of [-1, 1])
        for (const sz of [-1, 1]) {
          const leg = chamferBox(0.035, 0.42, 0.035, 0.005);
          leg.applyMatrix4(
            _m.makeRotationZ(sx * 0.06).setPosition(sx * 0.13, 0.21, sz * 0.13)
          );
          list.push(leg);
        }
      const g = mergeSimple(list);
      for (const p of list) p.dispose();
      paintMasks(g, (x, y, z, nx, ny, nz, out) => {
        out[0] = 0.8;
        out[1] = 0.3 + Math.max(0, -ny) * 0.4;
      });
      return g;
    })()
  );
  return A;
}

/**
 * Per-instance placement jitter for the set-dressing passes: +/-12 deg of yaw,
 * +/-8% of scale, and whatever tilt each prototype declared as loose (see
 * registerProps and Assembler.put). Instanced clouds are where the eye finds
 * repeats fastest, and a row of clones all plumb and all the same size is the
 * clearest possible sign that nobody placed any of it.
 *
 * It runs on its OWN fixed-seed stream. Drawing the jitter from the placement
 * rng would shift every subsequent position in the level, which walks props into
 * the shot cameras' keepout zones and re-rolls the whole layout on any edit.
 */
function jitterRig() {
  return { rng: new Rng(0x9e3779b1), yaw: 0.209, scale: 0.08 };
}

// ================================================================== street ==
export function dressStreet(A, rng) {
  // A FORK, not `rng` itself: drawing the jitter from the placement stream would
  // shift every subsequent position in the level and walk props into the shot
  // cameras' keepout zones.
  A.jitter = jitterRig();
  parkedCars(A, rng);
  frontGardens(A, rng);
  builderSkips(A, rng);
  streetTrees(A, rng);
  streetLamps(A, rng);
  overheadLines(A, rng);
  frontGardenClutter(A, rng);
  binClusters(A, rng);
  coverClusters(A, rng);
  streetFloor(A, rng);
  A.jitter = null;
}

/**
 * Where the named shot cameras stand, in LEVEL space (see src/dev/shots.js and
 * the SHOT_KEEPOUT list in src/render/probe.js — same idea, level coordinates).
 * A silhouette breaker dropped on top of a camera turns a hero capture into a
 * close-up of an oil drum, so every mid-ground mass is tested against these.
 */
const SHOT_CLEAR = [
  [0.0, 20.0], // hero / night / hud
  [1.1, 25.6], // sunset
  [-3.3, 10.6], // combat
  [-0.55, 10.0], // weapon / ads / muzzle
  [-1.25, 4.8], // impacts
  [-0.11, 4.3], // detail
  [-8.86, 6.8], // interior
];

/** True when a prop of radius `r` at (x,z) leaves every shot camera clear. */
function camClear(x, z, r = 1.6) {
  for (let i = 0; i < SHOT_CLEAR.length; i++) {
    const dx = x - SHOT_CLEAR[i][0];
    const dz = z - SHOT_CLEAR[i][1];
    if (dx * dx + dz * dz < (r + 1.5) * (r + 1.5)) return false;
  }
  return true;
}

// --- the street floor -------------------------------------------------------
/**
 * The bottom third of every wide shot.
 *
 * A street is not a plane with a few crates on it: it is a floor with mass —
 * sand and swept rubble banked against every wall base, masonry spilling off the
 * kerb, polished ruts down the driving line, and enough at eye level in the
 * 10-30 m band to give the alley depth. The berms do double duty: they bury the
 * hard geometric line where wall meets ground, which otherwise reads as a
 * Z-fighting seam in every establishing shot.
 */
function streetFloor(A, rng) {
  const { halfWidth: HW, kerb: KB, walkH: WH, zMin, zMax } = STREET;

  // ---- 0. the wall-to-ground junction ----
  // A facade that meets the pavement on a ruled line is the tell that says
  // "two boxes intersecting". Every real wall has a 15-25 cm band of splashed
  // dirt at its foot. It is drawn on the outer face of the building's PLINTH, in
  // the plinth's own material with the grime mask pinned high, so it reads as
  // staining on the concrete rather than as a stripe of mud geometry — and the
  // segment-by-segment height jitter keeps its top edge from ruling a second
  // straight line 20 cm up.
  for (const side of [-1, 1]) {
    let z = zMin;
    while (z < zMax) {
      const seg = rng.range(0.5, 1.1);
      const cz = z + seg / 2;
      let host = null;
      for (const b of BUILDINGS) {
        // the facade that faces the street sits at |x| = kerb
        if (Math.abs(Math.abs(b.x) - b.w / 2 - KB) > 0.3) continue;
        if (Math.sign(b.x) !== side) continue;
        if (cz > b.z - b.d / 2 + 0.05 && cz < b.z + b.d / 2 - 0.05) {
          host = b;
          break;
        }
      }
      if (host) {
        const h = rng.range(0.15, 0.25);
        // the plinth stands 7 cm proud of the facade: stain ITS face, not the
        // render 7 cm behind it, or the band is buried and does nothing
        const px = side * (KB + 0.056);
        A.add(
          host.plinthKey ?? 'concrete',
          BOX_THIN(A),
          LL(IDENT, px, WH + h / 2 - 0.025, cz, 0, 0.034, h, seg * 0.99),
          { masks: [0.0, 1.0, 0.85] }
        );
        // and a low fillet of swept grit in the corner itself
        if (rng.float() < 0.75) {
          const g = driftBerm(rng, seg * 0.95, rng.range(0.16, 0.34), rng.range(0.04, 0.09), {
            nz: 3,
          });
          A.addOnce(
            'dirt',
            g,
            LL(IDENT, side * (KB - 0.04), WH - 0.012, cz, side > 0 ? Math.PI / 2 : -Math.PI / 2, 1, 1, 1),
            { masks: [0.1, 0.95, 0.7] }
          );
        }
      }
      z += seg;
    }
  }

  // ---- 1. drift berms banked against the building line, both sides ----
  for (const side of [-1, 1]) {
    let z = zMin + 1;
    while (z < zMax - 2) {
      const len = rng.range(2.2, 6.5);
      const cz = z + len / 2;
      const x = side * (KB - 0.06);
      // Alley mouths and doorways stay clear: a berm across a door reads as a bug.
      if (isOpen(x - side * 0.5, cz, 0.05) && rng.float() < 0.96) {
        const h = rng.range(0.1, 0.28);
        const w = rng.range(0.5, 1.1);
        const g = driftBerm(rng, len, w, h);
        // ry = -PI/2 for the +X side puts the tall edge against the wall
        A.addOnce(
          'moss_verge',
          g,
          LL(IDENT, x, WH - 0.02, cz, side > 0 ? Math.PI / 2 : -Math.PI / 2, 1, 1, 1),
          { masks: [0.15, 0.55, 0.45] }
        );
        // litter and windblown leaves sitting IN the drift, half buried
        for (let i = 0; i < rng.int(1, 4); i++) {
          const px = x - side * rng.range(0.05, w * 0.8);
          const pz = cz + rng.range(-len / 2 + 0.2, len / 2 - 0.2);
          A.put(
            rng.pick(['litter', 'can', 'weeds']),
            px,
            WH + h * rng.range(0.1, 0.55),
            pz,
            rng.float() * 6.28,
            rng.range(0.6, 1.15),
            [1, rng.range(1.1, 1.5), 1],
            rng.range(-0.25, 0.25),
            rng.range(-0.25, 0.25)
          );
        }
      }
      z += len + rng.range(0.1, 0.9);
    }
  }

  // ---- 2. the kerb line: damp grit and moss spilling off the pavement ----
  for (let i = 0; i < 70; i++) {
    const side = rng.float() < 0.5 ? -1 : 1;
    const cz = rng.range(zMin + 2, zMax - 2);
    const len = rng.range(1.2, 3.4);
    if (!isOpen(side * (HW + 0.4), cz, 0.05)) continue;
    const g = driftBerm(rng, len, rng.range(0.35, 0.8), rng.range(0.05, 0.14), { nz: 3 });
    A.addOnce('moss_verge', g, LL(IDENT, side * (HW + 0.12), 0.02, cz, side > 0 ? -Math.PI / 2 : Math.PI / 2, 1, 1, 1), {
      masks: [0.15, 0.5, 0.3],
    });
  }

  // ---- 3. tyre tracks polished into the dust along the driving line ----
  // Two ruts, laid as long overlapping strips so the line wanders instead of
  // ruling a straight edge down the middle of the frame.
  for (const side of [-1, 1]) {
    let z = zMin + 2;
    while (z < zMax - 3) {
      const len = rng.range(5.0, 13.0);
      const x = side * rng.range(1.25, 1.95);
      const camber = (1 - (x / HW) ** 2) * 0.055 + 0.038;
      const g = patchGeometry(rng, 0.34, { lobes: 13, wobble: 0.28 });
      A.addOnce(
        'road_rut',
        g,
        LL(IDENT, x, camber, z + len / 2, rng.range(-0.03, 0.03), 1, 1, len / 0.68),
        { masks: [0.55, 0.5, 0.15] }
      );
      // a lighter, wider halo of oil staining either side of the polished strip
      if (rng.float() < 0.7) {
        const hg = patchGeometry(rng, 0.62, { lobes: 11, wobble: 0.4 });
        A.addOnce(
          'dirt',
          hg,
          LL(IDENT, x, camber - 0.004, z + len / 2, rng.range(-0.04, 0.04), 1, 1, len / 1.24),
          { masks: [0.45, 0.15, 0.08] }
        );
      }
      // grit thrown up between the wheels
      if (rng.float() < 0.6) {
        const dg = driftBerm(rng, len * 0.8, 0.3, 0.035, { nz: 3 });
        A.addOnce('dirt', dg, LL(IDENT, x - side * 0.42, camber + 0.004, z + len / 2, Math.PI / 2, 1, 1, 1), {
          masks: [0.1, 0.4, 0.2],
        });
      }
      z += len + rng.range(0.5, 4.0);
    }
  }
  // a couple of turning scuffs where vehicles have swung across the road
  for (let i = 0; i < 8; i++) {
    const z = rng.range(zMin + 5, zMax - 5);
    const g = patchGeometry(rng, rng.range(0.5, 1.1), { lobes: 12, wobble: 0.5 });
    const x = rng.range(-HW + 0.6, HW - 0.6);
    A.addOnce(
      'asphalt',
      g,
      LL(IDENT, x, (1 - (x / HW) ** 2) * 0.055 + 0.04, z, rng.float() * 3.14, 1, 1, rng.range(1.4, 2.6)),
      { masks: [0.45, 0.4, 0.15] }
    );
  }

  // ---- 4. everyday kerbside litter — no bombed-masonry rubble on a lived-in close ----
  for (let i = 0; i < 90; i++) {
    const side = rng.float() < 0.5 ? -1 : 1;
    const z = rng.range(zMin + 1, zMax - 1);
    const x = side * (KB - Math.abs(rng.gauss()) * 1.5 - 0.1);
    if (!isOpen(x, z, 0.05)) continue;
    const y = groundY(x, z);
    A.put(
      rng.pick(['litter', 'can', 'weeds', 'litter']),
      x,
      y + 0.02,
      z,
      rng.float() * 6.28,
      rng.range(0.7, 1.35),
      [1, rng.range(1.0, 1.5), 1],
      rng.range(-0.3, 0.3),
      rng.range(-0.3, 0.3)
    );
  }

  // ---- 5. silhouette breakers at eye level in the 10-30 m mid-ground ----
  // Two more parked cars, a kerbside bin store and a bike-shed-style pallet
  // stack: mass between the camera and the terminator, so the street has
  // depth cues rather than an empty floor and a wall at the end — the same
  // job the old wreck/drums/tyre-pile did, ordinary instead of war-damaged.
  const car2 = [-3.35, -6.2, 0.28];
  if (camClear(car2[0], car2[1], 2.6)) {
    const y = groundY(car2[0], car2[1]);
    A.putS(rng.pick(CAR_COLOURS), car2[0], y + 0.015, car2[1], car2[2] + Math.PI / 2, 1, rng.range(0.97, 1.03), 1);
    A.box('metal', car2[0], y + 0.7, car2[1], 1.75, 1.4, 4.1, car2[2] + Math.PI / 2);
    for (const [lx, lz] of [
      [0.78, 1.45],
      [-0.78, 1.45],
      [0.78, -1.45],
      [-0.78, -1.45],
    ]) {
      const ry = car2[2] + Math.PI / 2;
      const px = car2[0] + Math.cos(ry) * lx + Math.sin(ry) * lz;
      const pz = car2[1] - Math.sin(ry) * lx + Math.cos(ry) * lz;
      A.put('tyre', px, y + 0.005, pz, ry, 0.62, [1, 1.1, 1]);
    }
    groundSkirt(A, rng, car2[0], y, car2[1], 1.6, { pebbles: rng.int(1, 3), key: 'moss_verge' });
    for (let i = 0; i < 8; i++) {
      const px = car2[0] + rng.range(-2.2, 2.2);
      const pz = car2[1] + rng.range(-3.0, 3.0);
      if (!isOpen(px, pz, 0.1)) continue;
      A.put(
        rng.pick(['litter', 'can', 'weeds']),
        px,
        groundY(px, pz) + 0.015,
        pz,
        rng.float() * 6.28,
        rng.range(0.6, 1.2),
        [1, 1.4, 1]
      );
    }
  }

  // Kerbside bin stores. Same module in three places, so each gets its own
  // colour mix and ring radius — otherwise the eye recognises the arrangement.
  const BIN_MIX = [
    ['bin_black', 'bin_green', 'bin_brown'],
    ['bin_black', 'bin_blue', 'bin_black'],
    ['bin_green', 'bin_black', 'bin_blue'],
  ];
  let cluster = 0;
  for (const [dx, dz, n] of [
    [-5.1, -2.0, 4],
    [4.9, -11.5, 3],
    [4.75, 6.2, 3],
  ]) {
    const mix = BIN_MIX[cluster % BIN_MIX.length];
    cluster++;
    if (!camClear(dx, dz, 1.4)) continue;
    const ry0 = rng.float() * 6.28;
    for (let i = 0; i < n; i++) {
      const lx = (i - (n - 1) / 2) * 0.6;
      const px = dx + Math.cos(ry0) * lx;
      const pz = dz - Math.sin(ry0) * lx;
      if (!isOpen(px, pz, 0.2)) continue;
      const y = groundY(px, pz);
      A.put(rng.pick(mix), px, y, pz, ry0 + Math.PI / 2 + rng.range(-0.06, 0.06), rng.range(0.95, 1.05), null);
    }
    groundSkirt(A, rng, dx, groundY(dx, dz), dz, 0.5, { pebbles: rng.int(1, 3), key: 'moss_verge' });
  }

  // a bike-shed-style pallet/timber stack, on the pavement so it never blocks the road
  for (const [px, pz] of [
    [-5.5, 6.2],
    [5.55, -1.2],
  ]) {
    if (!camClear(px, pz, 1.2)) continue;
    const y = groundY(px, pz);
    const n = rng.int(4, 7);
    for (let i = 0; i < n; i++) {
      A.put('pallet', px + rng.range(-0.07, 0.07), y + i * 0.135, pz + rng.range(-0.07, 0.07), rng.range(-0.12, 0.12), 1, [
        1,
        rng.range(1.0, 1.4),
        1,
      ]);
    }
    A.box('wood', px, y + (n * 0.135) / 2, pz, 1.2, n * 0.135, 0.9);
    A.put('crate_b', px + 0.75, y, pz + 0.5, rng.float() * 6.28, 1, [1, 1.3, 1]);
    groundSkirt(A, rng, px, y, pz, 0.72, { pebbles: rng.int(3, 6), key: 'moss_verge' });
  }
}

// --- parked cars -------------------------------------------------------------
/**
 * Cars parked nose-to-tail along the kerb, the way every real close actually
 * looks. Each one gets its own colour, a slight settle into the verge, four
 * wheels placed separately (so a shot-out or bullet-holed wheel later can
 * still be an independent instance), and the odd bit of kerbside detail
 * — a supermarket trolley, a bin dragged out too early, bin bags waiting for
 * collection day.
 */
const CAR_COLOURS = ['car_red', 'car_blue', 'car_silver', 'car_white'];
function parkedCars(A, rng) {
  for (const [x, z, ry0, len] of SET_PIECES.cars) {
    const y = groundY(x, z);
    // parked parallel to the kerb: long axis along the street, nose in
    // whichever direction, with only a couple of degrees of parking-line skew
    const ry = ry0 + (Math.PI / 2) * (rng.float() < 0.5 ? 0 : 1) + rng.range(-0.04, 0.04);
    const s = len / 4.1;
    A.putS(rng.pick(CAR_COLOURS), x, y + 0.015, z, ry, s, rng.range(0.97, 1.03), s, [
      1,
      rng.range(0.9, 1.08),
      1,
    ]);
    A.box('metal', x, y + 0.7, z, 1.75 * s, 1.4, len, ry);
    // four wheels, tucked under the arches
    const wheelPos = [
      [0.78, 1.45],
      [-0.78, 1.45],
      [0.78, -1.45],
      [-0.78, -1.45],
    ];
    for (const [lx, lz] of wheelPos) {
      const px = x + (Math.cos(ry) * lx + Math.sin(ry) * lz) * s;
      const pz = z + (-Math.sin(ry) * lx + Math.cos(ry) * lz) * s;
      A.put('tyre', px, y + 0.005, pz, ry, 0.62 * s, [1, 1.1, 1]);
    }
    groundSkirt(A, rng, x, y, z, len * 0.42, { pebbles: rng.int(1, 3), key: 'moss_verge' });
    // kerbside clutter: bin day, a dropped bag, sometimes a bike leaning on it
    if (rng.float() < 0.3) {
      const bx = x + Math.cos(ry + Math.PI / 2) * 0.9;
      const bz = z - Math.sin(ry + Math.PI / 2) * 0.9;
      if (isOpen(bx, bz, 0.3)) {
        A.put('box_card_a', bx, groundY(bx, bz), bz, rng.float() * 6.28, rng.range(0.7, 0.95), [1, 1.1, 1]);
      }
    }
  }
}

// --- front gardens -------------------------------------------------------
/**
 * Every real house's own front plot: lawn, a paved driveway apron, a low
 * boundary wall along the lawn's kerb edge (broken where the driveway meets
 * the kerb, exactly like the reference photos — nobody walls off their own
 * drive), a foundation shrub or two by the door, and a bin.
 *
 * One procedural per-building treatment, driven directly off `BUILDINGS`'
 * own x/w/d/streetSide fields and `STREET.kerb`/`STREET.setback` — so it
 * automatically follows both the OSM-derived frontage spacing and the
 * Google Earth-calibrated street-section dimensions without this pass
 * touching `BUILDINGS` itself. The old hand-placed `SET_PIECES.gardenWalls`/
 * `hedges` sparse lists this replaced (a handful of walls scattered across
 * ~150 m, not real per-plot boundaries) have been removed from layout.js as
 * dead data. `BG*` background infill is skipped: it isn't a real addressable
 * plot (see layout.js).
 */
function frontGardens(A, rng) {
  const KB = STREET.kerb;
  for (const b of BUILDINGS) {
    if (b.id?.startsWith('BG')) continue;
    const side = b.x < 0 ? -1 : 1;
    const kerbX = side * KB;
    const faceX = b.x - side * (b.w / 2);
    const depth = Math.abs(kerbX - faceX);
    if (depth < 1.2) continue; // shouldn't happen on this map, but don't wall off a sliver
    const midX = (kerbX + faceX) / 2;
    const z0 = b.z - b.d / 2;
    const z1 = b.z + b.d / 2;
    const frontW = z1 - z0;
    if (frontW < 3.2) continue; // too narrow a frontage for a wall + drive to read

    // ---- lawn across the whole plot, then a driveway apron cut into it ----
    A.add('lawn', BOX(A), LL(IDENT, midX, 0.025, b.z, 0, depth, 0.05, frontW), {
      masks: [0.15, 0.55, 0.3],
    });
    A.box('dirt', midX, 0.02, b.z, depth, 0.05, frontW);

    const driveW = Math.min(3.4, Math.max(2.1, frontW * rng.range(0.3, 0.46)));
    const driveAtStart = rng.float() < 0.5;
    const dz0 = driveAtStart ? z0 : z1 - driveW;
    const dz1 = driveAtStart ? z0 + driveW : z1;
    const gz0 = driveAtStart ? dz1 : z0;
    const gz1 = driveAtStart ? z1 : dz0;
    A.add('concrete', BOX_SOFT(A), LL(IDENT, midX, 0.03, (dz0 + dz1) / 2, 0, depth - 0.1, 0.06, driveW - 0.06), {
      masks: [0.5, 0.4, 0.2],
    });
    A.box('concrete', midX, 0.03, (dz0 + dz1) / 2, depth, 0.06, driveW);

    // ---- low wall along the lawn's kerb edge only — the drive stays open ----
    const wallX = kerbX - side * 0.06;
    const wr = side > 0 ? -Math.PI / 2 : Math.PI / 2;
    if (gz1 - gz0 > 1.0) {
      let z = gz0 + 0.12;
      while (z < gz1 - 0.12) {
        const segLen = Math.min(rng.range(1.6, 2.4), gz1 - 0.12 - z);
        if (segLen < 0.55) break;
        const cz = z + segLen / 2;
        A.putS('garden_wall', wallX, groundY(wallX, cz), cz, wr, segLen / 2.4, rng.range(0.9, 1.05), 1);
        A.box('concrete', wallX, groundY(wallX, cz) + 0.28, cz, segLen, 0.56, 0.2, wr);
        groundSkirt(A, rng, wallX, groundY(wallX, cz), cz, 0.35, { pebbles: rng.int(1, 2), key: 'moss_verge' });
        z += segLen + rng.range(0.06, 0.2);
      }
      for (const pz of [gz0, gz1]) {
        A.put('garden_pier', wallX, groundY(wallX, pz), pz, wr, rng.range(0.95, 1.08));
      }
    }

    // ---- a foundation shrub or two near the house face, in the lawn ----
    if (gz1 - gz0 > 1.4) {
      const shrubs = rng.int(1, 2);
      for (let i = 0; i < shrubs; i++) {
        const sz = rng.range(gz0 + 0.5, gz1 - 0.5);
        const sx = faceX + side * rng.range(0.45, 0.95);
        hedgeRow(A, rng, sx, sz, rng.float() * 6.28, rng.range(0.6, 1.1), rng.range(0.4, 0.6));
      }
    }

    // ---- a bin (or two) by the driveway edge nearest the house ----
    if (rng.float() < 0.62) {
      const n = rng.float() < 0.35 ? 2 : 1;
      const bz0 = driveAtStart ? dz1 - 0.5 : dz0 + 0.5;
      for (let i = 0; i < n; i++) {
        const bx = faceX + side * rng.range(0.4, 0.9);
        const bz = bz0 + (driveAtStart ? -1 : 1) * i * 0.6;
        if (!isOpen(bx, bz, 0.2)) continue;
        A.put(rng.pick(['bin_black', 'bin_green', 'bin_brown', 'bin_blue']), bx, groundY(bx, bz), bz, rng.float() * 6.28, 1, [
          1,
          rng.range(0.95, 1.05),
          1,
        ]);
      }
    }
  }
}

/**
 * A run of clipped hedge, broken into a few blocks per run (real hedges are
 * planted in stretches, not one continuous ruled slab) with a bit of height
 * and depth jitter per block so the top line isn't dead level.
 */
export function hedgeRow(A, rng, x, z, ry, len, h = 1.0, baseY = null) {
  const y = baseY ?? groundY(x, z);
  const blockW = rng.range(0.9, 1.5);
  const n = Math.max(1, Math.round(len / blockW));
  const w = len / n;
  for (let i = 0; i < n; i++) {
    const lx = -len / 2 + (i + 0.5) * w;
    const px = x + Math.cos(ry) * lx;
    const pz = z - Math.sin(ry) * lx;
    const bh = h * rng.range(0.92, 1.08);
    A.putS('hedge', px, y, pz, ry + rng.range(-0.05, 0.05), (w * 0.98) / 2.0, bh, rng.range(0.85, 1.15));
  }
  A.box('foliage', x, y + h / 2, z, len, h, 0.5, ry);
}

// --- builder's skip -----------------------------------------------------------
/**
 * A skip outside the one house getting done up — the ordinary equivalent of
 * the old wreck. Kept to a single instance: a whole row of them would read as
 * a demolition site rather than one house mid-renovation.
 */
function builderSkips(A, rng) {
  const spots = SET_PIECES.skips.slice(0, 1);
  for (const [x, z, ry] of spots) {
    const y = groundY(x, z);
    A.put('skip', x, y, z, ry, 1, null, 0, 0);
    A.box('metal', x, y + 0.45, z, 1.9, 0.9, 2.4, ry);
    groundSkirt(A, rng, x, y, z, 0.9, { pebbles: rng.int(2, 4), key: 'moss_verge' });
    // a few offcuts and a bag of rubble beside it
    for (let i = 0; i < rng.int(3, 6); i++) {
      const px = x + rng.range(-1.6, 1.6);
      const pz = z + rng.range(-1.6, 1.6);
      if (!isOpen(px, pz, 0.2)) continue;
      A.put(
        rng.pick(['plank_a', 'plank_b', 'box_card_a', 'brick_a', 'brick_b']),
        px,
        groundY(px, pz) + 0.015,
        pz,
        rng.float() * 6.28,
        rng.range(0.7, 1.1),
        [1, 1.2, 1]
      );
    }
    A.put(rng.pick(['bin_black', 'bin_green']), x + Math.cos(ry) * 1.4, y, z - Math.sin(ry) * 1.4, rng.float() * 6.28, 1, null);
  }
}

// --- street & garden trees ----------------------------------------------------
/**
 * Ordinary deciduous street/garden trees in place of the old palms — a
 * tapered trunk, a couple of low limbs and a rough round canopy of foliage
 * cards. Ireland does not grow palms; this is the single highest-visibility
 * "wrong climate" tell in the old set.
 */
function streetTrees(A, rng) {
  for (const [x, z, s] of SET_PIECES.trees) {
    const y = groundY(x, z);
    const ry = rng.float() * 6.28;
    const h = 4.0 * s;
    A.putS('tree_trunk', x, y, z, ry, s, s, s);
    A.putS('tree_canopy', x, y + h * 0.92, z, rng.float() * 6.28, s, s * rng.range(0.85, 1.1), s, [
      1,
      rng.range(0.85, 1.15),
      1,
    ]);
    A.box('wood', x, y + h * 0.4, z, 0.4 * s, h * 0.8, 0.4 * s);
    // a ring of grass/weeds at the base, and the odd tree guard stake
    const g = patchGeometry(rng, rng.range(0.7, 1.1) * s, { lobes: 10, wobble: 0.45 });
    A.addOnce('moss_verge', g, LL(IDENT, x, y + 0.02, z, rng.float() * 6.28), { masks: [0.1, 0.7, 0.4] });
    for (let i = 0; i < rng.int(2, 5); i++) {
      const a = rng.float() * 6.28;
      const r = rng.range(0.35, 1.0) * s;
      A.put('weeds', x + Math.cos(a) * r, y + 0.02, z + Math.sin(a) * r, rng.float() * 6.28, rng.range(0.7, 1.3), [
        1,
        1.2,
        1,
      ]);
    }
  }
}

// --- street lamps -----------------------------------------------------------
function streetLamps(A, rng) {
  for (const [x, z] of SET_PIECES.lamps) {
    const y = groundY(x, z);
    // the arm must reach across the street, so face it inward
    const ry = x < 0 ? 0 : Math.PI;
    A.put('lamp_post', x, y, z, ry, 1, [1, rng.range(0.9, 1.2), 1]);
    const armX = x + Math.cos(ry) * 0.88;
    const armZ = z - Math.sin(ry) * 0.88;
    A.put('lamp_glass', armX, y + 5.33, armZ, ry, 1, null, 0, -0.16);
    A.box('metal', x, y + 2.7, z, 0.3, 5.4, 0.3);
    // the column stands in a broken square of concrete, not on a clean line
    groundSkirt(A, rng, x, y, z, 0.34, { pebbles: rng.int(3, 6) });
    A.lampAnchors.push({ x: armX, y: y + 5.3, z: armZ });
    // a hanging sign or a bundle of cable ties at head height
    if (rng.float() < 0.5) {
      A.put('sign_hang', x + Math.cos(ry) * 0.2, y + 3.4, z - Math.sin(ry) * 0.2, ry + Math.PI / 2, 1, [
        1,
        1.2,
        1,
      ]);
    }
    for (let i = 0; i < rng.int(2, 5); i++) {
      const a = rng.float() * 6.28;
      const r = rng.range(0.35, 1.1);
      const px = x + Math.cos(a) * r;
      const pz = z + Math.sin(a) * r;
      A.put(
        rng.pick(['litter', 'brick_b', 'can', 'weeds']),
        px,
        groundY(px, pz) + 0.02,
        pz,
        rng.float() * 6.28,
        rng.range(0.7, 1.2),
        [1, 1.3, 1]
      );
    }
  }
}

// --- cables, laundry --------------------------------------------------------
function overheadLines(A, rng) {
  const insulator = (x, y, z) => {
    A.add('concrete_dark', BOX_FINE(A), LL(IDENT, x, y, z, 0, 0.1, 0.16, 0.1), {
      masks: [0.6, 0.5, 0.2],
    });
  };
  for (const [x0, y0, z0, x1, y1, z1, sag] of SET_PIECES.cables) {
    const t = catenaryTube([x0, y0, z0], [x1, y1, z1], sag, 0.022, { seg: 14, radial: 4, jitter: 0.05 });
    A.addOnce('metal_dark', t, null, { masks: [0.4, 0.7, 0.2] });
    // a second, thinner line running with it — never one lonely wire
    const t2 = catenaryTube(
      [x0, y0 - 0.22, z0 + 0.18],
      [x1, y1 - 0.18, z1 + 0.2],
      sag * 1.12,
      0.014,
      { seg: 14, radial: 4, jitter: 0.06 }
    );
    A.addOnce('metal_dark', t2, null, { masks: [0.4, 0.7, 0.2] });
    insulator(x0, y0 + 0.06, z0);
    insulator(x1, y1 + 0.06, z1);
  }

  const SAG = 0.42;
  for (const [x0, y0, z0, x1, y1, z1] of SET_PIECES.laundry) {
    const line = catenaryTube([x0, y0, z0], [x1, y1, z1], SAG, 0.012, { seg: 12, radial: 4 });
    A.addOnce('metal_dark', line, null, { masks: [0.3, 0.6, 0.2] });
    const dx = x1 - x0;
    const dz = z1 - z0;
    const len = Math.hypot(dx, dz);
    const ry = Math.atan2(-dz, dx);
    const n = Math.max(2, Math.round(len / 1.7));
    const K = Math.cosh(1.5) - 1;
    for (let i = 0; i < n; i++) {
      const t = (i + 0.5) / n;
      if (rng.float() < 0.12) continue;
      // hang from the line where the line actually is: same catenary as the tube
      const droop = (Math.cosh(1.5) - Math.cosh((t - 0.5) * 3)) / K;
      const px = x0 + dx * t;
      const pz = z0 + dz * t;
      const py = y0 + (y1 - y0) * t - SAG * droop - 0.03;
      const w = rng.range(0.72, 1.15);
      const h = rng.range(0.85, 1.45);
      const cloth = clothGeometry(w, h, {
        segX: 9,
        segY: 10,
        sag: rng.range(0.18, 0.3),
        wrinkle: rng.range(0.05, 0.085),
        rng,
        twist: rng.range(0.1, 0.2),
        bulge: 0.06,
        thickness: rng.range(0.0016, 0.003),
        fray: rng.range(0.01, 0.03),
      });
      A.addOnce(
        rng.pick(['fabric_red', 'fabric_teal', 'fabric_cream', 'burlap']),
        cloth,
        LL(IDENT, px, py - h / 2 + 0.02, pz, ry, 1, 1, 1),
        { masks: [0.3, rng.range(0.4, 0.8), 0.2] }
      );
    }
  }
}

// --- front garden clutter -----------------------------------------------------
/**
 * Planters and window boxes by the front door. Reads as "someone lives here"
 * without the market-street rug-on-a-facade motif, which does not belong on
 * a Dublin semi.
 */
function frontGardenClutter(A, rng) {
  for (const [x, y, z, ry, w] of SET_PIECES.doorstepPlanters) {
    A.put('planter', x, y, z, ry, rng.range(0.9, 1.15), null);
    if (rng.float() < 0.5) {
      A.put('planter', x + Math.cos(ry + Math.PI / 2) * (w * 0.6), y, z - Math.sin(ry + Math.PI / 2) * (w * 0.6), rng.float() * 6.28, rng.range(0.7, 0.95), null);
    }
    for (let i = 0; i < rng.int(1, 3); i++) {
      const a = rng.float() * 6.28;
      const r = rng.range(0.2, 0.5);
      A.put('weeds', x + Math.cos(a) * r, y + 0.01, z + Math.sin(a) * r, rng.float() * 6.28, rng.range(0.7, 1.1), null);
    }
  }
}

// --- bin clusters --------------------------------------------------------------
/**
 * A kerbside bin store: several wheelie bins together, the everyday
 * equivalent of the old war-rubble mounds — density on the ground without
 * pretending the close has been shelled.
 */
function binClusters(A, rng) {
  const BINS = ['bin_black', 'bin_green', 'bin_brown', 'bin_blue'];
  for (const [x, z, radius, count] of SET_PIECES.binStores) {
    const y = groundY(x, z);
    const n = Math.max(2, Math.min(5, Math.round(count / 8)));
    const ry0 = rng.float() * 6.28;
    for (let i = 0; i < n; i++) {
      const lx = (i - (n - 1) / 2) * 0.62;
      const px = x + Math.cos(ry0) * lx;
      const pz = z - Math.sin(ry0) * lx;
      if (!isOpen(px, pz, 0.2)) continue;
      A.put(rng.pick(BINS), px, groundY(px, pz), pz, ry0 + Math.PI / 2 + rng.range(-0.06, 0.06), rng.range(0.95, 1.05), null);
    }
    groundSkirt(A, rng, x, y, z, radius * 0.6, { pebbles: rng.int(1, 3), key: 'moss_verge' });
    for (let i = 0; i < rng.int(1, 3); i++) {
      const px = x + rng.range(-radius, radius);
      const pz = z + rng.range(-radius, radius);
      if (!isOpen(px, pz, 0.15)) continue;
      A.put('box_card_a', px, groundY(px, pz) + 0.01, pz, rng.float() * 6.28, rng.range(0.7, 1.0), null);
    }
  }
}

/**
 * Deliberate cover clusters at chest height along the street, so the map
 * still plays: a garden wall and hedge stub to break contact behind every
 * ~12 m of open ground, in place of the old sandbag emplacements.
 */
function coverClusters(A, rng) {
  const spots = [
    [0.6, 0.9, 0.35],
    [-2.2, 8.6, 1.2],
    [2.6, -6.4, -0.4],
    [-3.0, -21.5, 0.6],
    [2.2, -33.0, 1.9],
    [-2.6, 27.5, 0.2],
  ];
  for (const [x, z, ry] of spots) {
    const y = groundY(x, z);
    const len = rng.range(1.8, 2.6);
    A.putS('garden_wall', x, y, z, ry, len / 2.4, rng.range(0.95, 1.15), 1);
    A.box('concrete', x, y + 0.28, z, len, 0.62, 0.2, ry);
    hedgeRow(A, rng, x, z + 0.3, ry, len * 0.8, 0.6);
    const bx = x + Math.cos(ry + 1.57) * 1.5;
    const bz = z - Math.sin(ry + 1.57) * 1.5;
    if (isOpen(bx, bz, 0.4)) {
      A.put(rng.pick(['bin_black', 'bin_green', 'crate_c']), bx, groundY(bx, bz), bz, rng.float() * 6.28, 1, null);
      groundSkirt(A, rng, bx, groundY(bx, bz), bz, 0.5, { pebbles: rng.int(3, 6), key: 'moss_verge' });
    }
    for (let i = 0; i < rng.int(2, 4); i++) {
      const px = x + rng.range(-2, 2);
      const pz = z + rng.range(-2, 2);
      if (!isOpen(px, pz, 0.2)) continue;
      A.put(
        rng.pick(['litter', 'can', 'weeds']),
        px,
        groundY(px, pz) + 0.02,
        pz,
        rng.float() * 6.28,
        rng.range(0.6, 1.2),
        null
      );
    }
  }
}

// =============================================================== buildings ==
/**
 * Facade services and roof clutter, driven by the anchors each building
 * returned while it was being generated.
 */
export function dressBuildings(A, rng, infos) {
  A.jitter = jitterRig();
  for (const info of infos) dressBuilding(A, rng, info);
  alleyLines(A, rng, infos);
  A.jitter = null;
}

function dressBuilding(A, rng, info) {
  const spec = info.spec;
  const top = info.roofY;

  // ---- AC units, conduit and sat dishes hung off the open facades ----
  for (const wnd of info.windows) {
    const pm = wnd.pm;
    if (wnd.f === 0) continue;
    if (rng.float() < 0.34) {
      // beside the window, bracketed off the wall
      const dx = (rng.float() < 0.5 ? -1 : 1) * (wnd.w / 2 + 0.55);
      const wp = worldOf(pm, wnd.x + dx, wnd.y - 0.35, -0.36);
      A.put('ac_unit', wp[0], wp[1], wp[2], ryOf(pm) + Math.PI, 1, [1, rng.range(0.8, 1.3), 1]);
      // condensate runs down the render below the unit: a narrow grime streak
      const runH = wnd.y - 1.1;
      if (runH > 0.5) {
        A.add(
          'plaster_sand',
          BOX_FINE(A),
          LL(pm, wnd.x + dx, wnd.y - 0.75 - runH / 2, -0.004, 0, 0.16, runH, 0.008),
          { masks: [0.0, 1.0, 0.75] }
        );
      }
    }
    if (rng.float() < 0.16) {
      const wp = worldOf(pm, wnd.x + (wnd.w / 2 + 0.4) * (rng.float() < 0.5 ? -1 : 1), wnd.y + 0.3, -0.07);
      A.put('conduit_box', wp[0], wp[1], wp[2], ryOf(pm) + Math.PI, 1, [1, 1.2, 1]);
    }
    // washing line strung across a balcony window
    if (rng.float() < 0.18) {
      const a = worldOf(pm, wnd.x - wnd.w / 2 - 0.1, wnd.y + 0.5, -0.12).slice();
      const b = worldOf(pm, wnd.x + wnd.w / 2 + 0.1, wnd.y + 0.45, -0.12).slice();
      const line = catenaryTube(a, b, 0.08, 0.008, { seg: 6, radial: 4 });
      A.addOnce('metal_dark', line, null, { masks: [0.3, 0.6, 0] });
      for (let i = 0; i < 2; i++) {
        const t = 0.3 + i * 0.4;
        const cloth = clothGeometry(rng.range(0.3, 0.5), rng.range(0.4, 0.7), {
          segX: 5,
          segY: 6,
          sag: 0.1,
          wrinkle: rng.range(0.04, 0.065),
          twist: 0.1,
          fray: 0.012,
          rng,
        });
        A.addOnce(
          rng.pick(['fabric_red', 'fabric_teal', 'fabric_cream']),
          cloth,
          LL(
            IDENT,
            a[0] + (b[0] - a[0]) * t,
            a[1] - 0.35,
            a[2] + (b[2] - a[2]) * t,
            ryOf(pm) + Math.PI / 2
          ),
          { masks: [0.35, 0.6, 0.2] }
        );
      }
    }
  }

  // ---- balconies get lived in ----
  for (const bal of info.balconies) {
    const pm = bal.pm;
    const n = rng.int(1, 4);
    for (let i = 0; i < n; i++) {
      const lx = bal.x + rng.range(-bal.w / 2 + 0.3, bal.w / 2 - 0.3);
      const lz = -rng.range(0.35, bal.d - 0.3);
      const wp = worldOf(pm, lx, bal.y + 0.13, lz);
      A.put(
        rng.pick(['crate_b', 'bucket', 'planter', 'box_card_b', 'stool', 'jerry_can', 'tyre_small']),
        wp[0],
        wp[1],
        wp[2],
        rng.float() * 6.28,
        rng.range(0.85, 1.1),
        [1, rng.range(1.0, 1.4), 1]
      );
    }
    // rug over the railing — instantly reads as inhabited
    if (rng.float() < 0.55) {
      const cloth = clothGeometry(rng.range(0.8, 1.4), rng.range(0.7, 1.1), {
        segX: 7,
        segY: 7,
        sag: 0.09,
        wrinkle: rng.range(0.04, 0.07),
        thickness: 0.0034,
        fray: rng.range(0.012, 0.03),
        rng,
      });
      const wp = worldOf(pm, bal.x + rng.range(-0.3, 0.3), bal.y + 0.95, -bal.d - 0.03);
      A.addOnce(
        rng.pick(['fabric_red', 'fabric_teal', 'fabric_cream']),
        cloth,
        LL(IDENT, wp[0], wp[1], wp[2], ryOf(pm) + Math.PI),
        { masks: [0.4, 0.55, 0.2] }
      );
    }
  }

  // ---- signage over shop and door openings ----
  for (const aw of info.awnings) {
    if (rng.float() < 0.55) {
      const wp = worldOf(aw.pm, aw.x, aw.y + 1.0, -0.16);
      A.putS('sign_board', wp[0], wp[1], wp[2], ryOf(aw.pm) + Math.PI, Math.min(1.3, aw.w / 1.6), 1, 1, [
        1,
        rng.range(0.8, 1.3),
        1,
      ]);
    }
  }
  for (const dr of info.doors) {
    if (rng.float() < 0.5) {
      const wp = worldOf(dr.pm, dr.x + rng.range(-0.2, 0.2), 2.55, -0.12);
      A.put('sign_hang', wp[0], wp[1], wp[2], ryOf(dr.pm) + Math.PI, rng.range(0.85, 1.15), [1, 1.2, 1]);
    }
    // step, mat, and the junk that lives beside a doorway
    const wp = worldOf(dr.pm, dr.x, 0.02, -0.55);
    for (let i = 0; i < rng.int(1, 4); i++) {
      const ox = wp[0] + rng.range(-1.3, 1.3);
      const oz = wp[2] + rng.range(-1.0, 1.0);
      if (!isOpen(ox, oz, 0.15)) continue;
      A.put(
        // Doorstep junk, minus the sandbag and jerry can that read as militia.
        rng.pick(['bucket', 'crate_b', 'stool', 'planter', 'litter', 'bin_black', 'planter']),
        ox,
        groundY(ox, oz),
        oz,
        rng.float() * 6.28,
        rng.range(0.85, 1.1),
        [1, rng.range(1.0, 1.4), 1]
      );
    }
  }

  // ---- roof clutter ----
  // Roofs are playable ground ONLY where `roofAccess` opens a stair onto them
  // (see buildings.js) — every other house on Kilmore Close now has a real
  // pitched, tiled roof over this flat slab, so water tanks, rusty aerials,
  // rubble and laundry lines here would be invisible AND, if they somehow
  // clipped through, exactly the industrial/war-torn skyline clutter this
  // fork has been removing everywhere else.
  if (!spec.roofAccess) return;
  // Roofs are playable ground in this map (balconies and parapets are the
  // elevation layer), so they get real density, not a token water tank.
  const rp = Math.round((spec.roofProps ?? 2) * 2.4) + 2;
  // The ROOF plate, not the ground footprint. On a setback building the two
  // differ by a couple of metres, and using the footprint hangs water tanks,
  // aerials and crate stacks in mid-air over the terrace void.
  const rs = info.roofSpec ?? spec;
  const rx0 = rs.x - rs.w / 2 + 1.0;
  const rx1 = rs.x + rs.w / 2 - 1.0;
  const rz0 = rs.z - rs.d / 2 + 1.0;
  const rz1 = rs.z + rs.d / 2 - 1.0;
  const roofY = top + 0.02;
  for (let i = 0; i < rp; i++) {
    const px = rng.range(rx0, rx1);
    const pz = rng.range(rz0, rz1);
    const pick = rng.float();
    if (pick < 0.22) {
      A.put('water_tank', px, roofY, pz, rng.float() * 6.28, rng.range(0.9, 1.15), [1, rng.range(0.9, 1.3), 1]);
      A.box('metal', px, roofY + 0.55, pz, 1.2, 1.1, 1.2);
    } else if (pick < 0.45) {
      A.put('sat_dish', px, roofY, pz, rng.float() * 6.28, rng.range(0.85, 1.15), [1, rng.range(0.8, 1.3), 1]);
    } else if (pick < 0.6) {
      A.put('roof_vent', px, roofY, pz, rng.float() * 6.28, 1, [1, 1.2, 1]);
    } else if (pick < 0.78) {
      const n = rng.int(2, 4);
      for (let k = 0; k < n; k++) {
        A.put(
          rng.pick(['crate_a', 'crate_b', 'crate_flat']),
          px + rng.range(-0.15, 0.15),
          roofY + k * 0.53,
          pz + rng.range(-0.15, 0.15),
          rng.float() * 6.28,
          1,
          [1, rng.range(1.0, 1.4), 1]
        );
      }
      A.box('wood', px, roofY + n * 0.26, pz, 0.7, n * 0.53, 0.7);
    } else {
      A.put(
        // Roof/yard clutter. tyre, barrel_rust and gas_bottle were the militia
        // set; a stool, a chair, a pallet and a water butt are ordinary.
        rng.pick(['stool', 'chair', 'crate_c', 'barrel_blue', 'pallet', 'planter']),
        px,
        roofY,
        pz,
        rng.float() * 6.28,
        1,
        [1, rng.range(1.1, 1.5), 1]
      );
    }
  }
  // dust and grit blown into the roof corners
  for (let i = 0; i < 4; i++) {
    const g = patchGeometry(rng, rng.range(0.6, 1.6), { lobes: 9, wobble: 0.5 });
    A.addOnce(
      'dirt',
      g,
      LL(IDENT, rng.range(rx0, rx1), roofY + 0.012, rng.range(rz0, rz1), rng.float() * 6.28, 1, 1, 0.7),
      { masks: [0.1, 0.85, 0.5] }
    );
  }
  for (let i = 0; i < rng.int(4, 10); i++) {
    const px = rng.range(rx0 + 0.7, rx1 - 0.7);
    const pz = rng.range(rz0 + 0.7, rz1 - 0.7);
    A.put(
      rng.pick(['brick_a', 'brick_b', 'rock_b', 'litter', 'cinder', 'can', 'plank_b']),
      px,
      roofY + 0.02,
      pz,
      rng.float() * 6.28,
      rng.range(0.6, 1.2),
      [1, 1.4, 1]
    );
  }
  // rooftop laundry line between the parapets, and rubble in a corner
  if (rs.w > 10 && rng.float() < 0.4) {
    const a = [rs.x - rs.w / 2 + 0.4, roofY + 1.0, rng.range(rz0, rz1)];
    const b = [rs.x + rs.w / 2 - 0.4, roofY + 0.96, rng.range(rz0, rz1)];
    const line = catenaryTube(a, b, 0.3, 0.01, { seg: 10, radial: 4 });
    A.addOnce('metal_dark', line, null, { masks: [0.3, 0.6, 0] });
    for (const sx of [-1, 1]) {
      A.add('metal_rust', BOX_FINE(A), LL(IDENT, rs.x + sx * (rs.w / 2 - 0.4), roofY + 0.9, a[2] + (sx > 0 ? b[2] - a[2] : 0), 0, 0.06, 1.8, 0.06), {
        masks: [0.9, 0.5, 0.1],
      });
    }
    const n = rng.int(2, 5);
    for (let i = 0; i < n; i++) {
      const t = (i + 0.5) / n;
      const cloth = clothGeometry(rng.range(0.5, 0.8), rng.range(0.45, 0.8), {
        segX: 7,
        segY: 8,
        sag: rng.range(0.12, 0.22),
        wrinkle: rng.range(0.045, 0.075),
        twist: rng.range(0.08, 0.18),
        fray: rng.range(0.01, 0.025),
        rng,
      });
      A.addOnce(
        rng.pick(['fabric_red', 'fabric_teal', 'fabric_cream', 'burlap']),
        cloth,
        LL(
          IDENT,
          a[0] + (b[0] - a[0]) * t,
          a[1] - 0.5 - 0.22 * Math.sin(t * Math.PI),
          a[2] + (b[2] - a[2]) * t,
          0
        ),
        { masks: [0.3, rng.range(0.4, 0.8), 0.2] }
      );
    }
  }
  if (rng.float() < 0.6) {
    rubbleMound(A, rng, rng.range(rx0, rx1), roofY, rng.range(rz0, rz1), rng.range(0.7, 1.3), rng.int(8, 16), {
      key: 'concrete_dark',
    });
  }
  // aerials: thin, tall, and they do a lot for a skyline
  for (let i = 0; i < rng.int(1, 3); i++) {
    const px = rng.range(rx0, rx1);
    const pz = rng.range(rz0, rz1);
    const h = rng.range(1.4, 3.2);
    const pipe = A.cache('aerial', () => tubeY(0.018, 1, { radial: 5 }));
    A.add('metal_rust', pipe, LL(IDENT, px, roofY, pz, 0, 1, h, 1), { masks: [0.9, 0.5, 0.1] });
    for (let k = 0; k < 4; k++) {
      A.add(
        'metal_rust',
        pipe,
        LL(IDENT, px, roofY + h * (0.5 + k * 0.11), pz, rng.float() * 3.14, 1, rng.range(0.25, 0.5), 1, 0, Math.PI / 2),
        { masks: [0.9, 0.5, 0.1] }
      );
    }
  }
}

/** Cables and washing lines strung across the alleys between buildings. */
function alleyLines(A, rng, infos) {
  const spans = [
    [-6.6, 5.0, 21.0, -6.6, 5.4, 24.0],
    [-6.6, 4.2, -9.0, -6.6, 4.6, -11.5],
    [7.0, 4.6, 2.5, 7.0, 4.2, 6.6],
    [7.0, 5.6, -16.0, 7.0, 5.2, -20.0],
    [-8.0, 6.4, 20.6, -8.0, 6.0, 23.8],
    [8.6, 6.2, 2.2, 8.6, 5.8, 7.2],
  ];
  for (const [x0, y0, z0, x1, y1, z1] of spans) {
    const t = catenaryTube([x0, y0, z0], [x1, y1, z1], 0.5, 0.016, { seg: 10, radial: 4, jitter: 0.04 });
    A.addOnce('metal_dark', t, null, { masks: [0.4, 0.7, 0.2] });
    const n = rng.int(2, 4);
    for (let i = 0; i < n; i++) {
      const f = (i + 0.5) / n;
      const cloth = clothGeometry(rng.range(0.45, 0.8), rng.range(0.5, 1.0), {
        segX: 6,
        segY: 8,
        sag: rng.range(0.12, 0.22),
        wrinkle: rng.range(0.045, 0.075),
        twist: rng.range(0.08, 0.18),
        fray: rng.range(0.01, 0.025),
        rng,
      });
      A.addOnce(
        rng.pick(['fabric_red', 'fabric_teal', 'fabric_cream', 'burlap']),
        cloth,
        LL(
          IDENT,
          x0 + (x1 - x0) * f,
          y0 + (y1 - y0) * f - 0.6 - 0.4 * Math.sin(f * Math.PI),
          z0 + (z1 - z0) * f,
          Math.atan2(-(z1 - z0), x1 - x0)
        ),
        { masks: [0.3, rng.range(0.4, 0.8), 0.2] }
      );
    }
  }
}

// ============================================================== the scatter ==
/**
 * The final pass: several hundred small instanced props biased toward wall
 * bases and kerbs, because that is where wind, water and people put things.
 * Empty ground is what makes a level read as a WebGL demo.
 */
export function scatterDebris(A, rng) {
  const { zMin, zMax, kerb } = STREET;
  A.jitter = jitterRig();

  // --- against the building line, both sides of the street ---
  // 340 was a war-damaged market street's worth of masonry. A lived-in close
  // collects litter, weeds and the odd bottle against a wall — not bricks,
  // cinder blocks, broken slabs and planks — so both the count and the
  // vocabulary come down. The gaussian falloff below is unchanged: where things
  // collect is right, it was only ever what collects that was wrong.
  for (let i = 0; i < 120; i++) {
    const side = rng.float() < 0.5 ? -1 : 1;
    const z = rng.range(zMin + 1, zMax - 1);
    // exponential falloff away from the wall
    const off = 0.12 + Math.abs(rng.gauss()) * 0.75;
    const x = side * (kerb - off);
    if (!isOpen(x, z, 0.05)) continue;
    const y = groundY(x, z);
    const pick = rng.float();
    let id;
    if (pick < 0.34) id = 'litter';
    else if (pick < 0.62) id = 'weeds';
    else if (pick < 0.78) id = rng.pick(['can', 'bottle']);
    else if (pick < 0.9) id = rng.pick(['box_card_a', 'box_card_b']);
    else id = rng.pick(['bucket', 'crate_b']);
    A.put(id, x, y + 0.015, z, rng.float() * 6.28, rng.range(0.65, 1.25), [
      1,
      rng.range(1.0, 1.5),
      1,
    ]);
  }

  // --- the road surface: sparser, and pushed to the gutters ---
  for (let i = 0; i < 70; i++) {
    const x = rng.range(-STREET.halfWidth + 0.1, STREET.halfWidth - 0.1) * (0.45 + 0.55 * Math.abs(rng.signed()));
    const z = rng.range(zMin + 1, zMax - 1);
    if (!isOpen(x, z, 0.05)) continue;
    A.put(
      // rock/brick on the carriageway read as shelling debris; gutter litter,
      // a can and weeds through the joints are what a real road carries.
      rng.pick(['litter', 'can', 'litter', 'weeds', 'litter', 'bottle', 'weeds']),
      x,
      groundY(x, z) + 0.012,
      z,
      rng.float() * 6.28,
      rng.range(0.6, 1.15),
      [1, rng.range(1.0, 1.5), 1]
    );
  }

  // --- alleys: denser, junkier ---
  for (const a of ALLEYS) {
    const [x0, z0, x1, z1] = a.rect;
    const area = (x1 - x0) * (z1 - z0);
    const n = Math.round(area * 0.85);
    for (let i = 0; i < n; i++) {
      const x = rng.range(x0 + 0.3, x1 - 0.3);
      const z = rng.range(z0 + 0.3, z1 - 0.3);
      if (inBuilding(x, z, 0.25)) continue;
      const near = nearestWall(x, z);
      const wallBias = near.d < 1.2 ? 1 : 0.45;
      if (rng.float() > wallBias) continue;
      const pick = rng.float();
      let id;
      // Alleys and rear lanes legitimately stay the junkiest ground in the
      // level — a back lane really does collect crates, a pallet, an old
      // barrel. What goes is the demolition vocabulary (cinder, slab_shard,
      // rebar) and the militia one (jerry_can, gas_bottle, rusted drums);
      // weeds and shrub take the freed weight, since an unswept lane greens up.
      if (pick < 0.2) id = 'litter';
      else if (pick < 0.34) id = rng.pick(['weeds', 'shrub']);
      else if (pick < 0.46) id = rng.pick(['rock_a', 'rock_b']);
      else if (pick < 0.56) id = 'weeds';
      else if (pick < 0.64) id = 'shrub';
      else if (pick < 0.72) id = rng.pick(['plank_a', 'plank_b']);
      else if (pick < 0.8) id = rng.pick(['crate_a', 'crate_b', 'crate_flat', 'pallet']);
      else if (pick < 0.86) id = rng.pick(['barrel_blue', 'barrel_wood']);
      else if (pick < 0.9) id = rng.pick(['bin_black', 'bin_green']);
      else if (pick < 0.95) id = rng.pick(['box_card_a', 'box_card_b', 'bucket', 'planter']);
      else id = rng.pick(['weeds', 'litter', 'bottle']);
      const y = groundY(x, z);
      A.put(id, x, y + 0.015, z, rng.float() * 6.28, rng.range(0.7, 1.2), [
        1,
        rng.range(1.0, 1.5),
        1,
      ]);
      // big items get a collision box; scatter does not
      if (id.startsWith('barrel')) A.box('metal', x, y + 0.45, z, 0.62, 0.9, 0.62);
      else if (id.startsWith('crate')) A.box('wood', x, y + 0.3, z, 0.62, 0.6, 0.62);
    }
    // a skip-load of rubble at one end of each alley
    if (rng.float() < 0.7) {
      const bx = rng.float() < 0.5 ? x0 + 1.6 : x1 - 1.6;
      const bz = rng.range(z0 + 1.2, z1 - 1.2);
      if (!inBuilding(bx, bz, 0.4)) rubbleMound(A, rng, bx, groundY(bx, bz), bz, rng.range(0.9, 1.8), rng.int(12, 24));
    }
  }

  // --- vegetation in the cracks: kerb line, wall bases, alley corners ---
  for (let i = 0; i < 220; i++) {
    const side = rng.float() < 0.5 ? -1 : 1;
    const z = rng.range(zMin + 1, zMax - 1);
    const atKerb = rng.float() < 0.55;
    const x = atKerb
      ? side * (STREET.halfWidth + rng.range(0.02, 0.3))
      : side * (kerb - rng.range(0.05, 0.35));
    if (!isOpen(x, z, 0.02)) continue;
    A.put(
      rng.float() < 0.78 ? 'weeds' : 'shrub',
      x,
      groundY(x, z) + 0.01,
      z,
      rng.float() * 6.28,
      rng.range(0.6, 1.25),
      [1, rng.range(1.0, 1.4), 1]
    );
  }

  // --- glass under every blown-out window is handled per-building; here we
  //     add the sun-bleached litter drifts that collect in corners ---
  for (let i = 0; i < 60; i++) {
    const side = rng.float() < 0.5 ? -1 : 1;
    const z = rng.range(zMin + 2, zMax - 2);
    const x = side * (kerb - rng.range(0.1, 0.5));
    if (!isOpen(x, z, 0.05)) continue;
    const g = patchGeometry(rng, rng.range(0.3, 0.8), { lobes: 8, wobble: 0.6 });
    A.addOnce('dirt', g, LL(IDENT, x, groundY(x, z) + 0.01, z, rng.float() * 6.28, 1, 1, 0.6), {
      masks: [0.1, 0.95, 0.7],
    });
    for (let k = 0; k < rng.int(2, 6); k++) {
      A.put(
        'litter',
        x + rng.range(-0.5, 0.5),
        groundY(x, z) + 0.02,
        z + rng.range(-0.6, 0.6),
        rng.float() * 6.28,
        rng.range(0.7, 1.2),
        [1, 1.5, 1]
      );
    }
  }
  A.jitter = null;
}

// ================================================================ the gate ==
/**
 * A deep opening in the terminator mass: a recessed panel with a genuinely dark
 * back plane and a lintel over it. Used for the loggia arcade and the tower's
 * window band — an opening you can see INTO is the cheapest way to prove a wall
 * has thickness, and a run of them breaks up the largest flat surface in the
 * frame without adding a single extra draw call.
 */
function gateAperture(A, rng, x, y, z, w, h, t, opts = {}) {
  // The street runs down -Z and every hero camera looks along it, so +Z is the
  // face that matters: the north elevation is the one in every frame.
  const zf = z + t / 2;
  const rec = opts.recess ?? 0.5;
  // the void: dark, set well back, so the reveal shadows across it
  A.add('window_void', BOX(A), LL(IDENT, x, y, zf - rec - 0.06, 0, w, h, 0.12), {
    masks: [0.15, 0.95, 1.0],
  });
  // reveal: four returns boxing the void in, in shadow all afternoon
  A.add('concrete_dark', BOX(A), LL(IDENT, x, y + h / 2 + 0.07, zf - rec / 2, 0, w + 0.3, 0.14, rec), {
    masks: [0.3, 0.85, 0.9],
  });
  A.add('concrete_dark', BOX(A), LL(IDENT, x, y - h / 2 - 0.07, zf - rec / 2, 0, w + 0.3, 0.14, rec), {
    masks: [0.55, 0.75, 0.7],
  });
  for (const s of [-1, 1]) {
    A.add(
      'concrete_dark',
      BOX(A),
      LL(IDENT, x + s * (w / 2 + 0.07), y, zf - rec / 2, 0, 0.14, h, rec),
      { masks: [0.3, 0.8, 0.85] }
    );
  }
  // stone lintel / arch head standing proud of the wall face
  A.add('concrete', BOX_SOFT(A), LL(IDENT, x, y + h / 2 + 0.16, zf + 0.09, 0, w + 0.5, 0.2, 0.34), {
    masks: [0.7, 0.5, 0.25],
  });
  if (opts.sill !== false) {
    A.add('concrete', BOX_SOFT(A), LL(IDENT, x, y - h / 2 - 0.1, zf + 0.12, 0, w + 0.44, 0.11, 0.42), {
      masks: [0.55, 0.45, 0.3],
    });
  }
  // a shutter or a rag hanging in some of them: nothing is uniform
  if (rng.float() < 0.4) {
    A.add(
      'metal_rust',
      BOX(A),
      LL(
        IDENT,
        x + rng.range(-0.1, 0.1),
        y - h * 0.1,
        zf - 0.14,
        0,
        w * rng.range(0.5, 0.9),
        h * rng.range(0.4, 0.8),
        0.03
      ),
      { masks: [0.9, 0.6, 0.2] }
    );
  }
}

/**
 * An irregular crenellated run.
 *
 * A merlon run at a perfectly regular pitch, all one height, all one value, is
 * the single loudest "untextured blockout" tell there is. This walks the run
 * with varied widths, varied gaps, varied heights, a few leaning, a few sheared
 * off level with the walkway, exposed clay block where the render has spalled
 * off the corners, and a coping course under the whole thing so the crenels
 * throw a hard shadow line back onto the wall.
 */
function merlonRun(A, rng, x0, x1, z, t, yTop, opts = {}) {
  const key = opts.key ?? 'plaster_sand';
  const dt = t * (opts.depth ?? 0.45);
  const zc = z + t / 2 - dt / 2 - (opts.set ?? 0.06); // set back from the +Z face
  // coping course the merlons stand on, proud of the wall on both faces
  A.add('concrete', BOX_SOFT(A), LL(IDENT, (x0 + x1) / 2, yTop + 0.07, z, 0, x1 - x0, 0.14, t + 0.3), {
    masks: [0.85, 0.4, 0.15],
  });
  let x = x0 + rng.range(0.05, 0.35);
  while (x < x1 - 0.4) {
    const w = Math.min(rng.range(0.62, 1.35), x1 - 0.1 - x);
    if (w < 0.3) break;
    const broken = rng.float() < 0.22;
    const h = broken ? rng.range(0.16, 0.42) : rng.range(0.62, 1.15);
    const cx = x + w / 2;
    const lean = rng.range(-0.035, 0.035);
    A.add(key, BOX(A), LL(IDENT, cx, yTop + 0.14 + h / 2, zc, 0, w, h, dt, 0, lean), {
      masks: [0.55, 0.45, 0.2],
    });
    A.box('concrete', cx, yTop + 0.14 + h / 2, zc, w, h, dt);
    // a cap stone on some, and spalled render showing the clay block beneath
    if (!broken && rng.float() < 0.55) {
      A.add('concrete', BOX_SOFT(A), LL(IDENT, cx, yTop + 0.16 + h, zc, 0, w + 0.1, 0.07, dt + 0.1), {
        masks: [0.9, 0.35, 0.1],
      });
    }
    if (rng.float() < 0.45) {
      const g = spallPatch(rng, w * rng.range(0.3, 0.62), h * rng.range(0.25, 0.55), 0.02);
      A.addOnce(
        'brick_fine',
        g,
        LL(IDENT, cx + rng.range(-w * 0.2, w * 0.2), yTop + 0.14 + h * rng.range(0.3, 0.7), zc + dt / 2 - 0.013)
      );
    }
    x += w + rng.range(0.34, 0.95);
  }
}

/**
 * The map edge — now an INVISIBLE boundary.
 *
 * This used to raise a continuous 3.0-3.8 m compound wall right around the
 * level. On a Middle-Eastern market street that read as a walled compound; on a
 * Dublin residential close it read as a prison yard, and it flatly contradicted
 * ROAD_ENDS, where both street ends are documented as opening onto real roads
 * (Kilmore Avenue north, Beechlawn Avenue south). So the wall mesh is gone and
 * only the collider ring remains: the player is stopped in exactly the same
 * place, but nothing draws.
 *
 * STOPGAP, not a finish. An invisible wall is honest about the boundary's
 * position and dishonest about its existence — walk into it and nothing
 * explains why you stopped. The real answer is a far-field treatment (fence
 * and hedgerow lines, rear-garden walls, distant terrain) so the edge reads as
 * something rather than as nothing. That belongs to a later dressing pass; this
 * one only removes what was wrong.
 */
export function buildPerimeter(A, rng) {
  // The compound wall has to sit outside the real ~253 m OSM street length
  // (STREET.zMin..zMax) and the BG* background infill either side of it —
  // R=58 was left over from the old ~104 m fictional market street and cut
  // straight across the lane around KW9/KW10 (z~90-110) once the street was
  // rescaled to real OSM length, walling off the middle of a street whose
  // ends are supposed to read as open. Margins clear the widest BG infill
  // (BGE2 reaches x=36; BGN2/BGS2 reach z=234/z=-64) and both real
  // zMin/zMax with room to spare.
  const RX = 44;
  const ZN = STREET.zMin - 30;
  const ZX = STREET.zMax + 30;
  const segs = [
    // [x0,z0,x1,z1] runs of compound wall
    [-RX, ZN, RX, ZN],
    [-RX, ZX, RX, ZX],
    [-RX, ZN, -RX, ZX],
    [RX, ZN, RX, ZX],
  ];
  for (const [x0, z0, x1, z1] of segs) {
    const dx = x1 - x0;
    const dz = z1 - z0;
    const len = Math.hypot(dx, dz);
    const ry = Math.atan2(dx, dz) - Math.PI / 2;
    const n = Math.round(len / 4);
    for (let i = 0; i < n; i++) {
      const t = (i + 0.5) / n;
      const px = x0 + dx * t;
      const pz = z0 + dz * t;
      const h = rng.range(3.0, 3.8);
      // The wall MESH is gone — see the note on this function. Only the collider
      // below survives, so the boundary still stops the player.
      //
      // This draw is dead but deliberate: buildPerimeter runs before every other
      // dressing pass (world/index.js), so removing a draw from the shared
      // placement stream would shift the position of every prop in the level and
      // walk them through the SHOT_CLEAR camera keepouts. Keeping the pick keeps
      // the stream — and therefore every downstream position — byte-identical.
      rng.pick(['plaster_sand', 'plaster_cream', 'concrete']);
      A.box('concrete', px, h / 2, pz, len / n + 0.05, h, 0.45, ry);
    }
  }
}
