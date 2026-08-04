/**
 * Input aggregation: keyboard, mouse (pointer-locked), and gamepad, exposed as
 * a stable per-frame snapshot so gameplay never touches raw DOM events.
 *
 * Edge queries (`pressed`, `released`) are valid only during the frame in which
 * the transition happened — read them in update(), not fixedUpdate().
 */

/**
 * ON-SCREEN BUTTONS for touch devices.
 *
 * Exported so `ui` draws exactly what `input` tests — one source of truth, so
 * the visual and the hit target cannot drift apart. Positions are fractions of
 * the viewport (y from the top); radius is a fraction of min(width, height).
 *
 * `code` is a synthetic key/mouse code injected into the normal `down` set, so
 * every consumer (`action()`, `get fire`, `held('Tab')`) works unchanged and
 * nothing downstream needs to know touch exists.
 */
export const TOUCH_BUTTONS = [
  { id: 'fire', code: 'Mouse0', label: 'FIRE', x: 0.885, y: 0.775, r: 0.085 },
  { id: 'use', code: 'KeyF', label: 'USE', x: 0.715, y: 0.735, r: 0.058 },
  { id: 'wheel', code: 'Tab', label: 'WEAP', x: 0.885, y: 0.545, r: 0.058 },
  { id: 'jump', code: 'Space', label: 'JUMP', x: 0.715, y: 0.925, r: 0.058 },
];

/** Left of this fraction of the screen is the movement stick; right is look. */
const TOUCH_STICK_ZONE = 0.42;
/** Stick travel, as a fraction of min(width, height), for full deflection. */
const TOUCH_STICK_RANGE = 0.10;
/**
 * Touch look is in CSS pixels while mouse look is in raw device deltas, and a
 * thumb drags far less than a mouse. This scales the drag before it enters the
 * shared accumulator so `config.sensitivity` stays meaningful for both.
 */
const TOUCH_LOOK_SCALE = 1.9;

export const ACTIONS = {
  forward: ['KeyW', 'ArrowUp'],
  back: ['KeyS', 'ArrowDown'],
  left: ['KeyA', 'ArrowLeft'],
  right: ['KeyD', 'ArrowRight'],
  jump: ['Space'],
  crouch: ['ControlLeft', 'KeyC'],
  prone: ['KeyZ'],
  sprint: ['ShiftLeft'],
  reload: ['KeyR'],
  use: ['KeyF'],
  melee: ['KeyV'],
  leanLeft: ['KeyQ'],
  leanRight: ['KeyE'],
  swapWeapon: ['Digit1', 'Digit2', 'Tab'],
  grenade: ['KeyG'],
  flashlight: ['KeyT'],
  pause: ['Escape'],
};

export class Input {
  constructor(canvas, config) {
    this.canvas = canvas;
    this.config = config;

    this.down = new Set(); // codes currently held
    this._pressed = new Set(); // went down this frame
    this._released = new Set(); // went up this frame
    this._pendingDown = new Set();
    this._pendingUp = new Set();

    /** Accumulated pointer delta for this frame, in radians after sensitivity. */
    this.look = { x: 0, y: 0 };
    this._rawLook = { x: 0, y: 0 };
    this.wheel = 0;
    this._pendingWheel = 0;

    this.pointerLocked = false;
    this.enabled = true;
    /** Set true by capture mode so scripted shots aren't fought by real input. */
    this.frozen = false;

    this.gamepadIndex = null;
    this.stick = { moveX: 0, moveY: 0, lookX: 0, lookY: 0 };

    /**
     * Touch state. `touchActive` flips true on the first touch and is what `ui`
     * uses to decide whether to draw the on-screen controls at all — a desktop
     * player never sees them.
     */
    this.touchActive = false;
    /** Live stick deflection, -1..1, for `ui` to draw the thumb position. */
    this.touchStick = { x: 0, y: 0, active: false, ox: 0, oy: 0 };
    this._touchMove = -1; // pointerId driving the stick
    this._touchLook = -1; // pointerId driving the camera
    this._touchLookX = 0;
    this._touchLookY = 0;
    this._touchBtn = new Map(); // pointerId -> button code
    /** Set once if the gamepad API is forbidden here; stops all polling. */
    this._padBlocked = false;

    this._bound = {
      keydown: this._onKeyDown.bind(this),
      keyup: this._onKeyUp.bind(this),
      mousedown: this._onMouseDown.bind(this),
      mouseup: this._onMouseUp.bind(this),
      mousemove: this._onMouseMove.bind(this),
      wheel: this._onWheel.bind(this),
      lockchange: this._onLockChange.bind(this),
      blur: this._onBlur.bind(this),
      contextmenu: (e) => e.preventDefault(),
      touchstart: this._onTouchStart.bind(this),
      touchmove: this._onTouchMove.bind(this),
      touchend: this._onTouchEnd.bind(this),
    };
  }

