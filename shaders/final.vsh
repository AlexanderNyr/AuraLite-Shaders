#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Final Post-Processing Pass Vertex Shader (GLSL 460)
// ==============================================================================

layout(location = 0) out vec2 texcoord;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    gl_Position = ftransform();
}
