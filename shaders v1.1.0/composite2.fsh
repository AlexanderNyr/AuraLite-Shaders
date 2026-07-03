#version 460 compatibility
// AuraLite Shaders v1.1.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - TAA History Copy Pass
// ==============================================================================
// Copies the resolved composite color into colortex7 for the next frame.

/* DRAWBUFFERS:7 */

in vec2 texcoord;
uniform sampler2D colortex0;

layout(location = 0) out vec4 colortex7Out;

void main() {
    colortex7Out = vec4(texture(colortex0, texcoord).rgb, 1.0);
}
