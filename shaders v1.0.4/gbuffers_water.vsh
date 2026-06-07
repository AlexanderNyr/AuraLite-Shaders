#version 460 compatibility
// AuraLite Shaders v1.0.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Water Vertex Shader (GLSL 460 - Storm Waves)
// ==============================================================================
// [FIX v0.2.5] Added lmcoord output for proper G-buffer data in fragment shader.
// [v1.0.4] Added isRegularIce, isPackedIce, isGlass detection for proper ice/glass
//          rendering with block textures instead of water-biome color.
// [v1.0.4] fma() fused multiply-add optimizations for wave math.

#define WATER_WAVES // [true false]
#define WIND_SPEED 2 // [1 2 3]



out vec2 texcoord;
out vec2 lmcoord;   // [FIX v0.2.5] Lightmap coordinates for composite lighting
out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;
out float isIce;        // 1.0 if any ice, 0.0 otherwise
out float isRegularIce; // [v1.0.4] 1.0 if regular ice (ID 10005), 0.0 otherwise
out float isPackedIce;  // [v1.0.4] 1.0 if packed/blue/frosted ice (ID 10007)
out float isGlass;      // [v1.0.4] 1.0 if glass (ID 10008), 0.0 otherwise
out float isPortal;     // 1.0 if Nether Portal, 0.0 if water/ice/glass

in vec4 mc_Entity; // Block ID attribute sent by Iris/OptiFine
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    lmcoord = clamp(gl_MultiTexCoord1.xy * 0.004166667, 0.0, 1.0); // [FIX v0.2.5]
    glcolor = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);

    vec4 position = gl_Vertex;

    // Check block IDs
    // [v1.0.4] Split ice into regular (10005) and packed/blue (10007);
    //          added glass (10008) for proper textured transparency.
    float entityId = mc_Entity.x;
    isRegularIce = (entityId == 10005.0) ? 1.0 : 0.0;
    isPackedIce  = (entityId == 10007.0) ? 1.0 : 0.0;
    isIce        = max(isRegularIce, isPackedIce); // legacy compat
    isGlass      = (entityId == 10008.0) ? 1.0 : 0.0;
    isPortal     = (entityId == 10006.0) ? 1.0 : 0.0;

    #ifdef WATER_WAVES
    // Only apply wave displacement to water (not ice, not glass, not portals)
    // and only to top faces.
    // [v1.0.4] Extended guard: ice AND glass skip wave displacement.
    if (isIce < 0.5 && isGlass < 0.5 && isPortal < 0.5 && gl_Normal.y > 0.5) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif

        // Dynamically boost water wave speed during storms (choppy oceans!)
        speedFactor = fma(mix(1.3, 1.8, thunderStrength) - 1.0, rainStrength, speedFactor);

        float t = fma(frameTimeCounter, 1.6 * speedFactor, 0.0);

        // Fused Multiply-Add wave simulation [v1.0.4 fma]
        float wave = fma(sin(fma(position.x, 2.2, fma(position.z, 1.8, t))), 0.04,
                     cos(fma(position.x, 1.2, fma(position.z, -2.2, fma(t, 0.9, 0.0)))) * 0.02);

        // Slightly higher waves during storms
        position.y = fma(wave, mix(1.0, 1.45, rainStrength), position.y);
    }
    #endif

    vec4 viewPosition = gl_ModelViewMatrix * position;
    viewPos = viewPosition.xyz;
    gl_Position = gl_ProjectionMatrix * viewPosition;

}
