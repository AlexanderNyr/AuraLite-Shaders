#version 460 compatibility
// AuraLite Shaders v1.0.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Terrain Translucent Fragment Shader (GLSL 460)
// ==============================================================================
// Oculus/Iris compatibility: translucent terrain pass (water, stained glass, ice).
// Mirrors gbuffers_water.fsh so translucent blocks render identically
// whether Iris uses the unified or split translucent path.

#define WATER_TRANSPARENCY 2   // [1 2 3]
#define WATER_RIFFLES 2        // [1 2 3]
#define WATER_SPECULAR_STRENGTH 2 // [1 2 3]

/* DRAWBUFFERS:012 */

uniform sampler2D gtexture;
uniform float frameTimeCounter;
uniform vec3 shadowLightPosition;
uniform int worldTime;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;
in float isIce;
in float isRegularIce;
in float isPackedIce;
in float isGlass;
in float isPortal;

layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), u.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (int i = 0; i < 4; ++i) {
        v += a * noise(p);
        p = (rot * p) * 2.1 + shift;
        a *= 0.5;
    }
    return v;
}

void main() {
    // ======================================================================
    // 1. NETHER PORTAL (ID 10006)
    // ======================================================================
    if (isPortal > 0.5) {
        float t = frameTimeCounter * 0.35;
        vec2 uv = texcoord * 1.5;
        float p1 = fbm(uv + vec2(t * 0.8, t * 0.4));
        float p2 = fbm(uv * 1.8 + vec2(t * -0.5, t * 0.9));
        float plasma = p1 * p2;
        vec3 portalColor = mix(vec3(0.12, 0.015, 0.28), vec3(0.55, 0.12, 0.92), plasma);
        portalColor = vec3(0.85, 0.45, 1.0) * pow(plasma, 3.2) * 1.4 + portalColor;
        colortex0 = vec4(portalColor, 0.85);
        colortex1 = vec4(lmcoord, 0.5, 0.0);
        colortex2 = vec4(normal * 0.5 + 0.5, 0.0);
        return;
    }

    // ======================================================================
    // 2. GLASS (ID 10008)
    // ======================================================================
    if (isGlass > 0.5) {
        vec4 glassTex = texture(gtexture, texcoord);
        vec3 glassColor = glassTex.rgb * glcolor.rgb;
        float glassOpacity = 0.0;
        #if WATER_TRANSPARENCY == 1
        glassOpacity = 0.22;
        #elif WATER_TRANSPARENCY == 2
        glassOpacity = 0.42;
        #elif WATER_TRANSPARENCY == 3
        glassOpacity = 0.62;
        #endif
        glassOpacity = glassTex.a * 0.45 + glassOpacity;
        colortex0 = vec4(glassColor, clamp(glassOpacity, 0.15, 0.85));
        colortex1 = vec4(lmcoord, 0.08, 0.0);
        colortex2 = vec4(normal * 0.5 + 0.5, 1.0);
        return;
    }

    // ======================================================================
    // 3. REGULAR ICE (ID 10005)
    // ======================================================================
    if (isRegularIce > 0.5) {
        vec4 iceTex = texture(gtexture, texcoord);
        vec3 iceColor = iceTex.rgb * glcolor.rgb;
        if (length(iceColor) < 0.05) {
            iceColor = vec3(0.55, 0.72, 0.85);
        }
        float iceOpacity = 0.62;
        #if WATER_TRANSPARENCY == 1
        iceOpacity = 0.42;
        #elif WATER_TRANSPARENCY == 3
        iceOpacity = 0.78;
        #endif
        colortex0 = vec4(iceColor, iceOpacity);
        colortex1 = vec4(lmcoord, 0.12, 0.0);
        colortex2 = vec4(normal * 0.5 + 0.5, 1.0);
        return;
    }

    // ======================================================================
    // 4. PACKED ICE / BLUE ICE / FROSTED ICE (ID 10007)
    // ======================================================================
    if (isPackedIce > 0.5) {
        vec4 packedTex = texture(gtexture, texcoord);
        vec3 packedColor = packedTex.rgb * glcolor.rgb;
        if (length(packedColor) < 0.05) {
            packedColor = vec3(0.45, 0.58, 0.72);
        }
        float packedOpacity = 0.90;
        #if WATER_TRANSPARENCY == 1
        packedOpacity = 0.78;
        #elif WATER_TRANSPARENCY == 3
        packedOpacity = 0.96;
        #endif
        colortex0 = vec4(packedColor, packedOpacity);
        colortex1 = vec4(lmcoord, 0.18, 0.0);
        colortex2 = vec4(normal * 0.5 + 0.5, 1.0);
        return;
    }

    // ======================================================================
    // 5. WATER
    // ======================================================================
    vec3 waterColor = glcolor.rgb;
    if (length(waterColor) < 0.1) {
        waterColor = vec3(0.08, 0.42, 0.68);
    }

    float t = frameTimeCounter * 1.5;
    vec2 waveOffset = vec2(0.0);
    float riffScale = 0.0035;
    #if WATER_RIFFLES == 1
    riffScale = 0.0015;
    #elif WATER_RIFFLES == 3
    riffScale = 0.0065;
    #endif

    waveOffset = vec2(
        sin(viewPos.x * 2.5 + viewPos.z * 1.8 + t),
        cos(viewPos.x * 1.5 + viewPos.z * -2.5 + t * 0.8)
    ) * riffScale;

    vec3 N = normalize(normal);
    vec3 helper = abs(N.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(helper, N));
    vec3 bitangent = normalize(cross(N, tangent));
    N = normalize(tangent * waveOffset.x * 2.7 + bitangent * waveOffset.y * 2.7 + N);

    vec3 V = normalize(-viewPos);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float F0 = 0.02;
    float fresnel = pow(1.0 - NdotV, 5.0) * (1.0 - F0) + F0;

    float baseOpacity = 0.55;
    #if WATER_TRANSPARENCY == 1
    baseOpacity = 0.32;
    #elif WATER_TRANSPARENCY == 3
    baseOpacity = 0.82;
    #endif

    float opacity = mix(baseOpacity, 0.92, fresnel);
    colortex0 = vec4(waterColor, opacity);

    float waterRoughness = 0.055;
    #if WATER_SPECULAR_STRENGTH == 1
    waterRoughness = 0.110;
    #elif WATER_SPECULAR_STRENGTH == 3
    waterRoughness = 0.032;
    #endif

    colortex1 = vec4(lmcoord, waterRoughness, 0.0);
    colortex2 = vec4(N * 0.5 + 0.5, 1.0);
}
