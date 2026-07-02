#version 460 compatibility
// AuraLite Shaders v1.0.8 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Terrain Fragment Shader (GLSL 460 - Advanced 3D POM)
// [v1.0.7] Normalized normal vector output in colortex2 for lava.
// ==============================================================================
// [FIX v0.2.3] Removed dead noise/fbm functions.
// [v1.0.4-fixed] Replaced fma() with direct multiply-add for GLSL compatibility.

#define MC_NORMAL_MAP
#define MC_SPECULAR_MAP
#define MC_TEXTURE_FORMAT_LAB_PBR

//#define PBR_POM // [true false]
#define POM_DEPTH 2 // [1 2 3]
#define POM_STEPS 2 // [1 2 3 4]

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

// Standard high performance 2D noise for the procedural lava magma cracks
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

// Procedural Voronoi crack generator (finds exact distance to cell borders)
float voronoiCracks(vec2 p) {
    vec2 n = floor(p);
    vec2 f = fract(p);
    
    // First pass: find closest cell center
    vec2 mg, mr;
    float md = 8.0;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = vec2(hash(n + g), hash(n + g + vec2(15.2, 37.8))) * 0.5 + 0.25;
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < md) {
                md = d;
                mr = r;
                mg = g;
            }
        }
    }
    
    // Second pass: find distance to closest edge
    float md2 = 8.0;
    for (int j = -2; j <= 2; ++j) {
        for (int i = -2; i <= 2; ++i) {
            vec2 g = mg + vec2(float(i), float(j));
            vec2 o = vec2(hash(n + g), hash(n + g + vec2(15.2, 37.8))) * 0.5 + 0.25;
            vec2 r = g + o - f;
            if (dot(mr - r, mr - r) > 1e-5) {
                float d = dot(0.5 * (mr + r), normalize(r - mr));
                md2 = min(md2, d);
            }
        }
    }
    return md2;
}

// Procedural Height field of Lava (1.0 = top crust, 0.0 = deep cracks)
float getLavaHeight(vec2 p) {
    float cracks = voronoiCracks(p * 1.8);
    float height = smoothstep(0.0, 0.22, cracks);
    return height;
}

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
    // [FIX v1.0.7] Optical view angle cotangent scaling with offset limiting (0.15)
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
    // [FIX v1.0.7] Prevent division by zero / sign flipping when afterDepth - beforeDepth < 0
    float weight = afterDepth / min(afterDepth - beforeDepth, -1e-5);
    return mix(currentTexCoords, prevTexCoords, clamp(weight, 0.0, 1.0));
}

void main() {
    mat3 tbn = mat3(normalize(tangent), normalize(binormal), normalize(normal));
    vec2 finalTexCoords = texcoord;
    #ifdef PBR_POM
    vec3 V_tangent = normalize(transpose(tbn) * normalize(-viewPos));
    finalTexCoords = getParallaxCoords(texcoord, V_tangent);
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
    colortex0 = albedo;
    colortex1 = vec4(lmcoord, roughness, metalness);
    colortex2 = vec4(((finalNormal) * (0.5) + (0.5)), materialMask);
}
