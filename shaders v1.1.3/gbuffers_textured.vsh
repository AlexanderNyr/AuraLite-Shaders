#version 460 compatibility
// AuraLite Shaders v1.1.3 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Textured Objects Vertex Shader (GLSL 460 - 100% Stable Fallback)
// ==============================================================================

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;




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

    vec4 position = gl_ModelViewMatrix * gl_Vertex;
    viewPos = position.xyz;
    gl_Position = gl_ProjectionMatrix * position;

    #ifdef TAA
    #if TAA_JITTER > 0
    // [v1.1.3] Apply the sub-pixel Halton jitter (NDC offset = px * 2 / viewSize),
    // scaled by the TAA_JITTER strength (0.5 / 1.0 / 1.5 px amplitude).
    gl_Position.xy += auraliteJitter(frameCounter & 7) * auraliteJitterAmp()
                      * gl_Position.w * (2.0 / vec2(viewWidth, viewHeight));
    #endif
    #endif

}
