#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

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
    // [v1.2.0] Re-derived from the calibrated coefficients instead of the old
    // hand-tuned values, which put ~9x too much aerosol in the beam (aerosol
    // scatters all wavelengths equally, so excess aerosol is exactly what greys
    // the sky out) and omitted ozone entirely.
    //   Rayleigh fit 0.075/0.155/0.375 ~= 1.45 x the vertical optical depth of
    //   (5.802, 13.558, 33.1)e-6 m^-1 over H=8 km;
    //   aerosol (scattering 3.996e-6 + absorption 0.444e-6) over H=1.2 km
    //   = 0.0053 -> 0.0077 in the same units;
    //   ozone (0.650, 1.881, 0.085)e-6 over the 30 km tent = (0.0195, 0.056,
    //   0.0026) -> (0.028, 0.082, 0.0037).
    // The LUT is a 64x32 approximation, so ozone is folded into the same airmass
    // instead of integrating its own path; that is why it is a low-frequency
    // term only.
    vec3 betaRayleigh = vec3(0.075, 0.155, 0.375);
    vec3 betaAerosol  = vec3(0.0077) * haze;
    vec3 betaOzone    = vec3(0.0283, 0.0818, 0.0037);
    vec3 transmittance = exp(-airMass * (betaRayleigh + betaAerosol + betaOzone));
    // [v1.2.0] Direct solar radiance must not illuminate the night hemisphere,
    // but the old smoothstep(-0.12, 0.025) killed the LUT by solar -1.4° — exactly
    // where civil twilight starts looking interesting. Ramp over the whole
    // twilight instead and let the per-sample shadow in the sky shader do the
    // geometric work.
    float twilightGate = smoothstep(-0.20, -0.03, sunY);
    transmittance *= twilightGate;
    colortex5Out = vec4(clamp(transmittance, vec3(0.0), vec3(1.0)), 1.0);
    #endif
}
