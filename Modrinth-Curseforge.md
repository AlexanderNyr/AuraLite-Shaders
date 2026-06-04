# 🌌 AuraLite Shaders

**AuraLite** is a modern, lightweight, and highly optimized Minecraft shader pack built around **OpenGL 4.6 / GLSL 460**. It is designed and tested for **Minecraft 1.16.5 – 26.1.2** with **Sodium + Iris**, and is also compatible with **OptiFine**.

AuraLite focuses on realistic lighting, atmosphere, water, and materials without relying on bloated post-processing such as aggressive motion blur or heavy bloom. Optional effects like **FXAA/SMAA anti-aliasing**, **SSR**, **TAA**, **godrays**, and **SSAO** are scaled through quality profiles, keeping the image cinematic but clean with strong FPS and stable frametimes.

---

> ℹ️ **Historical note:** older changelog recaps below are preserved for reference, but this description now reflects the current **v1.0.3** release.

## 🆕 What's New in v1.0.3 — Anti-Aliasing & PBR Performance

Version **1.0.3** adds configurable spatial anti-aliasing and a PBR render distance control for better performance on large render distances.

### 🖼️ Spatial Anti-Aliasing (FXAA / SMAA)

* **`SPATIAL_AA_MODE`** — new toggle in the `[Post-Processing]` menu:
  * **Off** — no spatial AA (TAA-only or nothing).
  * **FXAA** — Fast Approximate AA. Sobel gradient-directed edge detection with conservative blend. Cheap and effective.
  * **SMAA** — Subpixel Morphological AA. Combines luminance gradient with depth discontinuity detection for geometry edges where luma contrast is low. Better quality than FXAA, slightly more cost.
* Both modes use conservative weights (max 0.15–0.18) to avoid washing out the image.
* Freely combinable with TAA for temporal + spatial smoothing.
* Profile defaults: VERY_LOW=Off, LOW/MED=FXAA, HIGH/ULTRA/EXTREME=SMAA.

### ⚡ PBR Render Distance

* **`PBR_DISTANCE`** — new setting in `[Lighting Settings]`:
  * **Near (16m)** — PBR only on close surfaces. Maximum savings.
  * **Standard (48m)** — balanced. Default for LOW/MED.
  * **Far (128m)** — extended range. Default for HIGH/ULTRA.
  * **Unlimited** — no distance limit. EXTREME only.
* Beyond the fade range, the entire Cook-Torrance BRDF block (GGX + Smith + Fresnel) is completely skipped — no wasted GPU on sub-pixel specular.

---

## 🆕 What's New in v1.0.2 — Foliage Subsurface Scattering (SSS)

Version **1.0.2** adds realistic **subsurface scattering (SSS)** for vegetation. Leaves, grass, and plants now look more translucent and alive when light shines through them.

### 🌿 Foliage Subsurface Scattering (`FOLIAGE_SSS`)

* New toggle in the `[Foliage Settings]` menu.
* Light bleeding from the back side of foliage + soft wrap term on the unlit side.
* Enabled from **MED** profile upward by default (disabled on VERY_LOW/LOW for maximum FPS).
* Integrated with existing PBR pipeline using material ID tagging (`matID` 10001–10004) in `gbuffers_terrain`.
* Full English and Russian localization.

---

## 🆕 What's New in v1.0.1 — Hotfix: Refraction, AgX Tone Map & Stability

Version **1.0.1** is a hotfix release that introduces screen-space water refraction, a new photographic tone mapping curve, and fixes several rendering edge cases discovered after the v1.0.0 launch.

### 🌊 Screen-Space Water Refraction

* **Physically-plausible underwater distortion** — when looking at water from above, the scene behind the water surface is read through a displaced UV derived from the wave normal.
* **Snell's law approximation** — refraction strength follows `(1 − N·V)`: strongest at shallow grazing angles, vanishing when looking straight down.
* **Shared wave normal with SSR** — the refraction pass computes the water normal once, and SSR reuses it, eliminating redundant work.

### 🎬 Photographic (AgX-like) Tone Mapping

* **New `CONTRAST=4` option** — a sigmoidal tone curve inspired by AgX / Filmlight that naturally desaturates highlights as they approach clipping.
* **EXTREME profile default** — the heaviest cinematic preset now uses `CONTRAST=4` for filmic highlight rolloff.

### ✨ Subtle HDR Bloom

* **Single-pass neighbour bloom** — pixels whose post-exposure luminance exceeds a threshold receive a soft 3×3 glow. Affects sun/moon disks, lava, portals, bright specular, and torches without smearing the entire scene.

### 🛠️ Bug Fixes

* **TAA history acceptance** — reject uninitialized history samples to prevent smearing during the first frames after shader reload.
* **Vibrancy math** — negative saturation amounts now properly oversaturate.
* **SSR normal NaN guard** — zero-length normals no longer produce undefined reflection directions.
* **SSR near-field precision** — lowered minimum ray step for better hit rate on nearby surfaces.
* **Meteor moon-brightness curve** — consistent moon phase brightness model.

---

