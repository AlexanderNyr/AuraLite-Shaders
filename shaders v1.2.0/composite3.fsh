#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - HDR Bloom 1/5: Threshold Brightpass (colortex0 → colortex3)
// ==============================================================================
// [v1.1.4] First stage of the half-resolution HDR bloom chain that replaces the old
// single-pass 3x3 neighbour glow from v1.0.1 (its ~1.5px radius could only ever
// produce a tight halo). Runs AFTER composite1/TAA so the bloom energy is
// temporally stable, and applies the same exposure as final.fsh so the
// threshold tracks the EXPOSURE option.

#define COLOR_EXPOSURE 1.00 // [0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00] - mirrored from final.fsh; MUST stay identical there so the bloom threshold tracks the exposure slider
#define BLOOM             // [true false] - master switch; also disables composite3-7 through shaders.properties
#define HDR_BLOOM 2       // [1 2 3] - 1: Subtle, 2: Balanced, 3: Strong

/* DRAWBUFFERS:3 */

in vec2 texcoord;
uniform sampler2D colortex0; // TAA-resolved lit scene

layout(location = 0) out vec4 colortex3Out;

void main() {
    // Compatibility fallback for loaders that do not honour program.<name>.enabled.
    // The normal Iris/OptiFine path skips this full-screen program completely.
    #ifndef BLOOM
    colortex3Out = vec4(0.0);
    return;
    #endif

    vec3 c = texture(colortex0, texcoord).rgb;

    // [v1.2.0] Same exposure the final pass applies, so the bloom knee stays
    // put on screen no matter where the user drags the exposure slider.
    float expFactor = COLOR_EXPOSURE;
    c *= expFactor;

    // Soft-knee threshold at 0.75 — same luminance gate the retired 3x3 bloom
    // used, so the same sources glow (sun/moon disks, lava, portals, hot
    // specular) while mid-tones stay untouched. Strong mode lowers the knee
    // slightly for a fuller glow.
    float kneeHi = 1.5;
    #if HDR_BLOOM == 3
    kneeHi = 1.25;
    #endif
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    float w = smoothstep(0.75, kneeHi, luma);

    colortex3Out = vec4(c * w, 1.0);
}
