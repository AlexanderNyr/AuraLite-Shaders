#version 460 compatibility
// AuraLite Shaders v1.1.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// Physical atmosphere LUT 1/2 — direct solar transmittance
// ==============================================================================
// The 64x32 colortex5 LUT is indexed by sun elevation (x) and atmospheric
// altitude (y). It is intentionally tiny and is rebuilt every frame, providing
// stable low-frequency data without restoring full-resolution c5/c6 buffers.

#define SKY_MODE 0                 // [0 1]
#define ATMOSPHERE_TURBIDITY 2     // [1 2 3]
#define ATMOSPHERE_SCALE 3         // [1 2 3] blocks-to-metres mapping

/* DRAWBUFFERS:5 */

in vec2 texcoord;
uniform float rainStrength;
uniform float thunderStrength;

layout(location = 0) out vec4 colortex5Out;

float atmosphereMetersPerBlock() {
    #if ATMOSPHERE_SCALE == 1
    return 25.0;
    #elif ATMOSPHERE_SCALE == 2
    return 50.0;
    #else
    return 100.0;
    #endif
}

float baseTurbidity() {
    #if ATMOSPHERE_TURBIDITY == 1
    return 0.62;
    #elif ATMOSPHERE_TURBIDITY == 3
    return 1.70;
    #else
    return 1.00;
    #endif
}

float kastenAirmass(float sunY) {
    float elevation = max(sunY, -0.12);
    float elevationDeg = degrees(asin(clamp(elevation, -0.12, 1.0)));
    // Kasten-Young is defined near the horizon; this bounded extension remains
    // stable for the small below-horizon twilight portion of the LUT.
    return 1.0 / max(0.018, elevation + 0.50572 * pow(max(elevationDeg + 6.07995, 0.25), -1.6364));
}

void main() {
    #if SKY_MODE == 0
    colortex5Out = vec4(1.0);
    return;
    #else
    // -0.16 gives civil/nautical twilight room; 1.0 is zenith sun.
    float sunY = texcoord.x * 1.16 - 0.16;
    // LUT covers 0-30 km. Camera altitude is converted with the same scale as
    // gbuffers_skybasic.fsh, then clamped to its useful Minecraft range.
    float altitude = texcoord.y * 30000.0;
    float altitudeFade = exp(-altitude / 8200.0);
    float haze = baseTurbidity() * mix(1.0, 2.35, rainStrength) * mix(1.0, 1.35, thunderStrength * rainStrength);
    float airMass = kastenAirmass(sunY) * altitudeFade;

    // RGB extinction fit in linear display space. It mirrors the physical sky
    // coefficients while remaining numerically stable in a tiny LUT.
    vec3 betaRayleigh = vec3(0.075, 0.155, 0.375);
    vec3 betaAerosol = vec3(0.060, 0.072, 0.082) * haze;
    vec3 transmittance = exp(-airMass * (betaRayleigh + betaAerosol));
    // Direct solar radiance cannot illuminate the night hemisphere. Preserve a
    // small civil-twilight ramp, then explicitly zero the LUT below it so c6
    // never feeds daytime multi-scatter into midnight sky pixels.
    float solarVisibility = smoothstep(-0.12, 0.025, sunY);
    transmittance *= solarVisibility;
    colortex5Out = vec4(clamp(transmittance, vec3(0.0), vec3(1.0)), 1.0);
    #endif
}
