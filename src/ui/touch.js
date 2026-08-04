import { el, setStyle, setClass } from './util.js';
import { TOUCH_BUTTONS } from '../core/input.js';

/**
 * On-screen controls for touch devices.
 *
 * The game had no touch input at all — it needed a keyboard, a mouse and
 * pointer lock — so on a phone it was not slow, it was uncontrollable. `input`
 * now synthesises key codes from touch; this draws the affordances for it.
 *
 * The button table is imported from `input` rather than duplicated, so what is
 * drawn and what is hit-tested cannot drift apart.
 *
 * Hidden entirely until the first touch (`input.touchActive`), so a desktop
 * player never sees any of it. Everything is positioned with percentages and
 * sized off `vmin`, so it lands on the same place as the hit test at any aspect
 * ratio without JS doing layout maths per frame.
 */
export class TouchControls {
  constructor(parent) {
    this.root = el('div', 'ow-touch', parent);
    setStyle(this.root, 'display', 'none');
    this._shown = false;

    // Movement stick: a ring that appears where the thumb lands, with a nub.
    this.stick = el('div', 'ow-touch-stick', this.root);
    this.nub = el('i', null, this.stick);
    setStyle(this.stick, 'display', 'none');

    for (const b of TOUCH_BUTTONS) {
      const n = el('div', 'ow-touch-btn', this.root, b.label);
      // Percent for position and vmin for size: identical geometry to the hit
      // test in `input`, which uses viewport fractions and min(w, h).
      setStyle(n, 'left', `${b.x * 100}%`);
      setStyle(n, 'top', `${b.y * 100}%`);
      setStyle(n, 'width', `${b.r * 200}vmin`);
      setStyle(n, 'height', `${b.r * 200}vmin`);
      b._node = n;
    }
  }

  /** @param {object} input the core Input instance */
  update(input) {
    const on = input?.touchActive === true;
    if (on !== this._shown) {
      this._shown = on;
      setStyle(this.root, 'display', on ? '' : 'none');
    }
    if (!on) return;

    const s = input.touchStick;
    if (s.active) {
      setStyle(this.stick, 'display', '');
      setStyle(this.stick, 'left', `${s.ox}px`);
      setStyle(this.stick, 'top', `${s.oy}px`);
      // The nub follows the thumb inside the ring.
      setStyle(this.nub, 'transform', `translate(-50%,-50%) translate(${(s.x * 42).toFixed(1)}%,${(s.y * 42).toFixed(1)}%)`);
    } else {
      setStyle(this.stick, 'display', 'none');
    }

    // Lit while held. `down` is the same set the game reads, so a button cannot
    // look pressed while the game thinks it is up.
    for (const b of TOUCH_BUTTONS) setClass(b._node, 'on', input.down.has(b.code));
  }

  dispose() {
    this.root.remove();
    for (const b of TOUCH_BUTTONS) b._node = null;
  }
}
