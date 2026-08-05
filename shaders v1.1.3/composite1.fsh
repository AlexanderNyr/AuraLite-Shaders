#version 460 compatibility
// AuraLite Shaders v1.1.3 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Temporal Anti-Aliasing Resolve Pass
// ==============================================================================
// This pass performs a conservative temporal resolve using motion reprojection,
// previous-frame history in colortex7 and neighborhood clipping to suppress ghosting.

//#define TAA                 // [true false] - Temporal anti-aliasing (on by default in HIGH/ULTRA/EXTREME; toggle in settings)
#define TAA_STRENGTH 2 // [1 2 3] - 1: Light, 2: Balanced, 3: Stable
#define TAA_JITTER 0 // [0 1 2 3] - 0: Off (steady image), 1: Subtle, 2: Standard, 3: Strong — sub-pixel Halton camera jitter for TAA

/* DRAWBUFFERS:0 */

in vec2 texcoord;

uniform sampler2D colortex0; // Current composite color
uniform sampler2D colortex7; // Previous resolved history copied by composite2
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter; // [v1.1.3] drives the Halton jitter sequence index

// [v1.1.3] Halton(2,3) sub-pixel jitter table (8 frames), centred on 0 and
// expressed in PIXEL units. MUST match the identical table in the gbuffers
// vertex shaders — they offset gl_Position by this amount; we compensate the
// previous frame's offset below.
vec2 auraliteJitter(int i) {
    const vec2 J[8] = vec2[8](
        vec2(-0.5000, -0.5000), vec2( 0.0000, -0.1667),
        vec2(-0.2500,  0.1667), vec2( 0.2500, -0.3889),
        vec2(-0.3750, -0.0556), vec2( 0.1250,  0.2778),
        vec2(-0.1250, -0.2778), vec2( 0.3750,  0.0556));
    return J[i & 7];
}

// [v1.1.3] TAA_JITTER strength -> sub-pixel jitter amplitude (px). MUST match the gbuffer vertex shaders.
float auraliteJitterAmp() {
    #if TAA_JITTER == 1
    return 0.5; // Subtle - +/-0.25 px
    #elif TAA_JITTER == 3
    return 1.5; // Strong - +/-0.75 px
    #else
    return 1.0; // Standard - +/-0.5 px
    #endif
}

// [v1.1.3] YCoCg helpers for colour-space-correct variance clipping.
// Luma/chroma decorrelation stops one hot channel (e.g. lava orange) from
// dragging the other channels outside the clip box.
vec3 rgbToYCoCg(vec3 c) {
    return vec3( c.r * 0.25 + c.g * 0.5 + c.b * 0.25,
                 c.r * 0.5  - c.b * 0.5,
                -c.r * 0.25 + c.g * 0.5 - c.b * 0.25);
}
vec3 yCoCgToRGB(vec3 c) {
    return vec3(c.x + c.y - c.z,
                c.x        + c.z,
                c.x - c.y - c.z);
}

layout(location = 0) out vec4 colortex0Out;

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position) {
    vec4 homPos = projectionMatrix * vec4(position, 1.0);
    return homPos.xyz / homPos.w;
}

vec2 reprojectToPreviousUV(vec2 uv, float depth) {
    vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
    vec3 viewPos = projectAndDivide(gbufferProjectionInverse, ndc);

    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 worldPos = feetPlayerPos + cameraPosition;
    vec3 previousFeetPlayerPos = worldPos - previousCameraPosition;

    vec4 previousViewPos = gbufferPreviousModelView * vec4(previousFeetPlayerPos, 1.0);
    vec4 previousClipPos = gbufferPreviousProjection * previousViewPos;

    if (previousClipPos.w <= 0.0) return vec2(-1.0);
    return previousClipPos.xy / previousClipPos.w * 0.5 + 0.5;
}

