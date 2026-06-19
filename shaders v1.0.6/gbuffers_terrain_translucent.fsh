#version 460 compatibility
// AuraLite Shaders v1.0.6 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

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
in float isLava;

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

// Procedural Voronoi crack generator (finds exact distance to cell borders)
float voronoiCracks(vec2 p) {
    vec2 n = floor(p);
    vec2 f = fract(p);
    
    // First pass: find closest cell center
    vec2 mg, mr;
    float md = 8.0;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = vec2(hash(n + g), hash(n + g + vec2(15.2, 37.8))) * 0.5 + 0.25;
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < md) {
                md = d;
                mr = r;
                mg = g;
            }
        }
    }
    
    // Second pass: find distance to closest edge
    float md2 = 8.0;
    for (int j = -2; j <= 2; ++j) {
        for (int i = -2; i <= 2; ++i) {
            vec2 g = mg + vec2(float(i), float(j));
            vec2 o = vec2(hash(n + g), hash(n + g + vec2(15.2, 37.8))) * 0.5 + 0.25;
            vec2 r = g + o - f;
            if (dot(mr - r, mr - r) > 1e-5) {
                float d = dot(0.5 * (mr + r), normalize(r - mr));
                md2 = min(md2, d);
            }
        }
    }
    return md2;
}

// Procedural Height field of Lava (1.0 = top crust, 0.0 = deep cracks)
float getLavaHeight(vec2 p) {
    float cracks = voronoiCracks(p * 1.8);
    float height = smoothstep(0.0, 0.22, cracks);
    return height;
}

void main() {
    // ======================================================================
    // 0. LAVA / MAGMA BLOCK (ID 10009)
    // ======================================================================
    if (isLava > 0.5) {
        vec3 N = normalize(normal);
        vec3 helper = abs(N.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
        vec3 tangent = normalize(cross(helper, N));
        vec3 binormal = normalize(cross(N, tangent));
        mat3 tbn = mat3(tangent, binormal, N);

        float t = frameTimeCounter * 0.12;
        vec2 lavaUV = texcoord * 3.5;
        
        // Slow convection flow using noise
        vec2 flow = vec2(
            noise(lavaUV + vec2(t * 0.5, t * 0.2)),
            noise(lavaUV * 1.3 - vec2(t * 0.3, t * 0.6))
        ) * 0.18;
        
        // Tangent-space view vector
        vec3 V_tangent = normalize(transpose(tbn) * normalize(-viewPos));
        
        // Parallax Occlusion: 4-step raymarch for physical 3D cracks!
        float currentLayerDepth = 0.0;
        float layerDepth = 1.0 / 4.0;
        vec2 deltaTexCoords = V_tangent.xy * 0.022 / 4.0;
        vec2 currentTexCoords = p;
        float heightFromTexture = 1.0 - getLavaHeight(currentTexCoords);
        
        for (int i = 0; i < 4; ++i) {
            if (currentLayerDepth >= heightFromTexture) break;
            currentTexCoords -= deltaTexCoords;
            heightFromTexture = 1.0 - getLavaHeight(currentTexCoords);
            currentLayerDepth += layerDepth;
        }
        
        vec2 offsetUV = texcoord + V_tangent.xy * 0.015 * (1.0 - getLavaHeight(currentTexCoords));
        
        // Now calculate cracks and height with displaced coordinates
        vec2 displacedLavaUV = offsetUV * 3.5;
        vec2 displacedFlow = vec2(
            noise(displacedLavaUV + vec2(t * 0.5, t * 0.2)),
            noise(displacedLavaUV * 1.3 - vec2(t * 0.3, t * 0.6))
        ) * 0.18;
        
        vec2 p_displaced = displacedLavaUV + displacedFlow;
        float h = getLavaHeight(p_displaced);
        float crackStrength = 1.0 - h;
        
        // Base temperature inside cracks (rich glowing orange-red, not washed out)
        float crackNoise = fbm(p_displaced * 3.5);
        float temperature = crackStrength * (crackNoise * 0.5 + 0.3);
        
        // Localized hot spots (rare and high-contrast, not everywhere)
        float hotSpotNoise = pow(fbm(p_displaced * 1.5), 5.0) * 4.5 * crackStrength;
        
        // Pulsing rising bubbles (highly localized using high power)
        vec2 bubbleUV = p_displaced * 6.0;
        float b1 = noise(bubbleUV + vec2(0.0, frameTimeCounter * 1.2));
        float b2 = noise(bubbleUV * 1.5 - vec2(0.0, frameTimeCounter * 0.8));
        float bubbles = pow(b1 * b2, 8.0) * 16.0 * crackStrength;
        
        // Basalt crust color (darker charcoal for better contrast)
        vec3 crust = texture(gtexture, offsetUV).rgb * glcolor.rgb;
        if (length(crust) < 0.01) crust = vec3(0.06, 0.03, 0.03);
        else crust *= 0.35; // slightly darken crust to emphasize cracks
        
        // Liquid hot magma colors (gradient from deep volcanic red to rich orange)
        vec3 hotLava = mix(vec3(0.72, 0.04, 0.002), vec3(0.98, 0.42, 0.01), clamp(temperature * 1.5, 0.0, 1.0));
        
        // Mix in localized yellow-orange hot spots
        hotLava = mix(hotLava, vec3(1.0, 0.65, 0.05), clamp(hotSpotNoise - 0.85, 0.0, 1.0));
        // Add extreme heat spots (yellow-white)
        hotLava = mix(hotLava, vec3(1.0, 0.95, 0.65), clamp(bubbles - 0.9, 0.0, 1.0));
        
        // Mix basalt crust and lava colors based on height
        vec3 lavaColor = mix(crust * 0.35, hotLava * 1.85, crackStrength);
        
        // Pulsing breathing glow
        float pulse = sin(frameTimeCounter * 0.6) * 0.10 + 0.90;
        lavaColor *= pulse;
        
        colortex0 = vec4(lavaColor, 1.0);
        // PBR: Basalt plate is rough (0.95), magma cracks are extremely glossy/glassy (0.02)
        float lavaRoughness = mix(0.95, 0.02, crackStrength);
        colortex1 = vec4(lmcoord, lavaRoughness, 0.0);
        // Alpha set to 0.1 to flag it specifically as Lava (allows final.fsh to detect and apply Heat Shimmer!)
        colortex2 = vec4(N * 0.5 + 0.5, 0.1);
        return;
    }

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
