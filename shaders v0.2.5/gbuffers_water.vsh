#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Water Vertex Shader (GLSL 460 - Storm Waves)
// ==============================================================================
// [FIX v0.2.5] Added lmcoord output for proper G-buffer data in fragment shader.

#define WATER_WAVES // [true false]
#define WIND_SPEED 2 // [1 2 3]

out vec2 texcoord;
out vec2 lmcoord;   // [FIX v0.2.5] Lightmap coordinates for composite lighting
out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;
out float isIce;    // 1.0 if ice, 0.0 if water/portal
out float isPortal; // 1.0 if Nether Portal, 0.0 if water/ice

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
    float entityId = mc_Entity.x;
    isIce = (entityId == 10005.0) ? 1.0 : 0.0;
    isPortal = (entityId == 10006.0) ? 1.0 : 0.0;

    #ifdef WATER_WAVES
    // Only apply wave displacement to water (not ice, not portals) and only to top faces
    if (isIce < 0.5 && isPortal < 0.5 && gl_Normal.y > 0.5) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif

        // Dynamically boost water wave speed during storms (choppy oceans!)
        speedFactor = mix(speedFactor, speedFactor * mix(1.3, 1.8, thunderStrength), rainStrength);

        float t = frameTimeCounter * 1.6 * speedFactor;

        // Fused Multiply-Add wave simulation
        float wave = sin(position.x * 2.2 + position.z * 1.8 + t) * 0.04
                   + cos(position.x * 1.2 - position.z * 2.2 + t * 0.9) * 0.02;

        // Slightly higher waves during storms
        position.y += wave * mix(1.0, 1.45, rainStrength);
    }
    #endif

    vec4 viewPosition = gl_ModelViewMatrix * position;
    viewPos = viewPosition.xyz;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
