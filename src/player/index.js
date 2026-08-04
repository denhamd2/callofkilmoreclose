/**
 * PLAYER — movement state machine, camera feel, health.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * WHAT LIVES HERE
 *   movement.js   the state machine: stand/crouch/prone/sprint/tacsprint/slide/
 *                 jump/fall/mantle/vault (+ lean). 120 Hz, fully interruptible.
 *   camera.js     bob, landing dip, step shift, strafe/turn roll, breathing
 *                 sway, recoil + weapon kick channels, trauma shake, FOV.
 *   mantle.js     ledge detection via physics capsule sweeps + the rooted climb.
 *   health.js     health, regen, suppression, damage direction, heartbeat.
 *   lowhealth.js  the low-health screen treatment, registered with `render`.
 *   tuning.js     every number, with the CoD values it was calibrated against.
 *   springs.js    spring/damper + easing maths.
 *
 * Collision is *never* computed here — everything goes through
 * `physics.createCharacter()` capsule sweeps.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * PUBLIC API — `const p = ctx.get('player')`
 * ────────────────────────────────────────────────────────────────────────────
 * TRANSFORM
 *   p.position        Vector3, FEET (bottom of the capsule), interpolated
 *   p.eyePosition     Vector3, the composed camera position
 *   p.velocity        Vector3, m/s
 *   p.forward         Vector3, unit view forward
 *   p.yaw / p.pitch   radians (yaw is the movement basis, camera adds feel)
 *   p.speed / p.horizontalSpeed
 *   p.character       the physics CharacterController (read-only)
 *   p.height          capsule height of the current stance
 *   p.hitbox          physics collider on LAYER.PLAYER — trace against the
 *                     player with `phys.MASK.BULLET | phys.LAYER.PLAYER`
 *
 * STATE
 *   p.state           'stand'|'crouch'|'prone'|'sprint'|'tacsprint'|'slide'|
 *                     'jump'|'fall'|'mantle'|'vault'|'lean'
 *   p.stance          'stand'|'crouch'|'prone'
 *   p.sprinting  p.tacticalSprint  p.sliding  p.grounded  p.airborne
 *   p.mantling   p.leanAmount (-1..1)   p.slideProgress (0..1)
 *
 * AIM
 *   p.adsRequested            true while the aim button is held
 *   p.adsProgress             0..1 blend actually in use
 *   p.setAdsProgress(v)       `weapons` owns the real curve — push it here and
 *                             the camera FOV, sway and move speed follow it
 *
 * CAMERA FEEL (for `weapons`, `fx`, `ai`)
 *   p.addRecoil(pitch, yaw, roll, punch)   camera-owned recoil impulse (radians)
 *   p.addKick(pitch, yaw, roll)            independent weapon kick channel
 *   p.addTrauma(a)                         0..1 noise shake (explosions, hits)
 *   p.viewKick                             { pitch, yaw, roll, punch } this frame
 *   p.cameraRig                            the rig, if you need the raw springs
 *
 * HEALTH
 *   p.health  p.maxHealth  p.healthFraction  p.lowHealth  p.dead
 *   p.suppression  p.damageIndicators
 *   p.applyDamage(amount, fromVector3, opts)   p.heal(a)   p.addSuppression(a)
 *
 * CONTROL
 *   p.setControlEnabled(bool)     shot harness / cutscenes
 *   p.teleport(eyePosition, rotationEulerOrYaw)
 *   p.respawn(index)
 *   p.debugState(name)            'sprint'|'slide'|'crouch'|'hurt'|'critical'|
 *                                 'air'|'reset'
 *
 * EVENTS EMITTED
 *   player:state      { stance, sprinting, sliding, ads, state, grounded, ... }
 *   player:land       { velocity, surface, position }
 *   player:footstep   { position, surface, running, left, speed, stance }
 *   damage:taken      { amount, from, health, direction }
 *   player:health     { health, fraction, low, critical, regenerating, ... }  *
 *   player:heartbeat  { strength, fraction }                                  *
 *   player:mantle     { kind, height }                                        *
 *   player:jump       { position }                                            *
 *   player:death      { position }                                            *
 *   (*) not in the canonical table in ARCHITECTURE.md — additive, optional, and
 *   safe to ignore. The canonical `player:state` payload carries `health` too so
 *   a listener that only knows the documented four fields still gets everything.
 */

import * as THREE from 'three';
import { Movement } from './movement.js';
import { CameraRig } from './camera.js';
import { Health } from './health.js';
import { LowHealthPass } from './lowhealth.js';
import { STANCE, MOVE, CAMERA, HEALTH, FOOTSTEP, JUMP_SPEED, THIRD_PERSON as TP } from './tuning.js';
import { clamp, clamp01, lerp, approach, moveToward, angleDelta, DEG } from './springs.js';

