#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

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
out float isWaterBlock;    // [v1.2.0] real water (ID 10020), not a guess based on color

in vec4 mc_Entity;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;              // [v1.2.0] world-space wave anchoring
uniform mat4 gbufferModelViewInverse;     // [v1.2.0]
uniform float rainStrength;
uniform float thunderStrength;

// [v1.2.0] TAA jitter only. The resolve itself is compiled from the TAA switch
// in composite1.fsh; this file needs the same option value to offset gl_Position
// by exactly the amount the resolve compensates for. Both are set from the same
// menu entry, so they cannot disagree.
#define TAA // [true false] - Temporal anti-aliasing (menu: TAA, on in HIGH/ULTRA/EXTREME)
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
    // [v1.2.0] Water gets an explicit ID from block.properties (10011) and
    // ceases to be an “unknown block”. Fame - uniting everyone
    // explicit IDs, including water.
    isWaterBlock = (entityId == 10020.0) ? 1.0 : 0.0;
    float knownEntity = max(max(max(isRegularIce, isPackedIce), max(isGlass, isPortal)), max(isLava, isWaterBlock));
    isUnknownTagged = (entityId > 0.5 && knownEntity < 0.5) ? 1.0 : 0.0;

    #ifdef WATER_WAVES
    if (isIce < 0.5 && isGlass < 0.5 && isPortal < 0.5 && isLava < 0.5 && gl_Normal.y > 0.5) {   //  water - here too
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif

        speedFactor = ((mix(1.3, 1.8, thunderStrength) - 1.0) * (rainStrength) + (speedFactor));

        // [v1.2.0] Same spectrum as gbuffers_water.vsh. This pass draws the
        // translucent half of the water surface, so if the two disagreed the
        // surface would visibly shear along the pass boundary.
        float t = frameTimeCounter * speedFactor;
        float waveAmp = 0.30 * mix(1.0, 1.55, rainStrength) * mix(1.0, 1.35, thunderStrength * rainStrength);
        vec3 worldHere = (gbufferModelViewInverse * (gl_ModelViewMatrix * position)).xyz + cameraPosition;
        position.y += auraliteWaveField(worldHere.xz, t, waveAmp, true).x;
        position.xz += auraliteWaveOrbit(worldHere.xz, t, waveAmp);
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
