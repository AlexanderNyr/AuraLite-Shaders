#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Water Vertex Shader
// ==============================================================================
// DH water runs before normal water beyond the vanilla render distance.
// [v1.1.4] It now honors WATER_WAVES and uses the same optional TAA jitter as
// vanilla water, avoiding a static/flickering mismatch across the DH seam.

out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;
out vec2 lmcoord;

uniform mat4 dhProjection;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;

#define WATER_WAVES // [true false]
#define WIND_SPEED 2 // [1 2 3] - kept in sync with gbuffers_water.vsh

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

    // DH water is exterior LOD geometry: full skylight, no baked block light.
    lmcoord = vec2(0.0, 1.0);
    vec4 position = gl_Vertex;

    #ifdef WATER_WAVES
    if (gl_Normal.y > 0.5) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif
        speedFactor = mix(speedFactor, speedFactor * mix(1.3, 1.8, thunderStrength), rainStrength);
        float t = frameTimeCounter * (1.6 * speedFactor);
        // [v1.1.4] Match the balanced near-water base swell; final.fsh adds the
        // shared directional spectrum to reflections/refraction.
        float wave = sin(position.x * 2.2 + position.z * 1.8 + t) * 0.032
                   + cos(position.x * 1.2 - position.z * 2.2 + t * 0.9) * 0.016;
        position.y += wave * mix(1.0, 1.45, rainStrength);
    }
    #endif

    vec4 viewPosition = gl_ModelViewMatrix * position;
    viewPos = viewPosition.xyz;
    gl_Position = dhProjection * viewPosition;

    #ifdef TAA
    #if TAA_JITTER > 0
    gl_Position.xy += auraliteJitter(frameCounter & 7) * auraliteJitterAmp()
                      * gl_Position.w * (2.0 / vec2(viewWidth, viewHeight));
    #endif
    #endif
}
