#version 460 compatibility
// AuraLite Shaders v1.0.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Temporal Anti-Aliasing Resolve Pass
// ==============================================================================
// This pass performs a conservative temporal resolve using motion reprojection,
// previous-frame history in colortex7 and neighborhood clipping to suppress ghosting.

#define TAA          // [true false]
#define TAA_STRENGTH 2 // [1 2 3] - 1: Light, 2: Balanced, 3: Stable

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

    vec2 px = 1.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));

    // 3x3 neighborhood min/max clipping: prevents history from leaking across
    // disocclusions and high contrast edges, which is the main source of TAA ghosting.
    vec3 cMin = currentColor;
    vec3 cMax = currentColor;
    vec3 cAvg = vec3(0.0);
    float count = 0.0;

    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            vec3 c = texture(colortex0, texcoord + vec2(x, y) * px).rgb;
            cMin = min(cMin, c);
            cMax = max(cMax, c);
            cAvg += c;
            count += 1.0;
        }
    }
    cAvg /= count;

    // Slightly expand the clamp box to preserve subpixel highlights without
    // allowing old-frame colors to bleed far outside the current neighborhood.
    vec3 boxExtent = max((cMax - cMin) * 0.58, vec3(0.015));
    vec3 historyColor = clamp(historySample.rgb, cAvg - boxExtent, cAvg + boxExtent);

    float historyWeight = 0.78;
#if TAA_STRENGTH == 1
    historyWeight = 0.64;
#elif TAA_STRENGTH == 3
    historyWeight = 0.88;
#endif

    // Reduce temporal accumulation during fast motion to avoid trails.
    vec2 motionPixels = fma(texcoord - previousUV, vec2(viewWidth, viewHeight), vec2(0.0));
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