export class PlayerSystem {
  static id = 'player';
  static deps = ['physics', 'world', 'render'];

  constructor() {
    /** Lets `ai` / `physics` recognise the local player from an owner pointer. */
    this.isPlayer = true;
    this.movement = null;
    this.rig = null;
    this.health = null;
    this.lowHealthPass = null;
    this.hitbox = null;

    this.controlEnabled = true;
    this.adsAmount = 0;

    /**
     * THIRD PERSON. The camera rides a boom behind David's right shoulder; the
     * eye position the rig computes stays the AIM origin, so movement, the
     * look basis and `weapons`' muzzle ray are all unaffected by where the
     * camera actually sits. `aimOrigin` is published for `weapons`.
     */
    this.aimOrigin = new THREE.Vector3();
    this.body = null;
    this._bodyTried = false;
    this._boomDesired = new THREE.Vector3();
    this._boomDir = new THREE.Vector3();
    this._boomRight = new THREE.Vector3();
    this._boomUp = new THREE.Vector3(0, 1, 0);
    this._aimTarget = new THREE.Vector3();
    /**
     * Body orientation state. `_bodyYaw` is what is actually written to the
     * mesh; `_bodyYawWanted` latches the last real movement heading so the body
     * does not spin back to a default when the stick is released.
     */
    this._bodyYaw = 0;
    this._bodyYawWanted = 0;
    /** Seconds since the last shot — holds the body facing the crosshair. */
    this._sinceFire = 99;
    /** Preallocated animator state; setState only reads it. */
    this._animState = {
      clip: 'idle',
      speed: 0,
      crouch: false,
      aimTarget: this._aimTarget,
      lookTarget: this._aimTarget,
      aimWeight: 0.12,
      suppress: 0,
    };
    this._animAccum = 0;
    this._adsExternal = false;
    this._adsExternalAge = 0;
    this.adsRequested = false;

    this._lookFrame = -1;
    this._prevYaw = 0;

    // preallocated event payloads
    this._statePayload = {
      stance: 'stand', sprinting: false, sliding: false, ads: false,
      state: 'stand', grounded: true, airborne: false, mantling: false,
      lean: 0, speed: 0, health: HEALTH.max, healthFraction: 1, crouched: false,
    };
    this._landPayload = { velocity: 0, surface: 'concrete', position: new THREE.Vector3() };
    this._stepPayload = {
      position: new THREE.Vector3(), surface: 'concrete', running: false,
      left: false, speed: 0, stance: 'stand',
    };
    this._mantlePayload = { kind: 'none', height: 0 };
    this._jumpPayload = { position: new THREE.Vector3() };
    // Preallocated HUD snapshot polled by `ui` (see getHudState).
    this._hudState = {
      health: HEALTH.max, maxHealth: HEALTH.max, regen: false, dead: false,
      move: 0, sprint: false, crouch: false, ads: false, airborne: false,
      suppression: 0, position: null,
    };

    this._tmp = new THREE.Vector3();
    /** Last emitted discrete state, compared field-wise so no string is built. */
    this._prev = {
      state: '', stance: '', sprinting: false, tacticalSprint: false,
      sliding: false, grounded: true, ads: false, mantling: false,
    };
    this._offEvents = [];
  }

  /* ==================================================================== */
  /* init                                                                 */
  /* ==================================================================== */

  async init(ctx) {
    this.ctx = ctx;
    this.physics = ctx.get('physics');
    this.rng = ctx.rng.fork();

    this.movement = new Movement(ctx, this);
    this.rig = new CameraRig(ctx);
    this.health = new Health(ctx, this.rig);

    // ---- spawn -----------------------------------------------------------
    const spawn = this._resolveSpawn();
    this.movement.init(this.physics, spawn.feet);
    this.movement.yaw = spawn.yaw;
    this.movement.pitch = 0;
    this._prevYaw = spawn.yaw;
    this.rig.reset(STANCE.stand.eye);
    this.rig.update(1 / 60, this.movement, this.health);
    this.rig.applyTo(ctx.camera);

    // ---- hitbox ----------------------------------------------------------
    // A capsule on the PLAYER layer so `ai` has something to shoot at. PLAYER is
    // deliberately absent from MASK.BULLET and MASK.CHARACTER, so it can never
    // be hit by the player's own muzzle ray and never blocks the player's own
    // movement sweeps: an AI that wants to hit us traces with
    //   phys.MASK.BULLET | phys.LAYER.PLAYER
    this.hitbox = this.physics.addCollider({
      shape: 'capsule',
      layer: this.physics.LAYER.PLAYER,
      surface: 'flesh',
      owner: this,
      part: 'torso',
      radius: 0.3,
    });
    this._syncHitbox();

    // ---- low-health treatment -------------------------------------------
    const render = ctx.peek('render');
    if (render?.registerPass) {
      this.lowHealthPass = new LowHealthPass();
      this._unregisterPass = render.registerPass(this.lowHealthPass);
    }

    // ---- incoming damage / suppression ----------------------------------
    const on = (type, fn) => this._offEvents.push(ctx.events.on(type, fn));
    on('damage:dealt', (e) => this._onDamageDealt(e));
    on('explosion', (e) => this._onExplosion(e));
    on('bullet:impact', (e) => this._onBulletImpact(e));
    // Firing pins the body to the crosshair for a moment, so a shot taken while
    // running does not leave David shooting sideways.
    on('weapon:fire', () => {
      this._sinceFire = 0;
    });

    console.info(
      `[player] spawn ${spawn.feet.x.toFixed(1)}, ${spawn.feet.y.toFixed(2)}, ` +
      `${spawn.feet.z.toFixed(1)} · walk ${STANCE.stand.speed} sprint ${MOVE.sprintSpeed} ` +
      `tac ${MOVE.tacSprintSpeed} m/s · jump ${JUMP_SPEED.toFixed(2)} m/s (apex 0.60 m)`
    );
  }

