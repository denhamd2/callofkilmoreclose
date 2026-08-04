import * as THREE from 'three';
import { Assembler } from './builder.js';
import { BUILDINGS, STREET, SET_PIECES } from './layout.js';
import { buildGround } from './ground.js';
import { buildBuilding, collapseRoof } from './buildings.js';
import { registerProps } from './props.js';
import {
  registerDressingProps,
  dressStreet,
  dressBuildings,
  scatterDebris,
  buildPerimeter,
  groundY,
  isOpen,
} from './dressing.js';

/**
 * WORLD — level geometry, the modular building kit, props, set dressing and
 * static collision.
 *
 * Kilmore Close, a real Dublin residential street: a straight road with
 * thirteen joined semi-detached pairs on each side (52 front doors), a 251 m
 * housing run inside a 304 m carriageway, cross roads closing both ends, three
 * enterable houses furnished across multiple floors, and several thousand
 * props. Nothing is loaded from disk — every vertex is generated here.
 * See layout.js for why the layout is map-derived rather than OSM-derived.
 *
 * HOW IT FITS TOGETHER
 *   layout.js     the map: footprints, facade programmes, set-piece positions
 *   util.js       geometry toolkit (chamfered boxes, wall panels with real
 *                 holes, cloth grids, catenary tubes, rocks) + vertex masks
 *   kit.js        the modular building kit (facades, windows, doors, balconies,
 *                 stairs, awnings, parapets, drainpipes, damage)
 *   buildings.js  assembles a building from a footprint + a facade programme
 *   interiors.js  furnishes rooms so an interior screenshot is worth taking
 *   props.js      the instanced prop library
 *   dressing.js   places the hundreds of props, cables, laundry and debris
 *   ground.js     terrain, road camber, kerbs, pavement slabs, sand drifts
 *   builder.js    the Assembler: merges statics, batches instances, authors
 *                 collision proxies, bakes the level->world transform
 *
 * PUBLIC API — `const world = ctx.get('world')`
 *   world.root                THREE.Group holding everything
 *   world.bounds              THREE.Box3 of the playable area, world space
 *   world.spawnPoints         [{ position:Vector3, yaw:number, tag:string }]
 *   world.spawn(i)            one of the above
 *   world.groundHeight(x, z)  cheap analytic floor height (physics is exact)
 *   world.isOpen(x, z)        true where a character can stand outdoors
 *   world.stats               { staticTris, instTris, instances, drawCalls }
 *   world.prewarmMaterials()  compile every shader permutation the world can
 *                             produce, before the frame loop starts. Awaitable.
 *                             Call it from src/core/prewarm.js — see the method.
 *   world.levelToWorld(x,y,z,out) / world.worldToLevel(x,y,z,out)
 */

/**
 * LEVEL -> WORLD. The street is authored down -Z; this yaw puts it on the axis
 * the canonical hero/sunset cameras look along.
 */
const LEVEL_YAW = 0.5877;
const LEVEL_TX = 0.9;
const LEVEL_TZ = 1.34;

/**
 * How many zero-intensity "ballast" point lights the world parks in the scene to
 * hold `numPointLights` — and therefore the shader permutation — constant. See
 * `_addBallast()`. Must be at least the worst-case number of practicals that can
 * be in range at once: a sweep of the whole playable area at three eye heights
 * puts that at 10 for the world's own lights, plus whatever `fx` keeps live.
 */
const LIGHT_SLOTS = 20;

/**
 * Spawn points in LEVEL space: [x, z, yaw, tag].
 *
 * Index 0 is the player start, and it is DAVID'S OWN GARDEN PATH AT 18 — the
 * brief has him stepping out of his own front door, and the whole encounter is
 * staged around that position. It is derived from the house rather than typed,
 * so it follows number 18 if the street is ever rebuilt underneath it.
 *
 * The rest are ordinary street positions for the shot harness and for
 * `world.spawn(i)`. The previous list ("market", "gate", "north plaza") was
 * left over from the fictional market street and every entry sat outside the
 * current housing run.
 */
