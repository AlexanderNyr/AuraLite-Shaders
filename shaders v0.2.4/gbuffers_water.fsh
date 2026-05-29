#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Water & Portal Fragment Shader (GLSL 460 Optimized)
// ==============================================================================
// [FIX v0.2.5] Changed to DRAWBUFFERS:012 — water now outputs proper G-buffer data
//       (lightmap + PBR + normals) so the composite pass lights water correctly
//       instead of reading stale terrain data and double-lighting.
// [FIX v0.2.5] Removed water's own Blinn-Phong specular — composite's GGX PBR
//       now handles all water specular with proper Fresnel and microfacet model.
// [FIX v0.2.5] Portal pixels use colortex2.a < 0.5 as emissive flag so composite
//       skips scene lighting and displays the plasma as-is.
// [FIX v0.2.5] Removed incorrect view-space specular mask (used view-space up
//       instead of world-space up, breaking specular when looking steeply down).

#define WATER_TRANSPARENCY 2   // [1 2 3]
#define WATER_RIFFLES 2        // [1 2 3]
#define WATER_SPECULAR_STRENGTH 2 // [1 2 3]

/* DRAWBUFFERS:012 */ // [FIX v0.2.5] Was DRAWBUFFERS:0 — now outputs full G-buffer

uniform float frameTimeCounter;
uniform vec3 shadowLightPosition; // Active light source direction (Sun/Moon)
uniform int worldTime;

in vec2 texcoord;
in vec2 lmcoord;   // [FIX v0.2.5] Lightmap coordinates from vertex shader
in vec4 glcolor; // Water biome tint color
in vec3 normal;  // View space normal
in vec3 viewPos; // View space position
in float isIce;  // 1.0 if ice, 0.0 if water/portal
in float isPortal; // 1.0 if Nether Portal, 0.0 if water/ice

// Declare explicit outputs for modern GLSL 460 compatibility!
layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

// Standard high performance 2D noise for the portal swirl
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), u.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (int i = 0; i < 4; ++i) {
        v += a * noise(p);
        p = rot * p * 2.1 + shift;
        a *= 0.5;
    }
    return v;
}

void main() {
    // 1. Check if the block is a Nether Portal (ID 10006)
    if (isPortal > 0.5) {
        // --- COSMIC PORTAL VORTEX PLASMA ---
        float t = frameTimeCounter * 0.35;

        // Swirling plasma UV transformation
        vec2 uv = texcoord * 1.5;
        float p1 = fbm(uv + vec2(t * 0.8, t * 0.4));
        float p2 = fbm(uv * 1.8 - vec2(t * 0.5, -t * 0.9));
        float plasma = p1 * p2;

        // Deep purple to bright neon magenta/violet color gradient
        vec3 portalColor = mix(vec3(0.12, 0.015, 0.28), vec3(0.55, 0.12, 0.92), plasma);
        // Add a brilliant glowing central core
        portalColor += vec3(0.85, 0.45, 1.0) * pow(plasma, 3.2) * 1.4;

        // [FIX v0.2.5] Output full G-buffer for portal.
        // colortex2.a = 0.0 flags this pixel as emissive — composite will skip lighting.
        colortex0 = vec4(portalColor, 0.85);
        colortex1 = vec4(lmcoord, 0.5, 0.0);      // lightmap + placeholder PBR
        colortex2 = vec4(normal * 0.5 + 0.5, 0.0); // normal + emissive flag (alpha = 0)
        return;
    }

    // 2. Water/Ice Base Color
    vec3 waterColor = glcolor.rgb;
    if (length(waterColor) < 0.1) {
        waterColor = vec3(0.08, 0.42, 0.68);
    }

    // 3. Wave Normal Perturbation (Skip if Ice to prevent waviness on ice blocks)
    float t = frameTimeCounter * 1.5;
    vec2 waveOffset = vec2(0.0);

    // Water Ripples Intensity
    float riffScale = 0.0035;
    #if WATER_RIFFLES == 1
    riffScale = 0.0015; // Calm
    #elif WATER_RIFFLES == 3
    riffScale = 0.0065; // Choppy
    #endif

    if (isIce < 0.5) {
        waveOffset = vec2(
            sin(viewPos.x * 2.5 + viewPos.z * 1.8 + t),
            cos(viewPos.x * 1.5 - viewPos.z * 2.5 + t * 0.8)
        ) * riffScale;
    }

    vec3 N = normalize(normal);
    vec3 waveNormal = vec3(waveOffset * 18.0, 1.0);
    N = normalize(N + waveNormal * 0.15);

    // 4. Physical Fresnel Effect (reflective at angle, transparent straight down)
    vec3 V = normalize(-viewPos);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float F0 = 0.02; // Base water reflectivity
    float fresnel = pow(1.0 - NdotV, 5.0) * (1.0 - F0) + F0;

    // 5. Water Opacity styling
    float baseOpacity = 0.55;
    #if WATER_TRANSPARENCY == 1
    baseOpacity = 0.32; // Crystal clear
    #elif WATER_TRANSPARENCY == 3
    baseOpacity = 0.82; // Deep
    #endif

    // Ice blocks should have constant high opacity to look solid and non-liquidy
    float opacity = isIce > 0.5 ? 0.88 : mix(baseOpacity, 0.92, fresnel);

    // [FIX v0.2.5] Output raw water albedo (no pre-computed specular) to colortex0.
    // The composite pass now handles ALL lighting including GGX PBR specular.
    // Water PBR: roughness=0.05 (smooth dielectric), metalness=0.0 (non-metallic).
    // Ice PBR: roughness=0.15 (slightly rougher solid), metalness=0.0.
    colortex0 = vec4(waterColor, opacity);

    // Lightmap + PBR data for composite
    float pbrRoughness = isIce > 0.5 ? 0.15 : 0.05;
    colortex1 = vec4(lmcoord, pbrRoughness, 0.0);

    // Perturbed normal + emissive flag = 1.0 (not emissive)
    colortex2 = vec4(N * 0.5 + 0.5, 1.0);
}
