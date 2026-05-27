# 🌌 AuraLite Shaders (Minecraft 1.20.1)

[![Minecraft Version](https://img.shields.io/badge/Minecraft-1.20.1-blue?logo=minecraft&logoColor=white)](https://modrinth.com/)
[![Shader Loader](https://img.shields.io/badge/Loader-Iris%20%2F%20Sodium-green)](https://modrinth.com/)
[![API Standard](https://img.shields.io/badge/API-OpenGL%204.6%20%2F%20GLSL%20460-orange)](https://khronos.org/)
[![Materials Standard](https://img.shields.io/badge/PBR-LabPBR%201.3-cyan)](https://github.com/rre36/lab-pbr)
[![Version](https://img.shields.io/badge/Release-v0.2.0-purple)](https://github.com/AlexanderNyr/AuraLite-Shaders)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**AuraLite** is a modern, lightweight, and highly optimized shader pack built on top of the **OpenGL 4.6 / GLSL 460** standard. It is specifically designed and **exclusively tested for Minecraft 1.20.1 with Sodium + Iris** (and compatible with **OptiFine 1.20.1**).

AuraLite delivers a breathtaking, realistic visual experience without overcomplicating the screen with bloated post-processing effects (such as aggressive motion blur, heavy bloom, or screen-space reflections), ensuring **maximum FPS and smooth frametimes** on modern GPUs.

---

## 🆕 What's New in v0.2.0

Version **0.2.0** is a major content update that nearly doubles the pack's visual feature set (≈ +900 lines of shader code) while keeping the same lightweight philosophy:

* 🌠 **Night Sky Overhaul** — flowing **Aurora Borealis**, a diagonal **Milky Way nebula**, configurable **stars density & brightness**, and an animated **post-rain rainbow** that lingers as wetness decays.
* 🌧️ **Dynamic Weather Surfaces** — **Wet Reflections** on solid ground during rain, support for `thunderStrength` to separate thunderstorms from light showers.
* 🌫️ **Golden Ground Mist (Y = 62–66)** — soft, golden-white morning/evening fog sheets that drift over water and ice at dawn and dusk.
* 🕯️ **Cozy Light Flickering** — real-time warm flicker animations for torches, campfires, and lanterns. Held-item light is also taken into account.
* 🧱 **Parallax Occlusion Mapping (POM)** — true 3D block relief on LabPBR resource packs, with configurable depth and step count.
* 🌊 **Granular Water Tuning** — separate sliders for **ripple strength** (`WATER_RIFFLES`) and **specular glow** (`WATER_SPECULAR_STRENGTH`).
* 🎨 **New Post-Processing Pipeline** — 4-step **Color Vibrancy** saturation and 3 tone-mapping curves (**Soft / Filmic ACES / Intense**).
* 🌀 **Cosmic Nether Portal** — vanilla portal texture is replaced by a swirling 3D plasma vortex.
* 🧊 **Ice Glitch Fix** — dedicated block ID disables waving/refraction on ice variants to eliminate visual artifacts.
* 🌙 **Moon-Phase Aware Sky** — sky shading reacts to `moonPhase` and `dimension` for nether/end correctness.

> See the [Configuration Options](#%EF%B8%8F-in-game-configuration-options) section below for the full list of new toggles, or jump straight into [`shaders v0.2.0/`](shaders%20v0.2.0) for the source files.

---

## ✨ Features At A Glance

### ☁️ 1. Meteorological 3D Volumetric Clouds (Fly-Through!)
AuraLite features a fully physical, flyable 3D cloud system driven by **10-step Raymarching** in world coordinates:
* **True 3D Space:** Clouds float at a physical height (Y-level 160m to 240m). You can fly up, enter a dense, foggy overcast, and rise above the clouds to see an endless rolling sea of fluffy cumulus clouds.
* **Beer's Law Self-Shadowing:** Realistic light absorption makes cloud bottoms dense and dark while cloud tops glow with brilliant white/gold illumination.
* **Mie Scattering (Silver Lining):** Looking towards the sun produces a glowing golden halo around the cloud edges.
* **Overcast Storms:** When raining (`/weather rain`), the fluffy cumulus clouds automatically expand, darken, and merge into an ominous, heavy **Nimbostratus/Cumulonimbus** storm deck.

### 🌠 2. Living Night Sky *(new in v0.2.0)*
The night sky is no longer just a static starfield — it's a fully procedural cosmos:
* **Aurora Borealis:** Realistic, flowing northern lights that ripple across the upper sky. Modes: *Disabled / Only in Cold Biomes / Always Enabled*, with independent **speed** and **brightness** controls.
* **Milky Way Nebula:** A subtle diagonal brownish galactic band glows softly above the horizon, with adjustable brightness.
* **Procedural Stars:** Independent **brightness** and **density** sliders let you choose between a few crisp pinpricks or a brilliantly dense Hubble-style sky. Stars sparkle and twinkle in real time.
* **Persistent Rainbow:** After rain stops, a soft rainbow arcs across the sky and gently fades out as the `wetness` uniform decays. Brightness and saturation are configurable.

### ☀️ 3. Analytical Kelvin Temperature & Beer-Lambert Sunlight
* **Analytical Kelvin Temperature Color Model:** Sunlight color temperature is dynamically calculated in real-time based on the sun's elevation angle $\alpha$ using the scientific curve:  
  $K(\alpha) = 1800 + 4000 \cdot \sin(\alpha)^{0.5}$  
  This provides photorealistic sunset/sunrise colors (**1800K - 2200K**), warm golden hours (**2800K**), and clean crisp white noon light (**5700K - 5800K**).
* **Beer-Lambert Atmospheric Extinction:** Sunlight intensity dynamically drops as the sun approaches the horizon due to scattering in thick atmospheric masses:  
  $airMass = \frac{1}{\sin(\alpha) + 0.15 \cdot (\alpha_{deg} + 3.885)^{-1.253}}$  
  This yields incredibly soft, rich, and breathtaking sunset and sunrise golden hour transitions!
* **Crispy Circular Sun & Moon Disks:** Custom procedural, perfectly round, anti-aliased sun and moon disks are drawn onto the sky dome with glowing coronas and soft halo scattering.

### 👥 4. Soft Shadows, Immersive Dark Nights & Cozy Lights
* **Soft PCF Shadows:** Beautifully smoothed shadows utilizing a **3x3 PCF (Percentage-Closer Filtering)** kernel on a high-resolution shadow map (up to 4096x4096).
* **Deep Dark Nights (2x Darker):** Night ambient light, moonlight intensity, and fog have been reduced by 2x to create an incredibly atmospheric, immersive, and dark night. Caves and forests are pitch dark, requiring torches for exploration.
* **Warm Block Lights:** Torches, lanterns, and lava emit a cozy golden-amber glow with physically accurate quadratic falloff.
* 🕯️ **Cozy Torch Flickering** *(new in v0.2.0)*: Real-time flickering animations for torches, campfires, and lanterns add a living, warm atmosphere to your shelters. Held-item light contribution (`heldBlockLightValue`) is also accounted for.

### 🌊 5. Physical Fresnel Water & Silver Moonlight Path
* **Fresnel Effect:** Water reflectivity is mathematically calculated based on your viewing angle. Looking straight down provides crystal transparency, while looking towards the horizon transitions water into a highly reflective, glossy sheet reflecting the sky dome.
* **Silver Moonlight Path:** Moonlight specular reflection on water ripples has been increased by **4.5x**. At midnight, a brilliant silver lunar reflection path shimmers across the waving ocean.
* **3D Geometric Waves:** Vertex shader waves physically displace the water mesh in real-time, and now react to `rainStrength` / `thunderStrength` for choppier seas during storms.
* 🌊 **Independent Ripple & Specular Controls** *(new in v0.2.0)*: `WATER_RIFFLES` (Calm / Standard / Choppy) and `WATER_SPECULAR_STRENGTH` (Soft / Standard / Glinting) can now be tuned separately for the perfect water mood.
* **Zero Feedback Glitches:** Designed to be extremely stable, utilizing no feedback-loop depth buffer reads to guarantee bug-free solid rendering on all GPUs.

### 🌧️ 6. Dynamic Weather Surfaces *(new in v0.2.0)*
* **Wet Reflections:** During rain, solid blocks like grass, dirt, and stone darken and become glossy, picking up sky reflections under open weather. Disables itself under roofs.
* **Low Ground Mist (Y = 62–66):** Soft, golden-white fog sheets drift across water and ice surfaces at dawn and dusk — perfect for cinematic sunrise screenshots.
* **Thunderstorm Awareness:** Shaders distinguish between regular rain and full thunderstorms via the `thunderStrength` uniform, intensifying cloud darkness and wave chop accordingly.

### 🌿 7. Lively Foliage
* Waving animations for oak/spruce/birch leaves, tall grass, flowers, vines, lily pads, and crops.
* Gently animated using hardware-optimized sine waves and time constants.
* 🧊 **Ice fix** *(new in v0.2.0)*: ice / packed ice / blue ice / frosted ice are tagged with a dedicated block ID to disable waving and refraction, eliminating long-standing visual glitches.

### 💎 8. Full LabPBR 1.3 Material Support + POM
* **3D Normal Maps:** Real-time **TBN (Tangent-Binormal-Normal)** matrices generate true three-dimensional depth on blocks (stone crevices, brick joints) reacting dynamically to light angles.
* **Specular Reflection (GGX Microfacet):** Polished surfaces give sharp glossy glints, while metallic surfaces (gold, copper, iron) tint the specular reflection with the block's native albedo.
* 🧱 **Parallax Occlusion Mapping (POM)** *(new in v0.2.0)*: True per-pixel block relief that pops out of the surface. Configurable `POM_DEPTH` (1–3) and `POM_STEPS` (1–4). Disabled in the LOW/MED/HIGH profiles by default; enabled in ULTRA. Recommended to keep off on incompatible resource packs.
* *Seamless Fallback:* Falls back automatically to gorgeous flat vanilla textures if no PBR resource pack is active.

### 🌀 9. Cosmic Nether Portal *(new in v0.2.0)*
The vanilla Nether portal texture is procedurally transformed into a **swirling 3D plasma vortex** — animated purple/magenta cosmic energy that pulses with hypnotic depth. Mapped via dedicated block ID `10006` in `block.properties`.

### 🎬 10. Cinematic Post-Processing
* **Multiple Tone Mapping Curves** *(new in v0.2.0)*: Pick from **Soft**, **Filmic (ACES)**, or **Intense (High Contrast)** to match your preferred mood.
* **Color Vibrancy** *(new in v0.2.0)*: 4-step non-linear saturation control (*Muted / Balanced / Colorful / Vivid*) that makes foliage glow emerald and skies look lush, without crushing skin tones.
* **Exposure Brightness:** Muted / Balanced / Vibrant — global brightness lift.
* **Subtle Vignette:** Gentle lens-darkening at screen edges for improved depth and immersion.

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
* **Profile-Based Scaling:** New v0.2.0 features (POM, Auroras, Cozy Lights, Wet Reflections, Ground Mist) are intelligently distributed across the **LOW / MED / HIGH / ULTRA** profiles so low-end systems don't pay for effects they can't afford.

---

## 📥 Installation

1. Download **`AuraLite_ShaderPack.zip`** from the [Releases](https://github.com/AlexanderNyr/AuraLite-Shaders/releases) section on the right.
2. Open your Minecraft directory (e.g. `%appdata%/.minecraft` on Windows).
3. Place the downloaded `.zip` file inside the **`shaderpacks`** folder (Do **not** unzip it!).
4. Launch Minecraft **1.20.1** using a profile with **Sodium + Iris** or **OptiFine** installed.
5. In-game, go to **Options -> Video Settings -> Shader Packs**, select **AuraLite**, and click **Apply**.

> 💡 The repository ships two source folders: the legacy `shaders/` (v0.1) and the current `shaders v0.2.0/`. End users should grab the packaged release ZIP; developers can browse either folder directly.

---

## 🎛️ In-Game Configuration Options

AuraLite includes a fully translated **Russian & English** in-game configuration menu (`lang/ru_ru.lang`, `lang/en_us.lang`):

### `[Lighting Settings]`
* **Dynamic Shadows** — Toggle sun/moon shadows.
* **Shadow Resolution** — `1024 / 2048 / 4096`
* **Torch Warmth** — `Cozy / Warm / Intense` — Customize block light warmth.
* 🆕 **Torch Flickering (`COZY_LIGHTS`)** — Real-time flicker animations for torches, campfires, and lanterns.
* **PBR Lighting** — Toggle PBR specular reflections and normal mapping.
* 🆕 **3D Block Relief (POM)** — Enable Parallax Occlusion Mapping for true 3D block textures (LabPBR resource pack required).
* **PBR Intensity** — `Subtle / Standard / Mirror`

### `[Foliage Settings]`
* **Waving Leaves** — Toggle leaves animation.
* **Waving Foliage** — Toggle grass, flowers, and crops animation.
* **Wind Speed** — `Gentle / Breeze / Gale`

### `[Water Settings]`
* **Water Waves** — Toggle 3D vertex water waves.
* **Water Density** — `Clear / Balanced / Deep` — Adjust water transparency.
* 🆕 **Water Ripple Strength (`WATER_RIFFLES`)** — `Calm / Standard / Choppy` — Fine normal-map ripples.
* 🆕 **Water Specular Glow (`WATER_SPECULAR_STRENGTH`)** — `Soft / Standard / Glinting` — Brightness of sun/moon highlights on the ripples.

### `[Sky & Clouds]` *(renamed from "3D Clouds Settings")*
* **Volumetric 3D Clouds** — Toggle raymarched clouds.
* **Cloud Altitude** — `Low (~110m) / Standard (~160m) / High (~240m)`
* **Cloud Thickness** — `Thin (Cirrus) / Standard (Cumulus) / Dense (Stormy)`
* 🆕 **Aurora Borealis** — `Disabled / Only in Cold Biomes / Always Enabled`
* 🆕 **Aurora Speed** — `Slow / Standard / Fast`
* 🆕 **Aurora Brightness** — `Soft / Standard / Glowing`
* 🆕 **Milky Way Brightness** — `Dim / Standard / Bright`
* 🆕 **Stars Brightness** — `Faint / Standard / Brilliant`
* 🆕 **Stars Density** — `Few / Standard / Dense`
* 🆕 **Rainbow Intensity** — `Subtle / Balanced / Vivid` — Post-rain rainbow arc.

### `[Post-Processing & Fog]`
* **Fog Density** — `Low / Medium / High` — Atmospheric horizon mist.
* 🆕 **Low Ground Mist (`GROUND_MIST`)** — Golden-white fog sheets at Y = 62–66 during dawn/dusk.
* **Exposure Brightness** — `Muted / Balanced / Vibrant`
* 🆕 **Color Vibrancy (`COLOR_SATURATION`)** — `Muted / Balanced / Colorful / Vivid`
* 🆕 **Image Contrast (`CONTRAST`)** — `Soft / Filmic (ACES) / Intense (High Contrast)` — Choose the tone mapping curve.
* **Vignette** — Toggle cinematic corner darkening.
* (Hidden) 🆕 **Rain Wetness Reflections (`WET_REFLECTIONS`)** — Wet glossy ground during rain (enabled by default in MED+ profiles).

### 🎚️ Quality Profiles

| Profile | Shadows | Clouds | PBR | POM | Cozy Lights | Wet | Aurora | Stars / Milky Way | Tone Map |
|---|---|---|---|---|---|---|---|---|---|
| **LOW**   | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Off | — | Soft |
| **MED**   | ✅ 2048 | ✅ | ✅ | ❌ | ✅ | ✅ | Cold biomes | Standard | ACES |
| **HIGH**  | ✅ 4096 | ✅ | ✅ | ❌ | ✅ | ✅ | Cold biomes | Standard | ACES |
| **ULTRA** | ✅ 4096 | ✅ | ✅ | ✅ | ✅ | ✅ | Always   | Dense / Bright | Intense |

---

## 📄 License & Compatibility

* **AuraLite** is open-source and licensed under the [MIT License](LICENSE).
* **Officially Supported Platform:** Minecraft **1.20.1** with **Sodium + Iris** or **OptiFine** loader.
* *Note: Other Minecraft versions are not officially tested at this stage.*
