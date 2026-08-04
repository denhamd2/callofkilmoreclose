import * as THREE from 'three';

/**
 * VEHICLE — the car parked outside 18 Kilmore Close.
 *
 * One car, procedurally built like everything else in this project: no art
 * assets, no new dependencies. A two-box saloon with a clearcoated paint shell,
 * glazing, chrome trim, lamps and four wheels that actually roll and steer.
 *
 * INTERACTION follows the pattern the rest of the game already uses — walk up,
 * a prompt appears, press the use key. Getting out is the same key. The player
 * system keeps ownership of the camera the whole time: driving disables the
 * character controller and teleports the player to the driver's position each
 * step, so there is no second camera rig to keep in sync and no state the
 * player system does not already understand.
 *
 * DRIVING is a kinematic bicycle model, not a rigid body. It is stable at any
 * timestep, never tunnels, and gives the heavy, slightly-understeering feel a
 * saloon should have. Speed is integrated with separate accelerate/brake/drag
 * terms; steering authority falls off with speed so it does not spin on the
 * spot at 60 km/h.
 *
 * KNOCKDOWNS: anyone caught inside the car's footprint above a threshold speed
 * takes damage scaled by how fast it was going, delivered as `damage:dealt`
 * with the actor as `target` — the same path a bullet or a punch uses, so `ai`
 * applies it and the killfeed credits it normally.
 *
 * PERFORMANCE NOTE — the headlamps are EMISSIVE, not punctual lights. Adding
 * two point lights that switch on and off would change the visible light count
 * and recompile every lit material in the scene (see ARCHITECTURE.md,
 * "The point-light count is a shader permutation key" — measured at +33-36
 * programs and 640-900 ms on the frame it happens). An emissive lens costs
 * nothing and reads the same at the distances this car is seen from.
 *
 * PUBLIC API — `const v = ctx.get('vehicle')`
 *   v.driving        true while the player is behind the wheel (ui reads this)
 *   v.speed          m/s, signed
 *
 * EVENTS emitted: damage:dealt (knockdowns)
 */

/** House number the car is parked outside. */
const PARKED_AT = 18;

const ENTER_DIST = 3.6;
/** m/s below which the car cannot knock anyone down. Walking pace. */
const KNOCKDOWN_SPEED = 2.2;

/** Chassis footprint corners (+ centre) in the car's own frame, unit scale. */
const CORNERS = [
  [0, 0],
  [-1, -1],
  [1, -1],
  [-1, 1],
  [1, 1],
];

const MAX_SPEED = 22;
const MAX_REVERSE = -6;
const ACCEL = 9.5;
const BRAKE = 18;
const DRAG = 1.15;
const ROLL_RESIST = 2.4;
/** Wheelbase, metres — the bicycle model's only geometric input. */
const WHEELBASE = 2.62;
const MAX_STEER = 0.52;

export class VehicleSystem {
  static id = 'vehicle';
  static deps = ['world', 'player', 'ui', 'physics'];

  async init(ctx) {
    this.ctx = ctx;
    this.driving = false;
    this.speed = 0;
    this.steer = 0;
    this.heading = 0;
    this._promptShown = false;
    this._disposables = [];

    /* scratch — nothing below allocates per frame */
    this._v = new THREE.Vector3();
    this._v2 = new THREE.Vector3();
    this._eye = new THREE.Vector3();
    this._hitPoint = new THREE.Vector3();
    this._incident = new THREE.Vector3();
    this._damage = {
      target: null,
      amount: 0,
      headshot: false,
      killed: false,
      point: this._hitPoint,
      incident: this._incident,
    };
    this._prompt = { key: 'F', text: 'Get in' };

    const world = ctx.get('world');
    this.root = new THREE.Group();
    this.root.name = 'vehicle';
    this._build();
    ctx.scene.add(this.root);

    // Park it at the kerb outside its house, nose up the street.
    //
    // This asks `world` for the point rather than computing it here. Doing the
    // setback offset locally added it along world +X while the street is
    // rotated by LEVEL_YAW — about 3.9 m of error — and taking the heading from
    // the doorstep yaw, which faces the carriageway, parked it broadside across
    // the road.
    const spot = world.kerbside?.(PARKED_AT) ?? null;
    if (spot) {
      this.root.position.copy(spot.position);
      this.root.position.y = world.groundHeight?.(spot.position.x, spot.position.z) ?? 0;
      this.heading = spot.yaw;
    } else {
      const house = world.doorstep?.(PARKED_AT) ?? null;
      this.root.position.copy(house?.position ?? this._v.set(0, 0, 0));
      this.heading = house?.yaw ?? 0;
    }
    this.root.rotation.y = this.heading;
    this.parkedY = this.root.position.y;

    console.info(`[vehicle] parked outside ${PARKED_AT} Kilmore Close`);
  }

