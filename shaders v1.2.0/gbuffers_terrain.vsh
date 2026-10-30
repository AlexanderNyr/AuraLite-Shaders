#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Terrain Vertex Shader (GLSL 460 - Storm Waving Foliage)
// ==============================================================================
// Removed mc_EntityOut.

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
uniform vec3 cameraPosition;              // [v1.2.0] world-space sway phase
uniform mat4 gbufferModelViewInverse;     // [v1.2.0]

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
// [v1.2.0] FOLIAGE SWAY — three distinct physical behaviours
// ==============================================================================
// v1.1.4 applied ONE sine displacement to every plant type, so short grass, tall
// double-height grass and flowers moved identically. They are not the same
// object: a two-block stalk is long, light and whippy and bends from the base;
// short grass is a dense stiff mat that only flutters; a flower is a rigid stem
// with a heavy head. The three classes in block.properties (10002 tall,
// 10011 short, 10012 flowers) get three different profiles here.
// `h` is the height inside the block (0 at the base, 1 at the top), so the
// displacement is anchored at the ground and grows upward instead of
// translating the whole quad.
// IMPORTANT: this exact function must stay identical in gbuffers_terrain.vsh
// and shadow.vsh, otherwise the shadows detach from the plants.
vec3 auraliteFoliageSway(float entityId, vec3 p, vec2 worldXZ, float tSec, float windGust) {
    float h = clamp(fract(p.y), 0.0, 1.0);
    // [v1.2.0] The phase used to come from the LOCAL vertex position. That
    // is chunk-relative in Iris, so every chunk restarted the wave pattern at its
    // own origin: walking past chunk borders swept through phases, and the grass
    // looked like it sped up whenever the player moved. World coordinates make
    // the wave a property of the place, not of the mesh.
    float phase  = worldXZ.x * 1.5 + worldXZ.y * 1.5;
    float wave   = sin(phase + tSec * 2.2);
    float wave2  = cos(p.y * 1.2 + tSec * 1.76);

    if (entityId == 10002.0) {
        // TALL grass is a DOUBLE-HEIGHT plant: the lower and the upper half are
        // two separate block models, and each one reports h = 0..1 for its own
        // block. A plain height ramp would therefore leave the top of the lower
        // half at full displacement while the bottom of the upper half sits at
        // zero -- the stalk would tear in two at the block seam.
        // sin(pi*h) is zero at BOTH ends, so this weight is continuous across
        // the seam (both sides evaluate to 0.35) while still bulging to 1.0 in
        // the middle of each card, which is what makes a long stalk bend rather
        // than slide.
        float bend = 0.35 + 0.65 * sin(3.14159265 * h);
        p.x += wave  * 0.170 * windGust * bend;
        p.z += wave2 * 0.115 * windGust * bend;
        p.y -= abs(wave) * 0.040 * bend * windGust;   // bending shortens the stalk
    } else if (entityId == 10011.0) {
        // SHORT grass: stiff, dense, small high-frequency flutter.
        float fast = sin(phase * 2.3 + tSec * 4.1) * 0.5 + 0.5;
        p.x += (wave * 0.55 + (fast - 0.5) * 0.45) * 0.048 * windGust * h;
        p.z += (wave2 * 0.55 + (fast - 0.5) * 0.45) * 0.038 * windGust * h;
    } else if (entityId == 10012.0) {
        // FLOWERS: rigid stem, the head nods.
        p.x += wave  * 0.075 * windGust * h;
        p.z += wave2 * 0.055 * windGust * h;
        p.y -= abs(wave) * 0.014 * h * windGust;
    } else if (entityId >= 10003.0 && entityId <= 10004.0) {
        // Crops and vines keep the original gentle sway.
        p.x += wave  * 0.054 * windGust;
        p.z += wave2 * 0.042 * windGust;
    }
    return p;
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

    bool isPlant = (entityId >= 10001.0 && entityId <= 10004.0)
                || entityId == 10011.0 || entityId == 10012.0;
    if (isPlant) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif
        // [v1.2.0] Was mix(1.5, 2.2) * rainStrength + speedFactor: the first
        // rain multiplied the animation rate by up to 2.2x on top of WIND_SPEED,
        // so the whole world visibly sped up. Weather now adds gustiness and only
        // a modest amount of rate.
        speedFactor = mix(1.0, 1.35, rainStrength * mix(0.6, 1.0, thunderStrength));
        float t = frameTimeCounter * 2.2 * speedFactor;
        float gustScale = rainStrength * mix(1.0, 2.0, thunderStrength) + 0.45;
        float windGust = sin(frameTimeCounter * 0.4 * speedFactor) * gustScale + (1.0 - gustScale);

        #ifdef WAVING_LEAVES
        if (entityId == 10001.0) {
            float wave  = sin(position.x * 1.5 + position.z * 1.5 + t) * 0.06 * windGust;
            float wave2 = cos(position.y * 1.2 + t * 0.8) * 0.04 * windGust;
            position.x += wave;
            position.y += wave2 * 0.4;
            position.z += wave2;
        }
        #endif
        #ifdef WAVING_GRASS
        // [v1.2.0] World-space XZ for the wave phase.
        vec3 swayWorld = (gbufferModelViewInverse * (gl_ModelViewMatrix * position)).xyz + cameraPosition;
        if (entityId == 10002.0 || entityId == 10011.0 || entityId == 10012.0) {
            // [v1.2.0] class-specific profiles, shared with shadow.vsh
            position.xyz = auraliteFoliageSway(entityId, position.xyz, swayWorld.xz, t, windGust);
        } else if (entityId == 10003.0 || entityId == 10004.0) {
            position.xyz = auraliteFoliageSway(entityId, position.xyz, swayWorld.xz, t, windGust);
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
