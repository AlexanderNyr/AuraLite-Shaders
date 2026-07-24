#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Water Fragment Shader
// ==============================================================================
// [NEW v1.1.2] Tags DH water with the SAME colortex2.a = 0.8 marker used by
// gbuffers_water.fsh, so composite.fsh's water lighting/fresnel path and
// final.fsh's SSR/screen-space-refraction code treat distant DH water the same
// way as normal water instead of it being invisible or lit as opaque terrain.

/* DRAWBUFFERS:012 */

uniform float far; // [FIX v1.1.2] Needed for overdraw prevention (see dh_terrain.fsh)

in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;
in vec2 lmcoord;

layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

void main() {
    // [FIX v1.1.2] DH / vanilla overdraw prevention — see dh_terrain.fsh for the
    // full explanation. Without this, DH's own LOD water plane overlaps normal
    // water/terrain inside the vanilla render distance and both fight over the
    // same G-buffer pixel, causing exactly the "water/ice/blocks act like they
    // don't exist" symptom (wrong depth, wrong normal, wrong material tag).
    float distToCamera = length(viewPos);
    if (distToCamera < far + 16.0) {
        discard;
    }

    vec3 waterColor = glcolor.rgb;
    if (length(waterColor) < 0.1) {
        waterColor = vec3(0.08, 0.42, 0.68); // fallback: matches gbuffers_water.fsh
    }

    vec3 N = normalize(normal);
    vec3 V = normalize(-viewPos);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float F0 = 0.02;
    float fresnel = pow(1.0 - NdotV, 5.0) * (1.0 - F0) + F0;

    float opacity = mix(0.55, 0.92, fresnel); // matches WATER_TRANSPARENCY=2 default

    colortex0 = vec4(waterColor, opacity);
    colortex1 = vec4(lmcoord, 0.055, 0.0); // roughness matches WATER_SPECULAR_STRENGTH=2 default
    colortex2 = vec4(N * 0.5 + 0.5, 0.8);  // 0.8 = water material tag
}
