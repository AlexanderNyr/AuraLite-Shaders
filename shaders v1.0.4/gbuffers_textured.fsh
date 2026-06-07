#version 460 compatibility
// AuraLite Shaders v1.0.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Textured Objects Fragment Shader (GLSL 460 - 100% Stable Fallback)
// ==============================================================================

/* DRAWBUFFERS:012 */

uniform sampler2D gtexture;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;

// Explicit outputs for modern GLSL 460 compatibility
layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * glcolor;
    if (albedo.a < 0.1) {
        discard;
    }

    colortex0 = albedo;
    // For non-terrain fallback objects (hand, mobs, particles), set roughness=0.5, metalness=0.0
    colortex1 = vec4(lmcoord, 0.5, 0.0);
    colortex2 = vec4(((normal) * (0.5) + (0.5)), 1.0);
}