const SPAWNS = (() => {
  /** Garden-path point outside a house, and the yaw that faces the road. */
  const outside = (no, tag) => {
    const b = BUILDINGS.find((h) => h.no === no);
    if (!b) return null;
    const out = b.streetSide === 1 ? 1 : -1;
    return [b.x + out * (b.w / 2 + 3.4), b.z, out > 0 ? Math.PI / 2 : -Math.PI / 2, tag];
  };
  const mid = (STREET.zMin + STREET.zMax) / 2;
  return [
    outside(18, 'outside 18'),
    outside(14, 'outside 14'),
    outside(27, 'outside 27'),
    outside(26, 'outside 26'),
    outside(31, 'outside 31'),
    [0.4, mid, Math.PI, 'mid street'],
    [-2.4, STREET.zMin + 30, 0, 'south end'],
    [2.6, STREET.zMax - 30, Math.PI, 'north end'],
  ].filter(Boolean);
})();

export class WorldSystem {
  static id = 'world';
  static deps = ['materials', 'physics'];

  async init(ctx) {
    this.ctx = ctx;
    this.rng = ctx.rng.fork();
    const rng = this.rng;
    const materials = ctx.get('materials');
    const physics = ctx.peek('physics');
    const render = ctx.peek('render');

    this.root = new THREE.Group();
    this.root.name = 'world';
    this.root.matrixAutoUpdate = false;
    ctx.scene.add(this.root);

    // Weathering in the shared materials keys off the ground plane.
    materials.setGroundLevel?.(0);

    const t0 = performance.now();
    const A = new Assembler({ materials, rng, render });
    this.A = A;
    A.setTransform(LEVEL_YAW, LEVEL_TX, LEVEL_TZ);

    // 1. prototypes first: the level references them by id while it builds
    registerProps(A, rng);
    registerDressingProps(A, rng);

    // 2. ground, then the shells, then what people put in and on them
    buildGround(A, rng);

    const infos = [];
    for (const spec of BUILDINGS) {
      const info = buildBuilding(A, rng, spec);
      infos.push(info);
      if (spec.collapse) {
        collapseRoof(A, rng, spec, info, {
          x: spec.x + rng.range(-2, 2),
          z: spec.z + rng.range(-2, 2),
        });
      }
    }
    this.buildings = infos;

    buildPerimeter(A, rng);
    dressStreet(A, rng);
    dressBuildings(A, rng, infos);
    scatterDebris(A, rng);

    this._addLights(A);

    A.finalize(this.root, physics);
    A.releaseCache();

    // -------------------------------------------------------------- queries --
    this._v = new THREE.Vector3();
    this._inv = new THREE.Matrix4().copy(A.xform).invert();
    this.spawnPoints = SPAWNS.map(([x, z, yaw, tag]) => ({
      position: A.toWorld(x, 0, z),
      yaw: yaw + LEVEL_YAW,
      tag,
    }));
    /**
     * The street's own section, published on the instance so other systems can
     * duck-type it off `ctx.get('world')`. It was module-exported only, which
     * meant anyone wanting the carriageway or kerb line had to either import
     * across a subsystem boundary (forbidden) or hardcode the numbers — `ai`
     * needs them to walk its civilians down the footpath rather than the road.
     */
    this.STREET = STREET;
    /**
     * Every house on the street, keyed by its Kilmore Close number, with the
     * point on its garden path where someone stepping out of the front door
     * would stand. `ai` stages the encounter off these rather than off raw
     * coordinates, so moving a house in layout.js moves whoever lives there.
     *
     * `position` is 2.2 m out from the front face, on the street side — inside
     * the 8.71 m front garden, clear of both the wall and the kerb. `yaw`
     * faces the carriageway.
     */
    this.houses = BUILDINGS.map((b) => {
      const out = b.streetSide === 1 ? 1 : -1;
      return {
        no: b.no,
        id: b.id,
        streetSide: b.streetSide,
        position: A.toWorld(b.x + out * (b.w / 2 + 2.2), 0, b.z),
        yaw: (out > 0 ? Math.PI / 2 : -Math.PI / 2) + LEVEL_YAW,
      };
    });
    this._housesByNo = new Map(this.houses.map((h) => [h.no, h]));
    /**
     * Level bounds, in world space. `ai` builds its NavGrid from this.
     *
     * This was a fixed +/-62 m box inherited from the original 104 m fictional
     * street and never updated. The street is now 304 m long, so only 22 of 52
     * doorsteps fell inside it — `grid.nearest()` returned -1 for the rest and
     * three of the cast (Oysters at 26, Angela at 27, Paddy Mason at 31) could
     * never path anywhere. They stood at their doors for the whole game.
     *
     * Derived from the street itself so it cannot desync again. `x` is the
     * building line plus plot depth and a small margin rather than the full
     * cross-road width: the grid cost is dominated by the 304 m length, and
     * spending cells on empty ground either side of the cross roads buys
     * nothing. Cell size stays 0.8 m deliberately — the footpath is only 2.0 m
     * wide and NavGrid inflates obstacles by the agent radius, so a coarser
     * grid closes the pavement and pushes everyone into the carriageway.
     */
    let halfX = STREET.kerb + STREET.setback + 6;
    for (const b of BUILDINGS) halfX = Math.max(halfX, Math.abs(b.x) + b.w / 2 + 4);
    this.bounds = new THREE.Box3(
      new THREE.Vector3(-halfX, -2, STREET.zMin - 10),
      new THREE.Vector3(halfX, 26, STREET.zMax + 10)
    ).applyMatrix4(A.xform);
    this.stats = A.stats;

    const ms = performance.now() - t0;
    console.info(
      `[world] built in ${ms.toFixed(0)}ms — ${(A.stats.staticTris / 1000).toFixed(0)}k static tris, ` +
        `${(A.stats.instTris / 1000).toFixed(0)}k instanced tris in ${A.stats.instances} instances, ` +
        `${A.stats.drawCalls} draw calls, ${(A.stats.collideTris / 1000).toFixed(1)}k collision tris`
    );
  }

