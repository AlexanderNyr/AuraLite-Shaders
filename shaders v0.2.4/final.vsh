#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Final Post-Processing Pass Vertex Shader (GLSL 460)
// ==============================================================================
// [FIX v0.2.3] Upgraded from #version 130 to 460; replaced 'varying' with 'out'

out vec2 texcoord;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    gl_Position = ftransform();
}
