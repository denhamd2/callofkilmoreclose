/**
 * Central tuning + quality configuration.
 * Subsystems read from here rather than hardcoding magic numbers, so the
 * quality scaler and the capture harness can drive everything from one place.
 */

export const PHYSICS_HZ = 120;
export const FIXED_DT = 1 / PHYSICS_HZ;
/** Never simulate more than this many physics steps in one frame (spiral-of-death guard). */
export const MAX_SUBSTEPS = 8;

/** Real-world units are metres, seconds, kilograms. */
export const UNITS = {
  gravity: -9.81 * 2.1, // Games use exaggerated gravity; CoD-like feel.
  playerHeight: 1.78,
  playerCrouchHeight: 1.12,
  playerRadius: 0.32,
  eyeOffset: 0.12, // below top of capsule
};

export const QUALITY_PRESETS = {
  /**
   * MOBILE — the floor. Aimed at a basic Android phone, not a flagship.
   *
   * Everything optional is off: no TAA, GTAO, SSR, volumetrics, motion blur or
   * bloom, one shadow cascade at 512 and a short shadow distance, and a render
   * scale that resolves well under the panel. `low` still ran bloom, 1024 maps
   * and three cascades, which is more than weak hardware will hold.
   *
   * `aiMax` and `navCell` are read by `ai`: the cast is capped and the
   * navigation grid coarsened, because on this street the nav build and the
   * per-agent animation work cost more than the pixels do.
   */
  mobile: {
    renderScale: 0.55,
    shadowMapSize: 512,
    cascades: 1,
    shadowDistance: 26,
    taa: false,
    gtao: false,
    ssr: false,
    volumetrics: false,
    motionBlur: false,
    bloom: false,
    anisotropy: 1,
    particleBudget: 400,
    decalBudget: 16,
    aiMax: 5,
    navCell: 1.3,
  },
  low: {
    renderScale: 0.72,
    shadowMapSize: 1024,
    cascades: 3,
    shadowDistance: 60,
    taa: false,
    gtao: false,
    ssr: false,
    volumetrics: false,
    motionBlur: false,
    bloom: true,
    anisotropy: 4,
    particleBudget: 2000,
    decalBudget: 64,
    aiMax: 32,
    navCell: 0.8,
  },
  medium: {
    renderScale: 0.85,
    shadowMapSize: 2048,
    cascades: 3,
    shadowDistance: 90,
    taa: true,
    gtao: true,
    ssr: false,
    volumetrics: true,
    motionBlur: true,
    bloom: true,
    anisotropy: 8,
    particleBudget: 6000,
    decalBudget: 128,
    aiMax: 32,
    navCell: 0.8,
  },
  high: {
    renderScale: 1.0,
    shadowMapSize: 2048,
    cascades: 4,
    shadowDistance: 140,
    taa: true,
    gtao: true,
    ssr: true,
    volumetrics: true,
    motionBlur: true,
    bloom: true,
    anisotropy: 16,
    particleBudget: 12000,
    decalBudget: 256,
    aiMax: 32,
    navCell: 0.8,
  },
  ultra: {
    renderScale: 1.0,
    shadowMapSize: 4096,
    cascades: 4,
    shadowDistance: 200,
    taa: true,
    gtao: true,
    ssr: true,
    volumetrics: true,
    motionBlur: true,
    bloom: true,
    anisotropy: 16,
    particleBudget: 24000,
    decalBudget: 512,
    aiMax: 32,
    navCell: 0.8,
  },
};

export const DEFAULTS = {
  quality: 'ultra',
  fov: 80, // horizontal-ish vertical FOV, CoD default feel
  adsFovScale: 0.72,
  sensitivity: 0.0022,
  adsSensScale: 0.65,
  invertY: false,
  exposure: 1.0,
  /** Capture mode disables anything nondeterministic so screenshots are stable. */
  deterministic: false,
};

export function createConfig(overrides = {}) {
  const cfg = { ...DEFAULTS, ...overrides };
  cfg.q = { ...QUALITY_PRESETS[cfg.quality] };
  cfg.setQuality = (name) => {
    if (!QUALITY_PRESETS[name]) throw new Error(`unknown quality preset "${name}"`);
    cfg.quality = name;
    Object.assign(cfg.q, QUALITY_PRESETS[name]);
  };
  return cfg;
}
