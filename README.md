# 🌌 AuraLite Shaders (Minecraft 1.16.5 – 26.1.2)

![Minecraft Version](https://img.shields.io/badge/Minecraft-1.16.5%20--%2026.1.2-blue?logo=minecraft&logoColor=white)
[![Shader Loader](https://img.shields.io/badge/Loader-Iris%20%2F%20Sodium-green)](https://modrinth.com/mod/iris)
[![API Standard](https://img.shields.io/badge/API-OpenGL%204.6%20%2F%20GLSL%20460-orange)](https://khronos.org/)
[![Materials Standard](https://img.shields.io/badge/PBR-LabPBR%201.3-cyan)](https://github.com/rre36/lab-pbr)
[![Version](https://img.shields.io/badge/Release-v1.0.5-purple)](https://github.com/AlexanderNyr/AuraLite-Shaders)
[![License](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/)


**AuraLite** is a modern, lightweight, and highly optimized shader pack built on top of the **OpenGL 4.6 / GLSL 460** standard. It is specifically designed and **tested for Minecraft 1.16.5 – 26.1.2 with Sodium + Iris** (and compatible with **OptiFine**, **Oculus**).

AuraLite delivers a breathtaking, realistic visual experience without overcomplicating the screen with bloated post-processing effects (such as aggressive motion blur or heavy bloom). A lightweight HDR bloom was added in v1.0.1 to softly glow emissive sources without smearing the scene. Optional FXAA/SMAA anti-aliasing, SSR, TAA, godrays, and SSAO are profile-scaled so AuraLite keeps **high FPS and smooth frametimes** on modern GPUs.

---

> ℹ️ **Historical note:** older changelog sections below are preserved as original release notes.

## 🆕 What's New in v1.0.5 — *Expanded Localization*

Version **1.0.5** is a localization-focused release that adds **10 new in-game languages**, bringing the total to **69 supported locales**. No shader logic, profile defaults, or rendering behavior was changed — this is a pure translation / metadata update on top of **v1.0.4**.

### 🌐 New Languages

The following fully-translated `.lang` files were added (every option name, value label, profile name and tooltip — 289 keys each, 100% key parity with the English source):

| Code | Language | Code | Language |
|---|---|---|---|
| `gl_es` | Galician | `sw_ke` | Swahili |
| `ga_ie` | Irish | `nn_no` | Norwegian Nynorsk |
| `gd_gb` | Scottish Gaelic | `tt_ru` | Tatar |
| `af_za` | Afrikaans | `hy_am` | Armenian |
| `az_az` | Azerbaijani | `zh_hk` | Cantonese (Hong Kong) |

* As with all non-English locales, the in-game **⚠ Translations may contain errors** notice applies — some strings in rarer languages may be imperfect; compare with the English original if anything looks off.
* No shader logic, profile defaults, or rendering behavior changed in this release — **v1.0.5** is purely a localization / metadata refresh on top of **v1.0.4**.
* `README.md`, installation references, and source-folder notes updated to **v1.0.5**.
* `shaders.properties` and `block.properties` metadata headers updated to **v1.0.5**.
* Source-folder snapshots now run through `shaders v1.0.5/`.

---

## 🆕 What's New in v1.0.4 — *Profile Rebalance, Translucent Blocks & Glass Rendering*

Version **1.0.4** delivers a full quality-profile rebalance for smoother progression, introduces proper translucent block rendering for ice and glass, adds a dedicated Iris/Oculus translucent terrain pass, and fixes a cross-vendor GLSL compatibility issue.

### 🔄 Full Profile Rebalance

All six quality profiles (VERY_LOW → EXTREME) have been rebalanced for a smoother, more logical feature progression:

| Profile | Key Changes in v1.0.4 |
|---|---|
| **VERY_LOW** | Sun intensity lowered to *Dim* (1), underwater night set to *Moonlit Pool* for visibility. |
| **LOW** | Ambient brightness lowered, cozy lights disabled, Filmic tone mapping (ACES), underwater night set to *Dim*. Stars upgraded to *Standard*. |
| **MED** | Godrays now **enabled** (Fast quality) — this was the biggest missing piece in the sweet-spot preset. PBR strength raised to *Standard*. Meteor frequency normalized. |
| **HIGH** | SSAO now **enabled** (Subtle) — contact shadows appear at this tier. Godrays bumped to *Balanced*. Moon intensity lowered to *Standard*. |
| **ULTRA** | Godrays raised to *High*. TAA strength at *Balanced*. |
| **EXTREME** | Water wave scale pushed to *Stormy*. Underwater night set to *Pitch Dark* for maximum survival realism. Photographic (AgX) tone mapping. |

### 🧊 Split Ice & Glass Block Rendering

* **Regular ice** (`minecraft:ice`, block ID 10005) now renders with its actual texture and semi-transparency instead of being fully opaque. Transparency scales with the `WATER_TRANSPARENCY` setting (Clear / Balanced / Deep).
* **Packed ice, blue ice, and frosted ice** (block ID 10007) are now rendered **opaque with texture** — distinct from regular ice so the visual difference is clear.
* **All glass blocks and panes** (block ID 10008), including every stained-glass variant and tinted glass, now render with their actual texture and proper transparency. Glass opacity scales with `WATER_TRANSPARENCY`. This eliminates the old "invisible glass" problem where glass blocks disappeared against bright skies.
* Both ice types and glass are handled by the new `gbuffers_terrain_translucent` pass, ensuring correct rendering on Iris/Oculus split-translucent pipelines.

### 🪟 New Translucent Terrain Pass (`gbuffers_terrain_translucent`)

* A new **`gbuffers_terrain_translucent.fsh` / `.vsh`** shader pair was added. This pass handles water, ice, glass, and nether-portal blocks in a single Iris/Oculus-compatible translucent terrain path.
* Mirrors the existing `gbuffers_water.fsh` logic so translucent blocks render identically regardless of whether the loader uses a unified or split translucent G-buffer path.
* Nether portal plasma, ice Fresnel, glass opacity, and water Fresnel/ripples all route through this pass.

### 🛠️ GLSL Compatibility Fix

* **Replaced all `fma()` calls with direct multiply-add expressions** across every shader file. The `fma()` intrinsic, while correct on most modern GPUs, caused compilation failures on certain drivers (particularly older Intel iGPUs and some Mesa versions). The replacement `a * b + c` expressions are mathematically equivalent and compile universally.

### 🧭 Project metadata refresh

* README and installation references now point to **v1.0.4**.
* Source-folder notes now correctly describe the repository as containing snapshots through `shaders v1.0.4/`.
* All profile definitions and settings menus updated.

---

## 🆕 What's New in v1.0.3 — *Anti-Aliasing & PBR Performance*

Version **1.0.3** adds configurable spatial anti-aliasing (FXAA / SMAA) and a PBR render distance control that skips expensive Cook-Torrance specular calculations on distant terrain.

### 🖼️ Spatial Anti-Aliasing (FXAA / SMAA)

* **`SPATIAL_AA_MODE`** — new toggle in the `[Post-Processing]` menu with 3 modes:
  * **Off** — no spatial AA (TAA-only or nothing).
  * **FXAA** — Fast Approximate AA. Sobel gradient-directed edge detection with conservative blend weights. Cheap and effective.
  * **SMAA** — Subpixel Morphological AA. Combines luminance Sobel gradient with depth discontinuity detection for superior edge detection on geometry where luma contrast is low. Slightly more expensive than FXAA.
* Both modes operate in linear space before tone mapping and are conservative enough to avoid washing out the image (max blend weight 0.15–0.18, high edge thresholds).
* Freely combinable with TAA (composite1 pass) for temporal + spatial smoothing.
* Added to all 6 quality profiles: VERY_LOW=Off, LOW/MED=FXAA, HIGH/ULTRA/EXTREME=SMAA.

### ⚡ PBR Render Distance

* **`PBR_DISTANCE`** — new setting in the `[Lighting Settings]` menu with 4 levels:
  * **Near (16m)** — PBR specular only on very close surfaces. Maximum GPU savings.
  * **Standard (48m)** — balanced distance. Default for LOW/MED profiles.
  * **Far (128m)** — extended range. Default for HIGH/ULTRA profiles.
  * **Unlimited** — no distance limit. EXTREME profile only.
* Beyond the fade range, the entire Cook-Torrance BRDF block (GGX distribution, Smith geometry, Fresnel-Schlick) is **completely skipped** via early-out — no wasted ALU on sub-pixel specular.
* Fade is smooth (`smoothstep` between start and end distance) to avoid visible pop-in.

### 🌐 Localization

* Full English and Russian localization for both new settings (option names + value labels).
* Other language files fall back to English labels.

---

### 🌿 Foliage Subsurface Scattering (also finalized in v1.0.3)

* **`FOLIAGE_SSS`** — toggle in the `[Foliage Settings]` menu. Enables light bleeding through leaves and plants when looking toward the sun, plus a soft wrap term for the shaded side. Controlled per-profile (enabled from MED upward by default). Uses material ID tagging in `gbuffers_terrain` and a dedicated SSS pass in `composite.fsh`.
* Added to all quality profiles (VERY_LOW → EXTREME) with the `!FOLIAGE_SSS` or `FOLIAGE_SSS` flag.
* Full English + Russian localization strings added.

older changelog sections below are preserved as original release notes.

Version **1.0.2** adds realistic subsurface scattering for vegetation, making leaves, grass, and plants look more translucent and lifelike when light shines through them. This is a focused visual enhancement that integrates cleanly with the existing PBR and lighting pipeline.

### 🌿 New Feature
* **Foliage Subsurface Scattering (`FOLIAGE_SSS`)** — New toggle in the `[Foliage Settings]` menu. When enabled, foliage receives additional lighting from the back (light bleeding) and a soft wrap term for the unlit side. Controlled per-profile (enabled from MED upward by default). Uses material ID tagging in `gbuffers_terrain` and a dedicated SSS pass in `composite.fsh`.
* Added to all quality profiles (VERY_LOW → EXTREME) with the `!FOLIAGE_SSS` or `FOLIAGE_SSS` flag.
* Full English + Russian localization strings added.

### 🧭 Project metadata refresh
* README and installation references now point to **v1.0.3**.
* Source-folder notes now correctly describe the repository as containing snapshots through `shaders v1.0.3/`.
* Minor synchronization of `shaders.properties` (FOLIAGE_SSS screen entry and profile definitions).

--- older changelog sections below are preserved as original release notes.

## 🆕 What's New in v1.0.1 — *Stability, HDR Bloom & Photographic Tone Mapping*

Version **1.0.1** is a focused hotfix on top of v1.0.0 that addresses five edge-case rendering issues and introduces a new cinematic tone-mapping curve with lightweight HDR bloom.

### 🛠️ Bug Fixes

* **TAA history acceptance threshold.** Added `historySample.a < 0.99` guard in `composite1.fsh` so uninitialised or stale history buffers (e.g. right after shader reload or resolution change) are rejected instead of causing ghosting.
* **Vibrancy math.** `applyVibrancy` in `final.fsh` now correctly handles negative saturation values — oversaturation works as intended rather than relying on undefined GLSL `mix` extrapolation followed by hard clamping.
* **SSR normal NaN guard.** Added `length(N) > 0.5` check before `traceSSR()` so invalid normals from edge pixels are silently skipped instead of producing black reflections.
* **SSR near-field trace precision.** Minimum raymarch step lowered from `1.0` to `0.3` view-space units, dramatically improving hit rate on close surfaces (ripples, shallow pools, wet stone).
* **Meteor moon-brightness curve.** `gbuffers_skybasic.fsh` now uses `cos²(phase × π/8)` — identical to `getMoonPhaseBrightness()` in `composite.fsh` — so moon washout is physically consistent.

### 🎨 Visual Enhancements

* **HDR Bloom *(v1.0.1)*.** Cheap single-pass 3×3 neighbour blur for overbright pixels (luminance threshold 0.75). Naturally affects sun/moon disks, lava, portals, bright specular highlights, and torches — without smearing the entire scene or requiring extra render targets.
* **Photographic (AgX-like) Tone Mapping *(v1.0.1)*.** A new `CONTRAST = 4` option in `final.fsh` provides a sigmoidal tone curve with natural highlight chromatic attenuation, soft toe, and lifted blacks — giving a cinematic, non-clipped look that keeps foliage saturation under control while handling extreme brightness gracefully.
* **EXTREME profile updated.** Now uses `CONTRAST=4` (Photographic/AgX-like) instead of `CONTRAST=3` for cinematic highlight handling.

### 🧭 Project metadata refresh

* README and installation references now point to **v1.0.1**.
* Source-folder notes now correctly describe the repository as containing snapshots through `shaders v1.0.1/`. (Historical for that release)

--- older changelog sections below are preserved as original release notes.

## 🆕 What's New in v1.0.0 — *Meteor Showers & Finalized Reflection Pipeline*

Version **1.0.0** builds on the volumetric aurora work from v0.3.0 and introduces the first **v1.0.0** source snapshot in this repository. The update adds a physically-inspired meteor system to the night sky, finalizes the modern SSR path for reliable Iris compatibility, and refreshes the documentation so the project now correctly points to the `shaders v1.0.0/` folder.

### ☄️ Physically-Based Meteors / Falling Stars

* **True great-circle sky arcs.** Meteors are rendered as moving arcs on the celestial sphere instead of flat 2D streaks, so showers converge toward a shared radiant like real meteor photography.
* **Ablation-based brightness curve.** Each meteor rises, peaks, and fades with a bell-shaped light curve inspired by atmospheric entry.
* **Blackbody plasma colouring.** Meteor heads are tinted with the same Kelvin-based colour pipeline used by AuraLite's sun/moon lighting, giving physically consistent warm-to-white fireball tones.
* **Moonlight washout and weather attenuation.** Faint meteors are suppressed by bright moon phases, rain, and daytime sky brightness, improving realism and avoiding visual clutter in poor visibility.
* **Persistent trains on bright fireballs.** The strongest events leave a short-lived glowing ionization trail, including a subtle green oxygen-style tint on the lingering train.
* **Available in both Overworld and The End.** Overworld meteors respect moonlight and atmosphere; End meteors render against the permanent night sky without moon washout.

### 🪞 Finalized v1.0.0 SSR / Water Reflection Path

* **`colortex6` fully removed from the reflection workflow.** The older MRT export path was retired; `final.fsh` now reads normals directly from `colortex2` and roughness from `colortex1`, matching AuraLite's already-working PBR data path.
* **Depth-based water-surface detection.** Water is identified by comparing `depthtex0` and `depthtex1`, making reflections robust on Iris paths where water G-buffer writes may be inconsistent.
* **More stable water normals.** Reflection normals are reconstructed from neighbouring depth samples and then perturbed with coherent world-space ripple gradients, reducing faceting and torn reflections.
* **Cleaner post-pass reliability.** The reflection pipeline now lives entirely in the final post-processing pass, simplifying the frame graph and avoiding loader-specific MRT issues.

### 🎛️ New Sky Settings & Profile Integration

* New configurable options: **`SHOOTING_STARS`**, **`SHOOTING_STARS_FREQUENCY`**, and **`SHOOTING_STARS_BRIGHTNESS`**.
* Shooting stars are disabled on the lightest presets and enabled from **MED** upward through the normal profile system.
* English and Russian UI text was expanded for the new night-sky controls, while other language files continue to fall back safely.

### 🧭 Project metadata refresh

* README and installation references now point to **v1.0.0**.
* Source-folder notes now correctly describe the repository as containing snapshots through `shaders v1.0.0/`.
* The quality-profile and configuration sections below were refreshed for the current release, while older changelog entries remain intact for historical reference.

---

## 🆕 What's New in v0.3.0 — *Volumetric Aurora Realism Update*

Version **0.3.0** focuses on the night sky and replaces the older flat aurora overlay with a more photographic, volumetric aurora renderer. The rest of the rendering pipeline remains based on the stable v0.2.9 SSR/water foundation.

### 🌌 Realistic Volumetric Aurora Borealis

* **Raymarched aurora curtains.** Aurora rendering now samples a vertical volume above the horizon instead of drawing a simple 2D noise layer, giving the effect visible depth and height.
* **Distinct vertical pillars and rays.** Fine high-frequency striations create the characteristic upward beams seen in real aurora photography.
* **Sharper lower edge, softer upper fade.** The aurora now has a defined luminous base and gradually dissolves into the upper night sky.
* **More vivid photographic colours.** The palette was rebalanced toward saturated cyan-green, magenta/purple, and subtle deep-blue upper blending.
* **Better motion pacing.** Animation speed was reduced and smoothed so curtains drift naturally instead of sliding too quickly across the sky.
* **Preserved biome/weather logic.** Existing `AURORA_MODE`, cold-biome detection, rain attenuation, speed, and brightness settings continue to work.

### 🧭 Project metadata refresh

* README and installation references now point to **v0.3.0**.
* Source-folder notes now correctly describe the repository as containing snapshots through `shaders v0.3.0/`.

---

## 🆕 What's New in v0.2.9 — *Working SSR, Realistic Waves & True Night Underwater*

Version **0.2.9** is a focused water-quality update that finally delivers the long-requested **screen-space reflections** that work on every loader (including the tricky Iris 1.20+ pipeline), introduces **physically-coherent procedural waves** that don't tear reflections, and gives underwater scenes **true nocturnal darkness**.

### 🪞 Screen-Space Reflections (SSR) — Now Actually Working

* **Loader-agnostic SSR pipeline.** Previous SSR implementations relied on multi-render-target writes via `DRAWBUFFERS:06` + `layout(location = 1) out`. This combination silently failed on Iris 1.20 — the second attachment was never bound to the FBO, so reflection data was lost between the composite and final passes. v0.2.9 reads the surface normal directly from `colortex2` and roughness from `colortex1.z` (the same buffers PBR specular highlights already use), bypassing the broken MRT path entirely.

* **Bulletproof water detector.** Water surfaces are now identified by comparing `depthtex0` (depth *with* translucents) and `depthtex1` (depth *without* translucents). When they differ, the pixel is a water/glass/ice surface — no false positives on lapis lazuli, blue wool, packed ice, or terrain seen through water. Works regardless of whether `gbuffers_water` correctly writes its G-buffer attachments.

* **dFdx-stabilized normal reconstruction.** For pixels where `gbufferModelView` is identity in the final pass (a known Iris quirk), the water normal is rebuilt from depth-buffer derivatives using a 4-tap central-difference kernel. The result is the *true geometric normal* of the visible water surface, independent of any matrix uniforms.

* **Schlick-correct Fresnel.** Reflections now follow the physical F0 = 0.02 dielectric water curve: weak when looking straight down, near-mirror at grazing angles.

* **Adaptive view-space raymarcher with binary refinement.** Textbook real-time SSR: the reflected ray is marched in view space with a step length that scales with the current depth gap (long jumps in empty space, short jumps near the surface), then refined with 4–7 binary-search iterations once a crossing is detected. Distance-aware tolerance prevents Z-fighting on far samples. 14 / 24 / 40 march steps depending on `SSR_QUALITY`.

### 🌊 Coherent Procedural Wave System

* **4-octave fBm height-field** with C2-continuous quintic smoothing. Each octave is rotated ~33° to break grid alignment.
* **Analytic gradients** (4-sample central differences in world space) produce *coherent* wave slopes — reflections smoothly track wave geometry instead of jittering as random noise offsets did in earlier prototypes.
* New **`WATER_WAVE_SCALE`** menu setting: *Calm / Standard / Choppy / Stormy* — controls wave amplitude from mirror to broken horizon.
* New **`WATER_WAVE_DETAIL`** menu setting: *Coarse / Standard / Dense* — controls wave frequency from a few large swells to many fine ripples.

### 🌑 True Underwater Night Darkness

* The old underwater scattering formula had three baked-in brightness floors (`+0.25` on `dayFactor`, `+0.3` on `skyLight`, plus a constant deep-water blue tint), so even pitch-black midnight underwater looked like a moonlit pool. v0.2.9 rebuilds the formula to honour the actual day/night cycle.
* New **`UNDERWATER_NIGHT_DARKNESS`** menu setting:
  * **Moonlit Pool** — original 0.2.8 brightness (compat mode)
  * **Dim** — clearly night, still visible
  * **True Night** — realistic darkness (default)
  * **Pitch Dark** — extreme survival realism

### 🛠️ Smaller fixes

* Removed the unused `colortex6Out` MRT write from `composite.fsh` along with its `colortex6Format` declaration — fewer attachments, simpler pipeline, less to break.
* Centralized SSR/wave/underwater toggles into the regular profile system, so all six presets (VERY_LOW → EXTREME) carry sensible defaults.
* Added English and Russian translations for all new options, plus value-label localization (`Calm`/`Choppy`/`True Night` etc.) — other languages fall back to English labels.

***

## 🆕 What's New in v0.2.8 — *Dimension Upgrades, Precise Biomes & Physics Fixes*

Version **0.2.8** is a major dimension-specific realism, accuracy, and physics update. It implements bulletproof dimension detection using Minecraft's native engine uniforms, overhauls the End and Nether dimensions with custom atmospheres, solves long-standing visual and math bugs, and repacks the entire codebase.

### 🌌 Dimension Upgrades (The End & The Nether)
* **Crystal-Clear End Dimension** — completely removed clouds and fog in the End dimension (including on emissive surfaces). Obsidian towers and End cities are now perfectly clear, giving unblocked visibility to End stars and nebulae.
* **Dynamic Nether Biome Atmospheres** — completely overhauled the Nether dimension. Instead of a single hardcoded orange-red fog, the shader now dynamically reads the active biome's `fogColor` (Crimson Forest, Warped Forest, Soul Sand Valley, Basalt Deltas, and Nether Wastes) and adapts both block fog and ambient lighting color in real-time.
* **End Star Spherical Mapping** — replaced the old 2D stretched star projection in the End with a perfect, uniform 3D star grid mapping (synchronized with the Overworld). This completely eliminates equatorial star stretching and distortion near the horizon.

### 🛠️ Bulletproof Code & Physics Fixes
* **`worldTime` Overflow Protection** — replaced all occurrences of direct `float(worldTime)` casting with `mod(float(worldTime), 24000.0)`. This solves a major Minecraft bug where daylight cycles, twilight sunset factor, moon masks, and morning/evening mist would permanently freeze after the first Minecraft day (especially on long-term worlds and servers).
* **Nether/End Cook-Torrance BRDF Light Alignment** — resolved a critical mathematical mismatch in PBR highlights. In non-Overworld dimensions where there is no direct sun/moon light direction, the light vector `L` is now aligned to a physical upward vector (`vec3(0.0, 1.0, 0.0)`), matching the overridden half-vector `H`. This guarantees perfect, balanced glossy/metallic specular reflections on all faces.
* **Vibrancy Range Safety Clamp** — added a safety clamp inside the `applyVibrancy` saturation controller in `final.fsh`. This prevents negative values or channel overflows when using High/Extreme contrast or Vivid/Colorful presets, eliminating display clipping and driver-level color banding.
* **Precise Biome Name Mappings** — updated `shaders.properties` custom uniforms to explicitly map and track individual Minecraft End biomes (`BIOME_THE_END`, `BIOME_SMALL_END_ISLANDS`, etc.) and Nether biomes (`BIOME_NETHER_WASTES`, `BIOME_SOUL_SAND_VALLEY`, etc.) rather than guessing by biome category.
* **Minecraft Native `dimension` Uniform Integration** — declared and linked `uniform int dimension;` inside `composite.fsh` and `gbuffers_skybasic.fsh`. This provides 100% reliable, zero-overhead dimension checks (`-1` for Nether, `1` for End, `0` for Overworld) across all Minecraft versions, eliminating the "clouds in the Nether" and "fog in the End" glitches.

---

## 🆕 What's New in v0.2.7 — *Realism, TAA & Compatibility Update*

Version **0.2.7** is a practical visual-realism and compatibility update built on top of v0.2.6. It adds balanced next-generation effects for higher presets, fixes post-rain rainbows on more rendering paths, expands language support, and ships a correctly packaged shaderpack ZIP with a root `shaders/` folder.

### 🌈 Sky & Weather Fixes
* **Reliable post-rain rainbows** — rainbow and moonbow rendering moved into `gbuffers_skybasic` so they appear reliably after rain on Iris/OptiFine paths where the composite sky branch may not run.
* **Safer sky rendering** — fixed stale G-buffer/emissive handling for sky pixels and guarded against invalid normal normalization.

### ☀️ Physically-Inspired Light Shafts & Cloud Shadows
* **Volumetric godrays** — added physically-inspired single-scattering sun shafts with Beer–Lambert extinction, Henyey–Greenstein / Mie phase, height-based aerosol density, shadow-map occlusion, weather attenuation, and cloud-shadow transmittance.
* **Transparent procedural cloud shadows** — clouds now cast soft, variable-opacity shadows on terrain. Cirrus layers are faint, mid-level decks are moderate, and cumulus/storm decks are stronger and more dramatic.

### 🎞️ TAA and Profile Balancing
* **Temporal Anti-Aliasing (TAA)** — added a conservative temporal resolve with motion reprojection, previous-frame history, neighborhood clipping and motion/luminance rejection to reduce shimmer on high presets.
* **New VERY_LOW profile** — a true maximum-FPS preset for very weak GPUs.
* **Rebalanced profiles** — effects are distributed more gradually: cloud shadows begin at MED, godrays and TAA begin at HIGH, SSAO begins at ULTRA, and EXTREME pushes the heaviest variants.

### 🌐 Localization & Packaging
* **Localization expanded to 59 language files** — added many regional languages and compatibility aliases, including both `fil_ph.lang` and legacy `tl_ph.lang` for Filipino/Tagalog support.
* **Correct shaderpack ZIP layout** — release ZIPs now contain a root `shaders/` directory, matching Minecraft shaderpack expectations.

---

## 🆕 Recap — What landed in v0.2.6 — *License Migration & Version Support*

Version **0.2.6** is a legal protection and compatibility update. It migrates the project license to a copyleft non-commercial model to protect AuraLite from unauthorized commercial redistribution, adds copyright assertions to all source files, and officially expands tested compatibility.

### ⚖️ License Migration to CC BY-NC-SA 4.0
* **MIT to CC BY-NC-SA 4.0** — Migrated the project's license from MIT to **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International**. AuraLite is now legally protected against commercial reuse and unauthorized sales (e.g. on third-party launchers/portals).
* **Copyright Asserted** — Explicitly declared copyright: `Copyright (c) 2026 AlexanderNyr`.
* **Embedded Code Headers** — Embedded copyright headers (`// AuraLite Shaders - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.`) into all GLSL shader files (`.fsh`, `.vsh`), block properties (`.properties`), and translation tables (`.lang`).
* **Rules & Permissions FAQ** — Added a clear FAQ section outlining allowed actions (monetized videos/streaming, inclusion in free CurseForge/Modrinth modpacks) and prohibited actions (commercial sales, paid Patreon redistributions, raw rehosting on ad-supported download hubs).

### 🎮 Version Compatibility Expansion
* **Minecraft 26.1.2 Support Verified** — Tested and verified to work flawlessly on the latest Minecraft Java hotfix **26.1.2** with Iris + Sodium.
* **Minecraft 1.16.5 Support Verified** — Tested and confirmed to run beautifully on the legendary modding version **1.16.5** (Iris/OptiFine).

---

## 🆕 Recap — What landed in v0.2.5 — *Settings Fix & Cloud/Lighting Refinement*

Version **0.2.5** is a polish & stability update that fixes long-standing rendering bugs, adds a new **EXTREME** quality profile with screen-space ambient occlusion, completely overhauls the cloud system for camera-stable rendering, and refines fog, aurora, and water lighting. The composite pass grew to **~1 422 lines** of GLSL while keeping the same lightweight philosophy and FPS targets.

### ☁️ Cloud System Overhaul
* **Camera-stable cloud sampling** — clouds no longer change appearance or swim when rotating the camera. Samples are now height-anchored with a per-slice world-space strategy instead of screen-space jitter.
* **Independent wind-shear per layer** — Cirrus, Altocumulus, Altostratus, and Cumulus layers now move with separate rotated/sheared domains and wind offsets, preventing upper layers from looking like copies of lower ones.
* **Wind speed affects clouds** — the `WIND_SPEED` setting (Gentle / Breeze / Gale) now also controls cloud wind drift, with storms pushing layers faster.
* **Cloud Render Distance** (`CLOUD_DISTANCE`) — new 4-step setting (*Near / Standard / Far / Very Far*) that scales automatically with quality profiles. Range expanded: LOW 3 000 m → ULTRA 16 000 m for horizon-scale cloud decks.
* **Camera-inside-cloud volumetric veil** — when flying inside the cloud layer, a soft white/grey fog veil surrounds the camera for immersive flythrough.
* **Softer cloud self-shadowing** — cloud undersides are no longer crushed to black; ambient lift produces naturally dark but readable cloud bases.
* **Better silver lining / phase lighting** — precomputed Mie phase term gives soft golden glow on cloud edges without extra noise calls.
* **Soft layer edges** — vertical feathering on every cloud layer eliminates hard density boundaries.

### 🌟 New EXTREME Quality Profile & SSAO
* **EXTREME profile** — a new fifth quality tier that adds **SSAO/SAO-style contact ambient occlusion** for screen-space darkening in corners, under blocks, and around geometry intersections.
* **SSAO Strength** — 3-step control (*Subtle / Balanced / Deep*). SSAO is enabled on **ULTRA** and **EXTREME** profiles.

### 🔧 Rendering Fixes & Improvements
* **PBR specular BRDF fix** — added the missing NdotL cosine factor for correct Cook-Torrance BRDF. Specular is now properly dim at high sun angles and bright at grazing.
* **Shadow slope bias fix** — bias now uses raw NdotL (not light-wrapped) to prevent shadow acne artifacts.
* **Water G-buffer fix** — `gbuffers_water` now outputs full G-buffer data (`DRAWBUFFERS:012`) — lightmap, PBR, and normals — so the composite pass lights water correctly instead of reading stale terrain data.
* **Unified water specular** — water's own Blinn-Phong specular removed; composite's GGX PBR now handles all water specular with proper Fresnel and microfacet model.
* **Emissive pixel detection** — portals and self-lit surfaces now use `colortex2.a < 0.5` as an emissive flag; composite skips scene lighting for them, displaying the cosmic plasma as-is.
* **Sunset/twilight timing fix** — `/time set 12800` stays red/warm instead of snapping to neutral; twilight window widened to 11 000–13 000.
* **Redundant render call removed** — eliminated a second `projectAndDivide()` call in composite; viewPos is computed once.

### 🌌 Aurora Borealis Fixes
* **Aurora rendering moved to `gbuffers_skybasic`** — fixes auroras being invisible on some Iris/OptiFine pipelines where the composite sky branch didn't run for sky geometry.
* **North mask fixed** — the old `smoothstep(0.0, -0.65, ...)` was undefined on some GPUs; replaced with a correct north-facing mask.
* **Real cold-biome detection** — `AURORA_MODE=1` (Only in Cold Biomes) now uses a **real biome custom uniform** (`biome_category`, `biome_precipitation`, `temperature`) instead of unreliable fogColor heuristics. Fallback to fog-based detection remains for loaders that don't provide the uniform.

### 🌫️ Ground Mist & Fog Refinements
* **Realistic atmospheric fog** — fog now accounts for altitude (aerosol density), horizon path length, and outdoor/indoor exposure via skylight.
* **Ground mist overhaul** — the low mist layer (Y ≈ 60–70) now uses large slow sheets + small breakup noise, optical distance accumulation instead of a hard 120 m cutoff, and a broader dawn/evening timing window with humidity-based persistence.
* **Camera-inside-mist veil** — standing inside the mist layer veils the whole view with a subtle forward-scattering fog.

### 🛠️ Profile & UI Improvements
* **`<profile>` selector on main screen** — quality presets (LOW / MED / HIGH / ULTRA / EXTREME) are now visible and switchable directly on the main settings screen.
* **Translation notice** — a new `⚠ Translations may contain errors` entry warns that some localization strings may be inaccurate.
* **POM disabled in ALL presets** (including ULTRA) — POM is unstable on some resource packs / GPU drivers; users can still enable it manually.
* **All profiles use realistic terminator** (`LIGHT_WRAP=1` — Lambert) by default.
* **profile.LOW completeness fix** *(v0.2.3)* — LOW profile now includes every settings key for reliable profile switching.
* **Localization expanded in v0.2.5** — the base menu localization was expanded to **23 language files**. Later v0.2.7 builds extend this further to 59 language codes.

### 📋 Accumulated fixes from v0.2.3 & v0.2.4
* `CLOUD_HEIGHT` / `CLOUD_THICKNESS` defines now wired to actual cloud geometry.
* `GROUND_MIST` `#define` added so the toggle in `shaders.properties` works.
* `SUN_TEMPERATURE` applied to `gbuffers_skybasic`'s Kelvin curve, matching `composite.fsh`.
* All `texture2D()` calls replaced with `texture()` for GLSL 460 consistency.
* Dead code removed: unused `noise/fbm` functions in `gbuffers_terrain`, dead `renderVolumetricClouds()` in `gbuffers_skybasic`, unused `mc_EntityOut` varying.

---

## 🆕 Recap — What landed in v0.2.2 (Enhanced Lighting Edition)

Version **0.2.2** introduced a brand-new **`[Sun & Moon]`** configuration screen and deeply expanded the shadow / ambient pipeline:

* ☀️ **Sun & Moon Intensity** — 4 levels each.
* ☀️ **Sun & Moon Colour Temperature** — Kelvin-based via the Tanner Helland blackbody curve.
* ☀️ **Sun Halo (Mie Scatter)** & **Enhanced Sunrise/Sunset Glow**.
* 🌑 **Shadow Softness** (rotated Poisson disk), **Shadow Distance**, **Shadow Tint**, **Shadow Lift / Ambient**, **Light Wrap (Terminator Softness)**.

---

## 🆕 Recap — What landed in v0.2.0

Version **0.2.0** was the original content update that nearly doubled the pack's visual feature set (≈ +900 lines of shader code):

* 🌠 **Night Sky Overhaul** — flowing **Aurora Borealis**, a diagonal **Milky Way nebula**, configurable **stars density & brightness**, and an animated **post-rain rainbow** that lingers as wetness decays.
* 🌧️ **Dynamic Weather Surfaces** — **Wet Reflections** on solid ground during rain, support for `thunderStrength` to separate thunderstorms from light showers.
* 🌫️ **Golden Ground Mist (Y = 62–66)** — soft, golden-white morning/evening fog sheets that drift over water and ice at dawn and dusk.
* 🕯️ **Cozy Light Flickering** — real-time warm flicker animations for torches, campfires, and lanterns. Held-item light is also taken into account.
* 🧱 **Parallax Occlusion Mapping (POM)** — true 3D block relief on LabPBR resource packs, with configurable depth and step count.
* 🌊 **Granular Water Tuning** — separate sliders for **ripple strength** (`WATER_RIFFLES`) and **specular glow** (`WATER_SPECULAR_STRENGTH`).
* 🎨 **Color Vibrancy + Tone-Mapping Curves** — 4-step saturation and 3 tone-mapping curves (**Soft / Filmic ACES / Intense**).
* 🌀 **Cosmic Nether Portal** — vanilla portal texture is replaced by a swirling 3D plasma vortex.
* 🧊 **Ice Glitch Fix** — dedicated block ID disables waving/refraction on ice variants to eliminate visual artifacts. *(v1.0.4: split into regular ice (semi-transparent) and packed/blue ice (opaque) with proper texture rendering.)*
* 🌙 **Moon-Phase Aware Sky** — sky shading reacts to `moonPhase` and `dimension` for nether/end correctness.

> Source for every version is shipped in this repo under [`shaders v0.2.0/`](shaders%20v0.2.0) through [`shaders v1.0.5/`](shaders%20v1.0.5). The current source snapshot is **v1.0.5**. End users should grab the packaged release ZIP from [Releases](https://github.com/AlexanderNyr/AuraLite-Shaders/releases).

---

## ✨ Features At A Glance

### ☁️ 1. Meteorological 3D Volumetric Clouds (Fly-Through!)
AuraLite features a fully physical, flyable 3D cloud system driven by **12-step Raymarching** in world coordinates:
* **True 3D Space:** Clouds float at a physical height (configurable base altitude). You can fly up, enter a dense, foggy overcast, and rise above the clouds to see an endless rolling sea of fluffy cumulus clouds.
* **Camera-Inside-Cloud Veil** *(v0.2.5)*: When flying inside the cloud layer, a soft volumetric white/grey fog surrounds the camera.
* **Independent Wind-Shear Layers** *(v0.2.5)*: Each cloud layer (Cirrus, Altocumulus, Altostratus, Cumulus) moves on its own rotated/sheared domain with the `WIND_SPEED` setting.
* **Cloud Render Distance** *(v0.2.5)*: New 4-step control (*Near / Standard / Far / Very Far*) — from 3 000 m to 16 000 m horizon-scale decks.
* **Beer's Law Self-Shadowing:** Realistic light absorption makes cloud bottoms dense and dark while cloud tops glow with brilliant white/gold illumination.
* **Mie Scattering (Silver Lining):** Looking towards the sun produces a glowing golden halo around the cloud edges.
* **Overcast Storms:** When raining (`/weather rain`), the fluffy cumulus clouds automatically expand, darken, and merge into an ominous, heavy **Nimbostratus/Cumulonimbus** storm deck.

### 🌠 2. Living Night Sky *(since v0.2.0)*
The night sky is no longer just a static starfield — it's a fully procedural cosmos:
* **Aurora Borealis:** Realistic, flowing northern lights that ripple across the upper sky. Modes: *Disabled / Only in Cold Biomes / Always Enabled*, with independent **speed** and **brightness** controls. *(v0.2.5: rendered in `gbuffers_skybasic` for reliability; cold-biome detection uses real biome uniforms.)*
* **Milky Way Nebula:** A subtle diagonal brownish galactic band glows softly above the horizon, with adjustable brightness.
* **Procedural Stars:** Independent **brightness** and **density** sliders let you choose between a few crisp pinpricks or a brilliantly dense Hubble-style sky. Stars sparkle and twinkle in real time.
* **Physically-Based Meteors / Falling Stars** *(v1.0.0)*: configurable meteor activity, brightness, moon washout, and persistent ionization trails bring realistic night-sky streaks to the Overworld and the End.
* **Persistent Rainbow:** After rain stops, a soft rainbow arcs across the sky and gently fades out as the `wetness` uniform decays. Brightness and saturation are configurable.

### ☀️ 3. Analytical Kelvin Sun & Moon — *Enhanced in v0.2.2, refined in v0.2.5*
* **Tanner Helland Blackbody Sun:** Sunlight color temperature is dynamically calculated in real time based on the sun's elevation angle using a physically-correct **blackbody Kelvin curve** (selectable: *Cool / Realistic / Warm Golden*). This yields photoreal sunrise/sunset colors (~1800K–2200K), warm golden hours (~2800K), and clean crisp white noon light (~5700K–5800K).
* **Beer-Lambert Atmospheric Extinction:** Sunlight intensity dynamically drops as the sun approaches the horizon due to scattering in thick atmospheric masses:
  $airMass = \frac{1}{\sin(\alpha) + 0.15 \cdot (\alpha_{deg} + 3.885)^{-1.253}}$
  This yields incredibly soft, rich, and breathtaking sunset and sunrise golden hour transitions!
* **Independent Sun & Moon Intensity** *(v0.2.2)*: 4-step master sliders let you push the day brighter (*Blazing*) or sink nights into total darkness (*Pitch Night*).
* **Moon Color Temperature** *(v0.2.2)*: choose between *Icy Blue* (cold), *Silver* (physically accurate 4100K), or *Warm Cream* (harvest-moon).
* **Sun Halo (Mie forward-scatter)** & **Enhanced Sunrise/Sunset Glow** *(v0.2.2)* — warm scattering effects on terrain when looking near the low sun.
* 🆕 **Extended Twilight Window** *(v0.2.5)*: Sunset/sunrise lighting stays warm/red at `/time set 12800` instead of snapping to neutral.
* **Crispy Circular Sun & Moon Disks:** Custom procedural, perfectly round, anti-aliased sun and moon disks are drawn onto the sky dome with glowing coronas and soft halo scattering.

### 👥 4. Soft Shadows, Immersive Dark Nights & Cozy Lights — *Enhanced in v0.2.2, refined in v0.2.5*
* **Rotated Poisson Disk Soft Shadows** *(v0.2.2)*: replaces the old fixed 3×3 PCF kernel. Three quality steps — *Sharp / Soft / Ultra Soft* — give natural-looking penumbra on shadow maps up to 4096×4096.
* 🆕 **Shadow Slope Bias Fix** *(v0.2.5)*: bias now uses raw NdotL to prevent acne artifacts.
* **Shadow Distance Control** *(v0.2.2)*: cap dynamic shadow rendering at *60m / 80m / 120m / 160m* for performance or quality tuning.
* **Shadow Tint** *(v0.2.2)*: realistic cool-blue tint for daytime shadows under an open sky (or neutral / warm if you prefer).
* **Ambient Lift** *(v0.2.2)*: control how dark shadowed areas appear at night and in caves.
* **Light Wrap (Terminator Softness)** *(v0.2.2)*: choose physical Lambert, a soft photographic wrap, or a stylized look. *(v0.2.5: all profiles default to realistic Lambert.)*
* 🆕 **SSAO / SAO Contact Ambient Occlusion** *(v0.2.5)*: screen-space darkening in corners and at geometry intersections. Enabled on ULTRA+ profiles.
* **Deep Dark Nights (2× darker):** Night ambient light, moonlight intensity, and fog are reduced by 2× by default to create incredibly atmospheric, immersive nights. Caves and forests are pitch dark, requiring torches for exploration (combine with the new *Pitch Night* moon preset for extra spice).
* **Warm Block Lights:** Torches, lanterns, and lava emit a cozy golden-amber glow with physically accurate quadratic falloff.
* 🕯️ **Cozy Torch Flickering** *(since v0.2.0)*: Real-time flickering animations for torches, campfires, and lanterns add a living, warm atmosphere to your shelters. Held-item light contribution (`heldBlockLightValue`) is also accounted for.

### 🌊 5. Physical Fresnel Water & Silver Moonlight Path — *Refined in v0.2.5*
* **Fresnel Effect:** Water reflectivity is mathematically calculated based on your viewing angle. Looking straight down provides crystal transparency, while looking towards the horizon transitions water into a highly reflective, glossy sheet reflecting the sky dome.
* **Silver Moonlight Path:** Moonlight specular reflection on water ripples has been increased by **4.5×**. At midnight, a brilliant silver lunar reflection path shimmers across the waving ocean.
* 🆕 **Unified GGX PBR Water Specular** *(v0.2.5)*: Water's old Blinn-Phong specular replaced by composite's GGX microfacet model with proper Fresnel — physically consistent with terrain PBR.
* **3D Geometric Waves:** Vertex shader waves physically displace the water mesh in real-time, and react to `rainStrength` / `thunderStrength` for choppier seas during storms.
* **Independent Ripple & Specular Controls** *(since v0.2.0)*: `WATER_RIFFLES` (Calm / Standard / Choppy) and `WATER_SPECULAR_STRENGTH` (Soft / Standard / Glinting) can be tuned separately for the perfect water mood.
* **Zero Feedback Glitches:** Designed to be extremely stable, utilizing no feedback-loop depth buffer reads to guarantee bug-free solid rendering on all GPUs.

### 🌧️ 6. Dynamic Weather Surfaces *(since v0.2.0)*
* **Wet Reflections:** During rain, solid blocks like grass, dirt, and stone darken and become glossy, picking up sky reflections under open weather. Disables itself under roofs.
* **Low Ground Mist (Y ≈ 60–70)** *(refined in v0.2.5)*: Soft fog sheets drift across water and ice surfaces at dawn and dusk. Uses large slow sheets + small breakup noise with optical distance accumulation for natural-looking radiation fog. Humidity from rain/wetness makes the mist persist longer.
* **Camera-Inside-Mist Veil** *(v0.2.5)*: Standing inside the mist layer produces a subtle whole-view forward-scattering veil.
* **Thunderstorm Awareness:** Shaders distinguish between regular rain and full thunderstorms via the `thunderStrength` uniform, intensifying cloud darkness and wave chop accordingly.

### 🌿 7. Lively Foliage
* Waving animations for oak/spruce/birch leaves, tall grass, flowers, vines, lily pads, and crops.
* Gently animated using hardware-optimized sine waves and time constants.
* 🧊 **Ice fix** *(since v0.2.0, refined in v1.0.4)*: regular ice renders with texture + semi-transparency; packed/blue ice renders opaque with texture. All ice types have waving and refraction disabled to eliminate visual glitches.
* 🪟 **Glass rendering** *(v1.0.4)*: all glass blocks and panes (including every stained-glass variant and tinted glass) now render with their actual texture and proper transparency via the dedicated translucent terrain pass.

### 💎 8. Full LabPBR 1.3 Material Support + POM — *PBR refined in v0.2.5*
* **3D Normal Maps:** Real-time **TBN (Tangent-Binormal-Normal)** matrices generate true three-dimensional depth on blocks (stone crevices, brick joints) reacting dynamically to light angles.
* **Specular Reflection (GGX Microfacet):** Polished surfaces give sharp glossy glints, while metallic surfaces (gold, copper, iron) tint the specular reflection with the block's native albedo. *(v0.2.5: correct NdotL cosine factor added for Cook-Torrance BRDF accuracy.)*
* 🧱 **Parallax Occlusion Mapping (POM)** *(since v0.2.0)*: True per-pixel block relief that pops out of the surface. Configurable `POM_DEPTH` (1–3) and `POM_STEPS` (1–4). Disabled in all profiles by default for stability; can be enabled manually. Recommended to keep off on incompatible resource packs.
* *Seamless Fallback:* Falls back automatically to gorgeous flat vanilla textures if no PBR resource pack is active.

### 🌀 9. Cosmic Nether Portal *(since v0.2.0, improved in v0.2.5)*
The vanilla Nether portal texture is procedurally transformed into a **swirling 3D plasma vortex** — animated purple/magenta cosmic energy that pulses with hypnotic depth. Mapped via dedicated block ID `10006` in `block.properties`. *(v0.2.5: portal pixels are flagged as emissive so composite skips scene lighting and displays the plasma as-is.)*

### 🪟 10. Translucent Block Rendering *(added in v1.0.4, unchanged in v1.0.5)*
AuraLite renders translucent blocks with proper per-block transparency through a dedicated `gbuffers_terrain_translucent` pass, ensuring correct display on both Iris and Oculus pipelines:
* **Regular ice** — semi-transparent with actual texture; opacity scales with `WATER_TRANSPARENCY` (Clear / Balanced / Deep).
* **Packed ice / blue ice / frosted ice** — opaque with texture, visually distinct from regular ice.
* **All glass blocks and panes** — every vanilla glass type (clear, all 16 stained variants, pane variants, tinted glass) renders with its actual texture and correct transparency. No more invisible glass against bright skies.

### 🎬 11. Cinematic Post-Processing — *Refined in v1.0.1, v1.0.3*
* **Multiple Tone Mapping Curves** *(since v0.2.0)*: Pick from **Soft**, **Filmic (ACES)**, or **Intense (High Contrast)** to match your preferred mood.
* **Color Vibrancy** *(since v0.2.0)*: 4-step non-linear saturation control (*Muted / Balanced / Colorful / Vivid*) that makes foliage glow emerald and skies look lush, without crushing skin tones.
* **Exposure Brightness:** Muted / Balanced / Vibrant — global brightness lift.
* **Subtle Vignette:** Gentle lens-darkening at screen edges for improved depth and immersion.

### 🛡️ 12. Realistic Atmospheric Fog *(v0.2.5)*
* Fog density now accounts for **altitude** (aerosol concentration decays with height), **horizon path length**, and **indoor/outdoor exposure** via skylight.
* Consistent Beer-Lambert distance fog with height-weighted density — no delayed fog walls.

---

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
*AuraLite smoothly transitions these layers based on in-game weather conditions (clearing, rain, or storms).*

---

## ⚙️ Performance Optimizations (OpenGL 4.6 Native)

AuraLite is built from the ground up for maximum FPS using OpenGL 4.6 native hardware operations:
* **Multiply-Add Friendly Math:** Wave and waving-foliage math is written as simple multiply-add expressions so modern drivers can optimize it efficiently, while avoiding the explicit `fma()` intrinsic that caused compilation issues on some GPUs / Mesa drivers.
* **Bitwise Noise Generation:** Replacing slow transcendental float functions (`fract(sin(dot(...)))`) with ultra-fast **Integer Bitwise PCG-style hashes** utilizing `floatBitsToUint` and `uintBitsToFloat`.
* **Early-Ray Termination:** Volumetric raymarching terminates instantly once cloud transmittance falls below 2%, saving rendering power.
* **No Hand Transparency Glitches:** Handheld items, particles, and mobs are rendered in a separate stable path without tangent matrix overhead, eliminating "translucent hand" bugs.
* **Dead Code Elimination** *(v0.2.3–v0.2.5)*: Removed unused noise/fbm functions, dead cloud raymarching code from `gbuffers_skybasic`, and redundant render calls to reduce GPU compilation time.
* **Profile-Based Scaling:** Every feature (POM, Auroras, SSAO, Cozy Lights, Wet Reflections, Ground Mist, Shadow Distance, Cloud Distance, Sun Halo, etc.) is intelligently distributed across the **LOW / MED / HIGH / ULTRA / EXTREME** profiles so low-end systems don't pay for effects they can't afford.

---

## 📥 Installation

1. Download **`AuraLite-Shaders-v1.0.5.zip`** from the [Releases](https://github.com/AlexanderNyr/AuraLite-Shaders/releases) section on the right.
2. Open your Minecraft directory (e.g. `%appdata%/.minecraft` on Windows).
3. Place the downloaded `.zip` file inside the **`shaderpacks`** folder (Do **not** unzip it!).
4. Launch a supported Minecraft version (**1.16.5 – 26.1.2**) using a profile with **Sodium + Iris** or **OptiFine** installed.
5. In-game, go to **Options → Video Settings → Shader Packs**, select **AuraLite**, and click **Apply**.

> 💡 The repository ships source folders for every release snapshot: `shaders v0.2.0/` through `shaders v1.0.5/`. The current source snapshot is **v1.0.5**. End users should grab the packaged release ZIP; developers can browse any folder directly.

---

## 🎛️ In-Game Configuration Options

AuraLite includes localized in-game configuration files for **69 language codes**, including major European, Asian, American regional variants and compatibility aliases such as `fil_ph` / `tl_ph`.

> ⚠️ *Some localization strings may be inaccurate. If something looks strange, compare with the English original.*

### `[Lighting Settings]`
* **Dynamic Shadows** — Toggle sun/moon shadows.
* **Shadow Resolution** — `1024 / 2048 / 4096`
* **Shadow Softness** *(v0.2.2)* — `Sharp / Soft / Ultra Soft` — rotated Poisson disk filtering.
* **Shadow Distance** *(v0.2.2)* — `Near (60m) / Standard (80m) / Far (120m) / Ultra (160m)`.
* **Shadow Tint** *(v0.2.2)* — `Neutral Gray / Cool Blue (Realistic) / Warm`.
* **Shadow Lift / Ambient** *(v0.2.2)* — `Dark / Standard / Lifted (Bright)`.
* **Light Wrap (Terminator)** *(v0.2.2)* — `Realistic (Lambert) / Soft / Stylized`.
* **Torch Warmth** — `Cozy / Warm / Intense` — Customize block light warmth.
* **Torch Flickering (`COZY_LIGHTS`)** — Real-time flicker animations for torches, campfires, and lanterns.
* **PBR Lighting** — Toggle PBR specular reflections and normal mapping.
* **3D Block Relief (POM)** — Enable Parallax Occlusion Mapping for true 3D block textures (LabPBR resource pack required).
* **PBR Intensity** — `Subtle / Standard / Mirror`
* 🆕 **SSAO / SAO Occlusion** *(v0.2.5)* — Screen-space ambient occlusion for contact shadows in corners, under blocks, and around geometry intersections.
* 🆕 **SSAO Strength** *(v0.2.5)* — `Subtle / Balanced / Deep`.
* 🆕 **Screen-Space Reflections (`SSR`)** *(v0.2.9)* — loader-agnostic screen-space reflections for water and wet glossy surfaces.
* 🆕 **SSR Quality** *(v0.2.9)* — `Fast / Balanced / High` raymarch step budget.
* 🆕 **SSR Strength** *(v0.2.9)* — `Soft / Balanced / Mirror` reflection intensity.
* 🆕 **PBR Render Distance (`PBR_DISTANCE`)** *(v1.0.3)* — `Near (16m) / Standard (48m) / Far (128m) / Unlimited` — maximum distance for PBR specular calculations. Saves GPU on far terrain.

### `[Sun & Moon]` *(since v0.2.2)*
* **Sun Intensity** — `Dim / Standard / Bright / Blazing`
* **Sun Colour Temperature** — `Cool / Neutral · Realistic (Tanner Helland) · Warm Golden`
* **Sun Halo (Mie Scatter)** — toggle the warm forward-scatter glow when looking near the sun.
* **Enhanced Sunrise/Sunset Glow** — toggle stronger warm back-scatter at low sun angles.
* **Moon Intensity** — `Pitch Night / Standard / Bright Moon / Full Night`
* **Moon Colour Temperature** — `Icy Blue / Silver (Realistic 4100K) / Warm Cream`

### `[Foliage Settings]`
* **Waving Leaves** — Toggle leaves animation.
* **Waving Foliage** — Toggle grass, flowers, and crops animation.
* **Wind Speed** — `Gentle / Breeze / Gale`
* 🆕 **Foliage SSS (`FOLIAGE_SSS`)** *(v1.0.3)* — Subsurface scattering / translucency for leaves and plants (light bleeding when looking toward the sun).

### `[Water Settings]`
* **Water Waves** — Toggle 3D vertex water waves.
* **Water Density** — `Clear / Balanced / Deep` — Adjust water transparency.
* **Water Ripple Strength (`WATER_RIFFLES`)** — `Calm / Standard / Choppy` — Fine normal-map ripples.
* **Water Specular Glow (`WATER_SPECULAR_STRENGTH`)** — `Soft / Standard / Glinting` — Brightness of sun/moon highlights on the ripples.
* 🆕 **Water Wave Scale (`WATER_WAVE_SCALE`)** *(v0.2.9)* — `Calm / Standard / Choppy / Stormy` — procedural wave amplitude used by SSR.
* 🆕 **Water Wave Detail (`WATER_WAVE_DETAIL`)** *(v0.2.9)* — `Coarse / Standard / Dense` — procedural wave frequency/detail.
* 🆕 **Underwater Night Darkness** *(v0.2.9)* — `Moonlit Pool / Dim / True Night / Pitch Dark` — controls how dark underwater scenes become at night.

### `[Sky & Clouds]`
* **Volumetric 3D Clouds** — Toggle raymarched clouds.
* **Cloud Altitude** — `Low (~110m) / Standard (~160m) / High (~240m)`
* **Cloud Thickness** — `Thin (Cirrus) / Standard (Cumulus) / Dense (Stormy)`
* 🆕 **Cloud Render Distance** *(v0.2.5)* — `Near / Standard / Far / Very Far` — Maximum draw distance for volumetric clouds.
* 🆕 **Cloud Shadows** *(v0.2.7)* — transparent procedural shadows from cloud density.
* 🆕 **Cloud Shadow Strength** *(v0.2.7)* — `Soft / Balanced / Dramatic`.
* 🆕 **Godrays / Sun Shafts** *(v0.2.7)* — physically-inspired volumetric single-scattering light shafts.
* 🆕 **Godrays Quality** *(v0.2.7)* — `Fast / Balanced / High`.
* **Aurora Borealis** — `Disabled / Only in Cold Biomes / Always Enabled`
* **Aurora Speed** — `Slow / Standard / Fast`
* **Aurora Brightness** — `Soft / Standard / Glowing`
* **Milky Way Brightness** — `Dim / Standard / Bright`
* **Stars Brightness** — `Faint / Standard / Brilliant`
* **Stars Density** — `Few / Standard / Dense`
* 🆕 **Meteors (Falling Stars)** *(v1.0.0)* — Physically-based meteor streaks across the night sky.
* 🆕 **Meteor Activity (ZHR)** *(v1.0.0)* — `Sporadic (~10/hr) / Active Shower / Meteor Storm`.
* 🆕 **Meteor Brightness** *(v1.0.0)* — `Faint (Realistic) / Standard / Bright Fireballs`.
* **Rainbow Intensity** — `Subtle / Balanced / Vivid` — Post-rain rainbow arc.

### `[Post-Processing & Fog]`
* **Fog Density** — `Low / Medium / High` — Atmospheric horizon mist.
* **Low Ground Mist (`GROUND_MIST`)** — Realistic dawn/evening radiation fog at Y ≈ 60–70.
* **Exposure Brightness** — `Muted / Balanced / Vibrant`
* **Color Vibrancy (`COLOR_SATURATION`)** — `Muted / Balanced / Colorful / Vivid`
* **Image Contrast (`CONTRAST`)** — `Soft / Filmic (ACES) / Intense (High Contrast) / Photographic (AgX-like)` — Choose the tone mapping curve.
* 🆕 **HDR Bloom** *(v1.0.1)* — cheap single-pass neighbour blur for overbright emissive sources.
* 🆕 **Temporal Anti-Aliasing (`TAA`)** *(v0.2.7)* — motion-reprojected temporal resolve for high presets.
* 🆕 **TAA Strength** *(v0.2.7)* — `Light / Balanced / Stable`.
* 🆕 **Spatial Anti-Aliasing (`SPATIAL_AA_MODE`)** *(v1.0.3)* — `Off / FXAA / SMAA` — post-process edge smoothing. FXAA uses Sobel gradient-directed blending; SMAA adds depth discontinuity detection for geometry edges. Freely combinable with TAA.
* **Vignette** — Toggle cinematic corner darkening.
* (Hidden) **Rain Wetness Reflections (`WET_REFLECTIONS`)** — Wet glossy ground during rain (enabled by default in MED+ profiles).

### 🎚️ Quality Profiles *(rebalanced in v1.0.4, unchanged in v1.0.5)*

| Profile      | Target          | Shadows | Clouds | Cloud Shadows | Godrays | TAA | SSR | PBR | PBR Dist | AA   | SSAO | Heavy Extras |
|--------------|-----------------|---------|--------|---------------|---------|-----|-----|-----|----------|------|------|--------------|
| **VERY_LOW** | Maximum FPS     | ❌      | ❌     | ❌            | ❌      | ❌  | ❌  | ❌  | 16m      | Off  | ❌   | Most extras off |
| **LOW**      | Weak GPUs       | ❌      | ❌     | ❌            | ❌      | ❌  | ❌  | ❌  | 16m      | FXAA | ❌   | Water/foliage motion, stars, vignette |
| **MED**      | Balanced        | ✅ 1024 | ✅ Std  | ✅ Soft       | ✅ Fast | ❌  | ✅ F | ✅   | 48m      | FXAA | ❌   | Wet refl + ground mist + SSS |
| **HIGH**     | High quality    | ✅ 2048 | ✅ Far  | ✅ Balanced   | ✅ Bal  | ✅   | ✅ B | ✅   | 128m     | SMAA | ✅ Subtle | Full atmosphere + SSR + TAA |
| **ULTRA**    | Very high       | ✅ 4096 | ✅ VFar | ✅ Balanced   | ✅ High | ✅   | ✅ H | ✅   | 128m     | SMAA | ✅ Balanced | High-end visuals |
| **EXTREME**  | Max quality     | ✅ 4096 | ✅ Dense| ✅ Dramatic   | ✅ High | ✅   | ✅ H | ✅   | ∞        | SMAA | ✅ Deep | Heaviest cinematic |

> 💫 **Shooting stars** are disabled on **VERY_LOW / LOW** and enabled from **MED** upward.
> 🌿 **Foliage SSS** is enabled from **MED** upward (disabled on VERY_LOW/LOW for maximum FPS).

---

## 📄 License & Compatibility

* **AuraLite** is licensed under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License](LICENSE) (CC BY-NC-SA 4.0).
* **Copyright (c) 2026 AlexanderNyr.**
* **Officially Supported Platform:** Minecraft **1.16.5 – 26.1.2** with **Sodium + Iris** or **OptiFine** loader.
* *Note: Verified to work flawlessly on Minecraft 1.16.5, 1.20.1, 1.21.1, and 26.1.2.*

### ⚖️ Rules & Permissions (FAQ)

* **Videos & Streams:** You are free to showcase, stream, and use this shader in your videos (including monetized channels on YouTube, Twitch, etc.).
* **Modpacks:** You are free to include this shader in your free modpacks on CurseForge, Modrinth, or other platforms.
* **Personal Tweaks:** You can modify the shader code for personal use.
* **No Re-hosting:** Do not upload the raw shader files to third-party sites (especially behind ad links like AdFly). Always use and link to our official, authorized sources below.
* **Derivative Works:** If you modify this shader and distribute it, your version **must** be free, open-source, and licensed under the exact same **CC BY-NC-SA 4.0** license with clear attribution to the original author.

#### 🌐 Official & Authorized Sources:
* **GitHub:** [https://github.com/AlexanderNyr/AuraLite-Shaders](https://github.com/AlexanderNyr/AuraLite-Shaders)
* **Modrinth:** [https://modrinth.com/shader/auralite-shaders](https://modrinth.com/shader/auralite-shaders)
* **CurseForge:** [https://www.curseforge.com/minecraft/shaders/auralite-shaders](https://www.curseforge.com/minecraft/shaders/auralite-shaders)
