#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Shadow Vertex Shader (GLSL 460 Optimized)
// ==============================================================================

out vec2 texcoord;
out vec4 glcolor;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    glcolor = gl_Color;
    gl_Position = ftransform();
}
