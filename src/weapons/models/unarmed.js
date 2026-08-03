import { Assembly } from '../geometry.js';

/**
 * UNARMED — David's fists.
 *
 * There is no weapon geometry here, but this still has to be a complete model
 * DESCRIPTOR rather than a bare Object3D: `Viewmodel.addWeapon` calls
 * `model.body.build()` and `buildClips` dereferences `nodes.gripL`,
 * `nodes.magSeat.pos` and friends unconditionally. Handing it anything less
 * throws inside `init()`, and `core/engine.js` does not guard system init — so
 * the whole game fails to boot on a black screen.
 *
 * `body` is therefore a real but EMPTY Assembly: `build()` returns an empty
 * map, the loop over it does nothing, and the weapon group renders zero
 * triangles. The hands are drawn by `hands.js` off the grip nodes, so those
 * nodes still have to describe something sensible — here, two loose fists held
 * at roughly the ready position rather than wrapped around a grip.
 *
 * Positions are in the same weapon-local frame as the other models: +Z is
 * rearward toward the shooter, Y is up, X is the shooter's right. Wrist
 * targets, not palms (see models/rifle.js for the derivation).
 */
export function buildUnarmed() {
  const body = new Assembly();

  return {
    id: 'unarmed',
    label: 'Fists',
    fxClass: 'melee',
    body,
    // Nothing cycles, reciprocates or detaches on a fist.
    moving: {},
    nodes: {
      // `muzzle` is where `weapons` reports the strike as originating and where
      // `fx` would hang an effect. Put it out at the knuckles of the leading
      // hand rather than at the origin.
      muzzle: [0.02, 0.0, -0.13],
      chamber: [0, 0, 0],
      eject: [0, 0, 0],
      ejectDir: [0, 1, 0],
      // No optic. The sight axis still has to exist so the ADS solve has
      // something to align, even though `unarmed` never actually aims.
      sight: [0, 0.02, -0.04],
      sightAxis: [0, 0, -1],
      ironSight: [0, 0.02, -0.04],
      // Both fists, roughly shoulder-width, the right slightly forward.
      gripR: {
        pos: [0.035, 0.0, 0.045],
        finger: [0, -0.2, -0.98],
        back: [0.97, 0.1, -0.22],
      },
      gripL: {
        pos: [-0.045, -0.015, 0.075],
        finger: [0.28, -0.24, -0.93],
        back: [0.18, 0.94, -0.29],
      },
      // Reload machinery never runs for a melee weapon (magSize is 0 and
      // `tryFire` branches to `_meleeStrike` before any feed logic), but
      // `buildClips` reads these while constructing the clip table, so they
      // have to be present and finite.
      magSeat: { pos: [0, -0.03, 0.02], rot: [0, 0, 0] },
      magDrop: [0, -0.4, 0.05],
      triggerPivot: { pos: [0, -0.01, -0.015], rot: [0, 0, 0] },
      triggerPull: 0,
    },
    shell: { caseLen: 0.0001, rimR: 0.0001 },
    magSize: { len: 0.001, w: 0.001, d: 0.001 },
  };
}
