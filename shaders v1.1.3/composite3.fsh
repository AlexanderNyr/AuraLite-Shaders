#version 460 compatibility
// AuraLite Shaders v1.1.3 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - HDR Bloom 1/5: Threshold Brightpass (colortex0 → colortex3)
// ==============================================================================
// [NEW v1.1.3] First stage of the gaussian-pyramid bloom that replaces the old
// single-pass 3x3 neighbour glow from v1.0.1 (its ~1.5px radius could only ever
// produce a tight halo). Runs AFTER composite1/TAA so the bloom energy is
// temporally stable, and applies the same exposure as final.fsh so the
// threshold tracks the EXPOSURE option.

#define EXPOSURE 2 // [1 2 3] - mirrored from final.fsh; keep in sync via profile option
#define HDR_BLOOM 2 // [1 2 3] - 1: Subtle, 2: Balanced, 3: Strong

/* DRAWBUFFERS:3 */

in vec2 texcoord;
uniform sampler2D colortex0; // TAA-resolved lit scene

layout(location = 0) out vec4 colortex3Out;

void main() {
    vec3 c = texture(colortex0, texcoord).rgb;

    float expFactor = 1.0;
    #if EXPOSURE == 1
    expFactor = 0.75;
    #elif EXPOSURE == 3
    expFactor = 1.35;
    #endif
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