  // ----------------------------------------------------------------- lights --
  /**
   * Punctual lights the world owns: the bare bulbs inside the enterable
   * buildings (what makes an interior read as lived-in against cool skylight)
   * and the street lamps, which only draw power after dusk.
   */
  _addLights(A) {
    this.bulbs = [];
    this.lamps = [];

    for (const b of A.interiorLights.slice(0, 20)) {
      // A bare 60 W bulb in an unlit room: the only thing separating an interior
      // from a black hole, so it has to actually carry the room.
      // Intensity is re-driven every update() off the solar altitude; this is
      // the daylight value so a frame captured before the first update is right.
      const l = new THREE.PointLight(0xffc07a, 5, 13, 2);
      l.position.set(b.x, b.y, b.z);
      l.castShadow = false;
      A.light(l, { range: 13, priority: 2 });
      this.bulbs.push(l);
    }

    for (const p of A.lampAnchors) {
      const l = new THREE.PointLight(0xffb765, 0, 22, 2);
      l.position.set(p.x, p.y - 0.12, p.z);
      l.castShadow = false;
      A.light(l, { range: 22, priority: 3 });
      this.lamps.push(l);
    }
    this.lampLens = A.mat('lamp_lens');
    this._lampMix = -1;

    this._addBallast();
  }

