/**
 * GAME — mission state for Kilmore Close.
 *
 * Owns the one thing nothing else claims: is the level won or lost. Everything
 * it drives (objective text, banners, restart prompt, killfeed, garrison) is
 * already public on `ai`/`player`/`ui` — this system only sequences it.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * MISSION LOOP
 *   intro   -> banner, objective set. `ai` has already garrisoned the street
 *              during its own init() (see ai/index.js `_bootNav`), so there is
 *              nothing to spawn here.
 *   active  -> objective label tracks `ai.stats.alive`; reaching 0 (after the
 *              garrison actually stood up) wins the mission.
 *   success -> banner + restart prompt, player control frozen.
 *   fail    -> `player:death` fires this from any state; banner + restart
 *              prompt, player control frozen.
 *   restart -> press `use` (F) in success/fail: reload. Simplest correct
 *              restart — re-running `ai.populate()` in place would need a
 *              teardown hook `ai` doesn't expose yet, and a full boot is what
 *              every other system's state already assumes as "fresh".
 *
 * EVENTS consumed: player:death
 */

const INTRO_LIFE = 2.4;

export class GameSystem {
  static id = 'game';
  static deps = ['ai', 'player', 'ui'];

  async init(ctx) {
    this.ctx = ctx;
    this.state = 'intro';
    this.t = 0;
    this._aliveLast = -1;

    // Preallocated so `update()` never builds a new array/object — only the
    // label string changes, and only when the alive count actually does.
    this._objective = { position: null, label: 'CLEAR KILMORE CLOSE', name: 'clear' };
    this._objectives = [this._objective];

    const ui = ctx.get('ui');
    ui.setObjectives(this._objectives);
    ui.banner.show('GTA: Kilmore Close', 'Clear the street', INTRO_LIFE);

    this._offDeath = ctx.events.on('player:death', () => this._onPlayerDeath());
  }

  update(dt, ctx) {
    this.t += dt;
    switch (this.state) {
      case 'intro':
        if (this.t > INTRO_LIFE) this.state = 'active';
        break;
      case 'active':
        this._tickActive(ctx);
        break;
      case 'success':
      case 'fail':
        if (ctx.input.actionPressed('use')) location.reload();
        break;
    }
  }

  _tickActive(ctx) {
    const ai = ctx.get('ai');
    const alive = ai.stats.alive;
    if (alive !== this._aliveLast) {
      this._aliveLast = alive;
      this._objective.label = alive > 0 ? `CLEAR KILMORE CLOSE — ${alive} LEFT` : 'CLEAR KILMORE CLOSE';
    }
    // `ai.stats.agents` only goes positive once the garrison has actually
    // spawned (it stays 0 through capture's deterministic boot), so an empty
    // street before that never reads as an instant win.
    if (ai.stats.agents > 0 && alive === 0) this._succeed();
  }

  _succeed() {
    if (this.state === 'success' || this.state === 'fail') return;
    this.state = 'success';
    const ui = this.ctx.get('ui');
    ui.banner.show('Area Clear', 'Kilmore Close secured', 3);
    ui.setPrompt({ key: 'F', text: 'Restart' });
    this.ctx.get('player').setControlEnabled(false);
  }

  _onPlayerDeath() {
    if (this.state === 'success' || this.state === 'fail') return;
    this.state = 'fail';
    const ui = this.ctx.get('ui');
    ui.banner.show('Mission Failed', 'Kilmore Close was not held', 3);
    ui.setPrompt({ key: 'F', text: 'Restart' });
    this.ctx.get('player').setControlEnabled(false);
  }

  dispose() {
    this._offDeath?.();
  }
}