  _resolveSpawn() {
    const world = this.ctx.peek('world');
    const out = { feet: new THREE.Vector3(0, 0.2, 0), yaw: 0 };
    const sp = world?.spawn?.(0);
    if (sp?.position) {
      out.feet.copy(sp.position);
      out.yaw = sp.yaw ?? 0;
    }
    // Physics owns the exact floor; drop onto it so we never start embedded.
    const gy = this.physics.groundHeight(out.feet.x, out.feet.z, out.feet.y + 6);
    out.feet.y = Number.isFinite(gy) ? gy + 0.03 : out.feet.y + 0.2;
    return out;
  }

  /* ==================================================================== */
  /* look                                                                 */
  /* ==================================================================== */

  /**
   * Mouse/stick look is consumed once per rendered frame. It happens in the
   * first fixed step when there is one (so movement uses this frame's yaw with
   * zero latency) and in update() otherwise — above 120 fps a frame can contain
   * no fixed step at all and dropping the delta there would feel like a hitch.
   */
  _consumeLook(dt) {
    const frame = this.ctx.time.frame;
    if (frame === this._lookFrame) return;
    this._lookFrame = frame;
    const m = this.movement;
    if (!this.controlEnabled) {
      m.yawRate = 0;
      return;
    }
    const input = this.ctx.input;
    const cfg = this.ctx.config;
    const sens = lerp(1, cfg.adsSensScale, clamp01(this.adsAmount));

    let dYaw = -input.look.x * sens;
    let dPitch = -input.look.y * sens;

    // Gamepad: rate-based, already curved by Input.
    const stick = input.stick;
    if (stick.lookX || stick.lookY) {
      const rate = 3.1 * sens; // rad/s at full deflection
      dYaw -= stick.lookX * rate * dt;
      dPitch -= stick.lookY * rate * dt;
    }
    // Mantles are rooted: you keep your head, but the shoulders are committed.
    if (m.mantleMotion.active) {
      dYaw *= 0.55;
      dPitch *= 0.55;
    }

    m.yaw += dYaw;
    m.pitch = clamp(m.pitch + dPitch, -CAMERA.pitchLimit, CAMERA.pitchLimit);
    // Keep yaw bounded so long sessions never lose float precision.
    if (m.yaw > Math.PI) m.yaw -= Math.PI * 2;
    else if (m.yaw < -Math.PI) m.yaw += Math.PI * 2;

    m.yawRate = dt > 1e-5 ? dYaw / dt : 0;
    this._prevYaw = m.yaw;
  }

  /* ==================================================================== */
  /* frame                                                                */
  /* ==================================================================== */

  fixedUpdate(h, ctx) {
    if (!this.movement) return;
    this._consumeLook(ctx.time.dt > 1e-5 ? ctx.time.dt : h);
    this.movement.latchInput(ctx.time.frame);
    if (!this.controlEnabled) return;
    this.movement.adsAmount = this.adsAmount;
    this.movement.step(h);
  }

  update(dt, ctx) {
    if (!this.movement) return;
    this._consumeLook(dt);
    this.movement.latchInput(ctx.time.frame);

    this._updateAds(dt);
    this._drainMovementEvents();
    this.health.update(dt);

    this.rig.update(dt, this.movement, this.health);
    if (this.controlEnabled) this.rig.applyTo(ctx.camera);
    else this.rig.forward.set(0, 0, -1).applyQuaternion(ctx.camera.quaternion);

    // Third person. `applyTo` has just put the camera at the eye and settled
    // the aim basis; the boom moves the camera only, so `rig.forward` — which
    // is what movement and `weapons` aim along — is unchanged by it.
    this.aimOrigin.copy(ctx.camera.position);
    this._updateBody(dt, ctx);
    // Only drive the boom while we own the camera. `rig.applyTo` is already
    // skipped when control is disabled, so running the boom regardless yanked
    // the camera off whatever transform a cutscene or the shot harness had set,
    // using a stale aimOrigin.
    if (this.controlEnabled) this._applyBoom(ctx);

    this.lowHealthPass?.sync(this.health);
    this._syncHitbox();
    this._publishState();
  }

