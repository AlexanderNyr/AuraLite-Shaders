#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Terrain Vertex Shader
// ==============================================================================
// DH geometry has no textures/UVs — each LOD quad carries flat vertex colour,
// a normal and a coarse dhMaterialId mini-ID. We map that into the same G-buffer
// layout as vanilla terrain so composite.fsh can apply shared lighting/fog/PBR.
// [v1.1.4] DH geometry now receives the same optional Halton camera jitter as
// vanilla G-buffer geometry. composite1.fsh reprojects DH through dhProjection
// and dhPreviousProjection, keeping the vanilla↔DH boundary temporally stable.

out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;
out vec2 lmcoord;
flat out int dhMatId;

// Distant Horizons supplies a far-reaching projection matrix. Using the normal
// gl_ProjectionMatrix here would clip/mis-scale LOD geometry.
uniform mat4 dhProjection;

// [v1.2.0] TAA jitter only. The resolve itself is compiled from the TAA switch
// in composite1.fsh; this file needs the same option value to offset gl_Position
// by exactly the amount the resolve compensates for. Both are set from the same
// menu entry, so they cannot disagree.
#define TAA // [true false] - Temporal anti-aliasing (menu: TAA, on in HIGH/ULTRA/EXTREME)
#define TAA_JITTER 0 // [0 1 2 3] - Off, Subtle, Standard, Strong
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

vec2 auraliteJitter(int i) {
    const vec2 J[8] = vec2[8](
        vec2(-0.5000, -0.5000), vec2( 0.0000, -0.1667),
        vec2(-0.2500,  0.1667), vec2( 0.2500, -0.3889),
        vec2(-0.3750, -0.0556), vec2( 0.1250,  0.2778),
        vec2(-0.1250, -0.2778), vec2( 0.3750,  0.0556));
    return J[i & 7];
}

float auraliteJitterAmp() {
    #if TAA_JITTER == 1
    return 0.5;
    #elif TAA_JITTER == 3
    return 1.5;
    #else
    return 1.0;
    #endif
}

void main() {
    glcolor = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);

    // DH has no reliable vanilla lightmap. Its LOD mesh represents exterior
    // terrain, so use open skylight and no baked torch contribution.
    lmcoord = vec2(0.0, 1.0);
    dhMatId = dhMaterialId;

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    viewPos = viewPosition.xyz;
    gl_Position = dhProjection * viewPosition;

    #ifdef TAA
    #if TAA_JITTER > 0
    gl_Position.xy += auraliteJitter(frameCounter & 7) * auraliteJitterAmp()
                      * gl_Position.w * (2.0 / vec2(viewWidth, viewHeight));
    #endif
    #endif
}
