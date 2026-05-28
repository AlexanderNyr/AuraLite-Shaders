#version 130 compatibility

// ==============================================================================
// AuraLite Shader Pack - Final Post-Processing Pass Vertex Shader (GLSL 130)
// ==============================================================================

varying vec2 texcoord;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    gl_Position = ftransform();
}
