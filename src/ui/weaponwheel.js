import { el, setText, setStyle, setClass, TAU } from './util.js';

/**
 * Weapon wheel, screen centre. Held open rather than toggled: the wheel is a
 * quick-select you flick through and release, so it never becomes a mode you
 * can get stuck in.
 *
 * This widget is pure presentation. `weapons` owns which slots exist, which one
 * is highlighted and what equipping actually does — see `wp.wheel` — because it
 * owns weapon state and the holster timing. All this does is draw the state it
 * is handed, and only when that state changes.
 *
 * Slots are laid out on a circle starting at 12 o'clock and running clockwise,
 * which is the arrangement every player already has muscle memory for.
 */
export class WeaponWheel {
  constructor(parent) {
    this.root = el('div', 'ow-wheel', parent);
    this.slots = [];
    this._open = false;
    this._index = -1;
    this._count = 0;
    this._sig = '';
    setStyle(this.root, 'opacity', '0');
  }

  /** Build (once) enough slot nodes for the weapons the player is carrying. */
  _ensure(n) {
    if (this._count === n) return;
    for (const s of this.slots) s.node.remove();
    this.slots.length = 0;
    const R = 104;
    for (let i = 0; i < n; i++) {
      const a = -Math.PI / 2 + (i / n) * TAU;
      const node = el('div', 'ow-wheel-slot', this.root);
      setStyle(node, 'transform', `translate(-50%,-50%) translate(${Math.cos(a) * R}px, ${Math.sin(a) * R}px)`);
      const key = el('div', 'ow-wheel-key', node, String(i + 1));
      const name = el('div', 'ow-wheel-name', node);
      const ammo = el('div', 'ow-wheel-ammo', node);
      this.slots.push({ node, key, name, ammo });
    }
    this._count = n;
  }

  /**
   * @param {{open:boolean, index:number, items:{name:string,ammo:number,reserve:number}[]}} s
   */
  setState(s) {
    const items = s.items ?? [];
    this._ensure(items.length);

    if (s.open !== this._open) {
      this._open = s.open;
      setStyle(this.root, 'opacity', s.open ? '1' : '0');
      setClass(this.root, 'open', s.open);
    }
    if (!s.open) return;

    // Only touch the DOM when something actually changed — this runs every
    // frame the wheel is held open.
    const sig = `${s.index}|${items.map((i) => `${i.name}:${i.ammo}/${i.reserve}`).join(',')}`;
    if (sig === this._sig) return;
    this._sig = sig;

    for (let i = 0; i < items.length; i++) {
      const slot = this.slots[i];
      const it = items[i];
      setText(slot.name, String(it.name ?? '').toUpperCase());
      setText(slot.ammo, `${it.ammo ?? 0} / ${it.reserve ?? 0}`);
      setClass(slot.node, 'sel', i === s.index);
    }
  }

  dispose() {
    this.root.remove();
    this.slots.length = 0;
  }
}
