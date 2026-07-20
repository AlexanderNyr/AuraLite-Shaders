#version 460 compatibility
// AuraLite Shaders v1.1.1 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Weather Vertex Shader (Rain/Snow softener)
// ===============================================================================

out vec2 texcoord;
out vec4 glcolor;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    glcolor = gl_Color;
    gl_Position = ftransform();
}
