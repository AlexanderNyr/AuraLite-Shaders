#version 460 compatibility
// AuraLite Shaders v1.0.3 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Terrain Vertex Shader (GLSL 460 - Storm Waving Foliage)
// ==============================================================================
// [FIX v0.2.3] Removed mc_EntityOut — it was forwarded to fsh but never read there.

#define WAVING_LEAVES // [true false]
#define WAVING_GRASS  // [true false]
#define WIND_SPEED 2  // [1 2 3]

// PBR Triggers to tell Iris / OptiFine to bind normal & specular maps!
#define MC_NORMAL_MAP
#define MC_SPECULAR_MAP
#define MC_TEXTURE_FORMAT_LAB_PBR

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;
out vec3 tangent;
out vec3 binormal;
flat out float matID;

in vec4 mc_Entity; // Input attribute sent by Minecraft
in vec4 at_tangent; // Tangent vector sent by Iris for normal mapping (LabPBR)
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;



void main() {
    texcoord = gl_MultiTexCoord0.xy;
    lmcoord = clamp(gl_MultiTexCoord1.xy * 0.004166667, 0.0, 1.0);
    glcolor = gl_Color;

    // Normal & Tangent Space construction for PBR
    normal = normalize(gl_NormalMatrix * gl_Normal);
    tangent = normalize(gl_NormalMatrix * at_tangent.xyz);
    binormal = normalize(cross(normal, tangent) * at_tangent.w);

    matID = mc_Entity.x;

    vec4 position = gl_Vertex;

    // Waving Foliage animation with Dynamic Storm Wind Gusts!
    float entityId = mc_Entity.x;
    if (entityId >= 10001.0 && entityId <= 10004.0) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif

        // Dynamically boost wind speed during rain (1.5x) and heavy thunderstorms (2.2x!)
        speedFactor = mix(speedFactor, speedFactor * mix(1.5, 2.2, thunderStrength), rainStrength);

        float t = frameTimeCounter * 2.2 * speedFactor;

        // Boost gust intensity significantly during storms
        float gustScale = mix(0.45, 0.75, rainStrength * mix(1.0, 2.0, thunderStrength));
        float windGust = sin(frameTimeCounter * 0.4 * speedFactor) * gustScale + (1.0 - gustScale);

        float waveInput = position.x * 1.5 + position.z * 1.5 + t;
        float wave = sin(waveInput) * 0.06 * windGust;

        float waveInput2 = position.y * 1.2 + t * 0.8;
        float wave2 = cos(waveInput2) * 0.04 * windGust;

        #ifdef WAVING_LEAVES
        if (entityId == 10001.0) { // Leaves
            position.x += wave;
            position.y += wave2 * 0.4;
            position.z += wave2;
        }
        #endif

        #ifdef WAVING_GRASS
        if (entityId == 10002.0) { // Grass/Flowers
            position.x += wave * 1.5;
            position.z += wave2 * 1.3;
        } else if (entityId == 10003.0 || entityId == 10004.0) { // Crops/vines
            position.x += wave * 0.9;
            position.z += wave2 * 0.7;
        }
        #endif
    }

    vec4 viewPosition = gl_ModelViewMatrix * position;
    viewPos = viewPosition.xyz;
    gl_Position = gl_ProjectionMatrix * viewPosition;

    // so the TAA resolve pass accumulates different subpixel samples over time.
}
