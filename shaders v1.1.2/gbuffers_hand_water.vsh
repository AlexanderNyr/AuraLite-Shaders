#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Opaque Entity/Hand Vertex Shader
// ===============================================================================
// Fixes semi-transparent players/held items by routing them through explicit
// opaque passes instead of the generic textured fallback.

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    lmcoord = clamp(gl_MultiTexCoord1.xy * 0.004166667, 0.0, 1.0);
    glcolor = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);

    vec4 position = gl_ModelViewMatrix * gl_Vertex;
    viewPos = position.xyz;
    gl_Position = gl_ProjectionMatrix * position;
}
