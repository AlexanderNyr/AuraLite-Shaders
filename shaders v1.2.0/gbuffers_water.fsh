#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Water, Ice & Glass Fragment Shader (GLSL 460 Optimized)
// [v1.0.7] Fixed lava POM coordinate discard bug & added unique water alpha tag (0.8).
// ==============================================================================
// Changed to DRAWBUFFERS:012 — water now outputs proper G-buffer data.
// Portal pixels use colortex2.a < 0.5 as emissive flag.
// [v1.0.4] Regular ice (ID 10005) now samples gtexture — shows actual ice texture
//          with semi-transparency, NOT water-biome color.
// [v1.0.4] Packed/blue ice (ID 10007) — opaque with texture, no waves.
// [v1.0.4] Glass (ID 10008) — proper texture + transparency, no water behavior.

#define WATER_TRANSPARENCY 2   // [1 2 3]
#define WATER_RIFFLES 2        // [1 2 3]
#define WATER_SPECULAR_STRENGTH 2 // [1 2 3]

/* DRAWBUFFERS:012 */

uniform sampler2D gtexture; // [v1.0.4] Added — needed for ice and glass textures
uniform vec3 cameraPosition;              // [v1.2.0]
uniform mat4 gbufferModelViewInverse;     // [v1.2.0]
uniform float frameTimeCounter;
uniform float rainStrength;   // [v1.2.0] storm amplitude
uniform vec3 shadowLightPosition;
uniform int worldTime;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;
in float isIce;
in float isRegularIce; // [v1.0.4]
in float isPackedIce;  // [v1.0.4]
in float isGlass;      // [v1.0.4]
in float isPortal;
in float isLava;
in float isUnknownTagged; // [v1.1.1] safe fallback for unknown tagged translucent blocks
in float isWaterBlock;    // [v1.2.0] real water by ID 10020

// Declare explicit outputs for modern GLSL 460 compatibility!
layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

// Standard high performance 2D noise for the portal swirl
float hash(vec2 p) {
    p = fract(((p) * (vec2(123.34, 456.21)) + (vec2(0.0))));
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

const mat2 fbmRotMat = mat2(0.87758256, 0.47942554, -0.47942554, 0.87758256);

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += a * noise(p);
        p = fbmRotMat * p * 2.1 + vec2(100.0);
        a *= 0.5;
    }
    return v;
}

// [v1.1.4] Removed unused procedural Voronoi lava-height helpers.
// Lava is intentionally texture-driven; hash/noise/fbm above remain for portals.

// ==============================================================================
// [v1.2.0] ONE COHERENT WIND-WAVE SPECTRUM, EVALUATED IN WORLD SPACE
// ==============================================================================
// v1.1.4 drove the same water surface with THREE unrelated sine fields:
//   gbuffers_water.vsh : sin(x*2.2 + z*1.8 + t)        -> L = 2.9 blocks
//   gbuffers_water.fsh : sin(viewPos.x*2.5 + ...)      -> L = 2.5 blocks, and in
//                                                         VIEW space
//   final.fsh          : 4 components, 0.48..2.48 rad, hard-clamped at +-0.22
// They disagreed in direction, phase and speed, so the eye could not read one
// sea out of them, and they aliased: Minecraft's water mesh has ONE VERTEX PER
// BLOCK, so a 2.9-block wavelength is sampled about three times per period. The
// displaced surface turns into a strip of flat plates creased along the block
// grid -- the "square, cardboard waves" look. The view-space field additionally
// slides over the water whenever the camera moves, and the hard clamp flattens
// every crest into a hard corner.
// One spectrum instead, with the properties a real sea has:
//   * dispersion omega = sqrt(g*k): long waves travel faster, short ones lag;
//   * amplitude A = steepness / k, so short components are automatically small;
//   * the GEOMETRY is displaced only by the three longest components
//     (9.5, 15.5 and 26 blocks = 9..26 samples per period on the 1-block mesh,
//     no aliasing), everything else lives in the normal, where there is no mesh
//     to alias against;
//   * world space, so the wave pattern is anchored to the sea, not to the camera.
const float WAVE_G = 9.81;

