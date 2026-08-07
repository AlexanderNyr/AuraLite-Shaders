# 🌌 AuraLite Shaders (Minecraft 1.16 – 26.2)

![Minecraft Version](https://img.shields.io/badge/Minecraft-1.16.5%20--%2026.2-blue?logo=minecraft&logoColor=white)
[![Shader Loader](https://img.shields.io/badge/Loader-Iris%20%2F%20Sodium-green)](https://modrinth.com/mod/iris)
[![API Standard](https://img.shields.io/badge/API-OpenGL%204.6%20%2F%20GLSL%20460-orange)](https://khronos.org/)
[![Materials Standard](https://img.shields.io/badge/PBR-LabPBR%201.3-cyan)](https://github.com/rre36/lab-pbr)
[![Version](https://img.shields.io/badge/Release-v1.1.3-purple)](https://github.com/AlexanderNyr/AuraLite-Shaders)
[![License](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/)


**AuraLite** is a modern, lightweight, and highly optimized shader pack built on top of the **OpenGL 4.6 / GLSL 460** standard. It is specifically designed and **tested for Minecraft 1.16 – 26.2 with Sodium + Iris** (and compatible with **OptiFine**, **Oculus**).

AuraLite delivers a breathtaking, realistic visual experience without overcomplicating the screen with bloated post-processing effects (such as aggressive motion blur or heavy bloom). A lightweight HDR bloom (rebuilt in v1.1.3 as a multi-octave gaussian pyramid) softly glows emissive sources without smearing the scene. Optional FXAA/SMAA anti-aliasing, SSR, TAA, godrays, and SSAO are profile-scaled so AuraLite keeps **high FPS and smooth frametimes** on modern GPUs.

> 🧪 **v1.1.3 note:** Adds **true TAA** (Halton sub-pixel camera jitter + YCoCg variance clipping), a **multi-octave HDR bloom pyramid** (`composite3`–`composite7`), the **black-water regression fix** (MRT-proof water detection with analytic sky reflections), procedural raindrop rings, biome-aware swamp water, underwater plant sway, post-TAA sharpening, VRAM savings, and a soft Distant Horizons seam (carried over from the experimental v1.1.2 work). **TAA is on by default in HIGH/ULTRA/EXTREME; the camera jitter is OFF by default** — the new `TAA_JITTER` option (Off/Subtle/Standard/Strong) controls it. See changelog below.

---

> ℹ️ **Historical note:** older changelog sections below are preserved as original release notes.

## 🚀 What's New in v1.1.3 — *True TAA, HDR Bloom Pyramid & Black-Water Regression Fix*

Version **1.1.3** completes the TAA pipeline (Halton sub-pixel camera jitter + YCoCg variance clipping), replaces the old single-pass bloom with a true multi-octave HDR gaussian pyramid, and fixes the long-standing **black-water regression** with MRT-proof water detection. It also adds procedural raindrop rings, biome-aware murky swamp water, underwater plant sway, post-TAA sharpening, and a ~48 MB VRAM cleanup.

### 🎯 True Temporal Anti-Aliasing (Halton Jitter + YCoCg Clipping)

* **Halton(2,3) sub-pixel camera jitter** — every gbuffer vertex shader can offset `gl_Position` by a rotating 8-frame Halton pattern (±0.5 px). Previously TAA only blended history without jittering the sample point, so it could only blur noise instead of reconstructing sub-pixel detail.
* **`TAA_JITTER` option — Off / Subtle / Standard / Strong** (new in v1.1.3). The jitter is **OFF by default in all profiles** for a rock-steady image; Subtle (±0.25 px), Standard (±0.5 px) and Strong (±0.75 px) scale the amplitude for users who want the full sub-pixel reconstruction (removes high-frequency shimmer at the cost of a slight temporal wobble). Requires TAA enabled.
* **Previous-frame jitter compensation** in `composite1.fsh` — the old frame's offset is re-added to the reprojection (with the same strength scale), so static images converge instead of smearing ~0.5 px. Only active while jitter is on.
* **YCoCg variance clipping (μ ± γσ)** replaces the axis-aligned 3×3 min/max box — the old box caused ghost trails on saturated high-contrast edges (fences, wires, hot specular) while being too tight on flat gradients. Clip width scales with `TAA_STRENGTH`: 1.50 Light / 1.25 Balanced / 1.10 Stable.
* **Frame-rotated IGN dithers now resolve cleanly** — godrays and volumetric clouds rotate their interleaved-gradient-noise patterns per frame; with the temporal resolve they integrate into smooth gradients instead of shimmering.
* **TAA is on by default in HIGH / ULTRA / EXTREME profiles** (off on VERY_LOW / LOW / MED for maximum FPS); it can be toggled in the Post-Processing menu, and `TAA_STRENGTH` presets the variance-clip tightness.

### ✨ HDR Gaussian-Pyramid Bloom (composite3 – composite7)

* Replaces the v1.0.1 single-pass 3×3 neighbour glow, whose ~1.5 px radius could only produce a tight halo.
* New 5-pass chain: threshold **brightpass** (0.75 luma soft-knee, exposure-aware) → tight separable gaussian (9-tap, σ≈2.0) → wide separable gaussian (4× stride). Successive blurs compose to an effective **σ ≈ 8.2 px** — a soft cinematic falloff around the sun/moon disks, lava, portals and hot specular, without a mip chain.
* Runs **after the TAA resolve**, so the bloom energy is temporally stable.
* New **`HDR_BLOOM`** option (Subtle 0.06 / Balanced 0.12 / Strong 0.22 amplitude) wired into every quality profile.

### 💧 Black-Water Regression Fix — MRT-Proof Water Detection

* **Root cause:** on some Iris builds the translucent pass drops the `colortex1`/`colortex2` MRT writes entirely — water then arrives with a zeroed normal + alpha + lightmap. The emissive fast-path (alpha < 0.5) swallowed it and every tag/lightmap-based system died with it.
* **Detection ladder:** primary = `colortex2.a = 0.8` tag; **rescue** = the depth difference (`depthtex1` solid-only vs `depthtex0`) proves a translucent surface on top, then a **hue-fingerprint classifier** on the albedo rejects portals (violet, green-starved) and lava (blue-starved) while accepting water (blue/blue-green, never pale). Water, ice and glass classify; torch flames, portal sparkles, squid ink, pale ice and clear glass do not.
* **Synthesized flat water normal** when the decoded normal is untrustworthy (MRT loss or clear value), so Fresnel/reflections still have sane inputs.
* **Analytic sky reflection (`waterSkyRefl`)** — zenith/horizon gradient + warm sun-side glow, dimension-aware (Overworld palette, Nether biome sheen, End violet sheen), applied via Schlick Fresnel with a **0.20 floor** (pure F0≈0.02 at steep look-down angles was exactly what let shadowed water crush to black), multiplied by skyLight so cave water stays dark. This is the actual black-water fix and works with SSR disabled.
* **Diffuse ambient floor** for rescued pixels whose lightmap may read zero.
* **Navy-tint floor** in `gbuffers_water`/`gbuffers_terrain_translucent` — frozen-ocean biome tints (e.g. 0x3938C9) can no longer crush R/G to black after the gamma pipeline.
* **`WATER_DEBUG`** diagnostics overlay (Off / Classify / Lightmap / Raw tag alpha) — green = healthy tag, red = depth-rescued, yellow = rescued from the emissive path, magenta = lava/portal-guarded.

### 🪟 SSR & Refraction Fixes (final.fsh)

* **Procedural sky fallback** for reflection rays that leave the screen or hit the sky — previously black (the reason the `waterMirrorBoost` hack existed); now a day/night/sunset/storm-aware gradient with moon-phase brightness, Schlick-Fresnel weighting and edge fade.
* SSR march start moved **1.0 → 0.5** view units off the surface so the water plane at the player's feet still reflects near-field geometry.
* MRT-proof water detection reused for SSR/refraction (same hue guards as `composite.fsh`).
* **Procedural raindrop rings** on wet up-facing surfaces — two layers of expanding, world-stable circular waves perturb the SSR normal so rain reads as thousands of tiny ripples instead of one flat mirror.

### 🔍 Post-TAA Sharpening (POST_SHARPEN)

* Gentle 5-tap unsharp mask (0.18 amplitude, clamped ≥ 0) applied to the resolved image **before** refraction/SSR/bloom work, recovering texture detail softened by TAA's history blending. On in MED+ profiles.

### ☁️ Volumetric Clouds — Quality Scaling & Dithered Ray Start

* New **`CLOUD_QUALITY`** option: 8 / 12 / 16 raymarch steps (was hardcoded 12) — Cheap / Standard / High.
* **Dithered ray start** (frame-rotated IGN) on geometry pixels when TAA is enabled: the frame-rotating pattern is temporally resolved into a smooth volumetric integral, killing the 12-step ribbing on thick cumulus without the v0.2.5-era "swimming". Sky pixels keep the stable centred start.

### 🌿 Underwater Plants Sway

* New block class **10010** (`seagrass`, `tall_seagrass`, `kelp`, `kelp_plant`, `sea_pickle`) — fronds sway in a current, phase-shifted by height so the tips lag the base, storm-agitated along with the surface foliage path. Displacement is mirrored in `shadow.vsh` so shadows follow the visible fronds.

### 🌊 Biome-Aware Murky Water

* Smoothed swamp/mangrove detector (`isSwampBiome`) — swamp water absorbs more red and reads **greener and murkier** (`absorption (0.23, 0.038, 0.10)`, deep colour pushed to dark green) instead of open-ocean blue.

### 🧪 Physical Sky — Warm Ground Bounce

* The experimental `SKY_MODE=1` atmosphere now includes a **warm ground-bounce term**: terrain's ~15–20% mean albedo re-scatters in the lower atmosphere (strongest at the horizon and with a high sun), removing the "sterile" blue-bias horizon band.

### 🌇 Lighting & Ambience

* **Rayleigh-tinted day ambient** — the day hemisphere ambient now follows the actual sun extinction: golden-hour light is warm and blue-depleted instead of static grey-blue.
* **Held-light temperature** — strong held sources (sea lantern, glowstone, shroomlight, lava bucket) read slightly cooler than candle-strength light.

### 🌍 Distant Horizons — Soft Seam

* The v1.1.2 hard `discard` at `far + 16` is replaced by a **screen-door dithered transition band**: DH LOD fragments stochastically blend into vanilla chunks over 16 m, so crossing the boundary or changing render distance no longer shows a hard cut. The pattern is static per frame (DH-only pixels are excluded from TAA history).

### 🛠️ Pipeline & VRAM Cleanup

* **Removed `colortex5`/`colortex6` format directives** — never read or written, but each forced Iris/OptiFine to allocate a full RGBA16F screen buffer: **~32 MB saved @1080p, ~128 MB @4K**.
* **`shadowcolor0Format` RGBA16F → RGBA8** (it only carries LDR `tex * glcolor`): another ~16 MB @1080p / ~64 MB @4K.
* **`shadowcolor1Format` removed** (nothing ever wrote to it).
* **`colortex0Clear = true`** — no stale garbage on the first frame or after a window resize.
* `colortex3`/`colortex4` are now actually used by the bloom pyramid; the full 8-buffer HDR pipeline is engaged.

---

## 🚀 What's New in v1.1.2 — *Render-Distance Shadows & Experimental Distant Horizons (Partial)*

Version **1.1.2** extends shadow rendering to the actual render distance with an adaptive LOD system, fixes HDR/TAA pipeline strictness, cleans up deprecated GLSL, and introduces **partial, experimental Distant Horizons support (WIP)** — without claiming full compatibility yet. Work is ongoing.

### 🌗 Extended Shadow Distance with Adaptive LOD

* **Shadows now reach render distance.** `shadowDistance` was `60-160m` with a hard cutoff at `shadowDistance`. Now it scales with quality profiles: **60m (VERY_LOW/LOW, no shadows) → 120m (MED) → 256m (HIGH/ULTRA) → 384m (EXTREME)**. The cutoff is replaced by a soft fade `smoothstep(far*0.85, far*0.98)`.
* **New `SHADOW_LOD` toggle — Off / Balanced / Aggressive.** Reduces sample count and expands filter radius at distance to keep performance stable:
  * Balanced: `>25% far → 16 samples ×1.8 radius, >50% → 8 ×2.8`
  * Aggressive: `>15% → 16×2.0, >35% → 8×3.5, >60% → 4×5.0`
  * Beyond 95% `far` shadow sampling is skipped entirely.
* **`shadowMapResolution` now includes `8192`.** EXTREME uses 8192 for maximum texel density at 384m. HIGH stays 2048, ULTRA 4096.
* **New `SHADOW_PCSS_BLUR` toggle — fixed softness vs PCSS penumbra softening.** When enabled, penumbra grows with blocker distance and rain. When disabled, shadows use constant softness.
* **PCSS correctness fixes in `composite.fsh:sampleShadow()`:** added UV bounds checks (prevents clamp-to-border artifacts), `avgBlockerDepth` clamped to `1e-4` to avoid NaN, `penumbraSize` clamped `0-2.0`, `lightSize` reduced `140→40` to prevent light bleeding, `actualSpread` capped to `16.0`, out-of-bounds samples counted as unshadowed (1.0) for correct averaging.
* Shadow bias `distBias` now scales with `far` instead of `shadowDistance`, plus extra water receiver bias for tagged water pixels (`colortex2.a≈0.8`).

### 🔧 HDR Pipeline Strictness Fix

* **Dummy `#define RGBA16F 0` guards** added before the `const int colortex*Format = RGBA16F` directives. This satisfies strict GLSL validators (`C1503 undefined variable RGBA16F`) while Iris/OptiFine's parser still reads the format names (spec second clause). In v1.1.1 the directives were inside a `/* */` comment and were ignored by some loaders.
* Now **all used buffers are explicitly `RGBA16F`**: `colortex0/1/2` (main HDR + PBR + material tags), `colortex3/4/5/6` (unused today but set to HDR for a full pipeline), `colortex7` (TAA history, `colortex7Clear=false`), and optional `shadowcolor0/1Format = RGBA16F`.
* Cost noted: ~16MB per 1080p RGBA16F buffer → ~128MB VRAM for 8 buffers.

### 🌍 Experimental — Partial Distant Horizons Support (WIP, not full support)

> ⚠️ AuraLite does **NOT** yet claim full Distant Horizons compatibility. v1.1.2 only adds a **minimal, experimental code path** so LOD chunks are no longer invisible under Iris. It's functional enough for testing, but considered partial and work-in-progress.

* **Why it was needed:** Without `dh_terrain.vsh/.fsh`, `dh_water.vsh/.fsh`, `dh_shadow.vsh/.fsh`, Iris marks the pack as incompatible with DH and simply doesn't draw DH's simplified LOD chunks at all — symptom "shader works but DH chunks invisible". Presence of these files is enough for Iris/DH auto-detection (`dhShadow.enabled` defaults true).
* **What v1.1.2 does:**
  * `dh_terrain`/`dh_water` write the same `colortex0/1/2` layout as vanilla passes, so existing lighting/fog/shadow/cloud/godray code in `composite.fsh` applies to LOD geometry without other changes.
  * Depth reconciliation in `composite.fsh`: detects `depthtex0>=1.0 && dhDepthTex0<1.0` → `isDHTerrain`, reconstructs viewPos via `dhProjectionInverse` (not `gbufferProjectionInverse` — different far planes) and computes `isSkyPixel`. Fixes DH terrain being treated as sky (flat/washed-out).
  * Fog rescale: `effectiveDensity *= far/dhRenderDistance` prevents exponential fog from saturating to white before DH draw distance.
  * Emissive fast-path uses `!isSkyPixel` instead of `depth<1.0` so distant `DH_BLOCK_ILLUMINATED` (glowstone/lanterns) is still emissive.
  * `final.fsh` heat shimmer now checks `dhDepthTex0` via `isRealGeometry` so distant lava lakes also shimmer.
  * Overdraw prevention: `if(dist < far+16.0) discard` in DH passes — DH renders entire world including area already covered by vanilla chunks; without discard both fight over same G-buffer pixel causing Z-fighting / missing water/ice.
* **Current limitations (why it's partial):**
  * `gl_MultiTexCoord2` is not guaranteed to carry valid lightmap data for DH programs — v1.1.2 hardcodes `lmcoord = vec2(0.0,1.0)` (open sky, no torch). Correct for exterior DH, but not interior-perfect.
  * No LabPBR `normals`/`specular` maps for DH — roughness/metalness approximated per `dhMaterialId` (STONE/WOOD/METAL/SNOW/LEAVES/LAVA...). No POM on DH.
  * Water uses flat vertex normal, not procedurally displaced like near water.
  * Fog/sky/cloud code paths are shared but DH has coarser geometry.
* **Ongoing work:** proper skylight baking if DH ever exposes it, LabPBR fallback, smoother transition seam, performance tuning. Full support will be announced separately.

### 🛠️ Pipeline Cleanup & Fixes

* **Menu split fix — `[v1.1.1-ui-hotfix]`:** Oversized option screens were split into `[SHADOW_OPTIONS]`, `[PBR_OPTIONS]`, `[AO_REFLECTIONS]`, `[CLOUD_SHAPE]`, `[LIGHT_SHAFTS]`, `[NIGHT_SKY]` because some Iris/OptiFine UI builds silently hide buttons when a screen has too many entries.
* **Deprecated `ftransform()` removed** from `composite.vsh`, `final.vsh`, `gbuffers_clouds.vsh`, `composite1.vsh`, `composite2.vsh`, `gbuffers_weather.vsh` — replaced with explicit `gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex` for broader driver compat (same fix applied to `shadow.vsh` in v1.1.0).
* **Final pass cleanup:** Removed two duplicate copy-pasted post-gamma dither blocks that contradicted the comment about linear-space dither (triangle `±1/255` before tonemap). The single pre-tonemap dither remains — more effective in darks, silent in brights.
* **Bias & stale comment fixes:** Corrected stale `colortex6` hand-off comment (removed in v1.0.3), now notes that `final.fsh` reads normal from `colortex2` and roughness from `colortex1.z`.
* **Rebalanced profiles** to reflect new distances and LOD:
  * VERY_LOW/LOW 60m (no shadows), MED 120m Balanced, HIGH 256m Balanced, ULTRA 256m Aggressive, EXTREME 384m Aggressive + 8192 res.
* **Localization:** Bumped `lang/*.lang` headers `v1.0.7 → v1.1.2`, translated previously-English `profile.*.comment` placeholders into native languages (ur_pk, vi_vn, zh_cn, zh_hk, zh_tw and others).

---

## 🛠️ What's New in v1.1.1 — *Pipeline Correctness Fix*

Version **1.1.1** is a focused bug-fix release for the v1.1.0 codebase. It keeps the visual design intact while fixing configuration and runtime issues found in the shader pipeline:

* Moved HDR/TAA buffer directives to GLSL const directives so `colortex0/1/2/7` formats and persistent TAA history are actually applied by Iris/OptiFine.
* Replaced the custom `SHADOW_RES`/`SHADOW_DISTANCE` menu controls with real `shadowMapResolution` and `shadowDistance` pipeline constants.
* Fixed Nether/End dimension fallback detection so a default `dimension=0` cannot override biome/fog-based Nether/End detection.
* Retuned shadow bias to a balanced value with extra water receiver bias: fixes low-sun Peter Panning while cleaning remaining Shadow Acne on water/ice surfaces.
* Made underwater caustics and ground-mist sheets world-stable by using `cameraPosition`-corrected world coordinates.
* Added performance-neutral height-aware pseudo-3D cloud noise: same ray steps/noise calls, but cloud density now changes through Y instead of looking like flat 2D sheets.
* Added `WET_REFLECTIONS` to the menu and wired it into final-pass SSR wetness.
* Added profile-scaled `SKY_QUALITY`, removed physical-sky hash-noise by switching to centred higher-sample raymarching, fixed `SKY_STYLE` grading so it affects only the base sky, restored readable sun/moon sizes in gradient sky, and corrected moonbow direction.
* Fixed emissive-surface cloud lighting, added a safe fallback for unknown tagged translucent blocks, removed the empty translation submenu, made TAA default-off as a standard user toggle, and synced waving vegetation displacement in the shadow pass.
* Forced vanilla Minecraft clouds off via `clouds=false` and added `gbuffers_clouds` discard shaders as a fallback, so AuraLite's procedural clouds do not overlap with default clouds.
* Added `gbuffers_weather` to make vanilla rain/snow streaks less dense and more transparent by default.
* Added explicit opaque entity/hand passes to prevent players, mobs and held items from appearing semi-transparent.

---

## 🆕 What's New in v1.1.0 — *True Volumetric Godrays, HDR Pipeline & Experimental Physical Sky*

Version **1.1.0** replaces the screen-space godray approximation with a fully volumetric raymarched implementation, switches the entire G-buffer pipeline to true HDR (RGBA16F), and introduces an experimental, fully physical realtime atmospheric-scattering sky mode as an opt-in alternative to the stable gradient sky. This is a focused two-pillar update on top of the **v1.0.7** bug-fix baseline.

### 🌤️ True Volumetric Godrays

The old `computeGodrays()` screen-space approximation has been replaced by `computeVolumetricGodrays()` — a genuine single-scattering volumetric raymarch:

* **Per-step shadow-map occlusion** — every raymarch sample now tests the shadow map individually, so light shafts are actually carved by real geometry (trees, buildings, cave ceilings) instead of being implied by a "forward-looking boost" toward the sun.
* **Interleaved Gradient Noise dithering** (Jimenez 2014), rotated per-frame via the new `frameCounter` uniform when TAA is active — 8–24 raymarch steps now integrate as smoothly as hundreds, with no banding.
* **Exact per-segment Beer–Lambert integration** — `Tr₀ · σs/σt · (1 − e^(−σt·Δx))` per step, which is energy-conserving regardless of step size (no more over-brightening at low sample counts).
* **Dual-lobe Henyey-Greenstein phase function** (forward + weak backscatter lobe) with an isotropic floor, so crepuscular rays stay visible when looking *across* them, not only when staring directly at the sun.
* **Colored radiance** — shafts are now warm Kelvin-driven sunbeams by day, deep orange at sunset, and faint blue moonbeams at night, instead of a flat white/yellow overlay.
* **New `GODRAYS_STRENGTH`** setting (*Subtle / Balanced / Dramatic*) added to every quality profile.
* `GODRAYS_QUALITY` sample counts and distances increased: Fast 8 samples/96m, Balanced 16/128m, High 24/160m (up from 4/72m, 6/110m, 8/150m in v1.0.7).

### 🌈 Full HDR G-Buffer Pipeline

* **`colortex0`, `colortex1`, and `colortex2` are now explicitly `RGBA16F`.** Bright sources — the sun disk, lava, specular highlights, portals — no longer clip to `1.0` before tone mapping, so the ACES/AgX curves in `final.fsh` finally compress genuine HDR highlights instead of receiving pre-clamped input. Bloom now samples real HDR luminance rather than an already-saturated LDR buffer.
* `colortex2`'s alpha channel carries a 5-value material tag (`0.0`/`0.1`/`0.62`/`0.8`/`1.0`); RGBA16F guarantees these are preserved exactly, whereas a lower-precision format would have aliased and collided material tags (e.g. foliage vs. water).
* Godray intensity constants were re-tuned (roughly halved vs. the old LDR values) now that the additive shaft survives in full instead of clipping against a saturated scene; a stronger soft shoulder (`0.50` vs. the old `0.30`) keeps the sun-facing core from blowing out under HDR.

### 🧪 Experimental: Realtime Physical Sky (Off by Default)

A brand-new **`[EXPERIMENTAL]`** menu tab exposes an alternate sky renderer in `gbuffers_skybasic.fsh`, disabled in every shipped profile (`SKY_MODE=0`) so the stable gradient sky remains the default:

* **`SKY_MODE`** — `0` (Gradient, legacy v1.0.7-style sky) or `1` (Physical Realtime): a genuine per-pixel ray-marched atmosphere with exact 1st-order single scattering (Rayleigh + Mie + Ozone, full sun-ray optical-depth march with ground-occlusion detection) plus a blue-biased, bounded multiple-scattering ambient term that fills in the zenith/horizon without producing the typical LUT-based "yellow band" artifact. No lookup textures, no cross-frame reads.
* **`SKY_QUALITY`** — controls raymarch sample counts (*Fast 8×4 / Standard 12×6 / High 16×8*) for the physical mode.
* **`SKY_STYLE`** — new artistic-direction toggle independent of `SKY_MODE`: *Realistic* (true angular sun/moon size, neutral colors, minimal glow — an authentic astronomy look), *Semi-realistic* (readable ×2.8 sun/moon size, richer color, soft aureole — the default), or *Fantasy* (grand ×5.5 sun/moon, huge corona, vivid saturated teal/crimson/indigo palette for a stylized sky).
* Physical mode renders the sun disk with real limb darkening and a physically-derived angular radius, and computes its color from actual sun-ray transmittance (ozone-aware) rather than the legacy Kelvin/airmass approximation.
* Because this feature is explicitly experimental and disabled by default, it introduces no behavioral change to any existing profile.

### 🛠️ Smaller Fixes & Cleanup

* **Dark-sky/moon-halo banding fixed at the source** — a linear-space triangle-distributed dither (`±1/255`, matching the BSL/Complementary technique) is now applied in `final.fsh` *before* tone mapping, where gamma expansion makes a tiny linear noise term large enough in the darks to smooth the gradient, while staying invisible in bright regions. The old post-gamma dither (which couldn't fix pre-tonemap banding) has been removed and replaced with an explicit final `clamp()`.
* `shadow.vsh` no longer relies on the deprecated fixed-function `ftransform()`; it now builds the clip-space position explicitly via `gl_ModelViewMatrix` / `gl_ProjectionMatrix` for broader driver compatibility.
* Updated localization strings for `GODRAYS`, `GODRAYS_QUALITY`, and the new `GODRAYS_STRENGTH` / `SKY_MODE` / `SKY_STYLE` / `SKY_QUALITY` options and the new Experimental tab.

---

## 🆕 What's New in v1.0.7 — _Comprehensive Bug Fix, Stability & Aurora Refinement Update_

Version **1.0.7** conducts a deep code audit across the entire GLSL 460 pipeline to resolve rendering anomalies, feedback loops, and multi-pass inconsistencies introduced in earlier releases, and additionally refines the Aurora Borealis to remove high-frequency visual noise while softening its overall luminance.

### 🐞 Bug Fixes & Architectural Polish

*   **Massive Volumetric Cloud, Godray & Aurora FPS Bottleneck Resolved**
*   **Underwater Screen-Space Ripple Distortion Feedback Loop Fixed** — Removed legacy underwater ripple screen distortion from `composite.fsh` (where it erroneously sampled raw unlit G-buffer albedo `colortex0` and mixed unshaded texels into the lit scene). Moved clean underwater screen-space view perturbation directly into `final.fsh`, sampling the fully lit, composited, and TAA-resolved scene.
*   **Glass & Ice Water Refraction / Reflection Distortion Fixed** — Solved a multi-target G-buffer collision where stained glass windows and ice blocks triggered the depth-comparison detector `(depthS - depth) > 1e-5` in `final.fsh`. Added a dedicated material alpha tag `colortex2.a = 0.8` for water in `gbuffers_water` and `gbuffers_terrain_translucent`, ensuring glass windows (`1.0`) and ice blocks (`1.0`) never receive underwater refraction ripples or wavy water SSR reflections.
*   **Procedural Lava POM Coordinate Discard Fixed** — Standardized the 4-step Parallax Occlusion Mapping loop in `gbuffers_water.fsh` and `gbuffers_terrain_translucent.fsh` to match `gbuffers_terrain.fsh`. Displaced UV coordinates `p = currentTexCoords` are now properly retained across the entire shader block for crack height calculations, temperature gradients, hotspots, and rising bubbles.
*   **Unnormalized Lava Normal Output Fixed** — Normalized the G-buffer normal output `normalize(normal)` in `gbuffers_terrain.fsh` before encoding into `colortex2`, preventing interpolated vector length drift across triangle interiors.
*   **Camera-Inside Volumetric Fog, Ground Mist & Valley Sheets Fixed** — In `getInsideGroundMistVeil()`, `applyInsideCloudVeil()`, and distant ground mist sheet rendering, fixed the exponential absorption rate (lowered from `0.014`/`0.0105` to `0.0018`/`0.0035`) and removed hardcoded blanket opacity ceilings (`0.30`/`0.34`). Wired the user's `FOG_DENSITY_LEVEL` setting directly into volume optical thickness. Added a smooth attenuation factor `(1.0 - camMistHere * 0.95)` to distant 2D sheets when standing inside the ground mist layer, preventing double-accumulation with the screen-space volumetric veil.
*   **PCSS Blocker Search Self-Shadow Acne Fixed** — Updated the blocker depth comparison threshold in `composite.fsh` from a static `1e-4` epsilon to the dynamic surface slope bias (`bias`). Sloped terrain no longer detects itself as a false shadow occluder.
*   **POM Division-By-Zero NaN Fixed** — In `getParallaxCoords()`, changed the ray hit weight denominator from `(afterDepth - beforeDepth + 0.0001)` to `min(afterDepth - beforeDepth, -1e-5)`. Since `afterDepth - beforeDepth` is strictly negative, adding `+0.0001` mathematically cancelled out the denominator to zero on subtle step transitions, causing black dot NaN artifacts.
*   **POM Optical View Angle Cotangent Scaling & Limiting Added** — Scaled tangent-space UV step offsets by `V_tang.xy / max(abs(V_tang.z), 0.15)` across all POM passes. Parallax crack depth now physically stretches when viewed at grazing angles instead of flattening out.
*   **Procedural Lava Sub-Step POM Linear Interpolation Added** — Replaced the discrete sub-step endpoint `p = currentTexCoords` in the lava POM loop with exact linear interpolation `mix(currentTexCoords, prevTexCoords, weight)`. Internal crack walls no longer suffer from 4-step banding/stepping artifacts.
*   **Block Mapping Extended** — Added `minecraft:magma_block` to block ID `10009` in `block.properties`, granting overworld and nether magma blocks dynamic procedural glowing Voronoi cracks.

### 🌌 Aurora Borealis Refinement — Smoother & Softer

The volumetric Aurora in `gbuffers_skybasic.fsh` was producing subtle high-frequency "static" patterns and reading slightly oversaturated on bright presets. The shader pass has been retuned in this release:

*   **Dither offset re-centered and weakened** — Replaced the `0..1` per-pixel ray start offset with a centered `-0.5..+0.5` range scaled down to `0.6 × dt`. Adjacent pixels now sample closer ray distances, eliminating the flickering pattern that read as visual noise.
*   **Vertical ray frequency lowered (32.0 → 14.0)** — The single very-high-frequency `sin(uv.x × 32)` that powered the striations aliased into thin static-like lines. Two slightly offset waves (`14.0` + `9.0`) are now blended together with `mix(0.5)` to break the periodic aliasing while preserving the characteristic vertical pillar look.
*   **Ray sharpness softened (3.0 → 1.8) and amplitude reduced (2.0 → 1.3)** — Pillars no longer have harsh, sharp edges; they blend smoothly into the curtain ribbon.
*   **Curtain ribbon exponent softened (5.0 → 3.5)** and weight lowered from `0.5` to `0.45` — Lighter, more atmospheric curtains without the blocky stripe artifacts the high power was producing.
*   **Spatial color variation slowed down** — `sin(worldDir.x × 3.5 + worldDir.z × 2.8) × 0.2` → `sin(worldDir.x × 2.2 + worldDir.z × 1.7) × 0.18`. Color shifts across the sky are now gradual instead of rapid.
*   **Photographic palette toned down (~30% dimmer)**:
    *   Cyan-Green: `(0.0, 0.80, 0.50)` → `(0.0, 0.55, 0.32)`
    *   Magenta/Purple: `(0.60, 0.10, 0.70)` → `(0.42, 0.08, 0.50)`
    *   Deep Blue (upper edge): `(0.05, 0.10, 0.50)` → `(0.04, 0.08, 0.35)`
*   **Optical depth scaling lowered (0.35 → 0.26)** and final intensity multiplier `× 0.78` — Overall accumulation is roughly **35–40% softer** than the v1.0.7 original. The `AURORA_STRENGTH` profile setting still controls user-level intensity on top.

The aurora now reads as a soft, glowing, photographic northern light rather than an over-saturated neon stripe pattern. No menu changes; no new options; no profile changes. All existing `AURORA_MODE`, `AURORA_SPEED`, and `AURORA_STRENGTH` settings behave as before.

***

## 🆕 What's New in v1.0.6 — _Procedural Lava & Heat Shimmer_

Version **1.0.6** adds a physically-inspired procedural lava block renderer and a subtle heat-shimmer post-processing effect. It is a focused visual update on top of **v1.0.5**.

### 🔥 Procedural Lava / Magma (Block ID 10009)

*   **Block mapping** — `minecraft:lava` and `minecraft:flowing_lava` are now tagged with block ID `10009` in `block.properties`.
*   **3D Voronoi cracks** — the surface is generated with a procedural Voronoi crack field (basalt crust on top, glowing magma in the cracks) using a 4-step parallax occlusion raymarch for real depth.
*   **Animated convection flow** — slow noise-driven convection makes the magma crawl and pulse.
*   **Localized hot spots & bubbles** — rare high-contrast yellow-orange hot spots and short-lived rising bubbles add life without turning the surface into noise.
*   **Viscous waves** — only the top face receives a slower, heavier vertex displacement so lava feels thick and molten.
*   **PBR-ready** — the basalt crust is rough (0.95) while the magma cracks are extremely glossy (0.02), giving physically plausible highlights.
*   **Multi-pass coverage** — lava is handled in `gbuffers_terrain`, `gbuffers_water`, and `gbuffers_terrain_translucent` so it renders correctly on both Iris and Oculus pipelines regardless of which pass the loader assigns fluid blocks to.

### 🌡️ Heat Shimmer Above Lava

*   `final.fsh` detects lava pixels through a dedicated `colortex2` alpha signature (0.1) and applies a subtle, slow screen-space distortion that simulates rising hot air.
*   The effect is constrained by depth and by the lava mask, so it only affects pixels directly above or next to lava surfaces.
*   **New in-game options:** `HEAT_SHIMMER` (on/off) and `HEAT_SHIMMER_STRENGTH` (Subtle / Balanced / Strong), located in the `[Post-Processing & Fog]` menu.

***

## 🆕 What's New in v1.0.5 — _Expanded Localization_

Version **1.0.5** is a localization-focused release that adds **10 new in-game languages**, bringing the total to **69 supported locales**. No shader logic, profile defaults, or rendering behavior was changed — this is a pure translation / metadata update on top of **v1.0.4**.

### 🌐 New Languages

The following fully-translated `.lang` files were added (every option name, value label, profile name and tooltip — 289 keys each, 100% key parity with the English source):

| Code  |Language        |Code  |Language              |
| ----- |--------------- |----- |--------------------- |
| <code>gl_es</code> |Galician        |<code>sw_ke</code> |Swahili               |
| <code>ga_ie</code> |Irish           |<code>nn_no</code> |Norwegian Nynorsk     |
| <code>gd_gb</code> |Scottish Gaelic |<code>tt_ru</code> |Tatar                 |
| <code>af_za</code> |Afrikaans       |<code>hy_am</code> |Armenian              |
| <code>az_az</code> |Azerbaijani     |<code>zh_hk</code> |Cantonese (Hong Kong) |

*   As with all non-English locales, the in-game **⚠ Translations may contain errors** notice applies — some strings in rarer languages may be imperfect; compare with the English original if anything looks off.
*   No shader logic, profile defaults, or rendering behavior changed in this release — **v1.0.5** is purely a localization / metadata refresh on top of **v1.0.4**.
*   `README.md`, installation references, and source-folder notes updated to **v1.0.5**.
*   `shaders.properties` and `block.properties` metadata headers updated to **v1.0.5**.
*   Source-folder snapshots now run through `shaders v1.0.5/`.

***

## 🆕 What's New in v1.0.3 — _Anti-Aliasing & PBR Performance_

Version **1.0.3** adds configurable spatial anti-aliasing (FXAA / SMAA) and a PBR render distance control that skips expensive Cook-Torrance specular calculations on distant terrain.

### 🖼️ Spatial Anti-Aliasing (FXAA / SMAA)

*   **`SPATIAL_AA_MODE`** — new toggle in the `[Post-Processing]` menu with 3 modes:
    *   **Off** — no spatial AA (TAA-only or nothing).
    *   **FXAA** — Fast Approximate AA. Sobel gradient-directed edge detection with conservative blend weights. Cheap and effective.
    *   **SMAA** — Subpixel Morphological AA. Combines luminance Sobel gradient with depth discontinuity detection for superior edge detection on geometry where luma contrast is low. Slightly more expensive than FXAA.
*   Both modes operate in linear space before tone mapping and are conservative enough to avoid washing out the image (max blend weight 0.15–0.18, high edge thresholds).
*   Freely combinable with TAA (composite1 pass) for temporal + spatial smoothing.
*   Added to all 6 quality profiles: VERY\_LOW=Off, LOW/MED=FXAA, HIGH/ULTRA/EXTREME=SMAA.

### ⚡ PBR Render Distance

*   **`PBR_DISTANCE`** — new setting in the `[Lighting Settings]` menu with 4 levels:
    *   **Near (16m)** — PBR specular only on very close surfaces. Maximum GPU savings.
    *   **Standard (48m)** — balanced distance. Default for LOW/MED profiles.
    *   **Far (128m)** — extended range. Default for HIGH/ULTRA profiles.
    *   **Unlimited** — no distance limit. EXTREME profile only.
*   Beyond the fade range, the entire Cook-Torrance BRDF block (GGX distribution, Smith geometry, Fresnel-Schlick) is **completely skipped** via early-out — no wasted ALU on sub-pixel specular.
*   Fade is smooth (`smoothstep` between start and end distance) to avoid visible pop-in.

### 🌐 Localization

*   Full English and Russian localization for both new settings (option names + value labels).
*   Other language files fall back to English labels.

***

### 🌿 Foliage Subsurface Scattering (also finalized in v1.0.3)

*   **`FOLIAGE_SSS`** — toggle in the `[Foliage Settings]` menu. Enables light bleeding through leaves and plants when looking toward the sun, plus a soft wrap term for the shaded side. Controlled per-profile (enabled from MED upward by default). Uses material ID tagging in `gbuffers_terrain` and a dedicated SSS pass in `composite.fsh`.
*   Added to all quality profiles (VERY\_LOW → EXTREME) with the `!FOLIAGE_SSS` or `FOLIAGE_SSS` flag.
*   Full English + Russian localization strings added.

older changelog sections below are preserved as original release notes.

Version **1.0.2** adds realistic subsurface scattering for vegetation, making leaves, grass, and plants look more translucent and lifelike when light shines through them. This is a focused visual enhancement that integrates cleanly with the existing PBR and lighting pipeline.

### 🌿 New Feature

*   **Foliage Subsurface Scattering (`FOLIAGE_SSS`)** — New toggle in the `[Foliage Settings]` menu. When enabled, foliage receives additional lighting from the back (light bleeding) and a soft wrap term for the unlit side. Controlled per-profile (enabled from MED upward by default). Uses material ID tagging in `gbuffers_terrain` and a dedicated SSS pass in `composite.fsh`.
*   Added to all quality profiles (VERY\_LOW → EXTREME) with the `!FOLIAGE_SSS` or `FOLIAGE_SSS` flag.
*   Full English + Russian localization strings added.

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

AuraLite features a fully physical, flyable 3D cloud system driven by **12-step Raymarching** in world coordinates:

*   **True 3D Space:** Clouds float at a physical height (configurable base altitude). You can fly up, enter a dense, foggy overcast, and rise above the clouds to see an endless rolling sea of fluffy cumulus clouds.
*   **Camera-Inside-Cloud Veil** _(v0.2.5)_: When flying inside the cloud layer, a soft volumetric white/grey fog surrounds the camera.
*   **Independent Wind-Shear Layers** _(v0.2.5)_: Each cloud layer (Cirrus, Altocumulus, Altostratus, Cumulus) moves on its own rotated/sheared domain with the `WIND_SPEED` setting.
*   **Cloud Render Distance** _(v0.2.5)_: New 4-step control (_Near / Standard / Far / Very Far_) — from 3 000 m to 16 000 m horizon-scale decks.
*   **Beer's Law Self-Shadowing:** Realistic light absorption makes cloud bottoms dense and dark while cloud tops glow with brilliant white/gold illumination.
*   **Mie Scattering (Silver Lining):** Looking towards the sun produces a glowing golden halo around the cloud edges.
*   **Overcast Storms:** When raining (`/weather rain`), the fluffy cumulus clouds automatically expand, darken, and merge into an ominous, heavy **Nimbostratus/Cumulonimbus** storm deck.

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
*   **Independent Ripple & Specular Controls** _(since v0.2.0)_: `WATER_RIFFLES` (Calm / Standard / Choppy) and `WATER_SPECULAR_STRENGTH` (Soft / Standard / Glinting) can be tuned separately for the perfect water mood.
*   **Zero Feedback Glitches:** Designed to be extremely stable, utilizing no feedback-loop depth buffer reads to guarantee bug-free solid rendering on all GPUs.

### 🌧️ 6. Dynamic Weather Surfaces _(since v0.2.0)_

*   **Wet Reflections:** During rain, solid blocks like grass, dirt, and stone darken and become glossy, picking up sky reflections under open weather. Disables itself under roofs.
*   **Low Ground Mist (Y ≈ 60–70)** _(refined in v0.2.5)_: Soft fog sheets drift across water and ice surfaces at dawn and dusk. Uses large slow sheets + small breakup noise with optical distance accumulation for natural-looking radiation fog. Humidity from rain/wetness makes the mist persist longer.
*   **Camera-Inside-Mist Veil** _(v0.2.5)_: Standing inside the mist layer produces a subtle whole-view forward-scattering veil.
*   **Thunderstorm Awareness:** Shaders distinguish between regular rain and full thunderstorms via the `thunderStrength` uniform, intensifying cloud darkness and wave chop accordingly.

### 🌿 7. Lively Foliage

*   Waving animations for oak/spruce/birch leaves, tall grass, flowers, vines, lily pads, and crops.
*   Gently animated using hardware-optimized sine waves and time constants.
*   🧊 **Ice fix** _(since v0.2.0, refined in v1.0.4)_: regular ice renders with texture + semi-transparency; packed/blue ice renders opaque with texture. All ice types have waving and refraction disabled to eliminate visual glitches.
*   🪟 **Glass rendering** _(v1.0.4)_: all glass blocks and panes (including every stained-glass variant and tinted glass) now render with their actual texture and proper transparency via the dedicated translucent terrain pass.

### 💎 8. Full LabPBR 1.3 Material Support + POM — _PBR refined in v0.2.5_

*   **3D Normal Maps:** Real-time **TBN (Tangent-Binormal-Normal)** matrices generate true three-dimensional depth on blocks (stone crevices, brick joints) reacting dynamically to light angles.
*   **Specular Reflection (GGX Microfacet):** Polished surfaces give sharp glossy glints, while metallic surfaces (gold, copper, iron) tint the specular reflection with the block's native albedo. _(v0.2.5: correct NdotL cosine factor added for Cook-Torrance BRDF accuracy.)_
*   🧱 **Parallax Occlusion Mapping (POM)** _(since v0.2.0)_: True per-pixel block relief that pops out of the surface. Configurable `POM_DEPTH` (1–3) and `POM_STEPS` (1–4). Disabled in all profiles by default for stability; can be enabled manually. Recommended to keep off on incompatible resource packs.
*   _Seamless Fallback:_ Falls back automatically to gorgeous flat vanilla textures if no PBR resource pack is active.

### 🌀 9. Cosmic Nether Portal _(since v0.2.0, improved in v0.2.5)_

The vanilla Nether portal texture is procedurally transformed into a **swirling 3D plasma vortex** — animated purple/magenta cosmic energy that pulses with hypnotic depth. Mapped via dedicated block ID `10006` in `block.properties`. _(v0.2.5: portal pixels are flagged as emissive so composite skips scene lighting and displays the plasma as-is.)_

### 🪟 10. Translucent Block Rendering _(added in v1.0.4, unchanged in v1.0.6)_

AuraLite renders translucent blocks with proper per-block transparency through a dedicated `gbuffers_terrain_translucent` pass, ensuring correct display on both Iris and Oculus pipelines:

*   **Regular ice** — semi-transparent with actual texture; opacity scales with `WATER_TRANSPARENCY` (Clear / Balanced / Deep).
*   **Packed ice / blue ice / frosted ice** — opaque with texture, visually distinct from regular ice.
*   **All glass blocks and panes** — every vanilla glass type (clear, all 16 stained variants, pane variants, tinted glass) renders with its actual texture and correct transparency. No more invisible glass against bright skies.

### 🎬 11. Cinematic Post-Processing — _Refined in v1.0.1, v1.0.3_

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
*   **Bitwise Noise Generation:** Replacing slow transcendental float functions (`fract(sin(dot(...)))`) with ultra-fast **Integer Bitwise PCG-style hashes** utilizing `floatBitsToUint` and `uintBitsToFloat`.
*   **Early-Ray Termination:** Volumetric raymarching terminates instantly once cloud transmittance falls below 2%, saving rendering power.
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
*   **Shadow Distance** _(v0.2.2, extended in v1.1.2)_ — `Near (60m) / Standard (80-120m) / Far (120-256m) / Ultra (256-384m)` — now fades to `far` instead of hard-cutting, with `SHADOW_LOD`.
*   **Shadow LOD** _(v1.1.2)_ — `Off / Balanced / Aggressive` — reduces samples (32→16→8→4) and expands filter radius at distance.
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
*   🆕 **Water Wave Scale (`WATER_WAVE_SCALE`)** _(v0.2.9)_ — `Calm / Standard / Choppy / Stormy` — procedural wave amplitude used by SSR.
*   🆕 **Water Wave Detail (`WATER_WAVE_DETAIL`)** _(v0.2.9)_ — `Coarse / Standard / Dense` — procedural wave frequency/detail.
*   🆕 **Underwater Night Darkness** _(v0.2.9)_ — `Moonlit Pool / Dim / True Night / Pitch Dark` — controls how dark underwater scenes become at night.
*   🆕 **Water Diagnostics (`WATER_DEBUG`)** _(v1.1.3)_ — developer overlay (Off / Classify / Lightmap / Raw tag alpha) for diagnosing water classification on Iris builds that drop translucent MRT writes. Keep **Off** in normal play.

### `[Sky & Clouds]`

*   **Volumetric 3D Clouds** — Toggle raymarched clouds.
*   **Cloud Altitude** — `Low (~110m) / Standard (~160m) / High (~240m)`
*   **Cloud Thickness** — `Thin (Cirrus) / Standard (Cumulus) / Dense (Stormy)`
*   🆕 **Cloud Render Distance** _(v0.2.5)_ — `Near / Standard / Far / Very Far` — Maximum draw distance for volumetric clouds.
*   🆕 **Cloud Quality (`CLOUD_QUALITY`)** _(v1.1.3)_ — `Cheap (8 steps) / Standard (12 steps) / High (16 steps)` — raymarch step budget for volumetric clouds.
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
*   **Exposure Brightness** — `Muted / Balanced / Vibrant`
*   **Color Vibrancy (`COLOR_SATURATION`)** — `Muted / Balanced / Colorful / Vivid`
*   **Image Contrast (`CONTRAST`)** — `Soft / Filmic (ACES) / Intense (High Contrast) / Photographic (AgX-like)` — Choose the tone mapping curve.
*   🆕 **HDR Bloom (`HDR_BLOOM`)** _(v1.0.1, rebuilt in v1.1.3)_ — gaussian-pyramid bloom (composite3–7): threshold brightpass + tight & wide separable gaussian octaves, effective σ≈8.2 px soft cinematic glow around the sun/moon, lava, portals and hot specular. `Subtle / Balanced / Strong`.
*   🆕 **Temporal Anti-Aliasing (`TAA`)** _(v0.2.7, completed in v1.1.3)_ — Halton sub-pixel camera jitter + motion reprojection + YCoCg variance clipping. **On by default in HIGH/ULTRA/EXTREME** since v1.1.3, off on lighter profiles.
*   🆕 **TAA Strength** _(v0.2.7)_ — `Light / Balanced / Stable` — presets the variance-clip tightness (1.50 / 1.25 / 1.10 γ).
*   🆕 **TAA Camera Jitter (`TAA_JITTER`)** _(v1.1.3)_ — `Off / Subtle / Standard / Strong` — sub-pixel Halton camera jitter amplitude (±0.25 / ±0.5 / ±0.75 px) for full sub-pixel reconstruction. **Off by default** for a steady image; enable it to eliminate high-frequency shimmer. Requires TAA.
*   🆕 **Post-Sharpen (`POST_SHARPEN`)** _(v1.1.3)_ — gentle unsharp mask that recovers texture detail softened by TAA history blending (on in MED+ profiles).
*   🆕 **Spatial Anti-Aliasing (`SPATIAL_AA_MODE`)** _(v1.0.3)_ — `Off / FXAA / SMAA` — post-process edge smoothing. FXAA uses Sobel gradient-directed blending; SMAA adds depth discontinuity detection for geometry edges. Freely combinable with TAA.
*   **Vignette** — Toggle cinematic corner darkening.
*   (Hidden) **Rain Wetness Reflections (`WET_REFLECTIONS`)** — Wet glossy ground during rain (enabled by default in MED+ profiles).

### 🎚️ Quality Profiles _(rebalanced in v1.1.2 — shadows 60-384m with LOD; TAA on in HIGH+ since v1.1.3, camera jitter off by default everywhere)_

| Profile  |Target       |Shadows |Clouds  |Cloud Shadows |Godrays |TAA |SSR |PBR |PBR Dist |AA   |SSAO       |Heat Shimmer |Heavy Extras                          |
| -------- |------------ |------- |------- |------------- |------- |--- |--- |--- |-------- |---- |---------- |------------ |------------------------------------- |
| <strong>VERY_LOW</strong> |Maximum FPS  |❌ 512/60m |❌       |❌             |❌       |❌   |❌   |❌   |16m      |Off  |❌          |❌            |Most extras off                       |
| <strong>LOW</strong> |Weak GPUs    |❌ 512/60m |❌       |❌             |❌       |❌   |❌   |❌   |16m      |FXAA |❌          |❌            |Water/foliage motion, stars, vignette |
| <strong>MED</strong> |Balanced     |✅ 1024/120m |✅ Std   |✅ Soft        |✅ Fast  |❌   |✅ F |✅   |48m      |FXAA |❌          |✅ Subtle     |Wet refl + ground mist + SSS          |
| <strong>HIGH</strong> |High quality |✅ 2048/256m |✅ Far   |✅ Balanced    |✅ Bal   |✅   |✅ B |✅   |128m     |SMAA |✅ Subtle   |✅ Balanced   |Full atmosphere + SSR + TAA           |
| <strong>ULTRA</strong> |Very high    |✅ 4096/256m Aggr LOD |✅ VFar  |✅ Balanced    |✅ High  |✅   |✅ H |✅   |128m     |SMAA |✅ Balanced |✅ Balanced   |High-end visuals + TAA                |
| <strong>EXTREME</strong> |Max quality  |✅ 8192/384m Aggr LOD |✅ Dense |✅ Dramatic    |✅ High  |✅   |✅ H |✅   |∞        |SMAA |✅ Deep     |✅ Strong     |Heaviest cinematic + TAA              |

> 💫 **Shooting stars** are disabled on **VERY\_LOW / LOW** and enabled from **MED** upward. 🌿 **Foliage SSS** is enabled from **MED** upward (disabled on VERY\_LOW/LOW for maximum FPS). 🔥 **Heat shimmer** is disabled on **VERY\_LOW / LOW** and enabled from **MED** upward.
> 🎯 **TAA** is on by default in **HIGH / ULTRA / EXTREME** and off on lighter profiles (since v1.1.3). The **camera jitter is off by default everywhere** — enable `TAA_JITTER` (Off/Subtle/Standard/Strong) in `[Post-Processing & Fog]` for full sub-pixel reconstruction; `TAA_STRENGTH` presets the variance-clip tightness.
> 🗺️ **Distant Horizons:** experimental, **partial** DH support (dh_terrain/water/shadow, introduced in v1.1.2; v1.1.3 adds a soft screen-door seam at the vanilla↔DH boundary). LOD chunks now render and respect lighting/fog/shadow, but without full PBR maps and with hardcoded skylight. Consider it WIP, not full compatibility yet.

***

## 📄 License & Compatibility

*   **AuraLite** is licensed under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License](LICENSE) (CC BY-NC-SA 4.0).
*   **Copyright (c) 2026 AlexanderNyr.**
*   **Officially Supported Platform:** Minecraft **1.16.5 – 26.2** with **Sodium + Iris** or **OptiFine** loader.
*   _Note: Verified to work flawlessly on Minecraft 1.16.5, 1.20.1, 1.21.1, and 26.1.2._
*   **Distant Horizons:** v1.1.3 continues **experimental, partial** DH support (WIP, introduced in v1.1.2) — `dh_terrain`, `dh_water`, `dh_shadow` minimal passes to prevent Iris from hiding LOD chunks, now with a soft screen-door seam at the vanilla↔DH boundary. Provides fog rescaling, depth reconciliation, overdraw culling, emissive/heat-shimmer for distant lava. Still **NOT** full support: no LabPBR maps for DH, hardcoded full skylight, no POM — full compatibility will be announced separately when ready.

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
