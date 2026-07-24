#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Vanilla Clouds Kill Pass Fragment Shader
// ===============================================================================
// [v1.1.1] Make default Minecraft clouds fully transparent/invisible. AuraLite uses
// its own procedural cloud system in composite.fsh; vanilla clouds would overlap it.
// This is a robust fallback in addition to shaders.properties: clouds=false.

/* DRAWBUFFERS:0 */

layout(location = 0) out vec4 colortex0;

void main() {
    discard;
}