  attach() {
    addEventListener('keydown', this._bound.keydown);
    addEventListener('keyup', this._bound.keyup);
    addEventListener('mousedown', this._bound.mousedown);
    addEventListener('mouseup', this._bound.mouseup);
    addEventListener('mousemove', this._bound.mousemove);
    addEventListener('wheel', this._bound.wheel, { passive: true });
    addEventListener('blur', this._bound.blur);
    document.addEventListener('pointerlockchange', this._bound.lockchange);
    this.canvas.addEventListener('contextmenu', this._bound.contextmenu);
    // `passive: false` because the handlers preventDefault to stop the page
    // scrolling, pinch-zooming and firing synthetic mouse events under us.
    this.canvas.addEventListener('touchstart', this._bound.touchstart, { passive: false });
    this.canvas.addEventListener('touchmove', this._bound.touchmove, { passive: false });
    this.canvas.addEventListener('touchend', this._bound.touchend, { passive: false });
    this.canvas.addEventListener('touchcancel', this._bound.touchend, { passive: false });
  }

  /* ====================================================================== */
  /*  touch                                                                 */
  /* ====================================================================== */

  /** Screen-space radius of a button, in pixels. */
  _btnR(b) {
    return b.r * Math.min(innerWidth, innerHeight);
  }

  /** Which on-screen button, if any, is under this point. */
  _hitButton(px, py) {
    for (let i = 0; i < TOUCH_BUTTONS.length; i++) {
      const b = TOUCH_BUTTONS[i];
      const bx = b.x * innerWidth;
      const by = b.y * innerHeight;
      const r = this._btnR(b);
      if ((px - bx) ** 2 + (py - by) ** 2 <= r * r) return b;
    }
    return null;
  }

  _onTouchStart(e) {
    if (!this.enabled) return;
    e.preventDefault();
    // Anything gated on pointer lock (the menu's click-to-play, mouse-look
    // guards) should behave as "we have control" once a finger is down.
    this.touchActive = true;
    this.pointerLocked = true;
    for (const t of e.changedTouches) {
      const btn = this._hitButton(t.clientX, t.clientY);
      if (btn) {
        this._touchBtn.set(t.identifier, btn.code);
        this._pendingDown.add(btn.code);
        this.down.add(btn.code);
        continue;
      }
      if (t.clientX < innerWidth * TOUCH_STICK_ZONE) {
        if (this._touchMove !== -1) continue;
        this._touchMove = t.identifier;
        this.touchStick.active = true;
        this.touchStick.ox = t.clientX;
        this.touchStick.oy = t.clientY;
        this.touchStick.x = 0;
        this.touchStick.y = 0;
      } else if (this._touchLook === -1) {
        this._touchLook = t.identifier;
        this._touchLookX = t.clientX;
        this._touchLookY = t.clientY;
      }
    }
  }

