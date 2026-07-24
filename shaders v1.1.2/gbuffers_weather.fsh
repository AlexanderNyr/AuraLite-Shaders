#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Weather Fragment Shader (Rain/Snow softener)
// ===============================================================================
// Makes vanilla precipitation less dense and more transparent immediately after
// enabling the shader pack. AuraLite already has fog/cloud atmosphere; vanilla
// rain streaks at full density are visually noisy, so this pass keeps only a
// stable fraction of fragments and lowers their alpha.

/* DRAWBUFFERS:0 */

uniform sampler2D gtexture;
uniform float rainStrength;

in vec2 texcoord;
in vec4 glcolor;

layout(location = 0) out vec4 colortex0;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec4 tex = texture(gtexture, texcoord) * glcolor;
    if (tex.a < 0.03) discard;

    // Stable screen-space thinning. This reduces perceived particle density
    // without changing Minecraft's actual weather state.
    float keepChance = mix(1.0, 0.42, clamp(rainStrength, 0.0, 1.0));
    vec2 cell = floor(gl_FragCoord.xy * 0.33);
    if (hash(cell) > keepChance) discard;

    // Softer, more transparent precipitation. Slightly preserve visibility when
    // rainStrength is tiny so very light rain doesn't disappear completely.
    float opacity = mix(0.42, 0.24, clamp(rainStrength, 0.0, 1.0));
    tex.a *= opacity;
    tex.rgb *= mix(0.85, 1.0, tex.a);

    colortex0 = tex;
}
