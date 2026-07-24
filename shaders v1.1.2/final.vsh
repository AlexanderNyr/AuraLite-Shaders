#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Final Post-Processing Pass Vertex Shader (GLSL 460)
// ==============================================================================
// [FIX v0.2.3] Upgraded from #version 130 to 460; replaced 'varying' with 'out'
// [FIX v1.1.2] Replaced deprecated fixed-function ftransform() with an explicit
// gl_ModelViewMatrix/gl_ProjectionMatrix multiply for broader driver compatibility
// (matches the same fix already applied to shadow.vsh in v1.1.0).

out vec2 texcoord;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
}
