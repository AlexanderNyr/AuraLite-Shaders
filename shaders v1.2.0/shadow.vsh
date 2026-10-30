#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

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
    // [v1.2.0] Must stay bit-identical to the copy in composite.fsh. The old
    // `clipPos.z *= 0.5` is gone for the same reason documented there: it threw
    // away half the depth buffer and doubled the effective depth bias.
    // The 0.06 offset gives more shadow-map space to the near-centre region. Keep
    // this constant identical in all three shadow projection paths.
    float distortFactor = length(clipPos.xy) + 0.06;
    clipPos.xy /= distortFactor;
    return clipPos;
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
    glcolor = gl_Color;

    vec4 localPosition = gl_Vertex;
    float entityId = mc_Entity.x;

    // ======================================================================
    // [v1.2.0] WATER IS NOT WRITTEN INTO THE SHADOW CARD.
    // ======================================================================
    // In a frame with a perfectly flat world (only sand, water and bedrock) on the water
    // there was a smooth wavy pattern with a period of 83 px, and it COMPLETELY disappeared when
    // shadows turned off. This means that these are not waves, nor normals, nor identification of water,
    // and a shadow card.
    // Mechanism: water is a flat surface that itself falls into the shadow
    // map and when comparing depths it turns out to be almost the same depth as
    // receiver The waves move it by centimeters, and the depth buffer is 512...2048
    // texels across 128...512 blocks stores the step in centimeters-decimeters. As a result
    // water shades itself with stripes: the pattern is the beating of the shadow map grid
    // from the screen, so the period is constant in PIXELS (83 px) and does not depend on
    // where to look, and only the contrast changes depending on the time of day.
    // This does not cure any bias: it shifts the threshold, but does not remove the beats.
    // Physically, the water is almost transparent and does not cast a shadow at all - just like
    // Vanilla arrives. Therefore, water is simply not drawn in the shadow map:
    // the vertex is moved outside the clipping volume. Shadows from sand, stone,
    // foliage and buildings remain because their IDs are not touched.
    if (entityId == 10020.0) {                 // minecraft:water / flowing_water
        gl_Position = vec4(0.0, 0.0, -2.0, 1.0);   // outside [-1,1] along z -> the fragment is cut off
        texcoord = vec2(0.0);
        glcolor = vec4(0.0);
        return;
    }

    // [NEW v1.1.3] Match the underwater-plant sway from gbuffers_terrain.vsh so
    // kelp/seagrass shadows do not detach from the visible geometry.
    if (entityId == 10010.0) {
        float uwSpeed = 1.0;
        #if WIND_SPEED == 1
        uwSpeed = 0.55;
        #elif WIND_SPEED == 3
        uwSpeed = 1.65;
        #endif
        uwSpeed = mix(uwSpeed, uwSpeed * 1.6, rainStrength * thunderStrength);
        float ut = frameTimeCounter * (1.1 * uwSpeed);
        float heightFactor = clamp(fract(localPosition.y) * 2.0, 0.25, 2.0);
        float sway = sin(ut + localPosition.x * 0.9 + localPosition.z * 0.7) * 0.05
                   + cos(ut * 0.6 + localPosition.y * 1.3 + localPosition.z * 0.4) * 0.025;
        localPosition.x += sway * heightFactor;
        localPosition.z += sway * 0.6 * heightFactor;
    }

    // Match gbuffers_terrain.vsh wind displacement so animated vegetation shadows
    // do not lag behind the visible geometry.
    bool isPlant = (entityId >= 10001.0 && entityId <= 10004.0)
                || entityId == 10011.0 || entityId == 10012.0;
    if (isPlant) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif
        speedFactor = mix(1.0, 1.35, rainStrength * mix(0.6, 1.0, thunderStrength));
        float t = frameTimeCounter * 2.2 * speedFactor;
        float gustScale = rainStrength * mix(1.0, 2.0, thunderStrength) + 0.45;
        float windGust = sin(frameTimeCounter * 0.4 * speedFactor) * gustScale + (1.0 - gustScale);

        #ifdef WAVING_LEAVES
        if (entityId == 10001.0) {
            float wave  = sin(localPosition.x * 1.5 + localPosition.z * 1.5 + t) * 0.06 * windGust;
            float wave2 = cos(localPosition.y * 1.2 + t * 0.8) * 0.04 * windGust;
            localPosition.x += wave;
            localPosition.y += wave2 * 0.4;
            localPosition.z += wave2;
        }
        #endif
        #ifdef WAVING_GRASS
        // [v1.2.0] World-space XZ for the wave phase, same as the visible pass.
        vec3 swayWorld = (gl_ModelViewMatrix * localPosition).xyz;
        if (entityId == 10002.0 || entityId == 10011.0 || entityId == 10012.0) {
            localPosition.xyz = auraliteFoliageSway(entityId, localPosition.xyz, swayWorld.xz, t, windGust);
        } else if (entityId == 10003.0 || entityId == 10004.0) {
            localPosition.xyz = auraliteFoliageSway(entityId, localPosition.xyz, swayWorld.xz, t, windGust);
        }
        #endif
    }

    vec4 position = gl_ModelViewMatrix * localPosition;
    vec4 clipPos = gl_ProjectionMatrix * position;
    clipPos.xyz = distortShadowClipPos(clipPos.xyz);
    gl_Position = clipPos;
}
