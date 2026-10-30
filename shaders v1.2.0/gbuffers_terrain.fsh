#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Terrain Fragment Shader (GLSL 460 - Advanced 3D POM)
// [v1.0.7] Normalized normal vector output in colortex2 for lava.
// ==============================================================================
// Removed dead noise/fbm functions.

#define MC_NORMAL_MAP
#define MC_SPECULAR_MAP
#define MC_TEXTURE_FORMAT_LAB_PBR

// [v1.2.0] POM is a real option. It used to be `//#define PBR_POM`, so the menu
// switch and all seven profiles set a flag the shader could never see: the
// relief path below was dead code and "3D Block Relief" did nothing.
#define PBR_POM // [true false] - parallax occlusion mapping from LabPBR height maps
#define POM_DEPTH 2 // [1 2 3] - 1: Shallow, 2: Standard, 3: Deep
#define POM_STEPS 2 // [1 2 3 4] - 1: 8, 2: 16, 3: 32, 4: 64 marching steps

/* DRAWBUFFERS:012 */

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform float frameTimeCounter; // Needed for animated lava flow

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;
in vec3 tangent;
in vec3 binormal;
flat in float matID;

layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

// [v1.1.4] Removed unused procedural lava/Voronoi helpers. Lava is texture-driven;
// POM below samples LabPBR normal-map alpha directly.

vec2 getParallaxCoords(vec2 initialTexCoords, vec3 V_tang) {
    float parallaxScale = 0.038;
    #if POM_DEPTH == 1
    parallaxScale = 0.015;
    #elif POM_DEPTH == 3
    parallaxScale = 0.065;
    #endif
    float minSt = 4.0, maxSt = 12.0;
    #if POM_STEPS == 1
    minSt = 4.0; maxSt = 8.0;
    #elif POM_STEPS == 3
    minSt = 8.0; maxSt = 20.0;
    #elif POM_STEPS == 4
    minSt = 12.0; maxSt = 32.0;
    #endif
    float ndotv = clamp(abs(V_tang.z), 0.0, 1.0);
    float numLayers = mix(maxSt, minSt, ndotv);
    float layerDepth = 1.0 / numLayers;
    // Optical view angle cotangent scaling with offset limiting (0.15)
    vec2 p = (V_tang.xy / max(abs(V_tang.z), 0.15)) * parallaxScale;
    vec2 deltaTexCoords = p / numLayers;
    vec2 currentTexCoords = initialTexCoords;
    float heightFromTexture = 1.0 - texture(normals, currentTexCoords).a;
    float currentLayerDepth = 0.0;
    int maxIters = 12;
    #if POM_STEPS == 1
    maxIters = 8;
    #elif POM_STEPS == 3
    maxIters = 20;
    #elif POM_STEPS == 4
    maxIters = 32;
    #endif
    for (int i = 0; i < maxIters; ++i) {
        if (currentLayerDepth >= heightFromTexture) break;
        currentTexCoords -= deltaTexCoords;
        heightFromTexture = 1.0 - texture(normals, currentTexCoords).a;
        currentLayerDepth += layerDepth;
    }
    vec2 prevTexCoords = currentTexCoords + deltaTexCoords;
    float afterDepth  = heightFromTexture - currentLayerDepth;
    float beforeDepth = (1.0 - texture(normals, prevTexCoords).a) - currentLayerDepth + layerDepth;
    // Prevent division by zero / sign flipping when afterDepth - beforeDepth < 0
    float weight = afterDepth / min(afterDepth - beforeDepth, -1e-5);
    return mix(currentTexCoords, prevTexCoords, clamp(weight, 0.0, 1.0));
}

void main() {
    mat3 tbn = mat3(normalize(tangent), normalize(binormal), normalize(normal));
    vec2 finalTexCoords = texcoord;
    #ifdef PBR_POM
    // POM only means anything on a flat, opaque, really-three-dimensional block
    // face. Grass, plants, glass and anything else that is a card already gets its
    // shape from the model; offsetting its texture by a height map only smears it.
    // The LabPBR height channel (normals.a) must also be non-empty, or a pack
    // without height maps would jitter its whole terrain by the fallback value.
    bool pomEligible = matID < 10000.0 || matID > 10012.0;
    vec4 pomProbe = texture(normals, texcoord);
    if (pomEligible && pomProbe.a > 0.01 && pomProbe.a < 0.99) {
        vec3 V_tangent = normalize(transpose(tbn) * normalize(-viewPos));
        finalTexCoords = getParallaxCoords(texcoord, V_tangent);
    }
    #endif

    // ======================================================================
    // PROCEDURAL LAVA / MAGMA BLOCK (ID 10009) - HIGH PERFORMANCE TEXTURED MODE
    // ======================================================================
    if (matID == 10009.0) {
        // Read vanilla or resource pack texture albedo (much higher quality & respects packs!)
        vec4 albedo = texture(gtexture, finalTexCoords) * glcolor;
        
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

    vec4 albedo = texture(gtexture, finalTexCoords) * glcolor;
    if (albedo.a < 0.1) discard;
    vec4 normalMap = texture(normals, finalTexCoords);
    vec3 bumpedNormal = ((normalMap.xyz) * (2.0) + (-1.0));
    vec3 finalNormal = normalize(tbn * bumpedNormal);
    vec4 specData = texture(specular, finalTexCoords);
    float roughness = clamp(1.0 - specData.r, 0.0, 1.0);
    float metalness = clamp(specData.g, 0.0, 1.0);
    float materialMask = 1.0;
    if (matID >= 10001.0 && matID <= 10004.0) materialMask = 0.62;
    // [v1.2.0] New plant classes must carry the same foliage tag, otherwise
    // composite.fsh would stop recognising them as vegetation and the canopy
    // shading / translucency fixes would silently skip them.
    if (matID == 10011.0 || matID == 10012.0) materialMask = 0.62;

    // ------------------------------------------------------------------------
    // [v1.2.0] TALL vs SHORT grass read differently
    // v1.1.4 gave every plant one look because they shared one class. The two
    // growth forms are genuinely different material: a two-block stalk is old
    // growth with thick, waxy, dark blades and it self-shades its own base; a
    // one-block sward is fresh, thin, bright, more yellow-green growth that
    // stands in the open. Nudge albedo and roughness in that direction instead
    // of tinting arbitrarily.
    // ------------------------------------------------------------------------
    // [v1.2.0] Darkening tall grass (x0.90 plus a contrast curve) while
    // brightening short grass (x1.06) makes the two read as
    // "dark plant" and "light plant" rather than "the same grass, different
    // growth". Tall grass also carries TWO stacked quads, which already makes it
    // self-shadow more, so darkening it as well was double-counting. Both classes
    // are now at or slightly above their original brightness; the difference
    // between them is CARRIED BY FORM AND MOTION (two blocks vs one, heavy bend
    // vs flutter) plus a faint hue shift, not by darkness.
    if (matID == 10002.0) {
        albedo.rgb *= vec3(1.00, 1.02, 0.97);   // tall: a touch brighter, cool green
        roughness = clamp(roughness + 0.04, 0.0, 1.0);
    } else if (matID == 10011.0) {
        albedo.rgb *= vec3(1.03, 1.01, 0.94);   // short: a touch brighter, warmer
        roughness = clamp(roughness - 0.03, 0.0, 1.0);
    }
    colortex0 = albedo;
    colortex1 = vec4(lmcoord, roughness, metalness);
    colortex2 = vec4(((finalNormal) * (0.5) + (0.5)), materialMask);
}