  _onTouchMove(e) {
    if (!this.enabled) return;
    e.preventDefault();
    const range = TOUCH_STICK_RANGE * Math.min(innerWidth, innerHeight);
    for (const t of e.changedTouches) {
      if (t.identifier === this._touchMove) {
        let dx = (t.clientX - this.touchStick.ox) / range;
        let dy = (t.clientY - this.touchStick.oy) / range;
        const len = Math.hypot(dx, dy);
        if (len > 1) {
          dx /= len;
          dy /= len;
        }
        this.touchStick.x = dx;
        this.touchStick.y = dy;
        // `stick` is the gamepad channel; moveVector already blends it with the
        // keys, so touch needs no separate path. moveY is forward-positive.
        this.stick.moveX = dx;
        this.stick.moveY = -dy;
        // Push the stick most of the way and you run. Avoids a sprint button.
        const sprint = Math.hypot(dx, dy) > 0.85;
        if (sprint) this.down.add('ShiftLeft');
        else this.down.delete('ShiftLeft');
      } else if (t.identifier === this._touchLook) {
        // Feed the same accumulator mouse movement uses, so sensitivity,
        // inversion and the per-frame reset all apply unchanged.
        this._rawLook.x += (t.clientX - this._touchLookX) * TOUCH_LOOK_SCALE;
        this._rawLook.y += (t.clientY - this._touchLookY) * TOUCH_LOOK_SCALE;
        this._touchLookX = t.clientX;
        this._touchLookY = t.clientY;
      }
    }
  }

  _onTouchEnd(e) {
    e.preventDefault();
    for (const t of e.changedTouches) {
      const code = this._touchBtn.get(t.identifier);
      if (code !== undefined) {
        this._touchBtn.delete(t.identifier);
        this._pendingUp.add(code);
        this.down.delete(code);
        continue;
      }
      if (t.identifier === this._touchMove) {
        this._touchMove = -1;
        this.touchStick.active = false;
        this.touchStick.x = 0;
        this.touchStick.y = 0;
        this.stick.moveX = 0;
        this.stick.moveY = 0;
        this.down.delete('ShiftLeft');
      } else if (t.identifier === this._touchLook) {
        this._touchLook = -1;
      }
    }
  }

  detach() {
    removeEventListener('keydown', this._bound.keydown);
    removeEventListener('keyup', this._bound.keyup);
    removeEventListener('mousedown', this._bound.mousedown);
    removeEventListener('mouseup', this._bound.mouseup);
    removeEventListener('mousemove', this._bound.mousemove);
    removeEventListener('wheel', this._bound.wheel);
    removeEventListener('blur', this._bound.blur);
    document.removeEventListener('pointerlockchange', this._bound.lockchange);
    this.canvas.removeEventListener('contextmenu', this._bound.contextmenu);
    this.canvas.removeEventListener('touchstart', this._bound.touchstart);
    this.canvas.removeEventListener('touchmove', this._bound.touchmove);
    this.canvas.removeEventListener('touchend', this._bound.touchend);
    this.canvas.removeEventListener('touchcancel', this._bound.touchend);
  }

  requestPointerLock() {
    // Chrome returns a promise that rejects if the document is not eligible
    // (headless capture, an iframe, a lock request too soon after an exit).
    // An unhandled rejection there shows up as a page error in the harness, so
    // swallow it: failing to lock is not a game error.
    try {
      const p = this.canvas.requestPointerLock?.();
      if (p && typeof p.catch === 'function') p.catch(() => {});
    } catch {
      /* not eligible — keep running unlocked */
    }
  }

  _onKeyDown(e) {
    if (!this.enabled) return;
    if (e.repeat) return;
    // Let devtools/refresh through; swallow everything else the game binds.
    if (!e.metaKey && !e.ctrlKey) e.preventDefault();
    this._pendingDown.add(e.code);
  }

  _onKeyUp(e) {
    if (!this.enabled) return;
    this._pendingUp.add(e.code);
  }

  _onMouseDown(e) {
    if (!this.enabled) return;
    if (!this.pointerLocked && e.button === 0) this.requestPointerLock();
    this._pendingDown.add(`Mouse${e.button}`);
  }

  _onMouseUp(e) {
    if (!this.enabled) return;
    this._pendingUp.add(`Mouse${e.button}`);
  }

  _onMouseMove(e) {
    if (!this.enabled || !this.pointerLocked || this.frozen) return;
    // movementX/Y is already relative and unaffected by cursor clamping.
    this._rawLook.x += e.movementX ?? 0;
    this._rawLook.y += e.movementY ?? 0;
  }

  _onWheel(e) {
    if (!this.enabled) return;
    this._pendingWheel += Math.sign(e.deltaY);
  }

  _onLockChange() {
    this.pointerLocked = document.pointerLockElement === this.canvas;
    if (!this.pointerLocked) this._onBlur();
  }

