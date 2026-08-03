/**
 * AI — a bicycle, for Angela Carpenter.
 *
 * Built in the actor's bind space (metres, feet on y = 0, facing +Z) exactly
 * like every part in parts.js, so it can be handed to the CharacterBuilder and
 * skinned like anything else.
 *
 * IT BINDS TO `Hips`, as one rigid piece. A bicycle is not anatomy: it does not
 * deform, and the rider's pelvis is the one part of them genuinely fixed
 * relative to the frame. Splitting it across bones would make it flex as she
 * pedals.
 *
 * KNOWN LIMITATION: the wheels do not turn. Spinning them needs two extra bones
 * in rig.js, and rig.js is what every part's bind position is authored against,
 * so adding bones there has a long blast radius. At the distance this is seen —
 * crossing the far end of a 253 m street — a spoked wheel is a grey disc either
 * way. Up close it will read as wrong, and that is the trade being made.
 *
 * Real dimensions: 26" wheels (0.66 m), 1.05 m wheelbase, ~0.92 m saddle.
 */

import * as THREE from 'three';
import {
  emptyMesh, loft, tube, revolve, ellipseProfile, appendMesh, computeNormals,
  displace, transformMesh,
} from './geo.js';

const WHEEL_R = 0.33;
const WHEELBASE = 1.05;
/** Bottom bracket height — where the cranks turn. */
const BB_Y = 0.27;

/**
 * A straight frame tube between two points.
 *
 * `tube()` takes a profile FUNCTION of (t, i), not an array — passing the array
 * silently produces nothing, which is exactly the kind of thing that only shows
 * up as a missing bike.
 */
function frameTube(a, b, r) {
  const prof = ellipseProfile(r, r, 8);
  const m = tube([a, b], () => prof, { capStart: true, capEnd: true });
  computeNormals(m);
  return m;
}

/**
 * One wheel, standing in the YZ plane so it rolls along +Z.
 *
 * `revolve()` only ever revolves about +Y, giving a torus lying flat in XZ. A
 * bicycle wheel's plane contains the direction of travel and up, so the flat
 * ring is rotated 90 degrees about Z to stand it upright, then moved onto its
 * axle.
 */
function wheel(z) {
  const out = emptyMesh();
  const N = 10;
  const prof = [];
  for (let i = 0; i <= N; i++) {
    const a = (i / N) * Math.PI * 2;
    prof.push([WHEEL_R + Math.cos(a) * 0.019, Math.sin(a) * 0.019]);
  }
  const ring = revolve(prof, 20, { capStart: false, capEnd: false });
  const M = new THREE.Matrix4()
    .makeRotationZ(Math.PI / 2)
    .premultiply(new THREE.Matrix4().makeTranslation(0, WHEEL_R, z));
  computeNormals(ring);
  transformMesh(ring, M);
  appendMesh(out, ring);

  // hub
  appendMesh(out, frameTube([-0.03, WHEEL_R, z], [0.03, WHEEL_R, z], 0.018));

  // Eight spokes, not thirty-two: at any distance this is seen the wheel reads
  // as a dark disc with structure, and thin tubes nobody resolves are geometry
  // spent for nothing.
  for (let s = 0; s < 8; s++) {
    const a = (s / 8) * Math.PI * 2;
    appendMesh(out, frameTube(
      [0, WHEEL_R, z],
      [0, WHEEL_R + Math.sin(a) * (WHEEL_R - 0.02), z + Math.cos(a) * (WHEEL_R - 0.02)],
      0.0035
    ));
  }
  return out;
}

/**
 * @param nz      TileNoise, for the same light surface break-up every part gets
 * @param p.hipY  the rider's Hips height in bind space — the saddle meets it
 */
export function buildBicycle(nz, p = {}) {
  const out = emptyMesh();
  const hipY = p.hipY ?? 1.0;
  const zF = WHEELBASE * 0.5;
  const zR = -WHEELBASE * 0.5;
  const saddleY = hipY - 0.06;

  appendMesh(out, wheel(zF));
  appendMesh(out, wheel(zR));

  /* ---- frame: a step-through, which is what she would actually ride ---- */
  const bb = [0, BB_Y, zR + 0.30];
  const head = [0, saddleY + 0.02, zF - 0.16];
  const seatTop = [0, saddleY, zR + 0.16];
  appendMesh(out, frameTube(bb, seatTop, 0.019)); // seat tube
  appendMesh(out, frameTube(seatTop, head, 0.017)); // sloping top tube
  appendMesh(out, frameTube(bb, head, 0.019)); // down tube
  appendMesh(out, frameTube(bb, [0, WHEEL_R, zR], 0.013)); // chain stay
  appendMesh(out, frameTube(seatTop, [0, WHEEL_R, zR], 0.012)); // seat stay
  appendMesh(out, frameTube(head, [0, WHEEL_R, zF], 0.015)); // fork

  /* ---- saddle ---- */
  const saddle = loft(
    [
      { pts: ellipseProfile(0.030, 0.016, 10), o: [0, saddleY, zR + 0.10] },
      { pts: ellipseProfile(0.075, 0.022, 10), o: [0, saddleY + 0.012, zR + 0.20] },
      { pts: ellipseProfile(0.055, 0.018, 10), o: [0, saddleY + 0.010, zR + 0.27] },
    ],
    { capStart: true, capEnd: true }
  );
  computeNormals(saddle);
  appendMesh(out, saddle);

  /* ---- swept-back handlebars ---- */
  const barY = saddleY + 0.10;
  const barZ = zF - 0.13;
  appendMesh(out, frameTube(head, [0, barY, barZ], 0.015)); // stem
  for (const side of [-1, 1]) {
    appendMesh(out, frameTube([0, barY, barZ], [side * 0.20, barY, barZ - 0.02], 0.014));
    appendMesh(out, frameTube(
      [side * 0.20, barY, barZ - 0.02],
      [side * 0.24, barY - 0.01, barZ - 0.10],
      0.014
    ));
  }

  /* ---- cranks and pedals, opposed so the legs alternate ---- */
  for (const side of [-1, 1]) {
    const px = side * 0.075;
    const pedalY = BB_Y + side * 0.14;
    const pedalZ = bb[2] - side * 0.02;
    appendMesh(out, frameTube([px * 0.5, BB_Y, bb[2]], [px, pedalY, pedalZ], 0.010));
    appendMesh(out, frameTube([px - 0.02, pedalY, pedalZ], [px + 0.02, pedalY, pedalZ], 0.016));
  }

  computeNormals(out);
  displace(out, (x, y, z) => nz.fbm3(x * 90, y * 90, z * 90, 2) * 0.0008);
  computeNormals(out);
  return out;
}

/** Where the rider's hands and feet go, for the cycling pose. */
export const BIKE_ANCHORS = {
  barHalfWidth: 0.24,
  pedalRadius: 0.14,
  bbZ: -WHEELBASE * 0.5 + 0.30,
  bbY: BB_Y,
};
