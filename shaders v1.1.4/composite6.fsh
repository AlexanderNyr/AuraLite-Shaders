#version 460 compatibility
// AuraLite Shaders v1.1.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - HDR Bloom 4/5: Wide Horizontal Gaussian (colortex3 → colortex4)
// ==============================================================================
// [v1.1.4] Second blur octave at a 4-buffer-texel stride. Because the bloom
// buffers are half resolution, this creates a broad screen-space glow while
// retaining the inexpensive five-pass separable chain.

// [v1.1.4] Master bloom switch. The associated program is skipped through
// shaders.properties; this branch only protects legacy loaders.
#define BLOOM // [true false]

/* DRAWBUFFERS:4 */

in vec2 texcoord;
uniform sampler2D colortex3;
uniform float viewWidth;

layout(location = 0) out vec4 colortex4Out;

const float W[5] = float[5](0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162);

void main() {
    #ifndef BLOOM
    colortex4Out = vec4(0.0);
    return;
    #endif

    // colortex3/4 are half-resolution buffers; one buffer texel spans two
    // display pixels, hence the 2x normalized texel size below.
    vec2 px = vec2(8.0 / max(viewWidth, 1.0), 0.0);
    vec3 acc = texture(colortex3, texcoord).rgb * W[0];
    for (int i = 1; i < 5; ++i) {
        acc += texture(colortex3, texcoord + px * float(i)).rgb * W[i];
        acc += texture(colortex3, texcoord - px * float(i)).rgb * W[i];
    }
    colortex4Out = vec4(acc, 1.0);
}
