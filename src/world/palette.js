/**
 * WORLD — the surface palette.
 *
 * A named set of material variants pulled from the `materials` library. Keeping
 * them in one table means the level uses a deliberate, limited palette (which is
 * what makes a real map read as one place) and that every mesh sharing a key
 * merges into the same draw call.
 *
 * `surface` is the ARCHITECTURE.md physics/FX tag. `tint` is a linear multiply
 * on the baked albedo, so values stay inside 0.02–0.9 reflectance.
 */
export const PALETTE = {
  // ---------------------------------------------------------- architecture --
  // The four wallKey variants below (plaster_cream/plaster_white/brick/
  // brick_fine) are what every Kilmore Close house's facade rotates through
  // (see layout.js BUILDINGS). Retinted paler/less saturated to match the
  // pale rendered/pebbledash + painted-brick look in the Street View
  // reference — Irish semis read as an off-white or cream render, sometimes
  // over textured brick, essentially never as deep terracotta brick. The
  // brick GLSL's coursing is kept (it still reads as textured, painted
  // brick close-up) — only the colour moved into the same pale family as the
  // render keys, not swapped for a smooth surface.
  plaster_cream: {
    name: 'plaster',
    surface: 'plaster',
    opts: { vertexMasks: true, tint: 0xddd4bc, scale: 2.35, weather: [0.4, 0.5, 1.4, 0.55] },
  },
  plaster_sand: {
    name: 'plaster',
    surface: 'plaster',
    opts: { vertexMasks: true, tint: 0xb9a582, scale: 2.1, weather: [0.45, 0.5, 1.5, 0.6] },
  },
  plaster_blue: {
    name: 'plaster',
    surface: 'plaster',
    opts: { vertexMasks: true, tint: 0x8f9aa0, scale: 2.2, weather: [0.4, 0.55, 1.5, 0.6] },
  },
  plaster_pink: {
    name: 'plaster',
    surface: 'plaster',
    opts: { vertexMasks: true, tint: 0xc09a86, scale: 2.5, weather: [0.45, 0.5, 1.3, 0.55] },
  },
  plaster_white: {
    name: 'plaster',
    surface: 'plaster',
    opts: { vertexMasks: true, tint: 0xe4dfd0, scale: 1.9, weather: [0.3, 0.35, 0.9, 0.5] },
  },
  brick: {
    name: 'brick',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xb8a98f, scale: 1.3 },
  },
  /** Hollow clay block exposed where the render has spalled off. */
  brick_fine: {
    name: 'brick',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xa89c86, scale: 0.62, weather: [0.45, 0.5, 0.8, 0.6] },
  },
  concrete: {
    name: 'concrete',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xa9a49a, scale: 2.5 },
  },
  /**
   * Prop-scale concrete. A 2.5 m texture tile across a 0.5 m block shows a
   * single smear of noise and reads as untextured plastic; small objects need
   * their own, much tighter tiling.
   */
  concrete_prop: {
    name: 'concrete',
    surface: 'concrete',
    opts: {
      vertexMasks: true,
      tint: 0xa5a096,
      scale: 0.9,
      normalStrength: 1.3,
      weather: [0.45, 0.5, 0.35, 0.55],
    },
  },
  concrete_dark: {
    name: 'concrete',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0x7d7a73, scale: 2.2, weather: [0.4, 0.6, 1.2, 0.6] },
  },
  /** Roof screed: flat, sand-dusted, and the biggest surface in any skyline. */
  roof_screed: {
    name: 'concrete',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xb5a992, scale: 2.8, weather: [0.6, 0.2, 0.3, 0.45] },
  },
  /**
   * Pitched-roof covering for Kilmore Close's houses — dark, slightly warm
   * grey-brown, the concrete/clay tile colour in every Street View reference.
   * Reuses `concrete`'s generator rather than a new tile GLSL (out of scope
   * for a roof-geometry pass): at roofline viewing distance/angle a flat dark
   * tint reads fine, and this map has no close-up rooftop camera work.
   */
  roof_tile: {
    name: 'concrete',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0x4a4038, scale: 1.6, weather: [0.35, 0.3, 0.35, 0.4] },
  },
  floor_concrete: {
    name: 'concrete_floor',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0x9e9a91, scale: 3.0 },
  },
  tile_floor: {
    name: 'tile',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xa9a08d, scale: 1.4 },
  },

  // ----------------------------------------------------------------- ground --
  /**
   * The street itself. A black tarmac road makes a sunlit Levantine town read
   * as a wet European city at dusk — the actual surface is old tarmac buried
   * under years of blown sand and dust, so the base is warm compacted earth and
   * the asphalt only shows through where wheels have polished it.
   */
  road_dust: {
    name: 'gravel',
    surface: 'dirt',
    opts: {
      vertexMasks: true,
      tint: 0xc9b896,
      // 2.2 m, not 1.5: the aggregate reads as 25-45 mm stone instead of a
      // 15 mm rash, and the macro relief band lands on ruts rather than on
      // individual pebbles.
      scale: 2.2,
      // de-tile: a repeating cracked-earth tile down a 100 m street is the most
      // obvious tell in any procedural level.
      detile: 0.9,
      // .w is cavity grime. On gravel the height field IS the aggregate, so
      // this darkens every interstice: at 0.4 the road histogram was bimodal
      // (mass at 32-80 and 144-176 with a hollow middle) — dither, not surface.
      weather: [0.4, 0.04, 0.08, 0.14],
      // No edge wear on a road. The vertex wear mask exists to rub through the
      // arris of a prop; on a 100 m plane it just brightens every stone crown.
      wear: [0, 0.5, 0.45, 0],
    },
  },
  asphalt: {
    name: 'asphalt',
    surface: 'concrete',
    // Dark, damp Irish tarmac — this key inherited a warm 0x9d968a desert-dust
    // tint from the old road_dust entry when ground.js switched the road from
    // road_dust to asphalt; that tint alone was enough to make the retextured
    // street still read as a sand road in every render.
    // WET. Under the overcast sky this street now sits beneath, a bone-dry road
    // fights the weather — a wet or drying carriageway is the single most
    // recognisable thing about a Dublin street.
    //
    // Two changes, no new shader: the tint drops about a stop (wet tarmac is
    // genuinely darker, not just shinier), and `roughness` comes down from the
    // concrete surface's own ~0.98 so the road takes a broad specular sheen off
    // the sky. It is deliberately NOT mirror-smooth — standing water would be
    // 0.1 and would read as ice. 0.55 with a wide variation band keeps the
    // drying patches the wear masks already carry.
    opts: {
      vertexMasks: true,
      tint: 0x3a3935,
      scale: 3.2,
      detile: 0.6,
      wear: [0, 0.5, 0.4, 0],
      roughness: [0.55, -0.04, 0.30],
    },
  },
  /**
   * The driving line: tarmac polished bare by tyres and stained with oil. A
   * clear stop darker than `road_dust`, because a rut the same value as the dust
   * around it is invisible and the road goes back to being one flat plane.
   */
  road_rut: {
    name: 'asphalt',
    surface: 'concrete',
    opts: {
      vertexMasks: true,
      tint: 0x6f6a62,
      scale: 1.5,
      detile: 0.7,
      weather: [0.3, 0.5, 0.15, 0.28],
      wear: [0, 0.55, 0.45, 0],
    },
  },
  /**
   * Road-marking paint: the white triangles on a speed ramp / the give-way
   * chevrons at a junction mouth. Reuses the asphalt generator (so it still
   * reads as paint worn into a tarmac surface, not a decal) but bright and
   * with almost no cavity grime — traffic paint is refreshed far more often
   * than the road around it.
   */
  road_paint_white: {
    name: 'asphalt',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xdedcd2, scale: 2.0, detile: 0.4, weather: [0.15, 0.2, 0.1, 0.1], wear: [0, 0.3, 0.2, 0] },
  },
  sand: {
    name: 'sand',
    surface: 'sand',
    opts: { vertexMasks: true, scale: 2.6, detile: 0.7, wear: [0, 0.45, 0.45, 0] },
  },
  dirt: {
    name: 'dirt',
    surface: 'dirt',
    opts: { vertexMasks: true, scale: 2.4, detile: 0.8, wear: [0, 0.5, 0.45, 0] },
  },
  gravel: {
    name: 'gravel',
    surface: 'dirt',
    opts: { vertexMasks: true, scale: 1.8, wear: [0, 0.5, 0.45, 0] },
  },
  /**
   * The contact fillet swept up against anything standing on the ground (see
   * Assembler.put / props.dustSkirt). It has to read as the ground's own grit
   * piled up, so it is the same generator as the road at a slightly darker,
   * greyer tint, with the grime mask doing the work at the contact line. The
   * first attempt used `dirt`, which is a stop lighter and carries mud cracks:
   * every prop got a pale polygonal plate around it.
   */
  dust_skirt: {
    name: 'gravel',
    surface: 'dirt',
    opts: {
      vertexMasks: true,
      tint: 0xa89d86,
      scale: 1.1,
      weather: [0.3, 0.0, 0.0, 0.16],
      wear: [0, 0.9, 0.7, 0],
    },
  },

  // ------------------------------------------------------------------ metal --
  metal_rust: { name: 'metal_rust', surface: 'metal', opts: { vertexMasks: true, scale: 1.1 } },
  /**
   * Prop-scale rust. A 1.1 m tile wrapped round a 0.6 m oil drum shows one smear
   * of noise and the drum reads as pink plastic — the same trap as
   * `concrete_prop` / `wood_prop`. Drums and buckets are eye-level silhouette
   * breakers in the mid-ground, so they need tiling that resolves at 3 m.
   */
  metal_rust_prop: {
    name: 'metal_rust',
    surface: 'metal',
    opts: {
      vertexMasks: true,
      tint: 0x9d7c66,
      scale: 0.4,
      normalStrength: 1.35,
      weather: [0.5, 0.35, 0.3, 0.5],
    },
  },
  metal_blue: {
    name: 'metal_painted',
    surface: 'metal',
    opts: { vertexMasks: true, tint: 0x6d8390, scale: 1.3 },
  },
  metal_green: {
    name: 'metal_painted',
    surface: 'metal',
    opts: { vertexMasks: true, tint: 0x76806a, scale: 1.3 },
  },
  metal_dark: {
    name: 'metal_painted',
    surface: 'metal',
    opts: { vertexMasks: true, tint: 0x4a4a48, scale: 1.0 },
  },
  steel: { name: 'metal_brushed', surface: 'metal', opts: { vertexMasks: true, scale: 0.9 } },
  corrugated: { name: 'corrugated', surface: 'metal', opts: { vertexMasks: true, scale: 2.2 } },

  // ---------------------------------------------------------------- organic --
  wood: { name: 'wood', surface: 'wood', opts: { vertexMasks: true, scale: 1.8 } },
  /**
   * Prop-scale timber. A 1.8 m grain tile across a 0.5 m crate slat shows one
   * soft smear; crates, pallets, planks and stall tables need ~0.5 m tiling
   * before the grain, the saw marks and the dirt in the joints read at all.
   */
  wood_prop: {
    name: 'wood',
    surface: 'wood',
    opts: {
      vertexMasks: true,
      tint: 0xb08a5e,
      scale: 0.55,
      normalStrength: 1.45,
      weather: [0.35, 0.3, 0.35, 0.5],
    },
  },
  wood_prop_dark: {
    name: 'wood',
    surface: 'wood',
    opts: {
      vertexMasks: true,
      tint: 0x7d6244,
      scale: 0.5,
      normalStrength: 1.45,
      weather: [0.35, 0.35, 0.4, 0.55],
    },
  },
  wood_dark: {
    name: 'wood',
    surface: 'wood',
    opts: { vertexMasks: true, tint: 0x8a6a4a, scale: 1.5 },
  },
  wood_pale: {
    name: 'wood',
    surface: 'wood',
    opts: { vertexMasks: true, tint: 0xc0a482, scale: 1.2 },
  },
  fabric_red: {
    name: 'fabric',
    surface: 'fabric',
    opts: { vertexMasks: true, tint: 0xa2564a, scale: 0.26, three: { side: 2 } },
  },
  fabric_teal: {
    name: 'fabric',
    surface: 'fabric',
    opts: { vertexMasks: true, tint: 0x5f8a8c, scale: 0.26, three: { side: 2 } },
  },
  fabric_cream: {
    name: 'fabric',
    surface: 'fabric',
    opts: { vertexMasks: true, tint: 0xbcb298, scale: 0.26, three: { side: 2 } },
  },
  /**
   * Hessian. The weave has to be fine — a 0.5 m tile turns every sandbag into a
   * picnic basket, and sandbags are the most-repeated prop in the level.
   *
   * The tint is deliberately well under a bright sand value: an emplacement is
   * dozens of square metres of one material low in the frame, and at the old
   * value it was the brightest thing in the bottom two thirds of the night shot
   * with nothing lighting it. Filled hessian is a mid-tone — 0.18-0.24 linear —
   * darker than the plaster behind it and darker than the dust it sits on.
   */
  burlap: {
    name: 'burlap',
    surface: 'fabric',
    opts: { vertexMasks: true, tint: 0xa2957a, scale: 0.16, weather: [0.5, 0.3, 0.4, 0.5] },
  },
  rubber: { name: 'rubber', surface: 'rubber', opts: { vertexMasks: true, scale: 0.45 } },
  glass: { name: 'glass', surface: 'glass', opts: { scale: 2.0 } },
  foliage: { name: 'foliage', surface: 'foliage', opts: { vertexMasks: true } },

  // ------------------------------------------------------------- apertures --
  /**
   * The dark core BEHIND a window opening. A window is not a grey rectangle: it
   * is a hole with a dark room behind it, and the only thing that sells it is a
   * genuinely dark backing plane set 15-25 cm back from the glass so the reveal
   * casts onto it and the opening parallaxes as the camera moves. Final linear
   * albedo lands around 0.03 (the tint is a linear multiply on the baked
   * plaster albedo), which is the reflectance of an unlit room seen from a
   * sunlit street — dark, but still carrying plaster texture rather than being
   * a black hole.
   */
  window_void: {
    name: 'plaster',
    surface: 'plaster',
    opts: {
      vertexMasks: true,
      tint: 0x474441,
      scale: 1.1,
      roughness: [1.0, 0.15],
      weather: [0.2, 0.7, 0.2, 0.7],
    },
  },
  /**
   * The dark shell inside a non-enterable building. Seen through doorways and
   * blown-out holes as well as windows, so it sits a stop above `window_void`:
   * dark, readable, never a white blank.
   */
  interior_shell: {
    name: 'plaster',
    surface: 'plaster',
    opts: {
      vertexMasks: true,
      tint: 0x5f5b56,
      scale: 1.6,
      roughness: [1.0, 0.1],
      weather: [0.25, 0.8, 0.3, 0.65],
    },
  },
  /**
   * Window glass. Distinct from the `glass` used on bottles and shards purely
   * so the roughness can be forced down: below 0.62 the render's SSR/IBL path
   * kicks in and the pane picks up the sky, which is what stops a window
   * reading as taped-over paper.
   */
  window_glass: {
    name: 'glass',
    surface: 'glass',
    opts: {
      scale: 2.0,
      roughness: [0.3, 0.06],
      three: { opacity: 0.16, envMapIntensity: 2.1 },
    },
  },
  /** Plywood sheet nailed over a broken window. */
  plywood: {
    name: 'wood',
    surface: 'wood',
    opts: {
      vertexMasks: true,
      tint: 0x7a6549,
      scale: 0.62,
      normalStrength: 1.2,
      weather: [0.5, 0.45, 0.5, 0.6],
    },
  },

  // ---------------------------------------------------------------- emissive --
  /** Bare interior bulb. Tiny surface, so it needs real radiance to read. */
  emissive_warm: {
    name: 'plaster',
    surface: 'glass',
    opts: {
      scale: 0.4,
      tint: 0xfff0d8,
      three: { emissive: 0xffd39a, emissiveIntensity: 12, toneMapped: true },
    },
  },
  /**
   * A lit room seen from the street. Much dimmer than `emissive_warm`: this is a
   * whole wall of a room catching a bulb, not the bulb itself, and at daylight
   * exposure it only has to lift the opening off the dark-core value.
   */
  window_glow: {
    name: 'plaster',
    surface: 'plaster',
    opts: {
      vertexMasks: true,
      tint: 0x6a5a45,
      scale: 1.2,
      three: { emissive: 0xffb066, emissiveIntensity: 1.1, toneMapped: true },
    },
  },
  /** Street-lamp diffuser. Emission is driven by time of day at runtime. */
  lamp_lens: {
    name: 'glass',
    surface: 'glass',
    opts: {
      scale: 1.0,
      three: { emissive: 0xffc47a, emissiveIntensity: 0, opacity: 0.5 },
    },
  },

  // ------------------------------------------------------- residential kit --
  /**
   * Painted ground-floor spandrel band, the wine/maroon accent strip under
   * the front windows on the paired semis in the Street View references
   * (screenshots 1 & 4) — never the whole wall, just the band below sill
   * height that reads as a two-tone paint job rather than a flat single tint.
   *
   * Iteration 2: darkened and desaturated less (lower weather amount) than the
   * iteration-1 value — at the original 0x6e3f3c/[.35,.4,.8,.5] the band's own
   * grime pass muddied it toward the wall colour and it read as shadow, not
   * paint, at street distance.
   */
  plaster_wine: {
    name: 'plaster',
    surface: 'plaster',
    opts: { vertexMasks: true, tint: 0x5c2a28, scale: 1.4, weather: [0.25, 0.3, 0.5, 0.32] },
  },
  /**
   * Second band accent, for the neighbour half of a painted pair — a
   * saturated terracotta/coral rather than iteration 1's `plaster_pink`
   * (0xc09a86), which sat too close in value to `plaster_sand`/`plaster_butter`
   * wall tones to read as a separate paint colour.
   */
  plaster_coral: {
    name: 'plaster',
    surface: 'plaster',
    opts: { vertexMasks: true, tint: 0xb85a42, scale: 1.4, weather: [0.25, 0.3, 0.5, 0.32] },
  },
  /**
   * Butter-yellow render, for the second half of a painted pair — pulls the
   * mustard/yellow read from the Street View references that `plaster_sand`
   * (too brown/tan) didn't reach, and gives the paired house real separation
   * from its `plaster_white` neighbour instead of two close tans.
   */
  plaster_butter: {
    name: 'plaster',
    surface: 'plaster',
    opts: { vertexMasks: true, tint: 0xd9bf74, scale: 2.1, weather: [0.4, 0.5, 1.3, 0.55] },
  },
  /**
   * PEBBLEDASH house walls — the single most recognisable thing about these
   * houses, and until now the one material that wasn't modelled. The comment on
   * the plaster_* keys says outright that the render look is only approximated.
   *
   * No new shader and no new surface: the `concrete` surface already bakes an
   * exposed-aggregate layer (worley stone chips breaking the skin, plus a
   * 5-8 mm coarse sand fraction — see surfaces-arch.js), which is physically
   * what pebbledash IS: chip aggregate thrown at a wet render coat. `scale` is
   * what tunes the chip size to a house wall rather than a paving slab.
   *
   * These are separate keys rather than a change to plaster_*, because
   * plaster_white is also the INTERIOR partition material — dashing the inside
   * of every room would be wrong and expensive.
   *
   * Tints match the established exterior colour scheme so the paired-house
   * contrast the layout depends on survives; dash is painted over, and the
   * colour is the paint, not the aggregate.
   */
  dash_cream: {
    name: 'concrete',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xd7cfb8, scale: 2.6, weather: [0.4, 0.5, 1.2, 0.5] },
  },
  dash_white: {
    name: 'concrete',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xded9cb, scale: 2.5, weather: [0.3, 0.35, 0.9, 0.45] },
  },
  dash_sand: {
    name: 'concrete',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xb5a17f, scale: 2.6, weather: [0.45, 0.5, 1.3, 0.55] },
  },
  dash_butter: {
    name: 'concrete',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0xd3ba73, scale: 2.55, weather: [0.4, 0.5, 1.2, 0.5] },
  },
  /** Wet-look rendered/pebbledash boundary wall, the standard Dublin front garden wall. */
  wall_garden: {
    name: 'concrete',
    surface: 'concrete',
    opts: { vertexMasks: true, tint: 0x9a988e, scale: 1.6, weather: [0.35, 0.4, 0.5, 0.4] },
  },
  /** Wheelie bins. Irish kerbside colours: black/green general waste, brown organic, blue recycling. */
  bin_black: { name: 'metal_painted', surface: 'rubber', opts: { tint: 0x2a2a2c, scale: 0.8 } },
  bin_green: { name: 'metal_painted', surface: 'rubber', opts: { tint: 0x2e4a30, scale: 0.8 } },
  bin_brown: { name: 'metal_painted', surface: 'rubber', opts: { tint: 0x4a3626, scale: 0.8 } },
  bin_blue: { name: 'metal_painted', surface: 'rubber', opts: { tint: 0x2c4a6a, scale: 0.8 } },
  /** Parked-car paint. Ordinary, unremarkable colours — nothing showroom-bright. */
  car_red: { name: 'metal_painted', surface: 'metal', opts: { tint: 0x7a2a28, scale: 1.4, weather: [0.3, 0.25, 0.2, 0.35] } },
  car_blue: { name: 'metal_painted', surface: 'metal', opts: { tint: 0x35455c, scale: 1.4, weather: [0.3, 0.25, 0.2, 0.35] } },
  car_silver: { name: 'metal_painted', surface: 'metal', opts: { tint: 0x9a9a96, scale: 1.4, weather: [0.3, 0.25, 0.2, 0.35] } },
  car_white: { name: 'metal_painted', surface: 'metal', opts: { tint: 0xc8c8c2, scale: 1.4, weather: [0.3, 0.25, 0.2, 0.35] } },
  car_glass: { name: 'glass', surface: 'glass', opts: { scale: 1.2, roughness: [0.25, 0.05], three: { opacity: 0.22, envMapIntensity: 1.8 } } },
  /** A builder's skip outside the one house getting done up. */
  skip_yellow: { name: 'metal_painted', surface: 'metal', opts: { tint: 0xc9a227, scale: 1.2, weather: [0.4, 0.4, 0.3, 0.45] } },
  /** Clipped garden hedge / privet. Same generator as the rest of the foliage. */
  hedge: { name: 'foliage', surface: 'foliage', opts: { vertexMasks: true, tint: 0x4f6b3c } },
  /** Damp, mossy tarmac verge grime — replaces the desert sand/dust berms at wall bases. */
  moss_verge: {
    name: 'gravel',
    surface: 'dirt',
    opts: { vertexMasks: true, tint: 0x5a6249, scale: 1.4, weather: [0.35, 0.15, 0.2, 0.3] },
  },
  /**
   * Front-garden lawn. There is no dedicated grass/turf generator in the
   * shared materials library (`src/materials/`) — adding one is a bigger,
   * cross-subsystem lift than this dressing pass should take on — so this
   * reuses the same `dirt` surface generator as `moss_verge` at a distinctly
   * greener, more saturated tint. Cheap, but it is the difference between a
   * front garden and a builder's yard in every Street View reference.
   */
  lawn: {
    name: 'dirt',
    surface: 'dirt',
    opts: { vertexMasks: true, tint: 0x53694a, scale: 2.0, weather: [0.25, 0.15, 0.15, 0.25] },
  },
};
