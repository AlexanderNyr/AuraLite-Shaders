#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// Physical atmosphere LUT 2/2 — bounded multi-scattering / ground bounce
// ==============================================================================
// colortex6 combines the direct transmittance LUT with turbidity, altitude and
// a biome-aware ground albedo proxy. It is a compact energy-bounded fit rather
// than a full 3D radiance volume, but is shared by every physical-sky consumer.

#define SKY_MODE 0                 // [0 1]
#define ATMOSPHERE_TURBIDITY 2     // [1 2 3]
#define GROUND_BOUNCE_MODE 0       // [0 1 2 3 4] Auto/Neutral/Vegetation/Snow/Desert

/* DRAWBUFFERS:6 */

in vec2 texcoord;
uniform sampler2D colortex5;
uniform float rainStrength;
uniform float thunderStrength;
uniform float auroraColdBiome;
uniform float isSwampBiome;

layout(location = 0) out vec4 colortex6Out;

float baseTurbidity() {
    #if ATMOSPHERE_TURBIDITY == 1
    return 0.62;
    #elif ATMOSPHERE_TURBIDITY == 3
    return 1.70;
    #else
    return 1.00;
    #endif
}

vec3 groundBounceAlbedo() {
    vec3 neutral = vec3(0.18, 0.16, 0.13);
    #if GROUND_BOUNCE_MODE == 1
    return neutral;
    #elif GROUND_BOUNCE_MODE == 2
    return vec3(0.13, 0.21, 0.11);
    #elif GROUND_BOUNCE_MODE == 3
    return vec3(0.52, 0.58, 0.66);
    #elif GROUND_BOUNCE_MODE == 4
    return vec3(0.34, 0.25, 0.14);
    #else
    vec3 vegetation = vec3(0.13, 0.21, 0.11);
    vec3 snow = vec3(0.52, 0.58, 0.66);
    vec3 swamp = vec3(0.10, 0.18, 0.09);
    vec3 result = mix(neutral, vegetation, 0.46);
    result = mix(result, snow, clamp(auroraColdBiome, 0.0, 1.0) * 0.72);
    result = mix(result, swamp, clamp(isSwampBiome, 0.0, 1.0) * 0.60);
    return result;
    #endif
}

void main() {
    #if SKY_MODE == 0
    colortex6Out = vec4(0.0);
    return;
    #else
    float sunU = texcoord.x;
    float altitudeU = texcoord.y;
    float sunY = sunU * 1.16 - 0.16;
    vec3 trans = texture(colortex5, vec2(sunU, altitudeU)).rgb;
    // [v1.2.0] Same elevation window as gbuffers_skybasic (0.0..0.28 in sunY
    // space) so the LUT and the per-pixel term agree on when the multi-scatter
    // tint stops being warm.
    float sunHigh = smoothstep(0.0, 0.28, sunY);
    float twilightGate = smoothstep(-0.20, -0.03, sunY);
    float haze = baseTurbidity() * mix(1.0, 2.1, rainStrength) * mix(1.0, 1.25, thunderStrength * rainStrength);

    // Blue Rayleigh re-scatter at noon, warmer lower-atmosphere / ground term at
    // low sun. Values are bounded so bright sunsets do not explode in HDR.
    vec3 rayleighTint = normalize(vec3(5.8, 13.5, 33.1));
    vec3 warmTwilight = vec3(1.00, 0.58, 0.28);
    vec3 scatterTint = mix(warmTwilight, rayleighTint, sunHigh);
    vec3 ground = groundBounceAlbedo();
    // [v1.2.0] The twilight floor is raised (0.030 -> 0.100): with the sun below
    // the horizon this table is the only skylight budget left.
    float scatterStrength = mix(0.100, 0.180, sunHigh) * (0.72 + haze * 0.28);
    vec3 multiScatter = trans * (scatterTint * scatterStrength + ground * (0.08 + 0.15 * sunHigh));
    multiScatter *= twilightGate;

    colortex6Out = vec4(max(multiScatter, vec3(0.0)), 1.0);
    #endif
}
