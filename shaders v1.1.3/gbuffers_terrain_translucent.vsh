#version 460 compatibility
// AuraLite Shaders v1.1.3 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Terrain Translucent Vertex Shader (GLSL 460)
// ==============================================================================
// Oculus/Iris compatibility: translucent terrain pass (water, stained glass, ice).
// Mirrors gbuffers_water.vsh so translucent blocks render identically
// whether Iris uses the unified or split translucent path.

#define WATER_WAVES // [true false]
#define WIND_SPEED 2 // [1 2 3]



out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;
out float isIce;
out float isRegularIce;
out float isPackedIce;
out float isGlass;
out float isPortal;
out float isLava;
out float isUnknownTagged; // [v1.1.1] non-zero mc_Entity ID not handled by this pass

in vec4 mc_Entity;
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

    vec4 position = gl_Vertex;

    float entityId = mc_Entity.x;
    isRegularIce = (entityId == 10005.0) ? 1.0 : 0.0;
    isPackedIce  = (entityId == 10007.0) ? 1.0 : 0.0;
    isIce        = max(isRegularIce, isPackedIce);
    isGlass      = (entityId == 10008.0) ? 1.0 : 0.0;
    isPortal     = (entityId == 10006.0) ? 1.0 : 0.0;
    isLava       = (entityId == 10009.0) ? 1.0 : 0.0;
    float knownEntity = max(max(max(isRegularIce, isPackedIce), max(isGlass, isPortal)), isLava);
    isUnknownTagged = (entityId > 0.5 && knownEntity < 0.5) ? 1.0 : 0.0;

    #ifdef WATER_WAVES
    if (isIce < 0.5 && isGlass < 0.5 && isPortal < 0.5 && isLava < 0.5 && gl_Normal.y > 0.5) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif

        speedFactor = ((mix(1.3, 1.8, thunderStrength) - 1.0) * (rainStrength) + (speedFactor));

        float t = ((frameTimeCounter) * (1.6 * speedFactor) + (0.0));

        float wave = ((sin(((position.x) * (2.2) + (((position.z) * (1.8) + (t)))))) * (0.04) + (cos(((position.x) * (1.2) + (((position.z) * (-2.2) + (((t) * (0.9) + (0.0))))))) * 0.02));

        position.y = ((wave) * (mix(1.0, 1.45, rainStrength)) + (position.y));
    } else if (isLava > 0.5 && gl_Normal.y > 0.5) {
        // Slower, heavier, viscous magma swells
        float t = frameTimeCounter * 0.4;
        float wave = sin(position.x * 0.8 + position.z * 0.6 + t) * 0.02 +
                     cos(position.x * 0.4 - position.z * 0.8 + t * 0.5) * 0.01;
        position.y += wave;
    }
    #endif

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