  /**
   * David's body, built the first time a frame runs rather than in `init()`.
   *
   * `ai` initialises AFTER `player` (see main.js), so `ctx.get('ai')` during
   * init would force it up early and reorder the RNG stream every character is
   * stitched from — which the capture gate measures. By the first frame `ai` is
   * up and `peek` is enough. The variant's materials are already prewarmed by
   * `ai.prewarmMaterials()`; only its geometry is built here, once.
   */
  _ensureBody(ctx) {
    if (this.body || this._bodyTried) return;
    this._bodyTried = true;
    const ai = ctx.peek('ai');
    if (!ai?.createCharacter) return;
    this.body = ai.createCharacter(TP.variant);
    ctx.scene.add(this.body.group);
  }

  /** Put the body on the capsule and drive its animation from the movement state. */
  _updateBody(dt, ctx) {
    this._sinceFire += dt;
    this._ensureBody(ctx);
    const b = this.body;
    if (!b) return;
    const m = this.movement;

    b.group.visible = !this.health.dead;
    b.group.position.copy(m.renderPosition);

    /**
     * BODY YAW.
     *
     * This used to be `b.group.rotation.y = this.rig.rotation.y` — the composed
     * CAMERA yaw, assigned raw every frame. Two things were wrong with it.
     *
     * First, `rig.rotation.y` carries breath sway, recoil, weapon kick and
     * trauma shake on top of the look yaw, so David's whole body counter-
     * rotated with the breathing sine while standing still and flinched on
     * every shot.
     *
     * Second, it was instantaneous: a 180 degree flick teleported the body,
     * because nothing in the controller limited turn rate.
     *
     * Now: when he is aiming or has just fired, the body drives to the LOOK yaw
     * (m.yaw, clean of all the additive channels) fast, so the gun still points
     * down the crosshair. Otherwise it turns toward where he is actually
     * MOVING, at a limited rate — which is what reads as weight, and what stops
     * a strafing run cycle from moonwalking sideways.
     */
    const aiming = this.adsAmount > 0.15 || this._sinceFire < 0.9;
    let desiredYaw = m.yaw;
    if (!aiming) {
      const vx = m.velocity.x;
      const vz = m.velocity.z;
      if (vx * vx + vz * vz > 0.36) this._bodyYawWanted = Math.atan2(vx, vz);
      desiredYaw = this._bodyYawWanted;
    } else {
      this._bodyYawWanted = m.yaw;
    }
    const dYaw = angleDelta(this._bodyYaw, desiredYaw);
    // Rate scales with how far there is to go, so small corrections are smooth
    // and a full about-face still completes quickly instead of crawling.
    const rate = (aiming ? TP.aimTurnRate : TP.turnRate) * (1 + Math.abs(dYaw) * 0.85);
    this._bodyYaw += Math.sign(dYaw) * Math.min(Math.abs(dYaw), rate * dt);
    b.group.rotation.y = this._bodyYaw;
    b.group.updateMatrixWorld(true);

    // A look/aim point far down the aim ray. The animator aims the upper body
    // at it, which is what keeps the weapon on the crosshair.
    this._aimTarget.copy(this.aimOrigin).addScaledVector(this.rig.forward, 60);

    const speed = m.horizontalSpeed;
    const crouch = m.stance === 'crouch' || m.stance === 'prone';
    const moving = speed > 0.25;
    let clip;
    if (crouch) clip = moving ? 'crouchWalk' : 'crouchIdle';
    // The run threshold was 2.6 while steady ground speed is 4.57, so 'walk'
    // was only ever visible during the ~50 ms acceleration ramp — David went
    // from a standstill to a full run inside two frames. Walking now owns
    // everything up to a real jog.
    else if (speed > TP.runSpeed) clip = 'run';
    else if (moving) clip = 'walk';
    else clip = 'idle';

    /**
     * Preallocated. This was a fresh object literal every frame — the only
     * per-frame allocation in this file. `Animator.setState` only reads fields,
     * so reusing one object is behaviourally identical.
     */
    const st = this._animState;
    st.clip = clip;
    st.speed = speed;
    st.crouch = crouch;
    st.aimTarget = this._aimTarget;
    st.lookTarget = this._aimTarget;
    // Drop the aim pose right down when he is not actually aiming, so the
    // upper body relaxes instead of holding a permanent shouldered stance.
    st.aimWeight = Math.max(this.adsAmount, aiming ? 0.55 : 0.12);
    st.suppress = 0;
    b.animator.setState(st);

    this._animAccum += dt;
    b.animator.update(this._animAccum, ctx.time.elapsed);
    this._animAccum = 0;
  }

