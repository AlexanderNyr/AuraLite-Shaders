#version 460 compatibility
// AuraLite Shaders v1.1.3 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - HDR Bloom 3/5: Vertical Gaussian (colortex4 → colortex3)
// ==============================================================================
// [NEW v1.1.3] Completes the tight separable blur; result lands back in
// colortex3 which the wide-radius pass then reads.

/* DRAWBUFFERS:3 */

in vec2 texcoord;
uniform sampler2D colortex4;
uniform float viewHeight;

layout(location = 0) out vec4 colortex3Out;

const float W[5] = float[5](0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162);

void main() {
    vec2 px = vec2(0.0, 1.0 / max(viewHeight, 1.0));
    vec3 acc = texture(colortex4, texcoord).rgb * W[0];
    for (int i = 1; i < 5; ++i) {
        acc += texture(colortex4, texcoord + px * float(i)).rgb * W[i];
        acc += texture(colortex4, texcoord - px * float(i)).rgb * W[i];
    }
    colortex3Out = vec4(acc, 1.0);
}
