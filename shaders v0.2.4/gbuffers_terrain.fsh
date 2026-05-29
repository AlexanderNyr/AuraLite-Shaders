#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Terrain Fragment Shader (GLSL 460 - Advanced 3D POM)
// ==============================================================================
// [FIX v0.2.3] Removed dead noise/fbm functions (portal is rendered in gbuffers_water).
// [FIX v0.2.3] Removed unused mc_EntityOut input varying.

// PBR Triggers to tell Iris / OptiFine to bind normal & specular maps!
#define MC_NORMAL_MAP
#define MC_SPECULAR_MAP
#define MC_TEXTURE_FORMAT_LAB_PBR

// POM is disabled by default to ensure 100% out-of-the-box stability for standard resource packs!
//#define PBR_POM // [true false]
#define POM_DEPTH 2 // [1 2 3]
#define POM_STEPS 2 // [1 2 3 4]

/* DRAWBUFFERS:012 */

uniform sampler2D gtexture;
uniform sampler2D normals;  // Normal maps (LabPBR)
uniform sampler2D specular; // Specular maps (LabPBR)

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;
in vec3 tangent;
in vec3 binormal;

// Declare explicit outputs for modern GLSL 460 compatibility!
layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

// ==============================================================================
// HIGH-PERFORMANCE 3D PARALLAX OCCLUSION MAPPING (POM)
// ==============================================================================
vec2 getParallaxCoords(vec2 initialTexCoords, vec3 V_tang) {
    // Parallax depth scale options
    float parallaxScale = 0.038;
    #if POM_DEPTH == 1
    parallaxScale = 0.015; // Subtle
    #elif POM_DEPTH == 3
    parallaxScale = 0.065; // Deep
    #endif

    // Quality layers step configuration
    float minSt = 4.0;
    float maxSt = 12.0;
    #if POM_STEPS == 1
    minSt = 4.0; maxSt = 8.0;   // Low
    #elif POM_STEPS == 3
    minSt = 8.0; maxSt = 20.0;  // High
    #elif POM_STEPS == 4
    minSt = 12.0; maxSt = 32.0; // Ultra
    #endif

    // Dynamic layer steps based on angle (saves GPU power at grazing angles!)
    float numLayers = mix(minSt, maxSt, abs(dot(vec3(0.0, 0.0, 1.0), V_tang)));
    float layerDepth = 1.0 / numLayers;

    // Calculate tangent coordinate offset (offset limiting to prevent infinity stretching)
    vec2 p = V_tang.xy * parallaxScale;
    vec2 deltaTexCoords = p / numLayers;

    vec2 currentTexCoords = initialTexCoords;
    float heightFromTexture = 1.0 - texture(normals, currentTexCoords).a; // LabPBR height is in normal alpha

    // Instant fallback if block has no height map (fully flat)
    if (heightFromTexture < 0.005) {
        return initialTexCoords;
    }

    float currentLayerDepth = 0.0;

    // Raymarching inside the displacement volume
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

    // Parallax Occlusion linear interpolation
    vec2 prevTexCoords = currentTexCoords + deltaTexCoords;
    float afterDepth  = heightFromTexture - currentLayerDepth;
    float beforeDepth = (1.0 - texture(normals, prevTexCoords).a) - currentLayerDepth + layerDepth;

    float weight = afterDepth / (afterDepth - beforeDepth + 0.0001);
    vec2 finalTexCoords = mix(currentTexCoords, prevTexCoords, clamp(weight, 0.0, 1.0));

    return finalTexCoords;
}

void main() {
    // Reconstruct Tangent-Binormal-Normal matrix
    mat3 tbn = mat3(normalize(tangent), normalize(binormal), normalize(normal));

    vec2 finalTexCoords = texcoord;

    #ifdef PBR_POM
    // Calculate tangent-space view vector for Parallax mapping
    vec3 V_tangent = normalize(transpose(tbn) * normalize(-viewPos));
    // Apply 3D Parallax Occlusion Mapping!
    finalTexCoords = getParallaxCoords(texcoord, V_tangent);
    #endif

    // Sample texture atlas with displaced coordinates
    vec4 albedo = texture(gtexture, finalTexCoords) * glcolor;
    if (albedo.a < 0.1) {
        discard;
    }

    // Sample normal map with displaced coordinates (PBR)
    vec4 normalMap = texture(normals, finalTexCoords);
    vec3 bumpedNormal = normalMap.xyz * 2.0 - 1.0;
    vec3 finalNormal = normalize(tbn * bumpedNormal);

    // Sample specular map with displaced coordinates (PBR)
    vec4 specData = texture(specular, finalTexCoords);
    float roughness = clamp(1.0 - specData.r, 0.0, 1.0);
    float metalness = clamp(specData.g, 0.0, 1.0);

    colortex0 = albedo;
    // Pack lightmap and PBR roughness/metalness into colortex1
    colortex1 = vec4(lmcoord, roughness, metalness);
    colortex2 = vec4(finalNormal * 0.5 + 0.5, 1.0);
}
