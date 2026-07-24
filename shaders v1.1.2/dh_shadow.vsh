#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Shadow Vertex Shader
// ==============================================================================
// [NEW v1.1.2] Per Iris ShaderDoc: "The shadow pass retains the normal textures
// and projection" — unlike dh_terrain/dh_water, dh_shadow must use the regular
// shadow gl_ProjectionMatrix/gl_ModelViewMatrix (NOT dhProjection), so distant
// LOD chunks land correctly in the same shadow map as normal terrain and can
// cast/receive shadows consistently with nearby geometry.

out vec4 glcolor;

// Shared with shadow.vsh so the shadow map distortion (higher resolution near
// the player) matches exactly between normal and DH-LOD shadow casters.
vec3 distortShadowClipPos(vec3 clipPos) {
    float distortFactor = length(clipPos.xy) + 0.1;
    clipPos.xy /= distortFactor;
    clipPos.z *= 0.5;
    return clipPos;
}

void main() {
    glcolor = gl_Color;
    vec4 position = gl_ModelViewMatrix * gl_Vertex;
    vec4 clipPos = gl_ProjectionMatrix * position;
    clipPos.xyz = distortShadowClipPos(clipPos.xyz);
    gl_Position = clipPos;
}
