import { el, setText, setStyle } from './util.js';

/**
 * Persistent in-game controls panel, bottom left.
 *
 * The control list used to exist only as one line inside the pause menu
 * (`menu.js`), which meant a player never saw it while actually playing. This
 * is the same information, always on screen, quiet enough to ignore once
 * learned.
 *
 * It is CONTEXTUAL: the rows change when the player gets into a car, so the
 * driving controls are visible exactly when they apply and the on-foot ones are
 * not competing for attention. `ui` calls `setContext()` once a frame with the
 * current mode; the DOM is only touched when the mode actually changes.
 */

const SETS = {
  foot: [
    ['WASD', 'Move'],
    ['SHIFT', 'Sprint'],
    ['SPACE', 'Jump'],
    ['CTRL', 'Crouch'],
    ['LMB', 'Punch / Fire'],
    ['RMB', 'Aim'],
    ['TAB', 'Weapon wheel — hold'],
    ['1-4', 'Weapon slot'],
    ['R', 'Reload'],
    ['F', 'Enter car / Use'],
  ],
  drive: [
    ['W / S', 'Throttle / Brake'],
    ['A / D', 'Steer'],
    ['SPACE', 'Handbrake'],
    ['F', 'Get out'],
  ],
};

export class ControlsPanel {
  constructor(parent) {
    this.root = el('div', 'ow-controls', parent);
    this.title = el('div', 'ow-controls-title', this.root, 'CONTROLS');
    this.list = el('div', 'ow-controls-list', this.root);
    this.rows = [];
    this._context = null;
    this._visible = true;
    this.setContext('foot');
  }

  /** Build (or rebuild) the rows for a context. Only runs when it changes. */
  setContext(name) {
    if (name === this._context) return;
    const set = SETS[name] ?? SETS.foot;
    this._context = name;

    // Grow the row pool as needed, then refill in place — no per-frame churn,
    // and switching context does not thrash the DOM.
    while (this.rows.length < set.length) {
      const row = el('div', 'ow-controls-row', this.list);
      const key = el('span', 'ow-controls-key', row);
      const act = el('span', 'ow-controls-act', row);
      this.rows.push({ row, key, act });
    }
    for (let i = 0; i < this.rows.length; i++) {
      const r = this.rows[i];
      if (i < set.length) {
        setText(r.key, set[i][0]);
        setText(r.act, set[i][1]);
        setStyle(r.row, 'display', 'flex');
      } else {
        setStyle(r.row, 'display', 'none');
      }
    }
  }

  setVisible(v) {
    if (v === this._visible) return;
    this._visible = v;
    setStyle(this.root, 'opacity', v ? '1' : '0');
  }

  dispose() {
    this.root.remove();
    this.rows.length = 0;
  }
}