  /* ====================================================================== */
  /*  construction                                                          */
  /* ====================================================================== */

  _mat(opts) {
    const m = new THREE.MeshPhysicalMaterial(opts);
    this._disposables.push(m);
    return m;
  }

  _geo(g) {
    this._disposables.push(g);
    return g;
  }

  _add(geo, mat, x, y, z, ry = 0) {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, y, z);
    m.rotation.y = ry;
    this.root.add(m);
    return m;
  }

  _build() {
    // Deep metallic paint with a clearcoat over it — the one thing that makes
    // a procedural car read as a car and not as a painted box.
    const paint = this._mat({
      color: 0x1b2a3c,
      metalness: 0.86,
      roughness: 0.28,
      clearcoat: 1,
      clearcoatRoughness: 0.05,
    });
    const glass = this._mat({
      color: 0x0a1014,
      metalness: 0.1,
      roughness: 0.06,
      transmission: 0.55,
      transparent: true,
      opacity: 0.72,
    });
    const trim = this._mat({ color: 0xc9ced4, metalness: 1, roughness: 0.22 });
    const rubber = this._mat({ color: 0x0d0f11, metalness: 0, roughness: 0.92 });
    const lampF = this._mat({
      color: 0xfff4e0,
      emissive: 0xfff0d2,
      emissiveIntensity: 2.4,
      roughness: 0.18,
      metalness: 0,
    });
    const lampR = this._mat({
      color: 0x6b0f12,
      emissive: 0xd8202a,
      emissiveIntensity: 1.5,
      roughness: 0.25,
      metalness: 0,
    });

    const L = 4.42; // length
    const W = 1.82; // width
    const sill = 0.44;

    // lower body
    this._add(this._geo(new THREE.BoxGeometry(W, 0.62, L)), paint, 0, sill + 0.31, 0);
    // bonnet and boot decks, slightly narrower so there is a shoulder line
    this._add(this._geo(new THREE.BoxGeometry(W * 0.96, 0.2, 1.34)), paint, 0, sill + 0.7, -1.36);
    this._add(this._geo(new THREE.BoxGeometry(W * 0.96, 0.22, 1.06)), paint, 0, sill + 0.71, 1.56);
    // cabin, set in from the body sides
    this._add(this._geo(new THREE.BoxGeometry(W * 0.9, 0.56, 2.02)), paint, 0, sill + 0.9, 0.12);
    // glasshouse
    this._add(this._geo(new THREE.BoxGeometry(W * 0.83, 0.44, 1.9)), glass, 0, sill + 0.96, 0.12);
    // roof
    this._add(this._geo(new THREE.BoxGeometry(W * 0.86, 0.1, 1.86)), paint, 0, sill + 1.21, 0.14);

    // bumpers + waistline trim
    this._add(this._geo(new THREE.BoxGeometry(W * 1.01, 0.2, 0.16)), trim, 0, sill + 0.16, -L / 2 + 0.06);
    this._add(this._geo(new THREE.BoxGeometry(W * 1.01, 0.2, 0.16)), trim, 0, sill + 0.16, L / 2 - 0.06);
    for (const s of [-1, 1]) {
      this._add(this._geo(new THREE.BoxGeometry(0.04, 0.07, L * 0.74)), trim, (s * W) / 2, sill + 0.6, 0.05);
    }

    // lamps
    const lens = this._geo(new THREE.BoxGeometry(0.42, 0.17, 0.1));
    for (const s of [-1, 1]) {
      this._add(lens, lampF, s * 0.62, sill + 0.5, -L / 2 + 0.02);
      this._add(lens, lampR, s * 0.62, sill + 0.52, L / 2 - 0.02);
    }

    // wheels — kept as instances so steering can turn the front pair
    const tyre = this._geo(new THREE.CylinderGeometry(0.34, 0.34, 0.24, 18));
    const rim = this._geo(new THREE.CylinderGeometry(0.21, 0.21, 0.25, 12));
    this.wheels = [];
    const half = WHEELBASE / 2;
    for (const [wx, wz, front] of [
      [-W / 2 + 0.06, -half, true],
      [W / 2 - 0.06, -half, true],
      [-W / 2 + 0.06, half, false],
      [W / 2 - 0.06, half, false],
    ]) {
      const hub = new THREE.Group();
      hub.position.set(wx, 0.34, wz);
      const t = new THREE.Mesh(tyre, rubber);
      const r = new THREE.Mesh(rim, trim);
      t.rotation.z = Math.PI / 2;
      r.rotation.z = Math.PI / 2;
      hub.add(t, r);
      this.root.add(hub);
      this.wheels.push({ hub, front, tyre: t, rim: r });
    }
  }

  /* ====================================================================== */
  /*  interaction + driving                                                 */
  /* ====================================================================== */

  update(dt, ctx) {
    const player = ctx.peek('player');
    const ui = ctx.peek('ui');
    if (!player) return;

    const use = ctx.input.actionPressed('use');

    if (!this.driving) {
      // Near enough to get in?
      const near = player.position.distanceTo(this.root.position) < ENTER_DIST;
      if (near && !this._promptShown) {
        ui?.setPrompt(this._prompt);
        this._promptShown = true;
      } else if (!near && this._promptShown) {
        ui?.clearPrompt();
        this._promptShown = false;
      }
      if (near && use) this._enter(player, ui);
      return;
    }

    if (use) {
      this._exit(player, ui);
      return;
    }
    this._drive(dt, ctx, player);
  }

  _enter(player, ui) {
    this.driving = true;
    this.speed = 0;
    ui?.clearPrompt();
    this._promptShown = false;
    // The player system keeps the camera; it just stops steering the body.
    player.setControlEnabled(false);
  }

  _exit(player, ui) {
    this.driving = false;
    this.speed = 0;
    player.setControlEnabled(true);
    // Step out on the driver's side, clear of the car.
    const side = this._v2.set(Math.cos(this.heading), 0, -Math.sin(this.heading)).multiplyScalar(1.55);
    this._eye.copy(this.root.position).add(side);
    this._eye.y = this.root.position.y + 1.6;
    player.teleport(this._eye, this.heading);
    ui?.clearPrompt();
  }

  _drive(dt, ctx, player) {
    const input = ctx.input;
    const throttle = (input.action('forward') ? 1 : 0) - (input.action('back') ? 1 : 0);
    const turn = (input.action('left') ? 1 : 0) - (input.action('right') ? 1 : 0);
    const handbrake = input.action('jump');

    // longitudinal
    if (throttle > 0) this.speed += ACCEL * dt;
    else if (throttle < 0) {
      // Brake first, then reverse once stopped — a single key doing both is
      // what every driving game does and what players expect.
      this.speed -= (this.speed > 0.4 ? BRAKE : ACCEL) * dt;
    }
    if (handbrake) this.speed -= Math.sign(this.speed) * BRAKE * 1.3 * dt;
    // drag and rolling resistance
    this.speed -= this.speed * DRAG * dt * (throttle === 0 ? 1 : 0.25);
    if (throttle === 0 && Math.abs(this.speed) < 0.25) this.speed = 0;
    else if (throttle === 0) this.speed -= Math.sign(this.speed) * ROLL_RESIST * dt;
    this.speed = Math.max(MAX_REVERSE, Math.min(MAX_SPEED, this.speed));

    // steering authority falls off with speed
    const grip = 1 - Math.min(0.72, Math.abs(this.speed) / MAX_SPEED);
    const target = turn * MAX_STEER * (0.42 + 0.58 * grip);
    this.steer += (target - this.steer) * Math.min(1, dt * 9);

    // kinematic bicycle: heading rate = v/L * tan(steer)
    if (Math.abs(this.speed) > 0.02) {
      this.heading += (this.speed / WHEELBASE) * Math.tan(this.steer) * dt;
    }

    const dx = Math.sin(this.heading) * this.speed * dt;
    const dz = Math.cos(this.heading) * this.speed * dt;

    /**
     * Collision. There was none at all: the car drove through the houses, the
     * kerbs and off the map.
     *
     * This is a cheap swept test rather than a rigid-body solve — sample the
     * four corners of the chassis at the proposed position and reject the step
     * if any of them lands somewhere a character could not stand. `world.isOpen`
     * takes world coordinates and is exactly the query the AI navigation uses,
     * so the car is blocked by the same geometry that blocks people.
     *
     * On a block, forward motion is killed rather than reflected: a saloon that
     * bounces off a garden wall reads worse than one that simply stops.
     */
    const nx = this.root.position.x + dx;
    const nz = this.root.position.z + dz;
    if (this._clear(nx, nz)) {
      this.root.position.x = nx;
      this.root.position.z = nz;
    } else if (this._clear(this.root.position.x + dx * 0.35, this.root.position.z + dz * 0.35)) {
      // Half-step: lets the car creep out of a scrape instead of sticking.
      this.root.position.x += dx * 0.35;
      this.root.position.z += dz * 0.35;
      this.speed *= 0.45;
    } else {
      this.speed = 0;
    }

    const world = ctx.peek('world');
    const g = world?.groundHeight?.(this.root.position.x, this.root.position.z);
    if (typeof g === 'number' && Number.isFinite(g)) {
      // Follow the road surface, but damped — the analytic height is a hint and
      // snapping to it every frame reads as jitter.
      this.root.position.y += (g - this.root.position.y) * Math.min(1, dt * 8);
    }
    this.root.rotation.y = this.heading;

    // wheels: steer the front pair, roll all four
    const roll = (this.speed * dt) / 0.34;
    for (let i = 0; i < this.wheels.length; i++) {
      const w = this.wheels[i];
      if (w.front) w.hub.rotation.y = this.steer;
      w.tyre.rotation.x += roll;
      w.rim.rotation.x += roll;
    }

    // carry the player along in the driver's seat
    this._eye.copy(this.root.position);
    this._eye.y += 1.32;
    player.teleport(this._eye, this.heading);

    this._knockdowns(ctx);
  }

  /**
   * True when the chassis footprint at (x, z) is clear of world geometry.
   * Four corners plus the centre, in the car's own frame.
   */
  _clear(x, z) {
    const world = this.ctx.peek('world');
    if (!world?.isOpen) return true;
    const c = Math.cos(this.heading);
    const s = Math.sin(this.heading);
    const HX = 0.86; // half-width, a little inside the bodywork
    const HZ = 2.05; // half-length
    for (let i = 0; i < CORNERS.length; i++) {
      const lx = CORNERS[i][0] * HX;
      const lz = CORNERS[i][1] * HZ;
      // local -> world: forward is (sin h, cos h), right is (cos h, -sin h)
      const wx = x + lx * c + lz * s;
      const wz = z - lx * s + lz * c;
      if (!world.isOpen(wx, wz, 0.05)) return false;
    }
    return true;
  }

  /**
   * Anyone inside the car's footprint at speed goes down. Uses an oriented box
   * test in the car's own frame so a glancing pass along the side does not
   * count as a hit.
   */
  _knockdowns(ctx) {
    const sp = Math.abs(this.speed);
    if (sp < KNOCKDOWN_SPEED) return;
    const ai = ctx.peek('ai');
    if (!ai?.agents) return;

    /**
     * World -> car frame. Forward is (sin h, cos h) and right is (cos h, -sin h),
     * so the inverse rotation is lx = px*cos h - pz*sin h, lz = px*sin h + pz*cos h.
     *
     * This used to build c/s from `-this.heading` and then apply them with the
     * same signs, which rotates the wrong way: at a heading of 1.1 rad a target
     * standing directly in front of the car came out at lx 0.81, lz -0.59. The
     * oriented box was therefore tested against a box facing the wrong
     * direction, so people were clipped beside the car and missed in front of it.
     */
    const c = Math.cos(this.heading);
    const s = Math.sin(this.heading);
    for (let i = 0; i < ai.agents.length; i++) {
      const a = ai.agents[i];
      if (!a.alive) continue;
      const px = a.position.x - this.root.position.x;
      const pz = a.position.z - this.root.position.z;
      if (Math.abs(a.position.y - this.root.position.y) > 2.2) continue;
      // into the car's local frame
      const lx = px * c - pz * s;
      const lz = px * s + pz * c;
      if (Math.abs(lx) > 1.25 || Math.abs(lz) > 2.5) continue;

      this._damage.target = a;
      // 22 m/s flat out is comfortably lethal; walking pace barely stings.
      this._damage.amount = 26 + sp * 7.5;
      this._hitPoint.copy(a.position);
      this._incident.set(Math.sin(this.heading), 0, Math.cos(this.heading));
      ctx.events.emit('damage:dealt', this._damage);
      /**
       * Shove the body clear, PERPENDICULAR to the car's path.
       *
       * This used to displace along `_incident`, which is the car's forward
       * vector — i.e. further down its own path — so at speed the same actor
       * was re-entered and re-hit every ~3 frames, each hit spawning another
       * hitmarker, damage number and sound until they died. Pushing sideways,
       * on the side they were actually clipped, gets them out of the way.
       */
      const side = Math.sign(lx) || 1;
      a.position.x += c * side * 1.6;
      a.position.z -= s * side * 1.6;
    }
  }

  dispose() {
    this.root.parent?.remove(this.root);
    this.root.traverse((o) => {
      if (o.isMesh) o.geometry?.dispose?.();
    });
    for (const d of this._disposables) d.dispose?.();
    this._disposables.length = 0;
    this.wheels = null;
  }
}
