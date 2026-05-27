# 🌌 AuraLite Shaders (Minecraft 1.20.1)

[![Minecraft Version](https://img.shields.io/badge/Minecraft-1.20.1-blue?logo=minecraft&logoColor=white)](https://modrinth.com/)
[![Shader Loader](https://img.shields.io/badge/Loader-Iris%20%2F%20Sodium-green)](https://modrinth.com/)
[![API Standard](https://img.shields.io/badge/API-OpenGL%204.6%20%2F%20GLSL%20460-orange)](https://khronos.org/)
[![Materials Standard](https://img.shields.io/badge/PBR-LabPBR%201.3-cyan)](https://github.com/rre36/lab-pbr)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**AuraLite** is a modern, lightweight, and highly optimized shader pack built on top of the **OpenGL 4.6 / GLSL 460** standard. It is specifically designed and **exclusively tested for Minecraft 1.20.1 with Sodium + Iris** (and compatible with **OptiFine 1.20.1**). 

AuraLite delivers a breathtaking, realistic visual experience without overcomplicating the screen with bloated post-processing effects (such as aggressive motion blur, heavy bloom, or screen-space reflections), ensuring **maximum FPS and smooth frametimes** on modern GPUs.

---

## ✨ Features At A Glance

### ☁️ 1. Meteorological 3D Volumetric Clouds (Fly-Through!)
AuraLite features a fully physical, flyable 3D cloud system driven by **10-step Raymarching** in world coordinates:
* **True 3D Space:** Clouds float at a physical height (Y-level 160m to 240m). You can fly up, enter a dense, foggy overcast, and rise above the clouds to see an endless rolling sea of fluffy cumulus clouds.
* **Beer's Law Self-Shadowing:** Realistic light absorption makes cloud bottoms dense and dark while cloud tops glow with brilliant white/gold illumination.
* **Mie Scattering (Silver Lining):** Looking towards the sun produces a glowing golden halo around the cloud edges.
* **Overcast Storms:** When raining (`/weather rain`), the fluffy cumulus clouds automatically expand, darken, and merge into an ominous, heavy **Nimbostratus/Cumulonimbus** storm deck.

### ☀️ 2. Analytical Kelvin Temperature & Beer-Lambert Sunlight
* **Analytical Kelvin Temperature Color Model:** Sunlight color temperature is dynamically calculated in real-time based on the sun's elevation angle $\alpha$ using the scientific curve:  
  $K(\alpha) = 1800 + 4000 \cdot \sin(\alpha)^{0.5}$  
  This provides photorealistic sunset/sunrise colors (**1800K - 2200K**), warm golden hours (**2800K**), and clean crisp white noon light (**5700K - 5800K**).
* **Beer-Lambert Atmospheric Extinction:** Sunlight intensity dynamically drops as the sun approaches the horizon due to scattering in thick atmospheric masses:  
  $airMass = \frac{1}{\sin(\alpha) + 0.15 \cdot (\alpha_{deg} + 3.885)^{-1.253}}$  
  This yields incredibly soft, rich, and breathtaking sunset and sunrise golden hour transitions!
* **Crispy Circular Sun & Moon Disks:** Custom procedural, perfectly round, anti-aliased sun and moon disks are drawn onto the sky dome with glowing coronas and soft halo scattering.

### 👥 3. Soft Shadows & Immersive Dark Nights
* **Soft PCF Shadows:** Beautifully smoothed shadows utilizing a **3x3 PCF (Percentage-Closer Filtering)** kernel on a high-resolution shadow map (2048x2048).
* **Deep Dark Nights (2x Darker):** Night ambient light, moonlight intensity, and fog have been reduced by 2x to create an incredibly atmospheric, immersive, and dark night. Caves and forests are pitch dark, requiring torches for exploration.
* **Warm Block Lights:** Torches, lanterns, and lava emit a cozy golden-amber glow with physically accurate quadratic falloff.

### 🌊 4. Physical Fresnel Water & Silver Moonlight Path
* **Fresnel Effect:** Water reflectivity is mathematically calculated based on your viewing angle. Looking straight down provides crystal transparency, while looking towards the horizon transitions water into a highly reflective, glossy sheet reflecting the sky dome.
* **Silver Moonlight Path:** Moonlight specular reflection on water ripples has been increased by **4.5x**. At midnight, a brilliant silver lunar reflection path shimmers across the waving ocean.
* **3D Geometric Waves:** Vertex shader waves physically displace the water mesh in real-time.
* **Zero Feedback Glitches:** Designed to be extremely stable, utilizing no feedback-loop depth buffer reads to guarantee bug-free solid rendering on all GPUs.

### 🌿 5. Lively Foliage
* Waving animations for oak/spruce/birch leaves, tall grass, flowers, vines, lily pads, and crops.
* Gently animated using hardware-optimized sine waves and time constants.

### 💎 6. Full LabPBR 1.3 Material Support
* **3D Normal Maps:** Real-time **TBN (Tangent-Binormal-Normal)** matrices generate true three-dimensional depth on blocks (stone crevices, brick joints) reacting dynamically to light angles.
* **Specular Reflection (GGX Microfacet):** Polished surfaces give sharp glossy glints, while metallic surfaces (gold, copper, iron) tint the specular reflection with the block's native albedo.
* *Seamless Fallback:* Falls back automatically to gorgeous flat vanilla textures if no PBR resource pack is active.

### 🎬 7. Cinematic Post-Processing
* **ACES Filmic Tonemapping:** The industry-standard color grading algorithm prevents overexposure on bright blocks (sand, snow) while retaining rich shadow details.
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

---

## 📥 Installation

1. Download **`AuraLite_ShaderPack.zip`** from the [Releases]() section on the right.
2. Open your Minecraft directory (e.g. `%appdata%/.minecraft` on Windows).
3. Place the downloaded `.zip` file inside the **`shaderpacks`** folder (Do **not** unzip it!).
4. Launch Minecraft **1.20.1** using a profile with **Sodium + Iris** or **OptiFine** installed.
5. In-game, go to **Options -> Video Settings -> Shader Packs**, select **AuraLite**, and click **Apply**.

---

## 🎛️ In-Game Configuration Options

AuraLite includes a fully translated Russian & English in-game configuration menu:
* **`[Lighting Settings]`**
  * **Dynamic Shadows:** Toggle sun/moon shadows.
  * **Shadow Resolution:** [1024 / 2048 / 4096]
  * **Torch Warmth:** [Cozy / Warm / Intense] - Customize block light warmth.
  * **PBR Lighting:** Toggle PBR specular reflections and normal mapping.
  * **PBR Intensity:** [Subtle / Standard / Mirror]
* **`[Foliage Settings]`**
  * **Waving Leaves:** Toggle leaves animation.
  * **Waving Foliage:** Toggle grass, flowers, and crops animation.
  * **Wind Speed:** [Gentle / Breeze / Gale]
* **`[Water Settings]`**
  * **Water Waves:** Toggle 3D vertex water waves.
  * **Water Density:** [Clear / Balanced / Deep] - Adjust water transparency.
* **`[3D Clouds Settings]`**
  * **Volumetric 3D Clouds:** Toggle raymarched clouds.
  * **Cloud Altitude:** [Low (~110m) / Standard (~160m) / High (~240m)]
  * **Cloud Thickness:** [Thin / Standard / Dense]
* **`[Post-Processing & Fog]`**
  * **Fog Density:** [Low / Medium / High] - Adjust horizon mist.
  * **Exposure Brightness:** [Muted / Balanced / Vibrant] - Adjust screen lighting levels.
  * **Vignette:** Toggle cinematic corner darkening.

---

## 📄 License & Compatibility

* **AuraLite** is open-source and licensed under the [MIT License](LICENSE).
* **Officially Supported Platform:** Minecraft **1.20.1** with **Sodium + Iris** or **OptiFine** loader.
* *Note: Other Minecraft versions are not officially tested at this stage.*