  /**
   * Push the camera back onto the boom, pulling it in when the arm would put it
   * through geometry. A sphere cast rather than a ray: a ray slips through the
   * corner of a wall and lands the camera inside a house.
   */
  _applyBoom(ctx) {
    const cam = ctx.camera;
    this._boomDir.copy(this.rig.forward).normalize();
    this._boomRight.crossVectors(this._boomDir, this._boomUp).normalize();

    // Aim pulls the camera in and over — the same move GTA makes when you raise
    // the sights, so the shoulder stops eating the middle of the screen.
    const t = clamp01(this.adsAmount);
    const dist = lerp(TP.distance, TP.adsDistance, t);
    const side = lerp(TP.shoulder, TP.adsShoulder, t);

    this._boomDesired
      .copy(this.aimOrigin)
      .addScaledVector(this._boomRight, side)
      .addScaledVector(this._boomUp, TP.height)
      .addScaledVector(this._boomDir, -dist);

    const phys = this.physics;
    if (phys?.sphereCast) {
      this._boomDir.copy(this._boomDesired).sub(this.aimOrigin);
      const len = this._boomDir.length();
      if (len > 1e-4) {
        this._boomDir.divideScalar(len);
        const hit = phys.sphereCast(this.aimOrigin, this._boomDir, TP.radius, len, phys.MASK.WORLD);
        if (hit?.hit) {
          this._boomDesired
            .copy(this.aimOrigin)
            .addScaledVector(this._boomDir, Math.max(TP.minDistance, hit.distance - TP.skin));
        }
      }
    }

    cam.position.copy(this._boomDesired);
    cam.updateMatrixWorld();
  }

  /**
   * World-space muzzle of the weapon in David's hands, or null before the body
   * exists. `weapons` uses this instead of the viewmodel's muzzle in third
   * person: the viewmodel lives in `viewScene` on the camera, which now sits on
   * a boom three metres behind him, so its muzzle is nowhere near the gun.
   */
  muzzleWorld(out) {
    if (!this.body) return null;
    return out.copy(this.body.animator.muzzleWorld);
  }

  /** Keep the AI-facing hitbox on the interpolated capsule. */
  _syncHitbox() {
    if (!this.hitbox) return;
    const m = this.movement;
    const p = m.renderPosition;
    const r = 0.3;
    const h = STANCE[m.stance].height;
    this.hitbox.setSegment(p.x, p.y + r, p.z, p.x, p.y + Math.max(r, h - r), p.z, r);
    this.hitbox.enabled = !this.health.dead;
  }

  _updateAds(dt) {
    const input = this.ctx.input;
    const m = this.movement;
    this.adsRequested =
      this.controlEnabled && input.ads && !m.mantleMotion.active && !m.sliding && !this.health.dead;

    if (this._adsExternal) {
      // `weapons` is driving the blend; stop trusting it if it goes quiet.
      this._adsExternalAge += dt;
      if (this._adsExternalAge > 0.6) this._adsExternal = false;
    }
    if (!this._adsExternal) {
      this.adsAmount = approach(this.adsAmount, this.adsRequested ? 1 : 0, 0.075, dt);
    }
    m.adsAmount = this.adsAmount;
  }

  /** Turn the movement machine's one-shot flags into events + camera impulses. */
  _drainMovementEvents() {
    const m = this.movement;

    if (m.landEvent.pending) {
      m.landEvent.pending = false;
      const speed = m.landEvent.speed;
      const mag = this.rig.onLand(speed);
      this._landPayload.velocity = speed;
      this._landPayload.surface = m.landEvent.surface;
      this._landPayload.position.copy(m.position);
      this.ctx.events.emit('player:land', this._landPayload);
      // Fall damage — CoD only hurts you past a real drop.
      const L = CAMERA.land;
      if (speed > L.damageSpeed) {
        this.health.damage((speed - L.damageSpeed) * L.damagePerSpeed, null, { type: 'fall' });
      }
      if (mag > 0.35) this.movement._footHold = FOOTSTEP.landHold;
    }

    if (m.stepEvent.pending) {
      m.stepEvent.pending = false;
      const e = this._stepPayload;
      e.position.set(m.stepEvent.x, m.stepEvent.y, m.stepEvent.z);
      e.surface = m.stepEvent.surface;
      e.running = m.stepEvent.running;
      e.left = m.stepEvent.left;
      e.speed = m.horizontalSpeed;
      e.stance = m.stance;
      this.rig.onFootstep(e.running, m.stance);
      this.ctx.events.emit('player:footstep', e);
    }

    if (m.jumped) {
      m.jumped = false;
      this.rig.addRecoil(-0.35 * DEG, 0, 0, 0.004);
      this._jumpPayload.position.copy(m.position);
      this.ctx.events.emit('player:jump', this._jumpPayload);
    }

    if (m.slideStarted) {
      m.slideStarted = false;
      this.rig.onSlideStart(m._slideSide);
    }
    if (m.slideEnded) m.slideEnded = false;

    if (m.mantleEvent.pending) {
      m.mantleEvent.pending = false;
      this._mantlePayload.kind = m.mantleEvent.kind;
      this._mantlePayload.height = m.mantleEvent.height;
      this.rig.addTrauma(m.mantleEvent.kind === 'vault' ? 0.08 : 0.14);
      this.ctx.events.emit('player:mantle', this._mantlePayload);
    }
  }

