#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - TAA History Copy Vertex Shader
// ==============================================================================
// [FIX v1.1.2] Replaced deprecated fixed-function ftransform() with an explicit
// gl_ModelViewMatrix/gl_ProjectionMatrix multiply for broader driver compatibility.

out vec2 texcoord;

void main() {
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
    texcoord = gl_MultiTexCoord0.xy;
}
