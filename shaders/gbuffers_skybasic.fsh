#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Sky Fragment Shader (GLSL 460 Seamless Dome)
// ==============================================================================

/* DRAWBUFFERS:0 */

in vec4 glcolor;
in vec3 viewPos;

uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;
uniform int worldTime;
uniform float rainStrength;

// Declare explicit output for modern GLSL 460 compatibility!
layout(location = 0) out vec4 colortex0;

void main() {
    vec3 dir = normalize(viewPos);
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * dir);
    float dotUp = worldDir.y;
    
    // Dynamic Day/Night & Sunset transition based on precise worldTime
    float time = float(worldTime);
    
    // Smooth day/night factor: 1.0 during day, 0.0 during night
    float dayFactor = 0.0;
    if (time >= 0.0 && time < 12000.0) {
        dayFactor = 1.0;
    } else if (time >= 12000.0 && time < 13000.0) {
        dayFactor = 1.0 - (time - 12000.0) / 1000.0;
    } else if (time >= 13000.0 && time < 23000.0) {
        dayFactor = 0.0;
    } else {
        dayFactor = (time - 23000.0) / 1000.0;
    }

    // Sunset/sunrise factor: 1.0 during golden hour, 0.0 otherwise
    float sunsetFactor = 0.0;
    if (time >= 11500.0 && time < 12500.0) {
        sunsetFactor = 1.0 - abs(time - 12000.0) / 500.0;
    } else if (time >= 23500.0 || time < 500.0) {
        float t = time >= 23500.0 ? time - 24000.0 : time;
        sunsetFactor = 1.0 - abs(t) / 500.0;
    }
    
    // 2. Smooth Procedural Sky Dome Colors
    float gradHeight = clamp(fma(dotUp, 0.5, 0.5), 0.0, 1.0);
    
    vec3 daySky = mix(vec3(0.42, 0.62, 0.9), vec3(0.12, 0.32, 0.72), gradHeight);
    vec3 nightSky = mix(vec3(0.008, 0.012, 0.024), vec3(0.001, 0.002, 0.006), gradHeight);
    vec3 sunsetSky = mix(vec3(0.85, 0.42, 0.12), vec3(0.18, 0.08, 0.28), gradHeight);
    
    vec3 skyColor = mix(nightSky, daySky, dayFactor);
    skyColor = mix(skyColor, sunsetSky, sunsetFactor * dayFactor);
    
    // Desaturate and darken the sky during rain/thunderstorms
    vec3 rainSky = vec3(0.1, 0.11, 0.13); // Dark slate-grey stormy sky
    skyColor = mix(skyColor, rainSky, rainStrength * 0.85);
    
    // Blend with glcolor to preserve custom dimension colors (Nether / End)
    vec3 baseSky = mix(glcolor.rgb, skyColor, 0.85);
    
    // 3. Smooth Atmospheric Horizon Glow (Haze)
    float horizonGlow = clamp(1.0 - abs(dotUp), 0.0, 1.0);
    horizonGlow = pow(horizonGlow, 4.5);
    
    // 4. Dynamic Sun & Moon Glow
    vec3 worldL = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    float dotLight = dot(worldDir, worldL);
    
    vec3 sunColor = vec3(1.0, 0.92, 0.78);
    vec3 moonColor = vec3(0.55, 0.72, 1.0);
    vec3 glowColor = vec3(0.0);
    
    if (dayFactor > 0.1) {
        // Sun Glow
        float sunGlow = max(0.0, dotLight);
        float corona = pow(sunGlow, 180.0) * 0.95;
        float halo = pow(sunGlow, 12.0) * 0.28 * dayFactor;
        glowColor = sunColor * (corona + halo);
    } else {
        // Moon Glow
        float dotMoon = dot(worldDir, -worldL);
        float moonGlow = max(0.0, dotMoon);
        float moonCorona = pow(moonGlow, 260.0) * 0.5;
        float moonHalo = pow(moonGlow, 14.0) * 0.12 * (1.0 - dayFactor);
        glowColor = moonColor * (moonCorona + moonHalo);
    }
    
    // Obscure the Sun & Moon completely when raining
    glowColor *= (1.0 - rainStrength * 0.95);
    
    vec3 finalSky = baseSky + glowColor + baseSky * horizonGlow * 0.28;
    
    colortex0 = vec4(finalSky, glcolor.a);
}
