#version 460 compatibility
// AuraLite Shaders v1.1.3 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Terrain Vertex Shader (GLSL 460 - Storm Waving Foliage)
// ==============================================================================
// [FIX v0.2.3] Removed mc_EntityOut.
// [v1.0.4-fixed] Replaced fma() with direct multiply-add for GLSL compatibility.

#define WAVING_LEAVES // [true false]
#define WAVING_GRASS  // [true false]
#define WIND_SPEED 2  // [1 2 3]

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

in vec4 mc_Entity;
in vec4 at_tangent;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;


//#define TAA // [true false] - Temporal anti-aliasing (follows the TAA menu option; on by default in HIGH/ULTRA/EXTREME)
#define TAA_JITTER 0 // [0 1 2 3] - 0: Off (steady image), 1: Subtle, 2: Standard, 3: Strong — sub-pixel Halton camera jitter for TAA
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

// [v1.1.3] Halton(2,3) sub-pixel jitter table (8 frames), pixel units, centred
// on 0. MUST match the table in composite1.fsh, which compensates the offset.
// This jitter is the missing half of TAA: without it the temporal resolve only
// blurs noise; WITH it the history accumulation reconstructs sub-pixel detail
// and the frame-rotating IGN dithers (godrays, clouds) resolve cleanly.
vec2 auraliteJitter(int i) {
    const vec2 J[8] = vec2[8](
        vec2(-0.5000, -0.5000), vec2( 0.0000, -0.1667),
        vec2(-0.2500,  0.1667), vec2( 0.2500, -0.3889),
        vec2(-0.3750, -0.0556), vec2( 0.1250,  0.2778),
        vec2(-0.1250, -0.2778), vec2( 0.3750,  0.0556));
    return J[i & 7];
}

// [v1.1.3] TAA_JITTER strength -> sub-pixel jitter amplitude (px). MUST match composite1.fsh.
float auraliteJitterAmp() {
    #if TAA_JITTER == 1
    return 0.5; // Subtle - +/-0.25 px
    #elif TAA_JITTER == 3
    return 1.5; // Strong - +/-0.75 px
    #else
    return 1.0; // Standard - +/-0.5 px
    #endif
}

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    lmcoord = clamp(gl_MultiTexCoord1.xy * 0.004166667, 0.0, 1.0);
    glcolor = gl_Color;

    normal = normalize(gl_NormalMatrix * gl_Normal);
    tangent = normalize(gl_NormalMatrix * at_tangent.xyz);
    binormal = normalize(cross(normal, tangent) * at_tangent.w);

    matID = mc_Entity.x;
    vec4 position = gl_Vertex;
    float entityId = mc_Entity.x;

    // [NEW v1.1.3] Underwater plant sway (seagrass, tall seagrass, kelp, sea
    // pickles — class 10010). Slower and phase-shifted by height so fronds
    // lag the base like real vegetation in a current, and slightly storm-
    // agitated like the surface foliage path.
    if (entityId == 10010.0) {
        float uwSpeed = 1.0;
        #if WIND_SPEED == 1
        uwSpeed = 0.55;
        #elif WIND_SPEED == 3
        uwSpeed = 1.65;
        #endif
        uwSpeed = mix(uwSpeed, uwSpeed * 1.6, rainStrength * thunderStrength);
        float ut = frameTimeCounter * (1.1 * uwSpeed);
        // Fronds above the block base sway the most (fract Y ≈ block-relative height).
        float heightFactor = clamp(fract(position.y) * 2.0, 0.25, 2.0);
        float sway = sin(ut + position.x * 0.9 + position.z * 0.7) * 0.05
                   + cos(ut * 0.6 + position.y * 1.3 + position.z * 0.4) * 0.025;
        position.x += sway * heightFactor;
        position.z += sway * 0.6 * heightFactor;
    }

    if (entityId >= 10001.0 && entityId <= 10004.0) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif
        speedFactor = ((mix(1.5, 2.2, thunderStrength) - 1.0) * (rainStrength) + (speedFactor));
        float t = ((frameTimeCounter) * (2.2 * speedFactor) + (0.0));
        float gustScale = ((rainStrength) * (mix(1.0, 2.0, thunderStrength)) + (0.45));
        float windGust = ((sin(((frameTimeCounter) * (0.4 * speedFactor) + (0.0)))) * (gustScale) + (1.0 - gustScale));
        float waveInput = ((position.x) * (1.5) + (((position.z) * (1.5) + (t))));
        float wave = ((sin(waveInput)) * (0.06 * windGust) + (0.0));
        float waveInput2 = ((position.y) * (1.2) + (((t) * (0.8) + (0.0))));
        float wave2 = ((cos(waveInput2)) * (0.04 * windGust) + (0.0));
        #ifdef WAVING_LEAVES
        if (entityId == 10001.0) {
            position.x += wave;
            position.y = ((wave2) * (0.4) + (position.y));
            position.z += wave2;
        }
        #endif
        #ifdef WAVING_GRASS
        if (entityId == 10002.0) {
            position.x = ((wave) * (1.5) + (position.x));
            position.z = ((wave2) * (1.3) + (position.z));
        } else if (entityId == 10003.0 || entityId == 10004.0) {
            position.x = ((wave) * (0.9) + (position.x));
            position.z = ((wave2) * (0.7) + (position.z));
        }
        #endif
    }

    vec4 viewPosition = gl_ModelViewMatrix * position;
    viewPos = viewPosition.xyz;
    gl_Position = gl_ProjectionMatrix * viewPosition;

    #ifdef TAA
    #if TAA_JITTER > 0
    // [v1.1.3] Apply the sub-pixel Halton jitter (NDC offset = px * 2 / viewSize),
    // scaled by the TAA_JITTER strength (0.5 / 1.0 / 1.5 px amplitude).
    gl_Position.xy += auraliteJitter(frameCounter & 7) * auraliteJitterAmp()
                      * gl_Position.w * (2.0 / vec2(viewWidth, viewHeight));
    #endif
    #endif
}