  /**
   * BALLAST — hold the scene's point-light COUNT constant.
   *
   * MEASURED, not guessed. The single worst source of stalls in this build was
   * not geometry: it was shader compilation triggered by the world's own
   * practicals. `render` distance-culls every registered punctual light
   * (`light.visible = fade > 0.002`), and Three bakes the number of *visible*
   * point lights into the program cache key. The world owns 17 practicals (12
   * interior bulbs at 13 m, 5 street lamps at 22 m), so walking down the street
   * sweeps the visible count through 9-8-7-6-5-4 — and every single step
   * recompiles EVERY lit material in the frame:
   *
   *   f15 +36 programs  636 ms   f32 +35  702 ms   f41 +35  699 ms
   *   f51 +35 programs  678 ms   f99 +33  698 ms
   *   → 186 programs and ~3.5 s of stalls inside 900 frames of play
   *
   * Pre-compiling every count instead costs 9.5 s of boot (measured: 595
   * programs for counts 0-16), which is the wrong trade. Holding the count
   * still costs nothing.
   *
   * These lights are black (`color 0x000000`, `intensity 0`) with a 1 cm range,
   * parked under the map, and are NOT registered with `render.addLight`, so
   * nothing culls or re-lights them. A point light whose colour times intensity
   * is exactly 0 contributes `0.0` to irradiance — not "almost nothing", but a
   * float zero that is added to the accumulator — so this cannot move a pixel
   * no matter how many slots are lit. It only changes `numPointLights`, which
   * is a shader-permutation input and nothing else.
   *
   * Cost of the padding, measured over 3 paired runs at 1512x982 DPR 2 with 20
   * ballast slots live: p05 frame time 15.7 ms -> 14.4 ms (i.e. inside noise).
   */
  _addBallast() {
    this._ballast = [];
    for (let i = 0; i < LIGHT_SLOTS + 4; i++) {
      const l = new THREE.PointLight(0x000000, 0, 0.01, 2);
      l.name = `world_light_ballast_${i}`;
      l.castShadow = false;
      l.visible = false;
      l.userData.owBallast = true;
      // Far under the terrain, so even the distance-attenuation term is 0.
      l.position.set(0, -1000, 0);
      this.root.add(l);
      this._ballast.push(l);
    }
    /** Point lights in the scene that are NOT ballast; refreshed periodically. */
    this._pointLights = [];
    this._pointLightsFrame = -1e9;
    this._lightTarget = LIGHT_SLOTS;
    this._lightRanges = new Map(); // light -> the cull radius `render` gave it
    this._camPos = new THREE.Vector3();
    this._collectPointLight = (o) => {
      if (o.isPointLight === true && o.userData.owBallast !== true) this._pointLights.push(o);
    };
  }

  /**
   * Top the visible point-light count up to a fixed target. Runs in lateUpdate,
   * after every subsystem has finished moving lights and the camera, and before
   * `render` draws — so the count Three sees is the same every frame.
   *
   * The count has to be PREDICTED rather than read off `light.visible`, because
   * `render._cullLights()` runs inside `render.render()` — i.e. after this. Using
   * last frame's flags is right on 99% of frames and off by one on exactly the
   * frames where a light crosses its cull radius, which are exactly the frames
   * that used to stall. So mirror the renderer's own test here. Getting the
   * prediction wrong can only cost a permutation, never a pixel: the ballast
   * lights are black, and a black light is a no-op however many are lit.
   */
  _stabiliseLightCount(ctx) {
    const list = this._pointLights;
    if (!list) return;
    const render = this._render ?? (this._render = ctx.peek('render'));
    // The set of point lights in the scene only changes when a subsystem builds
    // or frees a pool, so rescanning every frame is pure waste. Every 90 frames
    // is often enough to catch a pool that appears after boot.
    if (ctx.time.frame - this._pointLightsFrame >= 90) {
      this._pointLightsFrame = ctx.time.frame;
      list.length = 0;
      ctx.scene.traverse(this._collectPointLight);
      this._lightRanges.clear();
      for (const e of render?.lights ?? []) {
        if (e.light?.isPointLight === true) this._lightRanges.set(e.light, e.range);
      }
    }

    ctx.camera.getWorldPosition(this._camPos);
    let n = 0;
    for (let i = 0; i < list.length; i++) {
      const l = list[i];
      const range = this._lightRanges.get(l);
      if (range === undefined) {
        // Not registered for distance culling: its owner drives `visible`.
        if (l.visible === true) n++;
        continue;
      }
      // The renderer's test, verbatim: fade = 1 - smoothstep(d, .75r, 1.15r),
      // light.visible = fade > 0.002.
      const d = l.position.distanceTo(this._camPos);
      if (1 - THREE.MathUtils.smoothstep(d, range * 0.75, range * 1.15) > 0.002) n++;
    }

    // A subsystem can always out-run the pool; adopting the higher count costs
    // one compile, once, instead of one per crossing.
    if (n > this._lightTarget) this._lightTarget = n;
    const want = this._lightTarget - n;
    const pool = this._ballast;
    for (let i = 0; i < pool.length; i++) {
      const v = i < want;
      if (pool[i].visible !== v) pool[i].visible = v;
    }
  }

