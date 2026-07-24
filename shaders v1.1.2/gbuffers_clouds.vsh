#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Vanilla Clouds Kill Pass Vertex Shader
// ===============================================================================
// [v1.1.1] Fallback for loaders/settings that still submit Minecraft's vanilla
// cloud geometry despite shaders.properties clouds=false. Fragment pass discards it.
// [FIX v1.1.2] Replaced deprecated fixed-function ftransform() with an explicit
// gl_ModelViewMatrix/gl_ProjectionMatrix multiply for broader driver compatibility.

void main() {
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
}