// x = direction angle (rad), y = wavelength (blocks), z = steepness, w = 1 if it
// also displaces geometry.
const vec4 WAVE_COMP[8] = vec4[8](
    vec4( 0.61, 26.0, 0.055, 1.0),
    vec4(-0.33, 15.5, 0.060, 1.0),
    vec4( 1.42,  9.5, 0.062, 1.0),
    vec4( 0.18,  6.2, 0.058, 0.0),
    vec4( 1.95,  3.9, 0.052, 0.0),
    vec4(-1.07,  2.5, 0.046, 0.0),
    vec4( 0.87,  1.8, 0.040, 0.0),
    vec4(-1.60,  1.3, 0.034, 0.0)
);

// Height in blocks and its analytic gradient. `geometryOnly` restricts the sum
// to the components the mesh can actually represent.
vec3 auraliteWaveField(vec2 worldXZ, float t, float amp, bool geometryOnly) {
    float h = 0.0;
    vec2 grad = vec2(0.0);
    for (int i = 0; i < 8; ++i) {
        vec4 c = WAVE_COMP[i];
        if (geometryOnly && c.w < 0.5) continue;
        float k     = 6.28318530718 / c.y;
        vec2  d     = vec2(cos(c.x), sin(c.x));
        float A     = c.z / k;                       // amplitude for a given steepness
        float omega = sqrt(WAVE_G * k);              // deep-water dispersion
        float phase = k * dot(d, worldXZ) - omega * t + float(i) * 1.7;
        h    += A * sin(phase);
        grad += A * k * d * cos(phase);              // = steepness * d * cos
    }
    return vec3(h, grad) * amp;
}

// Horizontal orbital motion of the three long components (Gerstner). Vertical
// displacement alone makes a surface that slides; a real wave also carries
// water forward at the crest and back in the trough.
vec2 auraliteWaveOrbit(vec2 worldXZ, float t, float amp) {
    vec2 offset = vec2(0.0);
    for (int i = 0; i < 8; ++i) {
        vec4 c = WAVE_COMP[i];
        if (c.w < 0.5) continue;
        float k     = 6.28318530718 / c.y;
        vec2  d     = vec2(cos(c.x), sin(c.x));
        float A     = c.z / k;
        float omega = sqrt(WAVE_G * k);
        float phase = k * dot(d, worldXZ) - omega * t + float(i) * 1.7;
        offset += d * (A * cos(phase));
    }
    return offset * amp * 0.45;
}