## 🆕 What's New in v1.0.0 — Meteor Showers & Finalized Reflection Pipeline

Version **1.0.0** introduces a physically-inspired meteor system to the night sky, finalizes the modern SSR path for reliable Iris compatibility, and refreshes project metadata.

### ☄️ Physically-Based Meteors / Falling Stars

* **True great-circle sky arcs** — meteors converge toward a shared radiant like real meteor photography.
* **Ablation-based brightness curve** — each meteor rises, peaks, and fades inspired by atmospheric entry.
* **Blackbody plasma coloring** — physically consistent warm-to-white fireball tones.
* **Moonlight washout and weather attenuation** — faint meteors suppressed by bright moon phases, rain, and daytime.
* **Persistent trains on bright fireballs** — short-lived glowing ionization trails.
* **Available in both Overworld and The End.**

### 🪞 Finalized SSR / Water Reflection Path

* **`colortex6` removed** — `final.fsh` reads normals from `colortex2` and roughness from `colortex1`.
* **Depth-based water detection** — water identified by comparing `depthtex0` and `depthtex1`.
* **More stable water normals** — reconstructed from depth-buffer derivatives.

---

## 🆕 Recap — Volumetric Aurora (v0.3.0), SSR & Waves (v0.2.9), Dimension Upgrades (v0.2.8)

<details>
<summary>📖 Click to expand older changelog</summary>

### v0.3.0 — Volumetric Aurora Realism
* Raymarched aurora curtains with visible height and depth.
* Distinct vertical pillars, sharper lower edge, softer upper fade.
* More vivid photographic colors (cyan-green, magenta/purple).

### v0.2.9 — Working SSR, Realistic Waves & True Night Underwater
* Loader-agnostic SSR pipeline. Bulletproof water detector via depth comparison.
* 4-octave fBm wave system with analytic gradients.
* `UNDERWATER_NIGHT_DARKNESS`: Moonlit Pool / Dim / True Night / Pitch Dark.

### v0.2.8 — Dimension Upgrades & Physics Fixes
* Crystal-Clear End (no fog/clouds). Dynamic Nether biome atmospheres.
* `worldTime` overflow protection. Cook-Torrance BRDF alignment for Nether/End.

### v0.2.7 — TAA, Godrays, Cloud Shadows
* Conservative TAA with motion reprojection and neighborhood clipping.
* Physically-inspired volumetric godrays with HG/Mie phase function.
* Transparent procedural cloud shadows on terrain.

### v0.2.5–v0.2.6 — License (CC BY-NC-SA 4.0), Cloud Overhaul, SSAO, EXTREME Profile
* Camera-stable cloud sampling, independent wind-shear layers.
* SSAO/SAO contact occlusion. Weather-aware PCSS soft shadows.
* Realistic atmospheric fog with altitude and horizon path.

</details>

---

## 🎚️ Quality Profiles (v1.0.3)

| Profile | Target | AA | PBR Dist | TAA | SSR | Cloud Shadows | Godrays | SSAO | SSS |
|---|---|---|---|---|---|---|---|---|---|
| **VERY_LOW** | Maximum FPS | Off | 16m | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **LOW** | Weak GPUs | FXAA | 48m | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **MED** | Balanced | FXAA | 48m | ❌ | ❌ | ✅ Soft | ❌ | ❌ | ✅ |
| **HIGH** | High quality | SMAA | 128m | ✅ Light | ✅ Fast | ✅ Balanced | ✅ Fast | ❌ | ✅ |
| **ULTRA** | Very high | SMAA | 128m | ✅ Balanced | ✅ Balanced | ✅ Balanced | ✅ Balanced | ✅ Balanced | ✅ |
| **EXTREME** | Max quality | SMAA | ∞ | ✅ Stable | ✅ High | ✅ Dramatic | ✅ High | ✅ Deep | ✅ |

---

## ✨ Main Features

### 🖼️ Spatial Anti-Aliasing *(new in v1.0.3)*
* FXAA (Fast Approximate AA) — Sobel gradient-directed edge smoothing.
* SMAA (Subpixel Morphological AA) — luma + depth edge detection for geometry edges.
* Conservative blend weights preserve image sharpness.
* Combinable with TAA for temporal + spatial smoothing.

### ⚡ PBR Render Distance *(new in v1.0.3)*
* Cook-Torrance BRDF skipped beyond configurable distance (16m / 48m / 128m / Unlimited).
* Smooth `smoothstep` fade — no visible pop-in.
* Significant GPU savings on large render distances.

### 🌿 Foliage Subsurface Scattering *(v1.0.2)*
* Realistic translucency for leaves and plants.
* Light bleeding + soft wrap term when looking toward the sun.

### 🌊 Screen-Space Water Refraction *(v1.0.1)*
* Snell's-law-approximated distortion of the underwater scene.
* Shared wave normal computation with SSR.

### 🎬 Photographic (AgX-like) Tone Mapping *(v1.0.1)*
* Sigmoidal curve with natural highlight desaturation.
* Available as `CONTRAST=4`, default for EXTREME profile.

