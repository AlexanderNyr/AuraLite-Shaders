#version 460 compatibility
// AuraLite Shaders v1.1.3 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - HDR Bloom 2/5: Horizontal Gaussian (colortex3 → colortex4)
// ==============================================================================
// [NEW v1.1.3] Tight blur (stride 1) that sets the base glow radius.

/* DRAWBUFFERS:4 */

in vec2 texcoord;
uniform sampler2D colortex3;
uniform float viewWidth;

layout(location = 0) out vec4 colortex4Out;

// 9-tap gaussian, sigma ≈ 2.0
const float W[5] = float[5](0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162);

void main() {
    vec2 px = vec2(1.0 / max(viewWidth, 1.0), 0.0);
    vec3 acc = texture(colortex3, texcoord).rgb * W[0];
    for (int i = 1; i < 5; ++i) {
        acc += texture(colortex3, texcoord + px * float(i)).rgb * W[i];
        acc += texture(colortex3, texcoord - px * float(i)).rgb * W[i];
    }
    colortex4Out = vec4(acc, 1.0);
}