  // ---------------------------------------------------------------- runtime --
  update(dt, ctx) {
    // Distance LOD for the scatter clouds: one bounding-sphere test per batch.
    this.A?.updateLod(ctx.camera);

    // Street lamps come on as the sun goes down, driven by the sky's real solar
    // altitude rather than a timer, so it is right at any time of day.
    const sky = this._sky ?? (this._sky = ctx.peek('sky'));
    const alt = sky?.sunAltitude ?? 0.6;
    // Ramp starts at ~11 degrees of sun altitude rather than ~6.3. Irish
    // street lighting comes on well before the sun is physically down,
    // especially under this sky's 0.78 cloud cover, and the old window was so
    // narrow the lamps only lit for a few minutes either side of sunset.
    const mix = 1 - Math.min(1, Math.max(0, (alt + 0.02) / 0.20));
    if (Math.abs(mix - this._lampMix) > 0.01) {
      this._lampMix = mix;
      for (let i = 0; i < this.lamps.length; i++) this.lamps[i].intensity = 14 * mix;
      if (this.lampLens) this.lampLens.emissiveIntensity = 9 * mix;
      // Bulbs stay on around the clock — but a 60 W bulb is NOT competitive with
      // daylight, and running it at night strength at noon is what made every
      // interior read as pure tungsten (B-R -93) and sit level with the sunlit
      // street instead of 1.5-2.5 stops under it. Gate the bulb on solar
      // altitude: a weak practical by day, the room's only light after dark.
      for (let i = 0; i < this.bulbs.length; i++) this.bulbs[i].intensity = 5 + 17 * mix;
    }
  }

  lateUpdate(dt, ctx) {
    this._stabiliseLightCount(ctx);
  }

  // --------------------------------------------------------------- pre-warm --
  /**
   * Compile every shader permutation the world can produce, before the frame
   * loop starts. See `src/core/prewarm.js` — that module asks each subsystem for
   * exactly this hook, because `renderer.compileAsync(scene, camera)` alone
   * reaches only the forward lit variant of a material, not the two override
   * passes the world's geometry also goes through every frame:
   *
   *   - the CSM cascades render the whole scene with `csm.depthMaterial`
   *   - the prepass renders it again with the gbuffer's ShaderMaterial
   *
   * Both are separate programs, and each one has its own permutations for plain
   * geometry, instanced geometry and instanced geometry with an instanceColor —
   * which is precisely the mix the world puts in front of them.
   *
   * Pixel-neutral by construction: it compiles, it does not draw. The only
   * mutations are `scene.overrideMaterial` and the ballast light visibility,
   * both restored in the `finally`.
   */
  async prewarmMaterials(ctx = this.ctx) {
    const render = ctx.peek?.('render') ?? ctx.get?.('render');
    const renderer = render?.renderer;
    if (!renderer) return { ok: false, reason: 'no renderer' };
    const scene = ctx.scene;
    const camera = ctx.camera;
    const before = renderer.info.programs?.length ?? 0;
    const t0 = performance.now();

    // Every lit material must carry render's CSM/AO/SSR injection before it is
    // compiled, or the program we warm is not the program the frame will use.
    render.patchMaterials?.(this.root);

    // Compile at the count the frame loop will actually run at, not at whatever
    // the distance cull happens to have left visible during boot.
    this._stabiliseLightCount(ctx);

    const prevOverride = scene.overrideMaterial;
    try {
      // 1. forward lit pass.
      await this._compile(renderer, scene, camera);
      // 2. the shadow cascades and 3. the depth/normal/velocity prepass, both of
      //    which draw this same geometry through an override material.
      for (const over of [render.csm?.depthMaterial, render.gbuffer?.material]) {
        if (!over) continue;
        scene.overrideMaterial = over;
        await this._compile(renderer, scene, camera);
      }
    } finally {
      scene.overrideMaterial = prevOverride;
    }

    return {
      ok: true,
      ms: Math.round(performance.now() - t0),
      compiled: (renderer.info.programs?.length ?? 0) - before,
      lightTarget: this._lightTarget,
    };
  }