  _publishState() {
    const m = this.movement;
    const s = this._statePayload;
    const leaning = Math.abs(m.leanAmount) > 0.35;
    const state = leaning && (m.state === 'stand' || m.state === 'crouch') ? 'lean' : m.state;
    s.state = state;
    s.stance = m.stance;
    s.crouched = m.stance !== 'stand';
    s.sprinting = m.sprinting;
    s.tacticalSprint = m.tacticalSprint;
    s.sliding = m.sliding;
    s.ads = this.adsAmount > 0.5;
    s.adsProgress = this.adsAmount;
    s.grounded = m.grounded;
    s.airborne = !m.grounded;
    s.mantling = m.mantleMotion.active;
    s.lean = m.leanAmount;
    s.speed = m.horizontalSpeed;
    s.health = this.health.value;
    s.healthFraction = this.health.fraction;
    // Emit only when something discrete actually changed. Field-wise compare,
    // because building a key string every frame would be a per-frame allocation.
    const q = this._prev;
    if (
      q.state !== s.state || q.stance !== s.stance || q.sprinting !== s.sprinting ||
      q.tacticalSprint !== s.tacticalSprint || q.sliding !== s.sliding ||
      q.grounded !== s.grounded || q.ads !== s.ads || q.mantling !== s.mantling
    ) {
      q.state = s.state; q.stance = s.stance; q.sprinting = s.sprinting;
      q.tacticalSprint = s.tacticalSprint; q.sliding = s.sliding;
      q.grounded = s.grounded; q.ads = s.ads; q.mantling = s.mantling;
      this.ctx.events.emit('player:state', s);
    }
  }

  /* ==================================================================== */
  /* incoming damage                                                      */
  /* ==================================================================== */

  _onDamageDealt(e) {
    if (!e) return;
    const t = e.target;
    if (t !== this && t !== 'player' && t?.isPlayer !== true) return;
    // Direction indicators need the *shooter*, not the impact point: `ai` sets
    // `point` to where the round landed (which is the player), and `from` to the
    // muzzle. Using `point` pinned every arc to dead ahead.
    const from = e.from ?? e.source?.position ?? e.point ?? null;
    this.applyDamage(e.amount ?? 0, from, { type: 'bullet' });
  }

  _onExplosion(e) {
    if (!e?.position) return;
    // `aimOrigin`, not `ctx.camera.position`. In third person the camera is the
    // boom, up to 3.1 m BEHIND David, so measuring blast range and line of
    // sight from it meant a grenade at his feet could read as occluded by
    // whatever stood behind the camera.
    const eye = this.aimOrigin;
    const r = e.radius ?? 5;
    const d = this._tmp.copy(e.position).distanceTo(eye);
    if (d > r * 1.6) return;
    // Occluded blasts still shake you, they just do not wound you.
    const clear = this.physics.lineOfSight(e.position, eye, this.physics.MASK.EXPLOSION);
    const falloff = Math.pow(clamp01(1 - d / r), 1.6);
    this.rig.addTrauma(clamp01(falloff * 1.4));
    this.health.addSuppression(HEALTH.suppression.perExplosion * falloff);
    if (clear && falloff > 0.02) {
      this.applyDamage((e.damage ?? 90) * falloff, e.position, { type: 'explosion' });
    }
  }

