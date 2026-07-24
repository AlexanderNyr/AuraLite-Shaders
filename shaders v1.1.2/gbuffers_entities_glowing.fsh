#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Opaque Entity/Hand Fragment Shader
// ===============================================================================
// [v1.1.1] Players, mobs and held items must write opaque G-buffer colour.
// Some loaders/resource packs submit these through alpha-capable render layers;
// preserving texture/glcolor alpha made players/items look semi-transparent.
// We still alpha-test cutout pixels, then force the surviving texels opaque.

/* DRAWBUFFERS:012 */

uniform sampler2D gtexture;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;

layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * glcolor;

    // Preserve cutout transparency for item silhouettes / player skin holes,
    // but never let valid entity/hand pixels blend with the previous scene.
    if (albedo.a < 0.10) discard;
    albedo.a = 1.0;

    colortex0 = albedo;
    colortex1 = vec4(lmcoord, 0.5, 0.0); // neutral rough dielectric fallback
    colortex2 = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
}
