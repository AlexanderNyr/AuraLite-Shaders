#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Water Vertex Shader
// ==============================================================================
// [NEW v1.1.2] Runs before normal gbuffers_water for the simplified DH water
// quads beyond the vanilla render distance. Mirrors gbuffers_water.vsh's wave
// displacement so distant water doesn't look like a static flat plane compared
// to the animated water close to the camera.

out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;
out vec2 lmcoord;

uniform mat4 dhProjection;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;

#define WIND_SPEED 2 // [1 2 3] - kept in sync with gbuffers_water.vsh

void main() {
    glcolor = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    // [FIX v1.1.2] Same fix as dh_terrain.vsh — gl_MultiTexCoord2 is NOT
    // guaranteed to carry a usable 0-240 vanilla-style lightmap for DH
    // programs, and reading it that way zeroed out skyLight, making all DH
    // water render pitch black. DH water is always open-air/exterior, so
    // hardcode full skylight, no baked torch light.
    lmcoord = vec2(0.0, 1.0);

    vec4 position = gl_Vertex;

    if (gl_Normal.y > 0.5) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif
        speedFactor = ((mix(1.3, 1.8, thunderStrength) - 1.0) * (rainStrength) + (speedFactor));
        float t = frameTimeCounter * (1.6 * speedFactor);
        float wave = sin(position.x * 2.2 + position.z * 1.8 + t) * 0.04
                   + cos(position.x * 1.2 - position.z * 2.2 + t * 0.9) * 0.02;
        position.y += wave * mix(1.0, 1.45, rainStrength);
    }

    vec4 viewPosition = gl_ModelViewMatrix * position;
    viewPos = viewPosition.xyz;
    gl_Position = dhProjection * viewPosition;
}