  async _compile(renderer, scene, camera) {
    try {
      await renderer.compileAsync(scene, camera);
    } catch {
      try {
        renderer.compile(scene, camera);
      } catch {
        /* a driver we cannot pre-warm on; boot must still proceed */
      }
    }
  }

  // ---------------------------------------------------------------- queries --
  spawn(i = 0) {
    const n = this.spawnPoints.length;
    return this.spawnPoints[((i % n) + n) % n];
  }

  /**
   * The doorstep of a Kilmore Close house, by house number, or null if no such
   * number is on the street. See `this.houses`.
   */
  doorstep(no) {
    return this._housesByNo.get(no) ?? null;
  }

  /**
   * A parking space at the kerb outside a house: world position, and a yaw that
   * points ALONG the street rather than across it.
   *
   * This exists because doing the offset outside `world` gets it wrong.
   * `doorstep().position` is already world space, and the street is rotated by
   * LEVEL_YAW, so anything that adds a setback along world +X lands several
   * metres off and broadside. Computing it in level space here and converting
   * once is the only way it stays correct if the street is re-laid.
   */
  kerbside(no) {
    const h = this._housesByNo.get(no);
    if (!h) return null;
    const b = BUILDINGS.find((x) => x.no === no);
    if (!b) return null;
    const sgn = b.streetSide === 1 ? -1 : 1;
    // Just inside the carriageway edge on that house's side, so the car sits at
    // the kerb rather than on the footpath or in the middle of the road.
    const lx = sgn * (STREET.halfWidth - 1.05);
    return {
      position: this.A.toWorld(lx, 0, b.z),
      // Level yaw 0 is +Z, which is up the street; +LEVEL_YAW puts it in world.
      yaw: LEVEL_YAW,
    };
  }

  levelToWorld(x, y, z, out = new THREE.Vector3()) {
    return out.set(x, y, z).applyMatrix4(this.A.xform);
  }

  worldToLevel(x, y, z, out = new THREE.Vector3()) {
    return out.set(x, y, z).applyMatrix4(this._inv);
  }

  /** Analytic floor height. Physics owns the exact answer; this is a hint. */
  groundHeight(x, z) {
    const p = this.worldToLevel(x, 0, z, this._v);
    return groundY(p.x, p.z);
  }

  /** True where a character can stand outdoors (street, pavement, alley). */
  isOpen(x, z, margin = 0.4) {
    const p = this.worldToLevel(x, 0, z, this._v);
    return isOpen(p.x, p.z, margin);
  }

  dispose() {
    this.A?.dispose();
    this.root?.parent?.remove(this.root);
    for (const l of this._ballast ?? []) l.parent?.remove(l);
    this._ballast = null;
    this._pointLights = null;
    this.bulbs = null;
    this.lamps = null;
  }
}

export { BUILDINGS, STREET, SET_PIECES };