  _onBulletImpact(e) {
    if (!e?.point || this.health.dead) return;
    // `aimOrigin`, not `ctx.camera.position`. In third person the camera is the
    // boom, up to 3.1 m BEHIND David, so measuring blast range and line of
    // sight from it meant a grenade at his feet could read as occluded by
    // whatever stood behind the camera.
    const eye = this.aimOrigin;
    const dx = e.point.x - eye.x, dy = e.point.y - eye.y, dz = e.point.z - eye.z;
    const d2 = dx * dx + dy * dy + dz * dz;
    const R = HEALTH.suppression.radius;
    if (d2 > R * R) return;
    // Heuristic: rounds we fired land where we are looking. Anything cracking in
    // beside or behind us is somebody shooting at us.
    const d = Math.sqrt(d2) || 1e-4;
    const f = this.rig.forward;
    if ((dx * f.x + dy * f.y + dz * f.z) / d > 0.55) return;
    this.health.addSuppression(HEALTH.suppression.perNearMiss * (1 - d / R));
  }

  /* ==================================================================== */
  /* public API                                                           */
  /* ==================================================================== */

  /**
   * HUD adapter polled by `ui` every lateUpdate. Shape is fixed by the contract
   * documented at the top of src/ui/index.js. Preallocated and mutated in place.
   */
  getHudState() {
    const h = this._hudState;
    const m = this.movement;
    const hp = this.health;
    h.health = hp.value;
    h.maxHealth = hp.max;
    h.regen = hp.regenerating;
    h.dead = hp.dead;
    h.suppression = hp.suppression;
    // 0..1 against tactical sprint, which is the fastest the player can move —
    // `ui` uses this directly as the reticle-bloom weight.
    h.move = Math.min(1, m.horizontalSpeed / MOVE.tacSprintSpeed);
    h.sprint = m.sprinting || m.tacticalSprint;
    h.crouch = m.stance === 'crouch' || m.stance === 'prone';
    h.ads = this.adsAmount > 0.5;
    h.airborne = !m.grounded;
    h.position = this.position;
    return h;
  }

  get position() {
    return this.movement.renderPosition;
  }
  get feetPosition() {
    return this.movement.position;
  }
  get eyePosition() {
    return this.rig.eyePosition;
  }
  get velocity() {
    return this.movement.velocity;
  }
  get forward() {
    return this.rig.forward;
  }
  get yaw() {
    return this.movement.yaw;
  }
  get pitch() {
    return this.movement.pitch;
  }
  get speed() {
    return this.movement.speed;
  }
  get horizontalSpeed() {
    return this.movement.horizontalSpeed;
  }
  get character() {
    return this.movement.character;
  }
  get state() {
    return this._statePayload.state;
  }
  get stance() {
    return this.movement.stance;
  }
  get sprinting() {
    return this.movement.sprinting;
  }
  get tacticalSprint() {
    return this.movement.tacticalSprint;
  }
  get sliding() {
    return this.movement.sliding;
  }
  get slideProgress() {
    return this.movement.slideProgress;
  }
  get grounded() {
    return this.movement.grounded;
  }
  get airborne() {
    return !this.movement.grounded;
  }
  get mantling() {
    return this.movement.mantleMotion.active;
  }
  get leanAmount() {
    return this.movement.leanAmount;
  }
  get eyeHeight() {
    return this.rig.eye;
  }
  get adsProgress() {
    return this.adsAmount;
  }
  get viewKick() {
    return this.rig.viewKick;
  }
  get cameraRig() {
    return this.rig;
  }
  get height() {
    return STANCE[this.movement.stance].height;
  }
  get maxHealth() {
    return this.health.max;
  }
  get healthFraction() {
    return this.health.fraction;
  }
  get lowHealth() {
    return this.health.low;
  }
  get dead() {
    return this.health.dead;
  }
  get suppression() {
    return this.health.suppression;
  }
  get damageIndicators() {
    return this.health.indicators;
  }
  get heartbeatPulse() {
    return this.health.pulse;
  }
  get bobPhase() {
    return this.rig.bobPhase;
  }

  /** `weapons` owns the ADS curve; hand it over and everything else follows. */
  setAdsProgress(v) {
    this.adsAmount = clamp01(v);
    this._adsExternal = true;
    this._adsExternalAge = 0;
    this.movement.adsAmount = this.adsAmount;
  }

  addRecoil(pitch, yaw, roll, punch) {
    this.rig.addRecoil(pitch, yaw, roll, punch);
  }
  addKick(pitch, yaw, roll) {
    this.rig.addKick(pitch, yaw, roll);
  }
  addTrauma(a) {
    this.rig.addTrauma(a);
  }
  /** Alias some subsystems may reach for. */
  addCameraShake(a) {
    this.rig.addTrauma(a);
  }

  applyDamage(amount, from, opts) {
    return this.health.damage(amount, from ?? null, { yaw: this.movement.yaw, ...opts });
  }
  heal(a) {
    this.health.heal(a);
  }
  addSuppression(a) {
    this.health.addSuppression(a);
  }

