# 🌌 AuraLite Shaders (Minecraft 1.16.5 – 26.1.2)

[![Minecraft Version](https://img.shields.io/badge/Minecraft-1.16.5%20--%2026.1.2-blue?logo=minecraft&logoColor=white)](https://modrinth.com/)
[![Shader Loader](https://img.shields.io/badge/Loader-Iris%20%2F%20Sodium-green)](https://modrinth.com/)
[![API Standard](https://img.shields.io/badge/API-OpenGL%204.6%20%2F%20GLSL%20460-orange)](https://khronos.org/)
[![Materials Standard](https://img.shields.io/badge/PBR-LabPBR%201.3-cyan)](https://github.com/rre36/lab-pbr)
[![Version](https://img.shields.io/badge/Release-v0.2.7-purple)](https://github.com/AlexanderNyr/AuraLite-Shaders)
[![License](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/)

> 🌐 **Languages:** **English** · [Русский](README_RU.md)

**AuraLite** is a modern, lightweight, and highly optimized shader pack built on top of the **OpenGL 4.6 / GLSL 460** standard. It is specifically designed and **tested for Minecraft 1.16.5 – 26.1.2 with Sodium + Iris** (and compatible with **OptiFine**).

AuraLite delivers a breathtaking, realistic visual experience without overcomplicating the screen with bloated post-processing effects (such as aggressive motion blur, heavy bloom, or screen-space reflections), ensuring **maximum FPS and smooth frametimes** on modern GPUs.

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
* **Localization expanded** — now maintained as **59 language files**, including major regional variants and compatibility aliases such as `fil_ph` and legacy `tl_ph`.

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
* 🧊 **Ice Glitch Fix** — dedicated block ID disables waving/refraction on ice variants to eliminate visual artifacts.
* 🌙 **Moon-Phase Aware Sky** — sky shading reacts to `moonPhase` and `dimension` for nether/end correctness.

> Source for every version is shipped in this repo under [`shaders v0.2.0/`](shaders%20v0.2.0) through [`shaders v0.2.7/`](shaders%20v0.2.7). End users should grab the packaged release ZIP from [Releases](https://github.com/AlexanderNyr/AuraLite-Shaders/releases).

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
* 🧊 **Ice fix** *(since v0.2.0)*: ice / packed ice / blue ice / frosted ice are tagged with a dedicated block ID to disable waving and refraction, eliminating long-standing visual glitches.

### 💎 8. Full LabPBR 1.3 Material Support + POM — *PBR refined in v0.2.5*
* **3D Normal Maps:** Real-time **TBN (Tangent-Binormal-Normal)** matrices generate true three-dimensional depth on blocks (stone crevices, brick joints) reacting dynamically to light angles.
* **Specular Reflection (GGX Microfacet):** Polished surfaces give sharp glossy glints, while metallic surfaces (gold, copper, iron) tint the specular reflection with the block's native albedo. *(v0.2.5: correct NdotL cosine factor added for Cook-Torrance BRDF accuracy.)*
* 🧱 **Parallax Occlusion Mapping (POM)** *(since v0.2.0)*: True per-pixel block relief that pops out of the surface. Configurable `POM_DEPTH` (1–3) and `POM_STEPS` (1–4). Disabled in all profiles by default for stability; can be enabled manually. Recommended to keep off on incompatible resource packs.
* *Seamless Fallback:* Falls back automatically to gorgeous flat vanilla textures if no PBR resource pack is active.

### 🌀 9. Cosmic Nether Portal *(since v0.2.0, improved in v0.2.5)*
The vanilla Nether portal texture is procedurally transformed into a **swirling 3D plasma vortex** — animated purple/magenta cosmic energy that pulses with hypnotic depth. Mapped via dedicated block ID `10006` in `block.properties`. *(v0.2.5: portal pixels are flagged as emissive so composite skips scene lighting and displays the plasma as-is.)*

### 🎬 10. Cinematic Post-Processing
* **Multiple Tone Mapping Curves** *(since v0.2.0)*: Pick from **Soft**, **Filmic (ACES)**, or **Intense (High Contrast)** to match your preferred mood.
* **Color Vibrancy** *(since v0.2.0)*: 4-step non-linear saturation control (*Muted / Balanced / Colorful / Vivid*) that makes foliage glow emerald and skies look lush, without crushing skin tones.
* **Exposure Brightness:** Muted / Balanced / Vibrant — global brightness lift.
* **Subtle Vignette:** Gentle lens-darkening at screen edges for improved depth and immersion.

### 🛡️ 11. Realistic Atmospheric Fog *(v0.2.5)*
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
* **Hardware FMA (Fused Multiply-Add):** All wave and waving foliage math is compiled into native single-cycle hardware operations (`fma`), reducing GPU execution cycles.
* **Bitwise Noise Generation:** Replacing slow transcendental float functions (`fract(sin(dot(...)))`) with ultra-fast **Integer Bitwise PCG-style hashes** utilizing `floatBitsToUint` and `uintBitsToFloat`.
* **Early-Ray Termination:** Volumetric raymarching terminates instantly once cloud transmittance falls below 2%, saving rendering power.
* **No Hand Transparency Glitches:** Handheld items, particles, and mobs are rendered in a separate stable path without tangent matrix overhead, eliminating "translucent hand" bugs.
* **Dead Code Elimination** *(v0.2.3–v0.2.5)*: Removed unused noise/fbm functions, dead cloud raymarching code from `gbuffers_skybasic`, and redundant render calls to reduce GPU compilation time.
* **Profile-Based Scaling:** Every feature (POM, Auroras, SSAO, Cozy Lights, Wet Reflections, Ground Mist, Shadow Distance, Cloud Distance, Sun Halo, etc.) is intelligently distributed across the **LOW / MED / HIGH / ULTRA / EXTREME** profiles so low-end systems don't pay for effects they can't afford.

---

## 📥 Installation

1. Download **`AuraLite-Shaders-v0.2.7.zip`** from the [Releases](https://github.com/AlexanderNyr/AuraLite-Shaders/releases) section on the right.
2. Open your Minecraft directory (e.g. `%appdata%/.minecraft` on Windows).
3. Place the downloaded `.zip` file inside the **`shaderpacks`** folder (Do **not** unzip it!).
4. Launch a supported Minecraft version (**1.16.5 – 26.1.2**) using a profile with **Sodium + Iris** or **OptiFine** installed.
5. In-game, go to **Options → Video Settings → Shader Packs**, select **AuraLite**, and click **Apply**.

> 💡 The repository ships source folders for every release snapshot: `shaders v0.2.0/` through `shaders v0.2.7/`. The current version is **v0.2.7**. End users should grab the packaged release ZIP; developers can browse any folder directly.

---

## 🎛️ In-Game Configuration Options

AuraLite includes localized in-game configuration files for **59 language codes**, including major European, Asian, American regional variants and compatibility aliases such as `fil_ph` / `tl_ph`.

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

### `[Water Settings]`
* **Water Waves** — Toggle 3D vertex water waves.
* **Water Density** — `Clear / Balanced / Deep` — Adjust water transparency.
* **Water Ripple Strength (`WATER_RIFFLES`)** — `Calm / Standard / Choppy` — Fine normal-map ripples.
* **Water Specular Glow (`WATER_SPECULAR_STRENGTH`)** — `Soft / Standard / Glinting` — Brightness of sun/moon highlights on the ripples.

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
* **Rainbow Intensity** — `Subtle / Balanced / Vivid` — Post-rain rainbow arc.

### `[Post-Processing & Fog]`
* **Fog Density** — `Low / Medium / High` — Atmospheric horizon mist.
* **Low Ground Mist (`GROUND_MIST`)** — Realistic dawn/evening radiation fog at Y ≈ 60–70.
* **Exposure Brightness** — `Muted / Balanced / Vibrant`
* **Color Vibrancy (`COLOR_SATURATION`)** — `Muted / Balanced / Colorful / Vivid`
* **Image Contrast (`CONTRAST`)** — `Soft / Filmic (ACES) / Intense (High Contrast)` — Choose the tone mapping curve.
* 🆕 **Temporal Anti-Aliasing (`TAA`)** *(v0.2.7)* — motion-reprojected temporal resolve for high presets.
* 🆕 **TAA Strength** *(v0.2.7)* — `Light / Balanced / Stable`.
* **Vignette** — Toggle cinematic corner darkening.
* (Hidden) **Rain Wetness Reflections (`WET_REFLECTIONS`)** — Wet glossy ground during rain (enabled by default in MED+ profiles).

### 🎚️ Quality Profiles (v0.2.7)

| Profile      | Target          | Shadows | Clouds | Cloud Shadows | Godrays | TAA | PBR | SSAO | Heavy Extras |
|--------------|-----------------|---------|--------|---------------|---------|-----|-----|------|--------------|
| **VERY_LOW** | Maximum FPS     | ❌      | ❌     | ❌            | ❌      | ❌  | ❌  | ❌   | Most extras off |
| **LOW**      | Weak GPUs       | ❌      | ❌     | ❌            | ❌      | ❌  | ❌  | ❌   | Cheap water/foliage motion only |
| **MED**      | Balanced        | ✅ 1024 | ✅ Near/Standard | ✅ Soft | ❌ | ❌ | ✅ Subtle | ❌ | Wet reflections + ground mist |
| **HIGH**     | High quality    | ✅ 2048 | ✅ Far | ✅ Balanced | ✅ Fast | ✅ Light | ✅ Standard | ❌ | Full atmosphere without SSAO |
| **ULTRA**    | Very high       | ✅ 4096 | ✅ Very Far | ✅ Balanced | ✅ Balanced | ✅ Balanced | ✅ Strong | ✅ Balanced | High-end visuals |
| **EXTREME**  | Maximum quality | ✅ 4096 | ✅ Dense/Very Far | ✅ Dramatic | ✅ High | ✅ Stable | ✅ Strong | ✅ Deep | Heaviest cinematic preset |

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
