#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Fullscreen Composite Pass Vertex Shader (GLSL 460)
// ==============================================================================

out vec2 texcoord;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    gl_Position = ftransform();
}