void main() {
    vec3 currentColor = texture(colortex0, texcoord).rgb;

#ifndef TAA
    colortex0Out = vec4(currentColor, 1.0);
    return;
#else
    float depth = texture(depthtex0, texcoord).r;

    // Sky pixels have no stable geometry reprojection. Keep them current to avoid
    // smearing clouds, auroras, rainbows and godrays across camera motion.
    if (depth >= 0.999999) {
        colortex0Out = vec4(currentColor, 1.0);
        return;
    }

    vec2 previousUV = reprojectToPreviousUV(texcoord, depth);

    // [v1.1.3] Compensate the previous frame's camera jitter. The gbuffers
    // vertex shaders offset gl_Position by Halton(frame) sub-pixel amounts, but
    // gbufferPreviousProjection is the UNjittered matrix — without re-adding
    // the old offset here the history sample lands ~0.5px off and static
    // images smear instead of converging. Only applies while camera jitter
    // is enabled (TAA_JITTER > 0) and must use the same amplitude.
    #if TAA_JITTER > 0
    previousUV += auraliteJitter((frameCounter - 1) & 7) * auraliteJitterAmp()
                  / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    #endif

    if (previousUV.x <= 0.001 || previousUV.x >= 0.999 || previousUV.y <= 0.001 || previousUV.y >= 0.999) {
        colortex0Out = vec4(currentColor, 1.0);
        return;
    }

    vec4 historySample = texture(colortex7, previousUV);
    // [FIX v1.0.3] Reject uninitialized / invalid history (alpha should be 1.0
    // because composite2 writes opaque). This prevents smearing garbage during
    // the first frames after shader reload or resolution change.
    if (historySample.a < 0.99) {
        colortex0Out = vec4(currentColor, 1.0);
        return;
    }

    // [v1.1.3] YCoCg variance clipping (μ ± γσ) replaces the axis-aligned
    // min/max box. The old box was simultaneously too generous in saturated
    // high-contrast corners (visible ghost trails on fences, wires, hot
    // specular) and wastefully tight on flat gradients. Variance adapts the
    // clip to the real neighbourhood statistics.
    vec2 px = 1.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    vec3 mean = vec3(0.0);
    vec3 mean2 = vec3(0.0);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            vec3 c = rgbToYCoCg(texture(colortex0, texcoord + vec2(x, y) * px).rgb);
            mean += c;
            mean2 += c * c;
        }
    }
    mean /= 9.0;
    mean2 /= 9.0;
    vec3 sigma = sqrt(max(mean2 - mean * mean, vec3(0.0)));
    float clipGamma = 1.25;
    #if TAA_STRENGTH == 3
    clipGamma = 1.10; // Stable: tightest clip, minimum ghosting
    #elif TAA_STRENGTH == 1
    clipGamma = 1.50; // Light: looser clip, snappier response
    #endif
    vec3 historyColor = yCoCgToRGB(clamp(rgbToYCoCg(historySample.rgb),
                                         mean - clipGamma * sigma,
                                         mean + clipGamma * sigma));

    float historyWeight = 0.78;
#if TAA_STRENGTH == 1
    historyWeight = 0.64;
#elif TAA_STRENGTH == 3
    historyWeight = 0.88;
#endif

    // Reduce temporal accumulation during fast motion to avoid trails.
    vec2 motionPixels = ((texcoord - previousUV) * (vec2(viewWidth, viewHeight)) + (vec2(0.0)));
    float motion = length(motionPixels);
    historyWeight *= 1.0 - smoothstep(4.0, 32.0, motion);

    // Extra protection for bright sparkles/specular: prefer current frame if the
    // luminance jump is large, so highlights do not leave long afterimages.
    float lumCurrent = dot(currentColor, vec3(0.2126, 0.7152, 0.0722));
    float lumHistory = dot(historyColor, vec3(0.2126, 0.7152, 0.0722));
    float lumDelta = abs(lumCurrent - lumHistory);
    historyWeight *= 1.0 - smoothstep(0.20, 1.10, lumDelta);

    vec3 resolved = mix(currentColor, historyColor, clamp(historyWeight, 0.0, 0.92));
    colortex0Out = vec4(resolved, 1.0);
#endif
}