  /** Losing focus must release every held key, or the player runs forever. */
  _onBlur() {
    for (const code of this.down) this._pendingUp.add(code);
    this._rawLook.x = 0;
    this._rawLook.y = 0;
  }

  beginFrame() {
    this._pressed.clear();
    this._released.clear();

    for (const code of this._pendingDown) {
      if (!this.down.has(code)) {
        this.down.add(code);
        this._pressed.add(code);
      }
    }
    for (const code of this._pendingUp) {
      if (this.down.delete(code)) this._released.add(code);
    }
    this._pendingDown.clear();
    this._pendingUp.clear();

    const s = this.config.sensitivity;
    this.look.x = this.frozen ? 0 : this._rawLook.x * s;
    this.look.y = this.frozen ? 0 : this._rawLook.y * s * (this.config.invertY ? -1 : 1);
    this._rawLook.x = 0;
    this._rawLook.y = 0;

    this.wheel = this._pendingWheel;
    this._pendingWheel = 0;

    this._pollGamepad();
  }

  endFrame() {}

  _pollGamepad() {
    /**
     * `navigator.getGamepads()` THROWS in a context whose permissions policy
     * disallows the gamepad feature — it does not return null, and optional
     * chaining does not help because the method exists. Sandboxed iframes do
     * exactly this.
     *
     * Unguarded, that threw once per frame from inside the update loop, which
     * aborted the frame before anything rendered: a black canvas with a working
     * DOM HUD, on hardware that was otherwise perfectly capable. Measured on a
     * Mali-G57 phone at 327 identical exceptions.
     *
     * One probe decides it. If the API is unavailable or forbidden, polling is
     * switched off permanently rather than throwing (or paying a try/catch)
     * every frame thereafter.
     */
    if (this._padBlocked) return;
    let pads;
    try {
      pads = navigator.getGamepads?.() ?? [];
    } catch {
      this._padBlocked = true;
      return;
    }
    const pad = pads[this.gamepadIndex ?? 0] ?? pads.find(Boolean);
    if (!pad) {
      // Do NOT zero the stick while touch is driving it — touch feeds this same
      // channel, so clearing it here would cancel every finger movement.
      if (!this.touchActive) {
        this.stick.moveX = this.stick.moveY = this.stick.lookX = this.stick.lookY = 0;
      }
      return;
    }
    const dz = (v) => (Math.abs(v) < 0.16 ? 0 : (v - Math.sign(v) * 0.16) / 0.84);
    this.stick.moveX = dz(pad.axes[0] ?? 0);
    this.stick.moveY = dz(pad.axes[1] ?? 0);
    // Cubic response curve on the look stick — fine aim near centre, fast flicks at the edge.
    const curve = (v) => Math.sign(v) * Math.abs(v) ** 2.4;
    this.stick.lookX = curve(dz(pad.axes[2] ?? 0));
    this.stick.lookY = curve(dz(pad.axes[3] ?? 0));
  }

  /** True while any key bound to `action` is held. */
  action(name) {
    const codes = ACTIONS[name];
    if (!codes) return false;
    for (const c of codes) if (this.down.has(c)) return true;
    return false;
  }

  actionPressed(name) {
    const codes = ACTIONS[name];
    if (!codes) return false;
    for (const c of codes) if (this._pressed.has(c)) return true;
    return false;
  }

  held(code) {
    return this.down.has(code);
  }

  pressed(code) {
    return this._pressed.has(code);
  }

  released(code) {
    return this._released.has(code);
  }

  get fire() {
    return this.down.has('Mouse0');
  }

  get firePressed() {
    return this._pressed.has('Mouse0');
  }

  get ads() {
    return this.down.has('Mouse2');
  }

  /** Normalised WASD + left-stick movement, clamped to the unit disc so
   *  diagonals aren't faster than cardinals. */
  moveVector(out = { x: 0, y: 0 }) {
    let x = (this.action('right') ? 1 : 0) - (this.action('left') ? 1 : 0);
    let y = (this.action('forward') ? 1 : 0) - (this.action('back') ? 1 : 0);
    x += this.stick.moveX;
    y -= this.stick.moveY;
    const len = Math.hypot(x, y);
    if (len > 1) {
      x /= len;
      y /= len;
    }
    out.x = x;
    out.y = y;
    return out;
  }
}
