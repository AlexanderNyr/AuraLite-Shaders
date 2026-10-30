# 🌌 AuraLite Shaders (Minecraft 1.16 – 26.2)

![Minecraft Version](<https://img.shields.io/badge/Minecraft-1.16.5 -- 26.2-blue?logo=minecraft&logoColor=white>) [![Shader Loader](<https://img.shields.io/badge/Loader-Iris / Sodium-green>)](https://modrinth.com/mod/iris) [![API Standard](<https://img.shields.io/badge/API-OpenGL 4.6 / GLSL 460-orange>)](https://khronos.org/) [![Materials Standard](<https://img.shields.io/badge/PBR-LabPBR 1.3-cyan>)](https://github.com/rre36/lab-pbr) [![Version](https://img.shields.io/badge/Release-v1.2.0-purple)](https://github.com/AlexanderNyr/AuraLite-Shaders) [![License](<https://img.shields.io/badge/License-CC BY--NC--SA 4.0-lightgrey.svg>)](https://creativecommons.org/licenses/by-nc-sa/4.0/)

**AuraLite** is a modern, lightweight, and highly optimized shader pack built on top of the **OpenGL 4.6 / GLSL 460** standard. It is specifically designed and **tested for Minecraft 1.16 – 26.2 with Sodium + Iris** (and compatible with **OptiFine**, **Oculus**). Since **v1.2.0** the cloud deck is a physically parameterised volumetric medium rather than a stack of painted layers, and every development instrument has been removed from the shipped code.

AuraLite delivers a breathtaking, realistic visual experience without overcomplicating the screen with bloated post-processing effects (such as aggressive motion blur or heavy bloom). A lightweight HDR bloom (gaussian pyramid since v1.1.3, **half-resolution and skippable since v1.1.4**) softly glows emissive sources without smearing the scene. Optional FXAA/SMAA anti-aliasing, SSR, TAA, godrays, and SSAO are profile-scaled so AuraLite keeps **high FPS and smooth frametimes** on modern GPUs.

> 🧪 **v1.2.0 note:** The **physical cloud line is now the default**. Clouds are a medium with a liquid water content and a droplet spectrum, so extinction follows from the droplet radius instead of a tuned constant; **`CLOUD_QUALITY`** (raymarch steps) and **`CLOUD_DETAIL`** (shape octaves) are independent, cirrus and a mid-level deck are separate families, and the cloud shadow that gates the godrays is one column per frame, generated from `composite.fsh` into `composite.vsh`. Twilight comes from the optical path, colour control is **twelve real sliders**, and the diagnostic layer of the 1.1.5 branch (on-screen stripes, gauges, class maps, bypass switches) is **gone**. **TAA is on by default in HIGH/ULTRA/EXTREME; camera jitter stays OFF.** See the changelog below.

***

> ℹ️ **Historical note:** older changelog sections below are preserved as original release notes.

## 🚀 What's New in v1.2.0 — _Physical Clouds_

Version **1.2.0** is the first release of the physical cloud line, and the first build since 1.1.4 that
contains no measuring equipment. The cloud deck stops being four painted sheets and becomes a medium with
a droplet spectrum; the atmosphere coefficients are re-derived from measured column depths; godrays
integrate a filtered transmittance with a fixed step count; the colour stage becomes twelve sliders; and
every debug stripe, gauge bar, class map and bypass switch from the development branch is removed.

> ⚠️ **This is a new minor version, not a patch.** The default look changes on purpose: cloud altitude is
> now in metres (a 1.2 km base instead of 160 blocks), coverage and density are separate controls, and the
> colour pipeline gained a complete slider set. Read `RELEASE_NOTES.md` inside the pack for the full,
> file-by-file account.

### ☁️ Volumetric Cloud Engine — _Microphysics, Not Constants_

*   **The deck is a medium.** `CLOUD_DENSITY` selects a **liquid water content** (0.075 / 0.15 / 0.30 g/m³) and `CLOUD_MICRO` a **droplet spectrum** (_Continental 6 µm / Typical 8 µm / Maritime 12 µm_); extinction is derived from them (`σ = 3·LWC·Q_ext / 4ρ·r_eff`), so "dense" is a physical quantity rather than a number that was tuned by eye.
*   **Resolution and detail are independent.** **`CLOUD_QUALITY`** is the raymarch budget (_Cheap 14 / Standard 24 / High 36 / Extreme 56 steps_) and the new **`CLOUD_DETAIL`** is the shape field (_2–5 octaves, 1080 → 135 m features_). A weak GPU can keep crisp cloud tops and drop the step count instead of the shape; the two multiply, and the cost table is in the release notes.
*   **Coverage is cloud fraction, not brightness.** New **`CLOUD_COVERAGE`** (_Clear / Scattered / Broken / Broken to overcast / Overcast_) moves the threshold the shape field has to cross, and each octave preset carries a bisected offset so "Broken" covers the same ~40 % of the sky on every profile.
*   **Cirrus is ice, not a small cumulus.** New **`CLOUD_CIRRUS`** marches a fibrous veil at 6.5–11.2 km with its own extinction (~0.09 g/m³, 25 µm), and it dissolves into the horizon haze instead of ending on a visible edge.
*   **An independent mid-level deck.** New **`CLOUD_MID_LAYER`** adds a second, separate layer rather than repeating the cumulus field.
*   **Real air.** Altitudes in metres via **`CLOUD_HEIGHT`** (_400 m / 1200 m / 2400 m / 3600 m_), deck depth as a fraction of the base altitude, reach out to **32 km**, wind as a velocity in m/s, per-cloud condensation level (**`CLOUD_BASE_VARIATION`**) and vertical development (**`CLOUD_UPDRAFT`**), and multiple scattering instead of a single-sample light tap.
*   **`CLOUD_MODE`** keeps the v1.1.4 layered sheets available (_Layered sheets / Volumetric_) for hardware that cannot afford the march.

### 🌤️ Godrays — _Filtered, Bounded and Stable in Time_

*   Shafts sample a **filtered** shadow term — a smoothstep band expressed in the same space as the depth compare — instead of `step()` on the blocker depth. Moving the camera by a fraction of a shadow texel no longer flips whole samples between lit and unlit.
*   **Fixed step count.** The path is bounded (40 km) and divided into a constant number of taps, so the optical depth changes continuously as the sun moves instead of jumping whenever the path crosses a multiple of the old 150 m step.
*   **One cloud-shadow column per frame.** The cloud transmittance that gates the shafts is screen-independent, so it is evaluated **once per fullscreen-quad vertex** in `composite.vsh` and handed over as a `flat` varying — 4 evaluations per frame instead of 2 million. That file is **generated** from `composite.fsh` by `tools/gen_composite_vsh.py`, so the duplicated field code cannot drift; CI can verify it with `--check`.
*   Near-horizontal light fades out towards the horizon instead of integrating an effectively infinite path through the deck, which is what made the shafts "breathe" at sunset.

### 🌇 Atmosphere — _Coefficients From Measurements, Twilight From Optics_

*   Rayleigh, aerosol **scattering and absorption**, and **ozone as a 25 ± 15 km tent** (Bruneton/Hillaire) replace the hand-tuned triplet that carried roughly 9× too much aerosol and no ozone at all.
*   Twilight is produced by the **optical path**: civil, nautical and astronomical phases, the Earth's shadow and the **Belt of Venus**, all in `gbuffers_skybasic`. The old global on/off ramp over the finished result is gone, so the sky no longer dies by solar −1.4°.
*   **Airglow is added after the dark-adaptation gain.** Multiplying it by the gain (which reaches 28 in deep twilight) used to paint the entire night sky blue at every hour.
*   The physical sky (`SKY_MODE = 1`) now **shares its LUT-derived transmittance with the default gradient sky**, so terrain fog, water reflection, clouds, godrays and the SSR sky fallback agree in both modes.

### 🎚️ Colour Grading — _Twelve Sliders, One Tone Curve_

*   The three-stop `EXPOSURE` / `COLOR_SATURATION` / `CONTRAST` buttons are replaced by a dedicated **`[Colour Grading]`** tab with continuous sliders: **Exposure, Brightness, Contrast, Saturation, Output Gamma, Red/Green/Blue gain, Warmth, Tint, Vibrance and Vignette strength**, plus a **Tone Curve** selector (_ACES / ACES soft / ACES punchy / Photographic (AgX-like)_).
*   These are declared as real Iris **`sliders`** — dragging is the point, and every value in between exists. Everything else in the pack stays an enumerated button on purpose.
*   **`COLOR_LUMA_PROTECT`** keeps average brightness fixed while the channel and warm/tint sliders move, so a white-balance experiment does not also change exposure.

### 💧 Water, Foliage and Stability

*   **Water has an ID.** `minecraft:water` / `flowing_water` map to block ID `10020`, so water classification no longer guesses from colour and depth — and the whole rescue ladder that existed for that guess is now a fallback, not the primary path.
*   **One wind-wave spectrum.** Eight components with deep-water dispersion (`ω = √(gk)`) and wavelength-derived amplitude, evaluated in **world space**. The three longest displace the mesh (26 / 15.5 / 9.5 blocks — no aliasing on Minecraft's one-vertex-per-block grid), the rest live in the normal. The v1.1.4 surface was driven by three unrelated sine fields, one of them in view space.
*   **Water no longer writes into the shadow map.** A flat receiver standing in its own shadow map with centimetre waves produced self-shadow stripes whose period was constant in *pixels*; the vertex shader now pushes water out of the shadow pass entirely.
*   **Vegetation is three classes**, not one: tall plants bend from the base, short grass flutters, flower heads nod — and the wave phase is taken from **world** coordinates, so grass stops "speeding up" when you walk across chunk borders. Mirrored in `shadow.vsh`.
*   **Dither is a fixed 4×4 ordered pattern**, not two `fract(sin(...))` hashes of `gl_FragCoord`: the hash was uncorrelated between pixels and unstable in float, so it read as grain over the whole frame and shimmered even when the camera was still. The **cloud ray start is deterministic** as well — every pixel aims at the middle of its shell, and the slicing that the jitter used to dissolve is now handled by `CLOUD_QUALITY`.

### 🎚️ Profile Rebalance (v1.2.0)

| Profile        |Shadows                   |Clouds                        |TAA |Bloom |Notes                              |
| -------------- |------------------------- |----------------------------- |--- |----- |---------------------------------- |
| VERY_LOW       |❌ 512 / 60 m              |❌                             |❌   |❌    |Gradient sky, minimal path         |
| LOW            |❌ 512 / 60 m              |❌                             |❌   |❌    |Water/foliage motion, stars        |
| MED            |✅ 1024 / <strong>192 m</strong>|✅ Volumetric 24 steps / 3 oct |❌   |✅     |The sweet spot                     |
| HIGH           |✅ 2048 / <strong>512 m</strong>|✅ Volumetric 36 steps / 3 oct |✅   |✅     |Full atmosphere + SSR              |
| ULTRA          |✅ 4096 / <strong>512 m</strong> Aggr|✅ Volumetric 36 steps / 3 oct |✅   |✅     |Higher SSAO / SSR / aurora         |
| EXTREME        |✅ 8192 / <strong>768 m</strong> Aggr|✅ Volumetric 56 steps / 4 oct |✅   |✅     |Cinematic                          |

Camera jitter remains **off by default in every profile**.


## 🚀 What's New in v1.1.4 — _Atmosphere LUTs, Distant Horizons Seam Fix & Half-Res Bloom_

Version **1.1.4** rebuilds the experimental physical sky around shared low-frequency LUTs, replaces the hole-producing DH screen-door seam with a deterministic hand-off, and cuts post-process cost with skippable half-resolution bloom. It also finishes the TAA story for Distant Horizons (correct DH reprojection + Halton jitter on LOD geometry) and swaps glittery water fBm for a coherent Gerstner swell.

### 🧪 Shared Physical-Atmosphere LUTs (`begin` / `begin1`)

*   **Tiny HDR LUTs, not fullscreen buffers.** v1.1.3 deleted unused full-screen `colortex5`/`colortex6` to save VRAM. v1.1.4 brings them back as **64×32** solar-transmittance (`colortex5`) and **32×16** multi-scatter / ground-bounce (`colortex6`) tables — kilobytes, not megabytes.
*   **`begin.fsh`** rebuilds direct solar transmittance every frame: sun elevation on X (`−0.16…1.0`, including civil twilight), camera altitude on Y (`0–30 km`), Kasten–Young airmass × Rayleigh + aerosol extinction, zeroed below the night hemisphere.
*   **`begin1.fsh`** layers bounded multi-scattering and biome-aware ground bounce on top of that transmittance. Noon is Rayleigh-blue; low sun is warm; swamp/snow/vegetation tints come from `GROUND_BOUNCE_MODE`.
*   **Shared by every physical-sky consumer** — `gbuffers_skybasic`, terrain fog, water analytic reflection, volumetric godrays, clouds and the SSR sky fallback all sample the same LUTs instead of each running a second atmosphere march.
*   When **`SKY_MODE=0`** (every shipped profile) the LUT passes write constants and cost almost nothing. Enable Physical Sky manually in the Experimental tab.

New Experimental → Atmosphere options (off-profile defaults stay cinematic / auto):

*   **`ATMOSPHERE_TURBIDITY`** — _Crisp / Balanced / Hazy_ aerosol load.
*   **`ATMOSPHERE_SCALE`** — _Compact 25 m / Balanced 50 m / Cinematic 100 m_ per block (how Minecraft Y maps into atmosphere kilometres).
*   **`GROUND_BOUNCE_MODE`** — _Auto (biome-aware) / Neutral Soil / Vegetation / Snow / Desert_.
*   **`SKY_TEMPORAL`** — rotation-only history blend for the sky (requires TAA). Physical sky uses a higher history weight than the animated gradient sky so stars/aurora do not trail.

The swamp detector now also matches **`BIOME_MANGROVE_SWAMP`**.

### 🌍 Distant Horizons — Hard Seam, TAA & Iris Workaround

> ⚠️ AuraLite still does **NOT** claim full Distant Horizons compatibility. v1.1.4 is a targeted correctness pass on the v1.1.2/v1.1.3 experimental path.

*   **Hard deterministic hand-off at `far`.** The v1.1.3 16 m screen-door dither discarded random LOD fragments in the seam band; on DH 3.2 those holes showed sky/white whenever vanilla geometry did not fill the same pixel. DH fragments with `dist < far` are now simply discarded — less cinematic, never stochastic.
*   **DH receives the same optional Halton camera jitter** as vanilla gbuffers. `composite1.fsh` reprojects DH pixels through `dhProjectionInverse` + `dhPreviousProjection` (vanilla matrices have the wrong far plane).
*   **Conservative DH history cap (0.45)** — LOD meshes change topology as chunks stream; they participate in TAA but cannot leave long trails.
*   **`DH_BLOCK_ILLUMINATED` tag `colortex2.a = 0.24`** — distant sea lanterns / glowstone stay self-emissive even when they are not lava-orange or portal-violet. Extra DH material classes: DIRT, SAND, TERRACOTTA.
*   **`dh_water`** now honours `WATER_WAVES` / riffles / transparency / specular, applies the frozen-ocean navy floor, and occludes against `dhDepthTex1` (plus Iris `depthtex1` via view-space Z, because raw depths use different projections).
*   **`DH_SHADOW_RANGE`** — _Seam (1.25×) / Extended (2×) / Far (4×)_ of vanilla `far`. LOD receivers can keep sampling the shared shadow map past the vanilla chunk edge.
*   **Shadow-map footprint rebalanced for DH:** MED **192 m**, HIGH/ULTRA **512 m**, EXTREME **768 m** (VERY\_LOW/LOW stay 60 m, no shadows).
*   **`dhShadow.enabled=false` by default.** DH 3.2.0-b + Iris 1.7.6 can replace/cull the _vanilla_ terrain shadow pass — symptom: mob shadows remain, block shadows vanish even in vanilla chunks. Users with a verified working Iris/DH bridge can turn the DH shadow pass back on and then use `DH_SHADOW_RANGE`.

### 🎯 TAA — Sky Temporal Resolve & Material Reactive Mask

*   **Sky temporal resolve (`SKY_TEMPORAL`)** — sky pixels have no stable world position, so history is reprojected with **camera rotation only** (no translation). Gradient-sky history weight is lower (0.28) than Physical (0.46) so clouds/aurora/meteors do not smear.
*   **Material reactive mask** — water (`0.8`), foliage (`0.62`) and emissive/lava (`< 0.5`) cut history weight by 46% / 30% / 58%. Without a per-object velocity buffer this is what stops waving leaves and water from ghosting after TAA.

### 🌊 Gerstner Water Spectrum

*   Replaces the v1.1.3 value-noise / fBm central-difference normal in `final.fsh`. That field was mathematically stable but read as high-frequency random glitter.
*   A 4-direction travelling swell (dominant wind + cross swell + two low-amplitude ripples) produces **analytic slopes** and a calmer default surface. Amplitude is clamped to `±0.22`.
*   Near-water vertex swell is slightly reduced (`0.04/0.02 → 0.032/0.016`) so the geometric mesh matches the new reflection spectrum.
*   Dead Voronoi lava-height helpers removed from `gbuffers_water`, `gbuffers_terrain_translucent` and `gbuffers_terrain` (lava stays texture-driven).

### ✨ Half-Resolution, Skippable HDR Bloom

*   New master **`BLOOM`** toggle. VERY\_LOW / LOW skip the entire 5-pass chain via `program.composite3–7.enabled=BLOOM` (Iris/OptiFine do not even dispatch the programs).
*   **`colortex3`/`colortex4` are half-resolution** (`size.buffer = 0.5 0.5`). Gaussian strides are doubled so the world-space radius stays the same; `final.fsh` linearly upsamples the glow.
*   `TAA` similarly gates `composite1`/`composite2`, so lighter profiles no longer pay for unused fullscreen passes.

### 🌌 Aurora Quality

*   New **`AURORA_QUALITY`** — _Soft 8 / Balanced 12 / Silky 18_ raymarch steps, with a centred globally-animated ray start (the previous per-pixel hash grain is gone).

### 🎚️ Profile Rebalance (v1.1.4)

| Profile        |Shadows                   |DH receivers |TAA |Bloom      |Sky temporal |
| -------------- |------------------------- |------------ |--- |---------- |------------ |
| VERY_LOW / LOW |❌ 512 / 60 m              |Seam         |❌   |❌          |❌            |
| MED            |✅ 1024 / <strong>192 m</strong> Balanced |Seam         |❌   |✅ Balanced |❌            |
| HIGH           |✅ 2048 / <strong>512 m</strong> Balanced |Extended     |✅   |✅ Balanced |✅            |
| ULTRA          |✅ 4096 / <strong>512 m</strong> Aggressive |Extended     |✅   |✅ Balanced |✅            |
| EXTREME        |✅ 8192 / <strong>768 m</strong> Aggressive |Far          |✅   |✅ Strong   |✅            |

Camera jitter remains **off by default in every profile**.

***

## 🚀 What's New in v1.1.3 — _True TAA, HDR Bloom Pyramid & Black-Water Regression Fix_

Version **1.1.3** completes the TAA pipeline (Halton sub-pixel camera jitter + YCoCg variance clipping), replaces the old single-pass bloom with a true multi-octave HDR gaussian pyramid, and fixes the long-standing **black-water regression** with MRT-proof water detection. It also adds procedural raindrop rings, biome-aware murky swamp water, underwater plant sway, post-TAA sharpening, and a ~48 MB VRAM cleanup.

### 🎯 True Temporal Anti-Aliasing (Halton Jitter + YCoCg Clipping)

*   **Halton(2,3) sub-pixel camera jitter** — every gbuffer vertex shader can offset `gl_Position` by a rotating 8-frame Halton pattern (±0.5 px). Previously TAA only blended history without jittering the sample point, so it could only blur noise instead of reconstructing sub-pixel detail.
*   **`TAA_JITTER` option — Off / Subtle / Standard / Strong** (new in v1.1.3). The jitter is **OFF by default in all profiles** for a rock-steady image; Subtle (±0.25 px), Standard (±0.5 px) and Strong (±0.75 px) scale the amplitude for users who want the full sub-pixel reconstruction (removes high-frequency shimmer at the cost of a slight temporal wobble). Requires TAA enabled.
*   **Previous-frame jitter compensation** in `composite1.fsh` — the old frame's offset is re-added to the reprojection (with the same strength scale), so static images converge instead of smearing ~0.5 px. Only active while jitter is on.
*   **YCoCg variance clipping (μ ± γσ)** replaces the axis-aligned 3×3 min/max box — the old box caused ghost trails on saturated high-contrast edges (fences, wires, hot specular) while being too tight on flat gradients. Clip width scales with `TAA_STRENGTH`: 1.50 Light / 1.25 Balanced / 1.10 Stable.
*   **Frame-rotated IGN dithers now resolve cleanly** — godrays and volumetric clouds rotate their interleaved-gradient-noise patterns per frame; with the temporal resolve they integrate into smooth gradients instead of shimmering.
*   **TAA is on by default in HIGH / ULTRA / EXTREME profiles** (off on VERY\_LOW / LOW / MED for maximum FPS); it can be toggled in the Post-Processing menu, and `TAA_STRENGTH` presets the variance-clip tightness.

### ✨ HDR Gaussian-Pyramid Bloom (composite3 – composite7)

*   Replaces the v1.0.1 single-pass 3×3 neighbour glow, whose ~1.5 px radius could only produce a tight halo.
*   New 5-pass chain: threshold **brightpass** (0.75 luma soft-knee, exposure-aware) → tight separable gaussian (9-tap, σ≈2.0) → wide separable gaussian (4× stride). Successive blurs compose to an effective **σ ≈ 8.2 px** — a soft cinematic falloff around the sun/moon disks, lava, portals and hot specular, without a mip chain.
*   Runs **after the TAA resolve**, so the bloom energy is temporally stable.
*   New **`HDR_BLOOM`** option (Subtle 0.06 / Balanced 0.12 / Strong 0.22 amplitude) wired into every quality profile.

### 💧 Black-Water Regression Fix — MRT-Proof Water Detection

*   **Root cause:** on some Iris builds the translucent pass drops the `colortex1`/`colortex2` MRT writes entirely — water then arrives with a zeroed normal + alpha + lightmap. The emissive fast-path (alpha < 0.5) swallowed it and every tag/lightmap-based system died with it.
*   **Detection ladder:** primary = `colortex2.a = 0.8` tag; **rescue** = the depth difference (`depthtex1` solid-only vs `depthtex0`) proves a translucent surface on top, then a **hue-fingerprint classifier** on the albedo rejects portals (violet, green-starved) and lava (blue-starved) while accepting water (blue/blue-green, never pale). Water, ice and glass classify; torch flames, portal sparkles, squid ink, pale ice and clear glass do not.
*   **Synthesized flat water normal** when the decoded normal is untrustworthy (MRT loss or clear value), so Fresnel/reflections still have sane inputs.
*   **Analytic sky reflection (`waterSkyRefl`)** — zenith/horizon gradient + warm sun-side glow, dimension-aware (Overworld palette, Nether biome sheen, End violet sheen), applied via Schlick Fresnel with a **0.20 floor** (pure F0≈0.02 at steep look-down angles was exactly what let shadowed water crush to black), multiplied by skyLight so cave water stays dark. This is the actual black-water fix and works with SSR disabled.
*   **Diffuse ambient floor** for rescued pixels whose lightmap may read zero.
*   **Navy-tint floor** in `gbuffers_water`/`gbuffers_terrain_translucent` — frozen-ocean biome tints (e.g. 0x3938C9) can no longer crush R/G to black after the gamma pipeline.
*   **`WATER_DEBUG`** diagnostics overlay (Off / Classify / Lightmap / Raw tag alpha) — green = healthy tag, red = depth-rescued, yellow = rescued from the emissive path, magenta = lava/portal-guarded.

### 🪟 SSR & Refraction Fixes (final.fsh)

*   **Procedural sky fallback** for reflection rays that leave the screen or hit the sky — previously black (the reason the `waterMirrorBoost` hack existed); now a day/night/sunset/storm-aware gradient with moon-phase brightness, Schlick-Fresnel weighting and edge fade.
*   SSR march start moved **1.0 → 0.5** view units off the surface so the water plane at the player's feet still reflects near-field geometry.
*   MRT-proof water detection reused for SSR/refraction (same hue guards as `composite.fsh`).
*   **Procedural raindrop rings** on wet up-facing surfaces — two layers of expanding, world-stable circular waves perturb the SSR normal so rain reads as thousands of tiny ripples instead of one flat mirror.

### 🔍 Post-TAA Sharpening (POST\_SHARPEN)

*   Gentle 5-tap unsharp mask (0.18 amplitude, clamped ≥ 0) applied to the resolved image **before** refraction/SSR/bloom work, recovering texture detail softened by TAA's history blending. On in MED+ profiles.

### ☁️ Volumetric Clouds — Quality Scaling & Dithered Ray Start

*   New **`CLOUD_QUALITY`** option: 8 / 12 / 16 raymarch steps (was hardcoded 12) — Cheap / Standard / High.
*   **Dithered ray start** (frame-rotated IGN) on geometry pixels when TAA is enabled: the frame-rotating pattern is temporally resolved into a smooth volumetric integral, killing the 12-step ribbing on thick cumulus without the v0.2.5-era "swimming". Sky pixels keep the stable centred start.

### 🌿 Underwater Plants Sway

*   New block class **10010** (`seagrass`, `tall_seagrass`, `kelp`, `kelp_plant`, `sea_pickle`) — fronds sway in a current, phase-shifted by height so the tips lag the base, storm-agitated along with the surface foliage path. Displacement is mirrored in `shadow.vsh` so shadows follow the visible fronds.

### 🌊 Biome-Aware Murky Water

*   Smoothed swamp/mangrove detector (`isSwampBiome`) — swamp water absorbs more red and reads **greener and murkier** (`absorption (0.23, 0.038, 0.10)`, deep colour pushed to dark green) instead of open-ocean blue.

### 🧪 Physical Sky — Warm Ground Bounce

*   The experimental `SKY_MODE=1` atmosphere now includes a **warm ground-bounce term**: terrain's ~15–20% mean albedo re-scatters in the lower atmosphere (strongest at the horizon and with a high sun), removing the "sterile" blue-bias horizon band.

### 🌇 Lighting & Ambience

*   **Rayleigh-tinted day ambient** — the day hemisphere ambient now follows the actual sun extinction: golden-hour light is warm and blue-depleted instead of static grey-blue.
*   **Held-light temperature** — strong held sources (sea lantern, glowstone, shroomlight, lava bucket) read slightly cooler than candle-strength light.

### 🌍 Distant Horizons — Soft Seam

*   The v1.1.2 hard `discard` at `far + 16` is replaced by a **screen-door dithered transition band**: DH LOD fragments stochastically blend into vanilla chunks over 16 m, so crossing the boundary or changing render distance no longer shows a hard cut. The pattern is static per frame (DH-only pixels are excluded from TAA history).

### 🛠️ Pipeline & VRAM Cleanup

*   **Removed `colortex5`/`colortex6` format directives** — never read or written, but each forced Iris/OptiFine to allocate a full RGBA16F screen buffer: **~32 MB saved [@1080p](https://github.com/1080p), ~128 MB [@4K](https://github.com/4K)**.
*   **`shadowcolor0Format` RGBA16F → RGBA8** (it only carries LDR `tex * glcolor`): another ~16 MB [@1080p](https://github.com/1080p) / ~64 MB [@4K](https://github.com/4K).
*   **`shadowcolor1Format` removed** (nothing ever wrote to it).
*   **`colortex0Clear = true`** — no stale garbage on the first frame or after a window resize.
*   `colortex3`/`colortex4` are now actually used by the bloom pyramid; the full 8-buffer HDR pipeline is engaged.

***

## 🚀 What's New in v1.1.2 — _Render-Distance Shadows & Experimental Distant Horizons (Partial)_

Version **1.1.2** extends shadow rendering to the actual render distance with an adaptive LOD system, fixes HDR/TAA pipeline strictness, cleans up deprecated GLSL, and introduces **partial, experimental Distant Horizons support (WIP)** — without claiming full compatibility yet. Work is ongoing.

### 🌗 Extended Shadow Distance with Adaptive LOD

*   **Shadows now reach render distance.** `shadowDistance` was `60-160m` with a hard cutoff at `shadowDistance`. Now it scales with quality profiles: **60m (VERY\_LOW/LOW, no shadows) → 120m (MED) → 256m (HIGH/ULTRA) → 384m (EXTREME)**. The cutoff is replaced by a soft fade `smoothstep(far*0.85, far*0.98)`.
*   **New `SHADOW_LOD` toggle — Off / Balanced / Aggressive.** Reduces sample count and expands filter radius at distance to keep performance stable:
    *   Balanced: `>25% far → 16 samples ×1.8 radius, >50% → 8 ×2.8`
    *   Aggressive: `>15% → 16×2.0, >35% → 8×3.5, >60% → 4×5.0`
    *   Beyond 95% `far` shadow sampling is skipped entirely.
*   **`shadowMapResolution` now includes `8192`.** EXTREME uses 8192 for maximum texel density at 384m. HIGH stays 2048, ULTRA 4096.
*   **New `SHADOW_PCSS_BLUR` toggle — fixed softness vs PCSS penumbra softening.** When enabled, penumbra grows with blocker distance and rain. When disabled, shadows use constant softness.
*   **PCSS correctness fixes in `composite.fsh:sampleShadow()`:** added UV bounds checks (prevents clamp-to-border artifacts), `avgBlockerDepth` clamped to `1e-4` to avoid NaN, `penumbraSize` clamped `0-2.0`, `lightSize` reduced `140→40` to prevent light bleeding, `actualSpread` capped to `16.0`, out-of-bounds samples counted as unshadowed (1.0) for correct averaging.
*   Shadow bias `distBias` now scales with `far` instead of `shadowDistance`, plus extra water receiver bias for tagged water pixels (`colortex2.a≈0.8`).

### 🔧 HDR Pipeline Strictness Fix

*   **Dummy `#define RGBA16F 0` guards** added before the `const int colortex*Format = RGBA16F` directives. This satisfies strict GLSL validators (`C1503 undefined variable RGBA16F`) while Iris/OptiFine's parser still reads the format names (spec second clause). In v1.1.1 the directives were inside a `/* */` comment and were ignored by some loaders.
*   Now **all used buffers are explicitly `RGBA16F`**: `colortex0/1/2` (main HDR + PBR + material tags), `colortex3/4/5/6` (unused today but set to HDR for a full pipeline), `colortex7` (TAA history, `colortex7Clear=false`), and optional `shadowcolor0/1Format = RGBA16F`.
*   Cost noted: ~16MB per 1080p RGBA16F buffer → ~128MB VRAM for 8 buffers.

### 🌍 Experimental — Partial Distant Horizons Support (WIP, not full support)

> ⚠️ AuraLite does **NOT** yet claim full Distant Horizons compatibility. v1.1.2 only adds a **minimal, experimental code path** so LOD chunks are no longer invisible under Iris. It's functional enough for testing, but considered partial and work-in-progress.

*   **Why it was needed:** Without `dh_terrain.vsh/.fsh`, `dh_water.vsh/.fsh`, `dh_shadow.vsh/.fsh`, Iris marks the pack as incompatible with DH and simply doesn't draw DH's simplified LOD chunks at all — symptom "shader works but DH chunks invisible". Presence of these files is enough for Iris/DH auto-detection (`dhShadow.enabled` defaults true).
*   **What v1.1.2 does:**
    *   `dh_terrain`/`dh_water` write the same `colortex0/1/2` layout as vanilla passes, so existing lighting/fog/shadow/cloud/godray code in `composite.fsh` applies to LOD geometry without other changes.
    *   Depth reconciliation in `composite.fsh`: detects `depthtex0>=1.0 && dhDepthTex0<1.0` → `isDHTerrain`, reconstructs viewPos via `dhProjectionInverse` (not `gbufferProjectionInverse` — different far planes) and computes `isSkyPixel`. Fixes DH terrain being treated as sky (flat/washed-out).
    *   Fog rescale: `effectiveDensity *= far/dhRenderDistance` prevents exponential fog from saturating to white before DH draw distance.
    *   Emissive fast-path uses `!isSkyPixel` instead of `depth<1.0` so distant `DH_BLOCK_ILLUMINATED` (glowstone/lanterns) is still emissive.
    *   `final.fsh` heat shimmer now checks `dhDepthTex0` via `isRealGeometry` so distant lava lakes also shimmer.
    *   Overdraw prevention: `if(dist < far+16.0) discard` in DH passes — DH renders entire world including area already covered by vanilla chunks; without discard both fight over same G-buffer pixel causing Z-fighting / missing water/ice.
*   **Current limitations (why it's partial):**
    *   `gl_MultiTexCoord2` is not guaranteed to carry valid lightmap data for DH programs — v1.1.2 hardcodes `lmcoord = vec2(0.0,1.0)` (open sky, no torch). Correct for exterior DH, but not interior-perfect.
    *   No LabPBR `normals`/`specular` maps for DH — roughness/metalness approximated per `dhMaterialId` (STONE/WOOD/METAL/SNOW/LEAVES/LAVA…). No POM on DH.
    *   Water uses flat vertex normal, not procedurally displaced like near water.
    *   Fog/sky/cloud code paths are shared but DH has coarser geometry.
*   **Ongoing work:** proper skylight baking if DH ever exposes it, LabPBR fallback, smoother transition seam, performance tuning. Full support will be announced separately.

### 🛠️ Pipeline Cleanup & Fixes

*   **Menu split fix — `[v1.1.1-ui-hotfix]`:** Oversized option screens were split into `[SHADOW_OPTIONS]`, `[PBR_OPTIONS]`, `[AO_REFLECTIONS]`, `[CLOUD_SHAPE]`, `[LIGHT_SHAFTS]`, `[NIGHT_SKY]` because some Iris/OptiFine UI builds silently hide buttons when a screen has too many entries.
*   **Deprecated `ftransform()` removed** from `composite.vsh`, `final.vsh`, `gbuffers_clouds.vsh`, `composite1.vsh`, `composite2.vsh`, `gbuffers_weather.vsh` — replaced with explicit `gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex` for broader driver compat (same fix applied to `shadow.vsh` in v1.1.0).
*   **Final pass cleanup:** Removed two duplicate copy-pasted post-gamma dither blocks that contradicted the comment about linear-space dither (triangle `±1/255` before tonemap). The single pre-tonemap dither remains — more effective in darks, silent in brights.
*   **Bias & stale comment fixes:** Corrected stale `colortex6` hand-off comment (removed in v1.0.3), now notes that `final.fsh` reads normal from `colortex2` and roughness from `colortex1.z`.
*   **Rebalanced profiles** to reflect new distances and LOD:
    *   VERY\_LOW/LOW 60m (no shadows), MED 120m Balanced, HIGH 256m Balanced, ULTRA 256m Aggressive, EXTREME 384m Aggressive + 8192 res.
*   **Localization:** Bumped `lang/*.lang` headers `v1.0.7 → v1.1.2`, translated previously-English `profile.*.comment` placeholders into native languages (ur\_pk, vi\_vn, zh\_cn, zh\_hk, zh\_tw and others).

***

## 🆕 What's New in v1.1.0 — _True Volumetric Godrays, HDR Pipeline & Experimental Physical Sky_

Version **1.1.0** replaces the screen-space godray approximation with a fully volumetric raymarched implementation, switches the entire G-buffer pipeline to true HDR (RGBA16F), and introduces an experimental, fully physical realtime atmospheric-scattering sky mode as an opt-in alternative to the stable gradient sky. This is a focused two-pillar update on top of the **v1.0.7** bug-fix baseline.

### 🌤️ True Volumetric Godrays

The old `computeGodrays()` screen-space approximation has been replaced by `computeVolumetricGodrays()` — a genuine single-scattering volumetric raymarch:

*   **Per-step shadow-map occlusion** — every raymarch sample now tests the shadow map individually, so light shafts are actually carved by real geometry (trees, buildings, cave ceilings) instead of being implied by a "forward-looking boost" toward the sun.
*   **Interleaved Gradient Noise dithering** (Jimenez 2014), rotated per-frame via the new `frameCounter` uniform when TAA is active — 8–24 raymarch steps now integrate as smoothly as hundreds, with no banding.
*   **Exact per-segment Beer–Lambert integration** — `Tr₀ · σs/σt · (1 − e^(−σt·Δx))` per step, which is energy-conserving regardless of step size (no more over-brightening at low sample counts).
*   **Dual-lobe Henyey-Greenstein phase function** (forward + weak backscatter lobe) with an isotropic floor, so crepuscular rays stay visible when looking _across_ them, not only when staring directly at the sun.
*   **Colored radiance** — shafts are now warm Kelvin-driven sunbeams by day, deep orange at sunset, and faint blue moonbeams at night, instead of a flat white/yellow overlay.
*   **New `GODRAYS_STRENGTH`** setting (_Subtle / Balanced / Dramatic_) added to every quality profile.
*   `GODRAYS_QUALITY` sample counts and distances increased: Fast 8 samples/96m, Balanced 16/128m, High 24/160m (up from 4/72m, 6/110m, 8/150m in v1.0.7).

### 🌈 Full HDR G-Buffer Pipeline

*   **`colortex0`, `colortex1`, and `colortex2` are now explicitly `RGBA16F`.** Bright sources — the sun disk, lava, specular highlights, portals — no longer clip to `1.0` before tone mapping, so the ACES/AgX curves in `final.fsh` finally compress genuine HDR highlights instead of receiving pre-clamped input. Bloom now samples real HDR luminance rather than an already-saturated LDR buffer.
*   `colortex2`'s alpha channel carries a 5-value material tag (`0.0`/`0.1`/`0.62`/`0.8`/`1.0`); RGBA16F guarantees these are preserved exactly, whereas a lower-precision format would have aliased and collided material tags (e.g. foliage vs. water).
*   Godray intensity constants were re-tuned (roughly halved vs. the old LDR values) now that the additive shaft survives in full instead of clipping against a saturated scene; a stronger soft shoulder (`0.50` vs. the old `0.30`) keeps the sun-facing core from blowing out under HDR.

### 🧪 Experimental: Realtime Physical Sky (Off by Default)

A brand-new **`[EXPERIMENTAL]`** menu tab exposes an alternate sky renderer in `gbuffers_skybasic.fsh`, disabled in every shipped profile (`SKY_MODE=0`) so the stable gradient sky remains the default:

*   **`SKY_MODE`** — `0` (Gradient, legacy v1.0.7-style sky) or `1` (Physical Realtime): a genuine per-pixel ray-marched atmosphere with exact 1st-order single scattering (Rayleigh + Mie + Ozone, full sun-ray optical-depth march with ground-occlusion detection) plus a blue-biased, bounded multiple-scattering ambient term that fills in the zenith/horizon without producing the typical LUT-based "yellow band" artifact. No lookup textures, no cross-frame reads.
*   **`SKY_QUALITY`** — controls raymarch sample counts (_Fast 8×4 / Standard 12×6 / High 16×8_) for the physical mode.
*   **`SKY_STYLE`** — new artistic-direction toggle independent of `SKY_MODE`: _Realistic_ (true angular sun/moon size, neutral colors, minimal glow — an authentic astronomy look), _Semi-realistic_ (readable ×2.8 sun/moon size, richer color, soft aureole — the default), or _Fantasy_ (grand ×5.5 sun/moon, huge corona, vivid saturated teal/crimson/indigo palette for a stylized sky).
*   Physical mode renders the sun disk with real limb darkening and a physically-derived angular radius, and computes its color from actual sun-ray transmittance (ozone-aware) rather than the legacy Kelvin/airmass approximation.
*   Because this feature is explicitly experimental and disabled by default, it introduces no behavioral change to any existing profile.

### 🛠️ Smaller Fixes & Cleanup

*   **Dark-sky/moon-halo banding fixed at the source** — a linear-space triangle-distributed dither (`±1/255`, matching the BSL/Complementary technique) is now applied in `final.fsh` _before_ tone mapping, where gamma expansion makes a tiny linear noise term large enough in the darks to smooth the gradient, while staying invisible in bright regions. The old post-gamma dither (which couldn't fix pre-tonemap banding) has been removed and replaced with an explicit final `clamp()`.
*   `shadow.vsh` no longer relies on the deprecated fixed-function `ftransform()`; it now builds the clip-space position explicitly via `gl_ModelViewMatrix` / `gl_ProjectionMatrix` for broader driver compatibility.
*   Updated localization strings for `GODRAYS`, `GODRAYS_QUALITY`, and the new `GODRAYS_STRENGTH` / `SKY_MODE` / `SKY_STYLE` / `SKY_QUALITY` options and the new Experimental tab.

***

## 🆕 What's New in v1.0.0 — _Meteor Showers & Finalized Reflection Pipeline_

Version **1.0.0** builds on the volumetric aurora work from v0.3.0 and introduces the first **v1.0.0** source snapshot in this repository. The update adds a physically-inspired meteor system to the night sky, finalizes the modern SSR path for reliable Iris compatibility, and refreshes the documentation so the project now correctly points to the `shaders v1.0.0/` folder.

### ☄️ Physically-Based Meteors / Falling Stars

*   **True great-circle sky arcs.** Meteors are rendered as moving arcs on the celestial sphere instead of flat 2D streaks, so showers converge toward a shared radiant like real meteor photography.
*   **Ablation-based brightness curve.** Each meteor rises, peaks, and fades with a bell-shaped light curve inspired by atmospheric entry.
*   **Blackbody plasma colouring.** Meteor heads are tinted with the same Kelvin-based colour pipeline used by AuraLite's sun/moon lighting, giving physically consistent warm-to-white fireball tones.
*   **Moonlight washout and weather attenuation.** Faint meteors are suppressed by bright moon phases, rain, and daytime sky brightness, improving realism and avoiding visual clutter in poor visibility.
*   **Persistent trains on bright fireballs.** The strongest events leave a short-lived glowing ionization trail, including a subtle green oxygen-style tint on the lingering train.
*   **Available in both Overworld and The End.** Overworld meteors respect moonlight and atmosphere; End meteors render against the permanent night sky without moon washout.

### 🪞 Finalized v1.0.0 SSR / Water Reflection Path

*   **`colortex6` fully removed from the reflection workflow.** The older MRT export path was retired; `final.fsh` now reads normals directly from `colortex2` and roughness from `colortex1`, matching AuraLite's already-working PBR data path.
*   **Depth-based water-surface detection.** Water is identified by comparing `depthtex0` and `depthtex1`, making reflections robust on Iris paths where water G-buffer writes may be inconsistent.
*   **More stable water normals.** Reflection normals are reconstructed from neighbouring depth samples and then perturbed with coherent world-space ripple gradients, reducing faceting and torn reflections.
*   **Cleaner post-pass reliability.** The reflection pipeline now lives entirely in the final post-processing pass, simplifying the frame graph and avoiding loader-specific MRT issues.

### 🎛️ New Sky Settings & Profile Integration

*   New configurable options: **`SHOOTING_STARS`**, **`SHOOTING_STARS_FREQUENCY`**, and **`SHOOTING_STARS_BRIGHTNESS`**.
*   Shooting stars are disabled on the lightest presets and enabled from **MED** upward through the normal profile system.
*   English and Russian UI text was expanded for the new night-sky controls, while other language files continue to fall back safely.

***

## 🆕 Recap — What landed in v0.2.6 — _License Migration & Version Support_

Version **0.2.6** is a legal protection and compatibility update. It migrates the project license to a copyleft non-commercial model to protect AuraLite from unauthorized commercial redistribution, adds copyright assertions to all source files, and officially expands tested compatibility.

### ⚖️ License Migration to CC BY-NC-SA 4.0

*   **MIT to CC BY-NC-SA 4.0** — Migrated the project's license from MIT to **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International**. AuraLite is now legally protected against commercial reuse and unauthorized sales (e.g. on third-party launchers/portals).
*   **Copyright Asserted** — Explicitly declared copyright: `Copyright (c) 2026 AlexanderNyr`.
*   **Embedded Code Headers** — Embedded copyright headers (`// AuraLite Shaders - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.`) into all GLSL shader files (`.fsh`, `.vsh`), block properties (`.properties`), and translation tables (`.lang`).
*   **Rules & Permissions FAQ** — Added a clear FAQ section outlining allowed actions (monetized videos/streaming, inclusion in free CurseForge/Modrinth modpacks) and prohibited actions (commercial sales, paid Patreon redistributions, raw rehosting on ad-supported download hubs).

### 🎮 Version Compatibility Expansion

*   **Minecraft 26.1.2 Support Verified** — Tested and verified to work flawlessly on the latest Minecraft Java hotfix **26.1.2** with Iris + Sodium.
*   **Minecraft 1.16.5 Support Verified** — Tested and confirmed to run beautifully on the legendary modding version **1.16.5** (Iris/OptiFine).

***

## ✨ Features At A Glance

### ☁️ 1. Meteorological 3D Volumetric Clouds (Fly-Through!)

AuraLite features a fully physical, flyable 3D cloud system driven by a **microphysically parameterised raymarch** in world coordinates — _rebuilt in v1.2.0_:

*   **True 3D Space:** Clouds float at a physical altitude in **metres** (400 m to 3.6 km by `CLOUD_HEIGHT`). You can fly up, enter a dense, foggy overcast, and rise above the clouds to see an endless rolling sea of fluffy cumulus.
*   **The deck is a medium** _(v1.2.0)_: liquid water content and droplet radius set the extinction, so density behaves like water rather than like a slider, and the shaded underside of a cloud is dark for a physical reason.
*   **Resolution ≠ detail** _(v1.2.0)_: `CLOUD_QUALITY` spends samples, `CLOUD_DETAIL` spends shape octaves, and either can be lowered without touching the other.
*   **Camera-Inside-Cloud Veil** _(v0.2.5)_: When flying inside the cloud layer, a soft volumetric white/grey fog surrounds the camera.
*   **Independent wind and updraft** _(v0.2.5, physical in v1.2.0)_: Clouds drift at a velocity in m/s with `WIND_SPEED`, grow upward with `CLOUD_UPDRAFT`, and each column gets its own condensation level (`CLOUD_BASE_VARIATION`) so the deck is not a flat sheet of identical blobs.
*   **Cloud Render Distance** _(v0.2.5, extended in v1.2.0)_: Four steps, up to **32 000 m** of horizon-scale deck.
*   **Cirrus and a mid-level deck** _(v1.2.0)_: Two independent families on top of the cumulus — a fibrous ice veil at 6.5–11.2 km and its own altocumulus layer, each switchable.
*   **Multiple scattering:** Cloud interiors receive light that has already scattered, which is why thick tops read bright instead of flat grey.
*   **Overcast Storms:** When raining (`/weather rain`), the cumulus expands, darkens, merges into a heavy **Nimbostratus/Cumulonimbus** deck, and lightning flashes inside it.
*   **One cloud shadow for the whole frame** _(v1.2.0)_: the term that gates the godrays is computed once per frame in the quad vertex shader, generated from the fragment source so the two can never disagree.

### 🌠 2. Living Night Sky _(since v0.2.0)_

The night sky is no longer just a static starfield — it's a fully procedural cosmos:

*   **Aurora Borealis:** Realistic, flowing northern lights that ripple across the upper sky. Modes: _Disabled / Only in Cold Biomes / Always Enabled_, with independent **speed** and **brightness** controls. _(v0.2.5: rendered in `gbuffers_skybasic` for reliability; cold-biome detection uses real biome uniforms. v1.0.7: tone softened and high-frequency noise removed — read as a photographic glow rather than oversaturated neon.)_
*   **Milky Way Nebula:** A subtle diagonal brownish galactic band glows softly above the horizon, with adjustable brightness.
*   **Procedural Stars:** Independent **brightness** and **density** sliders let you choose between a few crisp pinpricks or a brilliantly dense Hubble-style sky. Stars sparkle and twinkle in real time.
*   **Physically-Based Meteors / Falling Stars** _(v1.0.0)_: configurable meteor activity, brightness, moon washout, and persistent ionization trails bring realistic night-sky streaks to the Overworld and the End.
*   **Persistent Rainbow:** After rain stops, a soft rainbow arcs across the sky and gently fades out as the `wetness` uniform decays. Brightness and saturation are configurable.

### ☀️ 3. Analytical Kelvin Sun & Moon — _Enhanced in v0.2.2, refined in v0.2.5_

*   **Tanner Helland Blackbody Sun:** Sunlight color temperature is dynamically calculated in real time based on the sun's elevation angle using a physically-correct **blackbody Kelvin curve** (selectable: _Cool / Realistic / Warm Golden_). This yields photoreal sunrise/sunset colors (~1800K–2200K), warm golden hours (~2800K), and clean crisp white noon light (~5700K–5800K).
*   **Beer-Lambert Atmospheric Extinction:** Sunlight intensity dynamically drops as the sun approaches the horizon due to scattering in thick atmospheric masses: $airMass = \\frac{1}{\\sin(\\alpha) + 0.15 \\cdot (\\alpha\_{deg} + 3.885)^{-1.253}}$ This yields incredibly soft, rich, and breathtaking sunset and sunrise golden hour transitions!
*   **Independent Sun & Moon Intensity** _(v0.2.2)_: 4-step master sliders let you push the day brighter (_Blazing_) or sink nights into total darkness (_Pitch Night_).
*   **Moon Color Temperature** _(v0.2.2)_: choose between _Icy Blue_ (cold), _Silver_ (physically accurate 4100K), or _Warm Cream_ (harvest-moon).
*   **Sun Halo (Mie forward-scatter)** & **Enhanced Sunrise/Sunset Glow** _(v0.2.2)_ — warm scattering effects on terrain when looking near the low sun.
*   🆕 **Extended Twilight Window** _(v0.2.5)_: Sunset/sunrise lighting stays warm/red at `/time set 12800` instead of snapping to neutral.
*   **Crispy Circular Sun & Moon Disks:** Custom procedural, perfectly round, anti-aliased sun and moon disks are drawn onto the sky dome with glowing coronas and soft halo scattering.

### 👥 4. Soft Shadows, Immersive Dark Nights & Cozy Lights — _Enhanced in v0.2.2, refined in v0.2.5_

*   **Rotated Poisson Disk Soft Shadows** _(v0.2.2)_: replaces the old fixed 3×3 PCF kernel. Three quality steps — _Sharp / Soft / Ultra Soft_ — give natural-looking penumbra on shadow maps up to 4096×4096.
*   🆕 **Shadow Slope Bias Fix** _(v0.2.5)_: bias now uses raw NdotL to prevent acne artifacts.
*   **Shadow Distance Control** _(v0.2.2)_: cap dynamic shadow rendering at _60m / 80m / 120m / 160m_ for performance or quality tuning.
*   **Shadow Tint** _(v0.2.2)_: realistic cool-blue tint for daytime shadows under an open sky (or neutral / warm if you prefer).
*   **Ambient Lift** _(v0.2.2)_: control how dark shadowed areas appear at night and in caves.
*   **Light Wrap (Terminator Softness)** _(v0.2.2)_: choose physical Lambert, a soft photographic wrap, or a stylized look. _(v0.2.5: all profiles default to realistic Lambert.)_
*   🆕 **SSAO / SAO Contact Ambient Occlusion** _(v0.2.5)_: screen-space darkening in corners and at geometry intersections. Enabled on ULTRA+ profiles.
*   **Deep Dark Nights (2× darker):** Night ambient light, moonlight intensity, and fog are reduced by 2× by default to create incredibly atmospheric, immersive nights. Caves and forests are pitch dark, requiring torches for exploration (combine with the new _Pitch Night_ moon preset for extra spice).
*   **Warm Block Lights:** Torches, lanterns, and lava emit a cozy golden-amber glow with physically accurate quadratic falloff.
*   🕯️ **Cozy Torch Flickering** _(since v0.2.0)_: Real-time flickering animations for torches, campfires, and lanterns add a living, warm atmosphere to your shelters. Held-item light contribution (`heldBlockLightValue`) is also accounted for.

### 🌊 5. Physical Fresnel Water & Silver Moonlight Path — _Refined in v0.2.5_

*   **Fresnel Effect:** Water reflectivity is mathematically calculated based on your viewing angle. Looking straight down provides crystal transparency, while looking towards the horizon transitions water into a highly reflective, glossy sheet reflecting the sky dome.
*   **Silver Moonlight Path:** Moonlight specular reflection on water ripples has been increased by **4.5×**. At midnight, a brilliant silver lunar reflection path shimmers across the waving ocean.
*   🆕 **Unified GGX PBR Water Specular** _(v0.2.5)_: Water's old Blinn-Phong specular replaced by composite's GGX microfacet model with proper Fresnel — physically consistent with terrain PBR.
*   **3D Geometric Waves:** Vertex shader waves physically displace the water mesh in real-time, and react to `rainStrength` / `thunderStrength` for choppier seas during storms.
*   🌊 **One coherent wind-wave spectrum** _(v1.2.0)_: eight components with real deep-water dispersion (`ω = √(gk)`), evaluated in world space, so long swell travels faster than short chop and the pattern belongs to the sea instead of to the camera. Only the three longest components move the mesh — the rest live in the normal, where there is no one-vertex-per-block grid to alias against.
*   🆔 **Water is identified by ID, not by colour** _(v1.2.0)_: `minecraft:water` maps to block ID `10020`, so reflections, refraction and the underwater grade no longer depend on guessing from depth and hue.
*   **Independent Ripple & Specular Controls** _(since v0.2.0)_: `WATER_RIFFLES` (Calm / Standard / Choppy) and `WATER_SPECULAR_STRENGTH` (Soft / Standard / Glinting) can be tuned separately for the perfect water mood.
*   **Zero Feedback Glitches:** Designed to be extremely stable, utilizing no feedback-loop depth buffer reads to guarantee bug-free solid rendering on all GPUs.

### 🌧️ 6. Dynamic Weather Surfaces _(since v0.2.0)_

*   **Wet Reflections:** During rain, solid blocks like grass, dirt, and stone darken and become glossy, picking up sky reflections under open weather. Disables itself under roofs.
*   **Low Ground Mist (Y ≈ 60–70)** _(refined in v0.2.5)_: Soft fog sheets drift across water and ice surfaces at dawn and dusk. Uses large slow sheets + small breakup noise with optical distance accumulation for natural-looking radiation fog. Humidity from rain/wetness makes the mist persist longer.
*   **Camera-Inside-Mist Veil** _(v0.2.5)_: Standing inside the mist layer produces a subtle whole-view forward-scattering veil.
*   **Thunderstorm Awareness:** Shaders distinguish between regular rain and full thunderstorms via the `thunderStrength` uniform, intensifying cloud darkness and wave chop accordingly.

### 🌿 7. Lively Foliage

*   Waving animations for oak/spruce/birch leaves, tall grass, flowers, vines, lily pads, and crops.
*   🌾 **Three plant classes** _(v1.2.0)_: tall double-height plants bend from the base, short grass flutters fast and stiff, flower heads nod on a rigid stem — all phased from **world** coordinates, so the motion belongs to the field instead of to the chunk you happen to stand in.
*   🍃 **Vegetation canopy shading** _(v1.2.0)_: foliage is lit as a crown with light reaching the inside, not as a set of flat vertical cards (`VEGETATION_CANOPY`).
*   Gently animated using hardware-optimized sine waves and time constants, mirrored in the shadow pass so leaves never cast a shadow of their old position.
*   🧊 **Ice fix** _(since v0.2.0, refined in v1.0.4)_: regular ice renders with texture + semi-transparency; packed/blue ice renders opaque with texture. All ice types have waving and refraction disabled to eliminate visual glitches.
*   🪟 **Glass rendering** _(v1.0.4)_: all glass blocks and panes (including every stained-glass variant and tinted glass) now render with their actual texture and proper transparency via the dedicated translucent terrain pass.

### 💎 8. Full LabPBR 1.3 Material Support + POM — _PBR refined in v0.2.5_

*   **3D Normal Maps:** Real-time **TBN (Tangent-Binormal-Normal)** matrices generate true three-dimensional depth on blocks (stone crevices, brick joints) reacting dynamically to light angles.
*   **Specular Reflection (GGX Microfacet):** Polished surfaces give sharp glossy glints, while metallic surfaces (gold, copper, iron) tint the specular reflection with the block's native albedo. _(v0.2.5: correct NdotL cosine factor added for Cook-Torrance BRDF accuracy.)_
*   🧱 **Parallax Occlusion Mapping (POM)** _(since v0.2.0, working since v1.2.0)_: True per-pixel block relief that pops out of the surface. Configurable `POM_DEPTH` (1–3) and `POM_STEPS` (1–4). The switch used to be a commented-out `#define`, so the menu entry could never reach the shader — it is a real option now, and it restricts itself to flat opaque terrain faces that actually carry a LabPBR height map. Recommended to keep off on incompatible resource packs.
*   _Seamless Fallback:_ Falls back automatically to gorgeous flat vanilla textures if no PBR resource pack is active.

### 🌀 9. Cosmic Nether Portal _(since v0.2.0, improved in v0.2.5)_

The vanilla Nether portal texture is procedurally transformed into a **swirling 3D plasma vortex** — animated purple/magenta cosmic energy that pulses with hypnotic depth. Mapped via dedicated block ID `10006` in `block.properties`. _(v0.2.5: portal pixels are flagged as emissive so composite skips scene lighting and displays the plasma as-is.)_

### 🪟 10. Translucent Block Rendering _(added in v1.0.4, unchanged in v1.0.6)_

AuraLite renders translucent blocks with proper per-block transparency through a dedicated `gbuffers_terrain_translucent` pass, ensuring correct display on both Iris and Oculus pipelines:

*   **Regular ice** — semi-transparent with actual texture; opacity scales with `WATER_TRANSPARENCY` (Clear / Balanced / Deep).
*   **Packed ice / blue ice / frosted ice** — opaque with texture, visually distinct from regular ice.
*   **All glass blocks and panes** — every vanilla glass type (clear, all 16 stained variants, pane variants, tinted glass) renders with its actual texture and correct transparency. No more invisible glass against bright skies.

### 🎬 11. Cinematic Post-Processing — _Refined in v1.0.1, v1.0.3, rebuilt in v1.2.0_

*   **Multiple Tone Mapping Curves** _(since v0.2.0)_: Pick from **Soft**, **Filmic (ACES)**, or **Intense (High Contrast)** to match your preferred mood.
*   **Color Vibrancy** _(since v0.2.0)_: 4-step non-linear saturation control (_Muted / Balanced / Colorful / Vivid_) that makes foliage glow emerald and skies look lush, without crushing skin tones.
*   **Exposure Brightness:** Muted / Balanced / Vibrant — global brightness lift.
*   **Subtle Vignette:** Gentle lens-darkening at screen edges for improved depth and immersion.

### 🔥 12. Procedural Lava & Heat Shimmer _(v1.0.6)_

*   **Procedural Magma Surface:** Lava and flowing-lava blocks are rendered with a procedural Voronoi crack field, animated convection flow, rare hot spots, and rising bubbles.
*   **3D Parallax Cracks:** A 4-step parallax occlusion raymarch gives real depth between the dark basalt crust and glowing magma.
*   **Viscous Vertex Waves:** The top face slowly swells with a heavier, slower wave than water, giving a molten feel.
*   **Heat Shimmer:** `final.fsh` applies a subtle screen-space distortion above lava pixels to simulate rising hot air.
*   **PBR-Ready:** Rough basalt crust (0.95) and glossy magma cracks (0.02) produce physically plausible highlights.

### 🛡️ 13. Realistic Atmospheric Fog _(v0.2.5)_

*   Fog density now accounts for **altitude** (aerosol concentration decays with height), **horizon path length**, and **indoor/outdoor exposure** via skylight.
*   Consistent Beer-Lambert distance fog with height-weighted density — no delayed fog walls.

***

## ☁️ Cloud Altitude Classification

AuraLite's sky is meteorologically modeled after the international cloud classification system:

```
Altitude (m)
16 000 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  ↑ Cumulonimbus (Cb)
12 000 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│
10 000   Ci  ─ Cirrus              │ Vertical
 8 000   Cc  ─ Cirrocumulus         │ Development
 6 000 ─ ─ Cs ─ Cirrostratus ─ ─ ─ ─│─ High Clouds (Cirrus layer)
 5 000   Ac  ─ Altocumulus          │
 4 000   As  ─ Altostratus          │
 2 000 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ Mid Clouds
 1 500   Sc  ─ Stratocumulus        │
 1 000   St  ─ Stratus              │
 500     Ns  ─ Nimbostratus         │─ Low Clouds (Cumulus layer)
   0 ─ ─ Cu ─ Cumulus ─ ─ ─ ─ ─ ─ ─│
```

_AuraLite smoothly transitions these layers based on in-game weather conditions (clearing, rain, or storms)._

***

## ⚙️ Performance Optimizations (OpenGL 4.6 Native)

AuraLite is built from the ground up for maximum FPS using OpenGL 4.6 native hardware operations:

*   **Multiply-Add Friendly Math:** Wave and waving-foliage math is written as simple multiply-add expressions so modern drivers can optimize it efficiently, while avoiding the explicit `fma()` intrinsic that caused compilation issues on some GPUs / Mesa drivers.
*   **Per-frame work moved off the pixel** _(v1.2.0)_: the cloud shadow that gates the godrays is screen-independent, so it is evaluated once per quad vertex instead of once per pixel — 4 evaluations per frame replace ~2 million, and `tools/gen_composite_vsh.py` keeps the copied field code in sync with `composite.fsh`.
*   **Fixed-cost integration** _(v1.2.0)_: the godray march uses a constant tap count and a bounded path, so frame time and image do not change when the sun crosses a threshold; rays terminate early once transmittance falls below 2 %.
*   **Scheduled passes:** `composite1`–`composite7` are gated by their master switches (`TAA`, `BLOOM`), so profiles that do not want the resolve or the bloom chain do not pay for the dispatch at all.
*   **Ordered dither instead of hashes** _(v1.2.0)_: a 4×4 Bayer matrix replaces two `fract(sin(...))` hashes per pixel — no transcendental functions, and a pattern that does not crawl between frames.
*   **Profile-Based Scaling:** Every feature (POM, Auroras, SSAO, Cozy Lights, Wet Reflections, Ground Mist, Shadow Distance, Cloud Distance, Sun Halo, etc.) is intelligently distributed across the **VERY_LOW / LOW / MED / HIGH / ULTRA / EXTREME** profiles so low-end systems don't pay for effects they can't afford.
*   **No Hand Transparency Glitches:** Handheld items, particles, and mobs are rendered in a separate stable path without tangent matrix overhead, eliminating "translucent hand" bugs.
*   **Dead Code Elimination** _(v0.2.3–v0.2.5)_: Removed unused noise/fbm functions, dead cloud raymarching code from `gbuffers_skybasic`, and redundant render calls to reduce GPU compilation time.
*   **Profile-Based Scaling:** Every feature (POM, Auroras, SSAO, Cozy Lights, Wet Reflections, Ground Mist, Shadow Distance, Cloud Distance, Sun Halo, etc.) is intelligently distributed across the **LOW / MED / HIGH / ULTRA / EXTREME** profiles so low-end systems don't pay for effects they can't afford.

***

## 🎛️ In-Game Configuration Options

AuraLite includes localized in-game configuration files for **69 language codes**, including major European, Asian, American regional variants and compatibility aliases such as `fil_ph` / `tl_ph`.

> ⚠️ _Some localization strings may be inaccurate. If something looks strange, compare with the English original._

### `[Lighting Settings]`

*   **Dynamic Shadows** — Toggle sun/moon shadows.
*   **Shadow Resolution** — `512 / 1024 / 2048 / 4096 / 8192` — real Iris `shadowMapResolution` const (8192 for EXTREME).
*   **Shadow Softness** _(v0.2.2)_ — `Sharp / Soft / Ultra Soft` — rotated Poisson disk filtering.
*   **Shadow Distance** _(v0.2.2, extended in v1.1.2, rebalanced in v1.1.4)_ — `Near (60m) / Standard (80-120m) / DH Seam (192m) / Far (256m) / DH Extended (512m) / DH Far (768m)` — fades with `SHADOW_LOD`; 192/512/768 m give Distant Horizons a useful shadow-map footprint.
*   **Shadow LOD** _(v1.1.2)_ — `Off / Balanced / Aggressive` — reduces samples (32→16→8→4) and expands filter radius at distance.
*   🆕 **Distant Horizons Shadow Range (`DH_SHADOW_RANGE`)** _(v1.1.4)_ — `Seam (1.25×) / Extended (2×) / Far (4×)` of vanilla `far`. No effect without Distant Horizons. The DH-specific shadow _pass_ is **off by default** (`dhShadow.enabled=false`) to protect vanilla terrain shadows on Iris 1.7.6 + DH 3.2.
*   **Shadow PCSS Blur** _(v1.1.2)_ — `Disabled (fixed softness) / Enabled (distance/rain-based penumbra)`.
*   **Shadow Tint** _(v0.2.2)_ — `Neutral Gray / Cool Blue (Realistic) / Warm`.
*   **Shadow Lift / Ambient** _(v0.2.2)_ — `Dark / Standard / Lifted (Bright)`.
*   **Light Wrap (Terminator)** _(v0.2.2)_ — `Realistic (Lambert) / Soft / Stylized`.
*   **Torch Warmth** — `Cozy / Warm / Intense` — Customize block light warmth.
*   **Torch Flickering (`COZY_LIGHTS`)** — Real-time flicker animations for torches, campfires, and lanterns.
*   **PBR Lighting** — Toggle PBR specular reflections and normal mapping.
*   **3D Block Relief (POM)** — Enable Parallax Occlusion Mapping for true 3D block textures (LabPBR resource pack required).
*   **PBR Intensity** — `Subtle / Standard / Mirror`
*   🆕 **SSAO / SAO Occlusion** _(v0.2.5)_ — Screen-space ambient occlusion for contact shadows in corners, under blocks, and around geometry intersections.
*   🆕 **SSAO Strength** _(v0.2.5)_ — `Subtle / Balanced / Deep`.
*   🆕 **Screen-Space Reflections (`SSR`)** _(v0.2.9)_ — loader-agnostic screen-space reflections for water and wet glossy surfaces.
*   🆕 **SSR Quality** _(v0.2.9)_ — `Fast / Balanced / High` raymarch step budget.
*   🆕 **SSR Strength** _(v0.2.9)_ — `Soft / Balanced / Mirror` reflection intensity.
*   🆕 **PBR Render Distance (`PBR_DISTANCE`)** _(v1.0.3)_ — `Near (16m) / Standard (48m) / Far (128m) / Unlimited` — maximum distance for PBR specular calculations. Saves GPU on far terrain.

### `[Sun & Moon]` _(since v0.2.2)_

*   **Sun Intensity** — `Dim / Standard / Bright / Blazing`
*   **Sun Colour Temperature** — `Cool / Neutral · Realistic (Tanner Helland) · Warm Golden`
*   **Sun Halo (Mie Scatter)** — toggle the warm forward-scatter glow when looking near the sun.
*   **Enhanced Sunrise/Sunset Glow** — toggle stronger warm back-scatter at low sun angles.
*   **Moon Intensity** — `Pitch Night / Standard / Bright Moon / Full Night`
*   **Moon Colour Temperature** — `Icy Blue / Silver (Realistic 4100K) / Warm Cream`

### `[Foliage Settings]`

*   **Waving Leaves** — Toggle leaves animation.
*   **Waving Foliage** — Toggle grass, flowers, and crops animation.
*   **Wind Speed** — `Gentle / Breeze / Gale`
*   🆕 **Foliage SSS (`FOLIAGE_SSS`)** _(v1.0.3)_ — Subsurface scattering / translucency for leaves and plants (light bleeding when looking toward the sun).

### `[Water Settings]`

*   **Water Waves** — Toggle 3D vertex water waves.
*   **Water Density** — `Clear / Balanced / Deep` — Adjust water transparency.
*   **Water Ripple Strength (`WATER_RIFFLES`)** — `Calm / Standard / Choppy` — Fine normal-map ripples.
*   **Water Specular Glow (`WATER_SPECULAR_STRENGTH`)** — `Soft / Standard / Glinting` — Brightness of sun/moon highlights on the ripples.
*   🆕 **Water Wave Scale (`WATER_WAVE_SCALE`)** _(v0.2.9, spectrum rebuilt in v1.1.4)_ — `Calm / Standard / Choppy / Stormy` — Gerstner swell amplitude used by SSR/refraction.
*   🆕 **Water Wave Detail (`WATER_WAVE_DETAIL`)** _(v0.2.9, spectrum rebuilt in v1.1.4)_ — `Coarse / Standard / Dense` — Gerstner wavelength/capillary density.
*   🆕 **Underwater Night Darkness** _(v0.2.9)_ — `Moonlit Pool / Dim / True Night / Pitch Dark` — controls how dark underwater scenes become at night.
*   🆕 **Water Diagnostics (`WATER_DEBUG`)** _(v1.1.3)_ — developer overlay (Off / Classify / Lightmap / Raw tag alpha) for diagnosing water classification on Iris builds that drop translucent MRT writes. Keep **Off** in normal play.

### `[Sky & Clouds]`

*   **Procedural Clouds** — Toggle raymarched clouds.
*   🆕 **Cloud Renderer (`CLOUD_MODE`)** _(v1.2.0)_ — `Layered sheets (v1.1.4) / Volumetric` — the legacy cheap path is still there for weak hardware.
*   🆕 **Cloud Coverage (`CLOUD_COVERAGE`)** _(v1.2.0)_ — `Clear / Scattered / Broken / Broken to overcast / Overcast` — cloud fraction, not brightness.
*   🆕 **Cloud Density (`CLOUD_DENSITY`)** _(v1.2.0)_ — `Thin (0.075 g/m³) / Typical (0.15) / Dense (0.30)` — liquid water content of the medium.
*   🆕 **Cloud Microphysics (`CLOUD_MICRO`)** _(v1.2.0)_ — `Continental (6 µm, g 0.82) / Typical (8 µm, g 0.85) / Maritime (12 µm, g 0.87)` — droplet spectrum, which sets how much a cloud scatters forward.
*   🆕 **Cloud Scale (`CLOUD_SCALE`)** _(v1.2.0)_ — `Compact 1.2× / Typical 1.8× / Broad 3.0×` — cell width as a multiple of the deck depth.
*   🆕 **Cirrus Veil (`CLOUD_CIRRUS`)** _(v1.2.0)_ — high ice deck at 6.5–11.2 km with its own extinction.
*   🆕 **Mid-Level Deck (`CLOUD_MID_LAYER`)** _(v1.2.0)_ — an independent altocumulus layer.
*   🆕 **Cloud Base Variation (`CLOUD_BASE_VARIATION`)** _(v1.2.0)_ — `Even ±40 m / Natural ±120 m / Ragged ±250 m` — how much the condensation level differs from cloud to cloud.
*   🆕 **Cloud Updraft (`CLOUD_UPDRAFT`)** _(v1.2.0)_ — `Drifting 1.5 m/s / Natural 2.5 / Vigorous 4.0` — vertical development; storms multiply it.
*   **Cloud Altitude (`CLOUD_HEIGHT`)** _(v0.2.3, physical in v1.2.0)_ — `400 m / 1200 m / 2400 m / 3600 m`
*   **Cloud Thickness (`CLOUD_THICKNESS`)** _(v0.2.3, physical in v1.2.0)_ — `0.5× / 1.0× / 1.5×` of the base altitude
*   **Cloud Render Distance** _(v0.2.5, extended in v1.2.0)_ — `Near 6 km / Standard 12 km / Far 20 km / Very Far 32 km`
*   🆕 **Cloud Raymarch Quality (`CLOUD_QUALITY`)** _(v1.1.3, rescaled in v1.2.0)_ — `Cheap (14 steps) / Standard (24) / High (36) / Extreme (56)` — resolution of the march.
*   🆕 **Cloud Shape Detail (`CLOUD_DETAIL`)** _(v1.2.0)_ — `2 / 3 / 4 / 5 octaves` (1080 → 135 m features) — independent of the step count above.
*   🆕 **Cloud Shadows** _(v0.2.7)_ — transparent procedural shadows from cloud density.
*   🆕 **Cloud Shadow Strength** _(v0.2.7)_ — `Soft / Balanced / Dramatic`.
*   🆕 **Godrays / Sun Shafts** _(v0.2.7)_ — physically-inspired volumetric single-scattering light shafts.
*   🆕 **Godrays Quality** _(v0.2.7)_ — `Fast / Balanced / High`.
*   **Aurora Borealis** — `Disabled / Only in Cold Biomes / Always Enabled`
*   **Aurora Speed** — `Slow / Standard / Fast`
*   **Aurora Brightness** — `Soft / Standard / Glowing`
*   **Milky Way Brightness** — `Dim / Standard / Bright`
*   **Stars Brightness** — `Faint / Standard / Brilliant`
*   **Stars Density** — `Few / Standard / Dense`
*   🆕 **Meteors (Falling Stars)** _(v1.0.0)_ — Physically-based meteor streaks across the night sky.
*   🆕 **Meteor Activity (ZHR)** _(v1.0.0)_ — `Sporadic (~10/hr) / Active Shower / Meteor Storm`.
*   🆕 **Meteor Brightness** _(v1.0.0)_ — `Faint (Realistic) / Standard / Bright Fireballs`.
*   **Rainbow Intensity** — `Subtle / Balanced / Vivid` — Post-rain rainbow arc.

### `[Post-Processing & Fog]`

*   **Fog Density** — `Low / Medium / High` — Atmospheric horizon mist.
*   **Low Ground Mist (`GROUND_MIST`)** — Realistic dawn/evening radiation fog at Y ≈ 60–70.
*   🆕 **Ground Mist Density (`GROUND_MIST_DENSITY`)** _(v1.2.0)_ — `Light / Standard / Heavy`.
*   🎨 **`[Colour Grading]` tab** _(v1.2.0)_ — three short screens (`Tone`, `Channels`, `Look`) exposing **twelve continuous sliders** instead of three-stop buttons:
    *   **Tone** — `COLOR_EXPOSURE`, `COLOR_BRIGHTNESS`, `COLOR_CONTRAST`, `COLOR_SATURATION`, `COLOR_GAMMA`, `COLOR_TONEMAP` (_ACES / ACES soft / ACES punchy / Photographic (AgX-like)_).
    *   **Channels** — `COLOR_RED` / `COLOR_GREEN` / `COLOR_BLUE` gain (colour-coded labels), `COLOR_LUMA_PROTECT`, `COLOR_WARMTH`, `COLOR_TINT`.
    *   **Look** — `COLOR_VIBRANCE` (selective saturation), `COLOR_VIGNETTE` (strength) and the `VIGNETTE` master switch.
*   💡 **Dither Strength (`DITHER_STRENGTH`)** _(v1.2.0)_ — `Off / Light / Medium / v1.1.4` — the fixed ordered pattern that kills 8-bit banding in the darks.
*   🆕 **HDR Bloom (`BLOOM` / `HDR_BLOOM`)** _(v1.0.1, pyramid in v1.1.3, half-res + skippable in v1.1.4)_ — gaussian-pyramid bloom (`composite3`–`7`): threshold brightpass + tight & wide separable gaussian octaves. v1.1.4 runs the chain at **half resolution**(v1.0.1, pyramid in v1.1.3, half-res + skippable in v1.1.4)\_ — gaussian-pyramid bloom (`composite3`–`7`): threshold brightpass + tight & wide separable gaussian octaves. v1.1.4 runs the chain at **half resolution** and skips the five passes entirely when Bloom is off (VERY\_LOW/LOW). Strength: `Subtle / Balanced / Strong`.
*   🆕 **Temporal Anti-Aliasing (`TAA`)** _(v0.2.7, completed in v1.1.3, DH/sky/reactive in v1.1.4)_ — Halton sub-pixel camera jitter + motion reprojection + YCoCg variance clipping. **On by default in HIGH/ULTRA/EXTREME** since v1.1.3, off on lighter profiles. v1.1.4 adds DH-correct reprojection, a material reactive mask (water/foliage/emissive) and optional sky temporal resolve.
*   🆕 **TAA Strength** _(v0.2.7)_ — `Light / Balanced / Stable` — presets the variance-clip tightness (1.50 / 1.25 / 1.10 γ).
*   🆕 **TAA Camera Jitter (`TAA_JITTER`)** _(v1.1.3)_ — `Off / Subtle / Standard / Strong` — sub-pixel Halton camera jitter amplitude (±0.25 / ±0.5 / ±0.75 px) for full sub-pixel reconstruction. **Off by default** for a steady image; enable it to eliminate high-frequency shimmer. Requires TAA.
*   🆕 **Post-Sharpen (`POST_SHARPEN`)** _(v1.1.3)_ — gentle unsharp mask that recovers texture detail softened by TAA history blending (on in MED+ profiles).
*   🆕 **Spatial Anti-Aliasing (`SPATIAL_AA_MODE`)** _(v1.0.3)_ — `Off / FXAA / SMAA` — post-process edge smoothing. FXAA uses Sobel gradient-directed blending; SMAA adds depth discontinuity detection for geometry edges. Freely combinable with TAA.
*   **Vignette** — Toggle cinematic corner darkening.
*   (Hidden) **Rain Wetness Reflections (`WET_REFLECTIONS`)** — Wet glossy ground during rain (enabled by default in MED+ profiles).

### `[Experimental]` _(since v1.1.0, expanded in v1.1.4)_

*   **Sky Mode (`SKY_MODE`)** — `Gradient (Legacy) / Physical (Realtime)`. Off in every shipped profile.
*   **Sky Style (`SKY_STYLE`)** — `Realistic / Semi-realistic / Fantasy`.
*   **Sky Quality (`SKY_QUALITY`)** — `Fast / Standard / High` primary raymarch samples.
*   🆕 **Atmospheric Turbidity** _(v1.1.4)_ — `Crisp / Balanced / Hazy`.
*   🆕 **Atmosphere Scale** _(v1.1.4)_ — `Compact (25 m/block) / Balanced (50 m) / Cinematic (100 m)`.
*   🆕 **Ground Bounce Albedo** _(v1.1.4)_ — `Auto / Neutral Soil / Vegetation / Snow / Desert`.
*   🆕 **Sky Temporal Resolve (`SKY_TEMPORAL`)** _(v1.1.4)_ — rotation-only TAA for the sky (on in HIGH+). Requires TAA.

### 🎚️ Quality Profiles _(rebalanced in v1.2.0 — shadows 60–768 m with LOD + DH range; TAA on in HIGH+ and now actually compiled, camera jitter off by default everywhere)_

| Profile  |Target       |Shadows              |Clouds                  |Cloud Shadows |Godrays |TAA |SSR |PBR |PBR Dist |AA   |SSAO       |Heat Shimmer |Heavy Extras                          |
| -------- |------------ |-------------------- |----------------------- |------------- |------- |--- |--- |--- |-------- |---- |---------- |------------ |------------------------------------- |
| <strong>VERY_LOW</strong> |Maximum FPS  |❌ 512/60m            |❌                       |❌             |❌       |❌   |❌   |❌   |16m      |Off  |❌          |❌            |Most extras off, bloom off            |
| <strong>LOW</strong> |Weak GPUs    |❌ 512/60m            |❌                       |❌             |❌       |❌   |❌   |❌   |16m      |FXAA |❌          |❌            |Water/foliage motion, stars, vignette |
| <strong>MED</strong> |Balanced     |✅ 1024/<strong>192m</strong> |✅ 24 steps / 3 oct      |✅ Soft        |✅ Fast  |❌   |✅ F |✅   |48m      |FXAA |❌          |✅ Subtle     |Wet refl + ground mist + SSS + bloom  |
| <strong>HIGH</strong> |High quality |✅ 2048/<strong>512m</strong> |✅ 36 steps / 3 oct      |✅ Balanced    |✅ Bal   |✅   |✅ B |✅   |128m     |SMAA |✅ Subtle   |✅ Balanced   |Full atmosphere + SSR + TAA           |
| <strong>ULTRA</strong> |Very high    |✅ 4096/<strong>512m</strong> Aggr LOD |✅ 36 steps / 3 oct      |✅ Balanced    |✅ High  |✅   |✅ H |✅   |128m     |SMAA |✅ Balanced |✅ Balanced   |High-end visuals + TAA                |
| <strong>EXTREME</strong> |Max quality  |✅ 8192/<strong>768m</strong> Aggr LOD |✅ 56 steps / 4 oct      |✅ Dramatic    |✅ High  |✅   |✅ H |✅   |∞        |SMAA |✅ Deep     |✅ Strong     |Heaviest cinematic + TAA              |

> 💫 **Shooting stars** are disabled on **VERY\_LOW / LOW** and enabled from **MED** upward. 🌿 **Foliage SSS** is enabled from **MED** upward. 🔥 **Heat shimmer** is disabled on **VERY\_LOW / LOW** and enabled from **MED** upward. ✨ **HDR bloom** is skipped entirely on **VERY\_LOW / LOW**. 🎯 **TAA** is on in **HIGH / ULTRA / EXTREME** and is now a real compiled option — in v1.1.x the menu could switch the resolve pass while the shader still compiled its passthrough. The **camera jitter is off by default everywhere** — enable `TAA_JITTER` (Off/Subtle/Standard/Strong) for full sub-pixel reconstruction; `TAA_STRENGTH` presets the variance-clip tightness. **`SKY_TEMPORAL`** is on in HIGH+. 🗺️ **Distant Horizons:** experimental, **partial** DH support — the seam is a hard deterministic hand-off at `far`, DH pixels get TAA jitter/reprojection and a dedicated illuminated material tag (`0.24`), and `DH_SHADOW_RANGE` keeps LOD receivers sampling the shared shadow map. The DH-specific shadow pass is **off by default** on Iris 1.7.6 + DH 3.2. Still WIP, not full compatibility.

***

## 🧾 Release Engineering (v1.2.0)

*   **Sources are the release.** `tools/gen_composite_vsh.py` regenerates `composite.vsh` from `composite.fsh` (`--check` fails CI when it is stale), `tools/check_scope.py` verifies that every identifier read inside a function is declared somewhere visible, and `tools/strip_diag.py` is the cleaner that removed the diagnostic layer — kept so the same pass can be re-run on a future branch.
*   **No instruments in the shipped pack.** A full text scan of all 54 shader files finds no diagnostic switches, no on-screen gauges, no debug class maps and no bypass toggles. What remains next to the real code is documentation.
*   **Options, menu and profiles agree.** Every option that a profile sets is `#define`d in a shader, every `#define`d option has a menu row and a localization string, and the two options that used to be commented-out (`TAA`, `PBR_POM`) are now real.
*   **`RELEASE_NOTES.md`** ships inside the shader folder with the file-by-file account for people who want the details rather than the summary.

***

## 📄 License & Compatibility

*   **AuraLite** is licensed under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License](LICENSE) (CC BY-NC-SA 4.0).
*   **Copyright (c) 2026 AlexanderNyr.**
*   **Officially Supported Platform:** Minecraft **1.16.5 – 26.2** with **Sodium + Iris** or **OptiFine** loader.
*   _Note: Verified to work flawlessly on Minecraft 1.16.5, 1.20.1, 1.21.1, and 26.1.2._
*   **Distant Horizons:** v1.2.0 continues **experimental, partial** DH support (WIP, introduced in v1.1.2) — `dh_terrain`, `dh_water`, `dh_shadow` minimal passes so Iris keeps drawing LOD chunks, with a **hard deterministic seam** at `far` (v1.1.4 replaced the v1.1.3 screen-door dither, which punched white holes on DH 3.2). Provides fog rescaling, depth reconciliation, overdraw culling, emissive/heat-shimmer for distant lava, DH-aware TAA jitter and reprojection, and the `DH_BLOCK_ILLUMINATED` tag. Still **NOT** full support: no LabPBR maps for DH, hardcoded full skylight, flat water normal, no POM — full compatibility will be announced separately when ready.

### ⚖️ Rules & Permissions (FAQ)

*   **Videos & Streams:** You are free to showcase, stream, and use this shader in your videos (including monetized channels on YouTube, Twitch, etc.).
*   **Modpacks:** You are free to include this shader in your free modpacks on CurseForge, Modrinth, or other platforms.
*   **Personal Tweaks:** You can modify the shader code for personal use.
*   **No Re-hosting:** Do not upload the raw shader files to third-party sites (especially behind ad links like AdFly). Always use and link to our official, authorized sources below.
*   **Derivative Works:** If you modify this shader and distribute it, your version **must** be free, open-source, and licensed under the exact same **CC BY-NC-SA 4.0** license with clear attribution to the original author.

#### 🌐 Official & Authorized Sources:

*   **GitHub:** [https://github.com/AlexanderNyr/AuraLite-Shaders](https://github.com/AlexanderNyr/AuraLite-Shaders)
*   **Modrinth:** [https://modrinth.com/shader/auralite-shaders](https://modrinth.com/shader/auralite-shaders)
*   **CurseForge:** [https://www.curseforge.com/minecraft/shaders/auralite-shaders](https://www.curseforge.com/minecraft/shaders/auralite-shaders)