### ☄️ Physically-Based Meteors *(v1.0.0)*
* Great-circle meteor arcs. Shared-radiant showers.
* Moonlight washout, rain attenuation, persistent trains.
* Visible in Overworld and End.

### 🌌 Volumetric Aurora Borealis *(v0.3.0)*
* Raymarched aurora volume. Photographic cyan-green and magenta palette.
* Cold-biome mode, weather attenuation, speed and brightness controls.

### 🪞 Screen-Space Reflections *(v0.2.9+)*
* Working SSR on Iris 1.20+ and OptiFine.
* Depth-comparison water detector. Schlick Fresnel F0 = 0.02.
* Adaptive view-space raymarcher with binary refinement. 3 quality levels.

### 🌊 Procedural Water Waves *(v0.2.9)*
* 4-octave fBm with analytic gradients. `WATER_WAVE_SCALE` and `WATER_WAVE_DETAIL`.

### 🌑 True Underwater Night *(v0.2.9)*
* Underwater brightness follows day/night cycle. 4 darkness levels.

### ☁️ Volumetric 3D Clouds
* Fly-through raymarched clouds. Configurable altitude and thickness.
* Independent wind-shear per layer. Render distance 3 000 m – 16 000 m.
* Camera-inside-cloud veil. Storm transitions. Cloud self-shadowing.

### 🌠 Living Night Sky
* Volumetric aurora, Milky Way nebula, procedural stars, meteors, post-rain rainbows.

### ☀️ Kelvin Sun & Moon Lighting
* Tanner Helland blackbody color. Beer-Lambert atmospheric extinction.
* Independent brightness and color temperature controls for sun and moon.

### 👥 Shadows and Ambient
* Dynamic shadows (1024 / 2048 / 4096). Poisson-disk PCSS with weather-aware softness.
* Shadow distance up to 160m. Shadow tint, ambient lift, SSAO on high presets.

### 💎 LabPBR Support
* Normal maps, roughness, metalness. Cook-Torrance GGX specular with distance fade.
* Optional Parallax Occlusion Mapping (disabled by default for stability).

### 🌀 Cosmic Nether Portal
* Procedural purple/magenta plasma vortex, emissive-lit.

### 🎬 Post-Processing
* 4 tone mapping curves: Soft, ACES Filmic, Intense, Photographic (AgX-like).
* FXAA / SMAA spatial AA. TAA on high presets. Exposure, vibrancy, vignette, subtle HDR bloom.

---

## ⚙️ Performance Philosophy

* **VERY_LOW / LOW** — usable on weak GPUs. PBR off, no shadows, FXAA or no AA.
* **MED** — core atmosphere without expensive extras. FXAA enabled.
* **HIGH** — SSR, godrays, TAA, SMAA, PBR distance 128m.
* **ULTRA** — balanced SSAO, high-quality SSR, SMAA.
* **EXTREME** — heaviest cinematic settings, AgX tone mapping, unlimited PBR distance.

---

## 📥 Installation

1. Download **`AuraLite-Shaders-v1.0.3.zip`** from Modrinth, CurseForge, or GitHub Releases.
2. Open your Minecraft folder:
   * Windows: `%appdata%\.minecraft`
   * Linux: `~/.minecraft`
   * macOS: `~/Library/Application Support/minecraft`
3. Put the `.zip` file into the `shaderpacks` folder.
4. Do **not** unzip it.
5. Launch a supported Minecraft version with **Iris + Sodium** or **OptiFine**.
6. Select AuraLite in the shader pack menu.

---

## 🌐 Localization

AuraLite ships **59 language files**, including regional variants and compatibility aliases.

English and Russian are fully updated for the latest AA/PBR distance/SSR/water/aurora/meteor/refraction/SSS options. Other languages may fall back to English labels for newer settings.

---

## 📦 Shaderpack ZIP Layout

```text
AuraLite-Shaders-v1.0.3.zip
└── shaders/
    ├── composite.fsh
    ├── composite1.fsh
    ├── composite2.fsh
    ├── final.fsh
    ├── gbuffers_*.fsh / .vsh
    ├── shaders.properties
    └── lang/
        └── 59 language files
```

---

## 📄 License & Permissions

AuraLite is licensed under **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International**.

* Videos and streams are allowed, including monetized videos.
* Free modpacks on Modrinth / CurseForge are allowed.
* Personal modifications are allowed.
* **Commercial redistribution, paid reuploads, and ad-link rehosting are not allowed.**
* Public modified versions must remain free, open-source, and licensed under the same CC BY-NC-SA 4.0 license with attribution.

**Copyright (c) 2026 AlexanderNyr.**

### 🌐 Official Sources

* GitHub: [https://github.com/AlexanderNyr/AuraLite-Shaders](https://github.com/AlexanderNyr/AuraLite-Shaders)
* Modrinth: [https://modrinth.com/shader/auralite-shaders](https://modrinth.com/shader/auralite-shaders)
* CurseForge: [https://www.curseforge.com/minecraft/shaders/auralite-shaders](https://www.curseforge.com/minecraft/shaders/auralite-shaders)
