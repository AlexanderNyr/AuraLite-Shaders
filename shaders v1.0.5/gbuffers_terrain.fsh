#version 460 compatibility
// AuraLite Shaders v1.0.5 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Terrain Fragment Shader (GLSL 460 - Advanced 3D POM)
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
    vec2 p = ((V_tang.xy) * (parallaxScale) + (vec2(0.0)));
    vec2 deltaTexCoords = p / numLayers;
    vec2 currentTexCoords = initialTexCoords;
    float heightFromTexture = 1.0 - texture(normals, currentTexCoords).a;
    if (heightFromTexture < 0.005) return initialTexCoords;
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
    float weight = afterDepth / (afterDepth - beforeDepth + 0.0001);
    return mix(currentTexCoords, prevTexCoords, clamp(weight, 0.0, 1.0));
}

void main() {
    mat3 tbn = mat3(normalize(tangent), normalize(binormal), normalize(normal));
    vec2 finalTexCoords = texcoord;
    #ifdef PBR_POM
    vec3 V_tangent = normalize(transpose(tbn) * normalize(-viewPos));
    finalTexCoords = getParallaxCoords(texcoord, V_tangent);
    #endif
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
