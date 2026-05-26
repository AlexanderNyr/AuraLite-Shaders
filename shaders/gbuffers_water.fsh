#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Water Fragment Shader (GLSL 460 Optimized with Fresnel)
// ==============================================================================

#define WATER_TRANSPARENCY 2   // [1 2 3]

/* DRAWBUFFERS:0 */

uniform float frameTimeCounter;
uniform vec3 shadowLightPosition; // Active light source direction (Sun/Moon)
uniform int worldTime;

in vec2 texcoord;
in vec4 glcolor; // Water biome tint color
in vec3 normal;  // View space normal
in vec3 viewPos; // View space position

// Declare explicit output for modern GLSL 460 compatibility!
layout(location = 0) out vec4 colortex0;

void main() {
    // 1. Water Base Color
    vec3 waterColor = glcolor.rgb;
    if (length(waterColor) < 0.1) {
        waterColor = vec3(0.08, 0.42, 0.68);
    }
    
    // 2. Wave Normal Perturbation using hardware-level FMA wave math
    float t = frameTimeCounter * 1.5;
    vec2 waveOffset = vec2(
        sin(fma(viewPos.x, 2.5, fma(viewPos.z, 1.8, t))),
        cos(fma(viewPos.x, 1.5, fma(-viewPos.z, 2.5, t * 0.8)))
    ) * 0.0035;
    
    vec3 N = normalize(normal);
    vec3 waveNormal = vec3(waveOffset * 18.0, 1.0);
    N = normalize(N + waveNormal * 0.15);
    
    // 3. Physical Fresnel Effect (reflective at angle, transparent straight down)
    vec3 V = normalize(-viewPos);
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float F0 = 0.02; // Base water reflectivity
    float fresnel = fma(pow(1.0 - NdotV, 5.0), 1.0 - F0, F0);
    
    // 4. Specular Reflections on ripples (Blinn-Phong)
    vec3 L = normalize(shadowLightPosition);
    vec3 H = normalize(L + V);
    float NdotH = max(0.0, dot(N, H));
    float specular = pow(NdotH, 90.0) * 0.85;
    specular *= clamp(dot(normal, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
    
    // Determine light intensity based on active day/night cycle
    float wTime = float(worldTime);
    float dayFactor = 0.0;
    if (wTime >= 0.0 && wTime < 12000.0) {
        dayFactor = 1.0;
    } else if (wTime >= 12000.0 && wTime < 13000.0) {
        dayFactor = 1.0 - (wTime - 12000.0) / 1000.0;
    } else if (wTime >= 13000.0 && wTime < 23000.0) {
        dayFactor = 0.0;
    } else {
        dayFactor = (wTime - 23000.0) / 1000.0;
    }
    
    vec3 specColor = mix(vec3(0.12, 0.22, 0.35) * 0.3, vec3(1.0, 0.95, 0.88) * 1.8, dayFactor) * specular;
    
    // 5. Water Opacity styling
    float baseOpacity = 0.55;
    #if WATER_TRANSPARENCY == 1
    baseOpacity = 0.32; // Crystal clear
    #elif WATER_TRANSPARENCY == 3
    baseOpacity = 0.82; // Deep
    #endif
    
    float opacity = mix(baseOpacity, 0.92, fresnel);
    
    colortex0 = vec4(waterColor + specColor, opacity);
}
