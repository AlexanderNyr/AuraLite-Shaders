#version 460 compatibility
// AuraLite Shaders v1.1.1 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Shadow Vertex Shader (GLSL 460 - Enhanced)
// ==============================================================================
// [v1.1.1] Shadow pass foliage waving sync: shadows now follow displaced plants/leaves.
// ==============================================================================

#define WAVING_LEAVES // [true false]
#define WAVING_GRASS  // [true false]
#define WIND_SPEED 2  // [1 2 3]

out vec2 texcoord;
out vec4 glcolor;

in vec4 mc_Entity;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;

// Shadow distortion: increases near-camera shadow resolution without increasing map size
vec3 distortShadowClipPos(vec3 clipPos) {
    float distortFactor = length(clipPos.xy) + 0.1;
    clipPos.xy /= distortFactor;
    clipPos.z *= 0.5; // Compress Z range to reduce depth fighting
    return clipPos;
}

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    glcolor = gl_Color;

    vec4 localPosition = gl_Vertex;
    float entityId = mc_Entity.x;

    // Match gbuffers_terrain.vsh wind displacement so animated vegetation shadows
    // do not lag behind the visible geometry.
    if (entityId >= 10001.0 && entityId <= 10004.0) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif
        speedFactor = ((mix(1.5, 2.2, thunderStrength) - 1.0) * rainStrength + speedFactor);
        float t = frameTimeCounter * (2.2 * speedFactor);
        float gustScale = rainStrength * mix(1.0, 2.0, thunderStrength) + 0.45;
        float windGust = sin(frameTimeCounter * (0.4 * speedFactor)) * gustScale + (1.0 - gustScale);
        float waveInput = localPosition.x * 1.5 + localPosition.z * 1.5 + t;
        float wave = sin(waveInput) * (0.06 * windGust);
        float waveInput2 = localPosition.y * 1.2 + t * 0.8;
        float wave2 = cos(waveInput2) * (0.04 * windGust);

        #ifdef WAVING_LEAVES
        if (entityId == 10001.0) {
            localPosition.x += wave;
            localPosition.y += wave2 * 0.4;
            localPosition.z += wave2;
        }
        #endif

        #ifdef WAVING_GRASS
        if (entityId == 10002.0) {
            localPosition.x += wave * 1.5;
            localPosition.z += wave2 * 1.3;
        } else if (entityId == 10003.0 || entityId == 10004.0) {
            localPosition.x += wave * 0.9;
            localPosition.z += wave2 * 0.7;
        }
        #endif
    }

    vec4 position = gl_ModelViewMatrix * localPosition;
    vec4 clipPos = gl_ProjectionMatrix * position;
    clipPos.xyz = distortShadowClipPos(clipPos.xyz);
    gl_Position = clipPos;
}