  setControlEnabled(on) {
    this.controlEnabled = !!on;
    this.movement.controlEnabled = this.controlEnabled;
    if (!on) {
      this.movement.latchInput(-2); // flush held keys
      this.movement.velocity.set(0, 0, 0);
      this.movement.sprinting = false;
      this.movement.tacticalSprint = false;
      this.movement.sliding = false;
      this.movement.cancelMantle();
      this.adsAmount = 0;
      this._adsExternal = false;
    } else {
      this.movement._cmdFrame = -1;
    }
  }

  /**
   * Move the player. `eyeOrPos` is the EYE position (that is what the shot
   * harness hands us — it passes the camera transform); `rot` may be a
   * THREE.Euler, an object with `.y`, or a yaw in radians.
   */
  teleport(eyeOrPos, rot) {
    if (!eyeOrPos) return;
    const eyeH = STANCE.stand.eye;
    const feetY = eyeOrPos.y - eyeH;
    if (typeof rot === 'number') {
      this.movement.yaw = rot;
    } else if (rot) {
      this.movement.yaw = rot.y ?? this.movement.yaw;
      this.movement.pitch = clamp(rot.x ?? 0, -CAMERA.pitchLimit, CAMERA.pitchLimit);
    }
    this.movement.teleport(eyeOrPos.x, feetY, eyeOrPos.z);
    this.rig.reset(eyeH);
    this.rig.eyePosition.set(eyeOrPos.x, eyeOrPos.y, eyeOrPos.z);
    this.rig.fov = this.ctx.config.fov;
    this._lookFrame = this.ctx.time.frame;
    this._prev.state = '';
  }

  respawn(index = 0) {
    const world = this.ctx.peek('world');
    const sp = world?.spawn?.(index);
    this.health.reset(true);
    if (!sp?.position) return;
    const gy = this.physics.groundHeight(sp.position.x, sp.position.z, sp.position.y + 6);
    const feetY = Number.isFinite(gy) ? gy + 0.03 : sp.position.y;
    this.movement.yaw = sp.yaw ?? 0;
    this.movement.pitch = 0;
    this.movement.teleport(sp.position.x, feetY, sp.position.z);
    this.rig.reset(STANCE.stand.eye);
  }

  /** Named states for dev overlays and future shots. */
  debugState(name) {
    const m = this.movement;
    switch (name) {
      case 'sprint':
        m.stanceWant = 'stand';
        m.sprinting = true;
        m.velocity.set(-Math.sin(m.yaw), 0, -Math.cos(m.yaw)).multiplyScalar(MOVE.sprintSpeed);
        break;
      case 'tacsprint':
        m.sprinting = true;
        m.tacticalSprint = true;
        break;
      case 'crouch':
        m.stanceWant = 'crouch';
        break;
      case 'prone':
        m.stanceWant = 'prone';
        break;
      case 'slide':
        m.sprinting = true;
        m.velocity.set(-Math.sin(m.yaw), 0, -Math.cos(m.yaw)).multiplyScalar(MOVE.sprintSpeed);
        m._beginSlide(m.cmd, m._wish.set(-Math.sin(m.yaw), 0, -Math.cos(m.yaw)), 1, MOVE.sprintSpeed);
        m.slideStarted = false;
        this.rig.onSlideStart(1);
        break;
      case 'air':
        m.velocity.y = JUMP_SPEED;
        m.grounded = false;
        break;
      case 'hurt':
        this.health.value = this.health.max * 0.28;
        this.health.lastDamageTime = this.ctx.time.elapsed;
        this.health.effect = clamp01((HEALTH.lowThreshold - 0.28) / HEALTH.lowThreshold);
        break;
      case 'critical':
        this.health.value = this.health.max * 0.11;
        this.health.lastDamageTime = this.ctx.time.elapsed;
        this.health.effect = 1;
        this.health.hitFlash = 0.6;
        break;
      case 'reset':
        this.health.reset(true);
        this.health.effect = 0;
        break;
      default:
        break;
    }
    return {
      state: this.state, stance: m.stance, speed: m.horizontalSpeed,
      health: this.health.value, ads: this.adsAmount,
    };
  }

  /** Snapshot for the dev HUD / debugging. */
  get stats() {
    const m = this.movement;
    return {
      state: this.state,
      stance: m.stance,
      speed: m.horizontalSpeed,
      vertical: m.velocity.y,
      grounded: m.grounded,
      lean: m.leanAmount,
      fov: this.rig.fov,
      health: this.health.value,
      suppression: this.health.suppression,
    };
  }

  dispose() {
    for (const off of this._offEvents) off?.();
    this._offEvents.length = 0;
    if (this.hitbox) {
      this.physics?.removeCollider(this.hitbox);
      this.hitbox = null;
    }
    this._unregisterPass?.();
    this.lowHealthPass?.dispose();
    this.lowHealthPass = null;
    this.movement?.dispose();
  }
}
