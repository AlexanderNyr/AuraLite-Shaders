#version 460 compatibility
// AuraLite Shaders v1.1.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Water Fragment Shader
// ==============================================================================
// DH has no per-block textures, but it supplies a vertex colour, normal and LOD
// depth. This pass writes AuraLite's normal/lightmap/material-tag layout so the
// shared composite water path can light distant water consistently.
//
// [v1.1.4] Mirrors the user-facing water options, applies the frozen-ocean navy
// floor and uses a hard DH hand-off to avoid stochastic boundary holes.

#define WATER_TRANSPARENCY 2       // [1 2 3]
#define WATER_RIFFLES 2            // [1 2 3]
#define WATER_SPECULAR_STRENGTH 2  // [1 2 3]

/* DRAWBUFFERS:012 */

uniform float far;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform sampler2D dhDepthTex1; // DH solid-only depth, same dhProjection as this fragment
// Iris 1.7.6 exposes the regular solid depth and projection to DH programs.
// Keep this optional so non-Iris loaders retain the DH-only safety path.
#ifdef IS_IRIS
uniform sampler2D depthtex1;
uniform mat4 gbufferProjectionInverse;
#endif

in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;
in vec2 lmcoord;

layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

#ifdef IS_IRIS
vec3 vanillaScreenToView(vec2 uv, float depth) {
    vec4 ndc = vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * ndc;
    return view.xyz / view.w;
}
#endif

void main() {
    float distToCamera = length(viewPos);

    // Match dh_terrain: never dither/discard a random subset in the seam band.
    // The old 16m screen-door transition was the source of visible white holes.
    if (distToCamera < far) discard;

    // HARD OCCLUSION GUARD FOR DH WATER.
    // dhDepthTex1 shares this fragment's dhProjection, so it reliably removes
    // water hidden behind closer DH LOD terrain/walls before translucent output.
    vec2 screenUV = gl_FragCoord.xy / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));

    // On Iris, also cull water behind a genuinely closer vanilla foreground
    // block. Raw depths use different projections, so compare reconstructed
    // view-space Z rather than comparing raw texture values.
    #ifdef IS_IRIS
    float vanillaSolidDepth = texture(depthtex1, screenUV).r;
    if (vanillaSolidDepth < 0.99999) {
        vec3 vanillaSolidView = vanillaScreenToView(screenUV, vanillaSolidDepth);
        float depthEpsilon = max(0.05, abs(viewPos.z) * 0.0005);
        if (vanillaSolidView.z > viewPos.z + depthEpsilon) discard;
    }
    #endif

    float dhSolidDepth = texture(dhDepthTex1, screenUV).r;
    if (dhSolidDepth < gl_FragCoord.z - 1e-5) discard;

    vec3 waterColor = glcolor.rgb;
    if (length(waterColor) < 0.1) {
        waterColor = vec3(0.08, 0.42, 0.68);
    }
    // Same frozen-ocean safeguard as near water: preserve hue while preventing
    // navy biome tints from crushing red/green into black after deferred gamma.
    waterColor = max(waterColor, waterColor.b * vec3(0.16, 0.34, 1.0));

    float t = frameTimeCounter * 1.5;
    float riffScale = 0.0030;
    #if WATER_RIFFLES == 1
    riffScale = 0.0013;
    #elif WATER_RIFFLES == 3
    riffScale = 0.0055;
    #endif

    vec2 waveOffset = vec2(
        sin(viewPos.x * 2.5 + viewPos.z * 1.8 + t),
        cos(viewPos.x * 1.5 - viewPos.z * 2.5 + t * 0.8)
    ) * riffScale;

    vec3 N = normalize(normal);
    vec3 helper = abs(N.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(helper, N));
    vec3 bitangent = normalize(cross(N, tangent));
    N = normalize(tangent * waveOffset.x * 2.7 + bitangent * waveOffset.y * 2.7 + N);

    vec3 V = normalize(-viewPos);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float fresnel = pow(1.0 - NdotV, 5.0) * 0.98 + 0.02;

    float baseOpacity = 0.55;
    #if WATER_TRANSPARENCY == 1
    baseOpacity = 0.32;
    #elif WATER_TRANSPARENCY == 3
    baseOpacity = 0.82;
    #endif

    float waterRoughness = 0.055;
    #if WATER_SPECULAR_STRENGTH == 1
    waterRoughness = 0.110;
    #elif WATER_SPECULAR_STRENGTH == 3
    waterRoughness = 0.032;
    #endif

    colortex0 = vec4(waterColor, mix(baseOpacity, 0.92, fresnel));
    colortex1 = vec4(lmcoord, waterRoughness, 0.0);
    colortex2 = vec4(N * 0.5 + 0.5, 0.8);
}