void main() {
    // ======================================================================
    // 0. LAVA / MAGMA BLOCK (ID 10009) - HIGH PERFORMANCE TEXTURED MODE
    // ======================================================================
    if (isLava > 0.5) {
        // Read vanilla or resource pack texture albedo (much higher quality & respects packs!)
        vec4 albedo = texture(gtexture, texcoord) * glcolor;
        
        // Add a pulsing breathing glow (0.90 to 1.10) to make it alive
        float pulse = sin(frameTimeCounter * 0.8) * 0.10 + 1.0;
        vec3 lavaColor = albedo.rgb * pulse;
        
        colortex0 = vec4(lavaColor, albedo.a);
        // PBR: Lava is hot & emissive (roughness = 0.05, extremely shiny for reflections)
        colortex1 = vec4(lmcoord, 0.05, 0.0);
        // Alpha set to 0.1 to flag it as Lava so final.fsh can apply Heat Shimmer!
        colortex2 = vec4(normalize(normal) * 0.5 + 0.5, 0.1);
        return;
    }

    // ======================================================================
    // 1. NETHER PORTAL (ID 10006)
    // ======================================================================
    if (isPortal > 0.5) {
        float t = ((frameTimeCounter) * (0.35) + (0.0));
        vec2 uv = ((texcoord) * (1.5) + (vec2(0.0)));
        float p1 = fbm(uv + vec2(((t) * (0.8) + (0.0)), ((t) * (0.4) + (0.0))));
        float p2 = fbm(((uv) * (1.8) + (vec2(((t) * (-0.5) + (0.0)), ((t) * (0.9) + (0.0))))));
        float plasma = p1 * p2;
        vec3 portalColor = mix(vec3(0.12, 0.015, 0.28), vec3(0.55, 0.12, 0.92), plasma);
        portalColor = ((vec3(0.85, 0.45, 1.0)) * (pow(plasma, 3.2) * 1.4) + (portalColor));
        colortex0 = vec4(portalColor, 0.85);
        colortex1 = vec4(lmcoord, 0.5, 0.0);
        colortex2 = vec4(((normal) * (0.5) + (0.5)), 0.0); // emissive flag
        return;
    }

    // ======================================================================
    // 2. GLASS (ID 10008) — [v1.0.4] NEW: textured glass rendering
    // ======================================================================
    if (isGlass > 0.5) {
        vec4 glassTex = texture(gtexture, texcoord);
        vec3 glassColor = glassTex.rgb * glcolor.rgb;
        float glassOpacity = 0.0;
        #if WATER_TRANSPARENCY == 1
        glassOpacity = 0.22;
        #elif WATER_TRANSPARENCY == 2
        glassOpacity = 0.42;
        #elif WATER_TRANSPARENCY == 3
        glassOpacity = 0.62;
        #endif
        glassOpacity = ((glassTex.a) * (0.45) + (glassOpacity));
        colortex0 = vec4(glassColor, clamp(glassOpacity, 0.15, 0.85));
        colortex1 = vec4(lmcoord, 0.08, 0.0); // glass: smooth, non-metal
        colortex2 = vec4(((normal) * (0.5) + (0.5)), 1.0);
        return;
    }

    // ======================================================================
    // 3. REGULAR ICE (ID 10005) — [v1.0.4] FIXED: textured, semi-transparent
    // ======================================================================
    if (isRegularIce > 0.5) {
        vec4 iceTex = texture(gtexture, texcoord);
        vec3 iceColor = iceTex.rgb * glcolor.rgb;
        if (length(iceColor) < 0.05) {
            iceColor = vec3(0.55, 0.72, 0.85);
        }
        float iceOpacity = 0.62;
        #if WATER_TRANSPARENCY == 1
        iceOpacity = 0.42;
        #elif WATER_TRANSPARENCY == 3
        iceOpacity = 0.78;
        #endif
        colortex0 = vec4(iceColor, iceOpacity);
        colortex1 = vec4(lmcoord, 0.12, 0.0); // ice: slightly rough dielectric
        colortex2 = vec4(((normal) * (0.5) + (0.5)), 1.0);
        return;
    }

    // ======================================================================
    // 4. PACKED ICE / BLUE ICE / FROSTED ICE (ID 10007) — [v1.0.4]
    // ======================================================================
    if (isPackedIce > 0.5) {
        vec4 packedTex = texture(gtexture, texcoord);
        vec3 packedColor = packedTex.rgb * glcolor.rgb;
        if (length(packedColor) < 0.05) {
            packedColor = vec3(0.45, 0.58, 0.72);
        }
        float packedOpacity = 0.90;
        #if WATER_TRANSPARENCY == 1
        packedOpacity = 0.78;
        #elif WATER_TRANSPARENCY == 3
        packedOpacity = 0.96;
        #endif
        colortex0 = vec4(packedColor, packedOpacity);
        colortex1 = vec4(lmcoord, 0.18, 0.0); // rougher than regular ice
        colortex2 = vec4(((normal) * (0.5) + (0.5)), 1.0);
        return;
    }

    // ======================================================================
    // 5. UNKNOWN TAGGED TRANSLUCENT BLOCK FALLBACK — [v1.1.1]
    // Do not treat every unrecognized translucent block as water. If mc_Entity
    // is non-zero but not one of our explicit material tags, render it as a
    // normal textured translucent surface with no water SSR/refraction tag.
    // ======================================================================
    // [v1.2.0] WATER MUST NOT FALL INTO THE “UNKNOWN” BRANCH.
    // ------------------------------------------------------------------
    // When block.properties assigned no ID to minecraft:water, water arrived as an
    // “unknown tagged block” and was written with colortex2.a = 1.0 (a regular
    // surface). The 0.8 water tag therefore never survived, and final.fsh could only
    // fall back to a colour test that bright water failed as well.
    // A horizontal surface with non-earthy colour is now sent to the real water
    // branch below, which writes the 0.8 tag, applies waves and computes Fresnel.
    // Criteria: the surface is horizontal (water always has an upper edge) and the
    // colour is not “earthy” (b and g not lower than r). Every block that is not
    // handled by a BRANCH ABOVE - lava, glass, regular and packed ice - passes, so
    // this is almost always water, including swamp water
    // (0x617B64: r 0.38, g 0.48, b 0.39).
    bool waterLikeAlbedo = (normal.y > 0.5) &&
                           (glcolor.b >= glcolor.r * 0.98) &&
                           (glcolor.g >= glcolor.r * 0.98);
    // [v1.2.0] Water according to an explicit ID ALWAYS goes to the water branch, regardless
    // from color and normal. waterLikeAlbedo remains a fallback for assemblies,
    // where mc_Entity water for some reason did not come.
    if (isUnknownTagged > 0.5 && !waterLikeAlbedo && isWaterBlock < 0.5) {
        vec4 tex = texture(gtexture, texcoord) * glcolor;
        if (tex.a < 0.1) discard;
        colortex0 = tex;
        colortex1 = vec4(lmcoord, 0.5, 0.0);
        colortex2 = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
        return;
    }

    // ======================================================================
    // 6. WATER — original behavior (biome-tinted, wavy, Fresnel)
    // ======================================================================
    vec3 waterColor = glcolor.rgb;
    if (length(waterColor) < 0.1) {
        waterColor = vec3(0.08, 0.42, 0.68);
    }
    // Frozen-ocean biome tints (e.g. 0x3938C9) are navy-purple
    // with almost no green; after the deferred pipeline's pow(albedo, 2.2)
    // their R/G channels crush to black, which was the other half of the
    // black-water regression. Pin R/G to a minimum fraction of B so the tint
    // keeps its hue but can never annihilate the diffuse term. Neutral ocean
    // (0x3F76E4) and swamp tints are unaffected (already above the floor).
    waterColor = max(waterColor, waterColor.b * vec3(0.16, 0.34, 1.0));

    // [v1.2.0] Same spectrum as the vertex shader, in WORLD space.
    // The old field was evaluated on `viewPos`, so the ripple pattern travelled
    // with the camera: walking or turning made the surface swim instead of the
    // water staying put. It also used a different wavelength and direction from
    // the displaced geometry, which is why the surface read as noise.
    float riffMult = 1.0;
    #if WATER_RIFFLES == 1
    riffMult = 0.55;
    #elif WATER_RIFFLES == 3
    riffMult = 1.45;
    #endif
    vec3 worldHere = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
    vec3 field = auraliteWaveField(worldHere.xz, frameTimeCounter,
                                   riffMult * mix(1.0, 1.5, rainStrength), false);

    vec3 N = normalize(normal);
    vec3 helper = abs(N.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(helper, N));
    vec3 bitangent = normalize(cross(N, tangent));
    // The gradient IS the slope, so it tilts the normal one-to-one: no magic
    // multiplier, and no separate phase that could fall out of sync with the
    // displaced geometry. (The old code multiplied a sine by 2.7, which combined
    // with a 2.5 rad/block frequency to give slopes far past 45 degrees.)
    N = normalize(N - tangent * field.y - bitangent * field.z);

    vec3 V = normalize(-viewPos);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float F0 = 0.02;
    float fresnel = ((pow(1.0 - NdotV, 5.0)) * (1.0 - F0) + (F0));

    float baseOpacity = 0.55;
    #if WATER_TRANSPARENCY == 1
    baseOpacity = 0.32;
    #elif WATER_TRANSPARENCY == 3
    baseOpacity = 0.82;
    #endif

    float opacity = mix(baseOpacity, 0.92, fresnel);
    colortex0 = vec4(waterColor, opacity);

    float waterRoughness = 0.055;
    #if WATER_SPECULAR_STRENGTH == 1
    waterRoughness = 0.110;
    #elif WATER_SPECULAR_STRENGTH == 3
    waterRoughness = 0.032;
    #endif

    colortex1 = vec4(lmcoord, waterRoughness, 0.0);
    colortex2 = vec4(N * 0.5 + 0.5, 0.8);
}
