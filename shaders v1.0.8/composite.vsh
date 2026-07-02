#version 460 compatibility
// AuraLite Shaders v1.0.8 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Fullscreen Composite Pass Vertex Shader (GLSL 460)
// ==============================================================================
// [FIX v0.2.3] Upgraded from #version 130 to 460; replaced 'varying' with 'out'

out vec2 texcoord;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    gl_Position = ftransform();
}
