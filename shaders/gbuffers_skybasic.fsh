#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Sky Fragment Shader (GLSL 460 - Kelvin Sun & Crispy Moon)
// ==============================================================================

#define PROCEDURAL_CLOUDS // [true false]

/* DRAWBUFFERS:0 */

in vec4 glcolor;
in vec3 viewPos;

uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
uniform int worldTime;
uniform float rainStrength;

// Declare explicit output for modern GLSL 460 compatibility
layout(location = 0) out vec4 colortex0;

// ==============================================================================
// ANALYTICAL KELVIN TEMPERATURE TO RGB CONVERSION
// ==============================================================================
vec3 kelvinToRGB(float k) {
    k = clamp(k, 1000.0, 40000.0) / 100.0;
    float r, g, b;
    
    if (k <= 66.0) {
        r = 255.0;
        g = clamp(99.4708025861 * log(k) - 161.1195681661, 0.0, 255.0);
        if (k < 19.0) {
            b = 0.0;
        } else {
            b = clamp(138.5177312231 * log(k - 10.0) - 305.0447927307, 0.0, 255.0);
        }
    } else {
        r = clamp(329.698727446 * pow(k - 60.0, -0.1332047592), 0.0, 255.0);
        g = clamp(288.1221695283 * pow(k - 60.0, -0.0755148492), 0.0, 255.0);
        b = 255.0;
    }
    
    return vec3(r, g, b) / 255.0;
}

// EXTREMELY FAST INTEGER BITWISE PCG-STYLE HASH (GLSL 460 Native Hardware)
float hash(vec2 p) {
    uvec2 u = floatBitsToUint(p);
    u = u * 1107332578u + uvec2(12345u, 67890u);
    u.x += u.y * 3202034522u;
    u.y += u.x * 2910403541u;
    u ^= u >> 16u;
    return uintBitsToFloat((u.x & 0x007FFFFFu) | 0x3F800000u) - 1.0;
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
        v = fma(a, noise(p), v);
        p = rot * p * 2.1 + shift;
        a *= 0.5;
    }
    return v;
}

// PHYSICALLY-BASED 3D RAYMARCHED VOLUMETRIC CLOUDS
vec4 renderVolumetricClouds(vec3 viewDir, vec3 lightDir, vec3 lightColor, float t) {
    if (viewDir.y < 0.02) return vec4(0.0);
    
    float cloudStartHeight = 250.0;
    float cloudThickness = 90.0;
    
    float t_start = cloudStartHeight / viewDir.y;
    float t_end = (cloudStartHeight + cloudThickness) / viewDir.y;
    
    if (t_start > 3000.0) return vec4(0.0);
    
    float stepSize = (t_end - t_start) / 10.0;
    vec3 p = viewDir * t_start;
    
    float densityAccum = 0.0;
    float transmission = 1.0;
    vec3 cloudLighting = vec3(0.0);
    
    for (int i = 0; i < 10; ++i) {
        vec2 uv = p.xz * 0.0018 + vec2(t * 0.12, t * 0.04);
        float d = fbm(uv);
        
        float hFactor = clamp((p.y - cloudStartHeight) / cloudThickness, 0.0, 1.0);
        float heightProfile = hFactor * (1.0 - hFactor) * 4.0;
        
        float cloudMin = mix(0.42, 0.18, rainStrength);
        float cloudMax = mix(0.68, 0.48, rainStrength);
        float stepDensity = smoothstep(cloudMin, cloudMax, d) * heightProfile * 0.32;
        
        if (stepDensity > 0.0) {
            vec3 lightPos = p + lightDir * 35.0;
            float dLight = fbm(lightPos.xz * 0.0018 + vec2(t * 0.12, t * 0.04));
            float shadowDensity = smoothstep(cloudMin, cloudMax, dLight);
            float shadow = exp(-shadowDensity * 3.5);
            
            vec3 dayCloudLight = mix(vec3(0.12, 0.16, 0.24) * 0.7, lightColor * 0.85, shadow);
            vec3 stormyCloudLight = vec3(0.08, 0.09, 0.1);
            vec3 stepLighting = mix(dayCloudLight, stormyCloudLight, rainStrength);
            
            float sunGlint = pow(max(0.0, dot(viewDir, lightDir) * 0.5 + 0.5), 4.0);
            stepLighting += vec3(1.0, 0.9, 0.78) * sunGlint * stepDensity * 0.45 * (1.0 - rainStrength);
            
            cloudLighting += stepLighting * stepDensity * transmission;
            densityAccum += stepDensity * transmission;
            transmission *= (1.0 - stepDensity);
            
            if (transmission < 0.02) {
                transmission = 0.0;
                break;
            }
        }
        
        p += viewDir * stepSize;
    }
    
    float horizonFade = smoothstep(0.02, 0.18, viewDir.y);
    return vec4(cloudLighting, (1.0 - transmission) * horizonFade);
}

void main() {
    vec3 dir = normalize(viewPos);
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * dir);
    float dotUp = worldDir.y;
    
    // Dynamic Day/Night & Sunset transition based on precise worldTime
    float time = float(worldTime);
    
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
    vec3 nightSky = mix(vec3(0.004, 0.006, 0.012), vec3(0.0005, 0.001, 0.003), gradHeight); // 2x Darker night sky!
    vec3 sunsetSky = mix(vec3(0.85, 0.42, 0.12), vec3(0.18, 0.08, 0.28), gradHeight);
    
    vec3 skyColor = mix(nightSky, daySky, dayFactor);
    skyColor = mix(skyColor, sunsetSky, sunsetFactor * dayFactor);
    
    vec3 rainSky = vec3(0.05, 0.055, 0.065); // 2x Darker rain sky
    skyColor = mix(skyColor, rainSky, rainStrength * 0.85);
    
    vec3 baseSky = mix(glcolor.rgb, skyColor, 0.85);
    
    float horizonGlow = clamp(1.0 - abs(dotUp), 0.0, 1.0);
    horizonGlow = pow(horizonGlow, 4.5);
    
    // 3. Dynamic Sun & Moon Glow
    vec3 worldL = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    float dotLight = dot(worldDir, worldL);
    
    vec3 glowColor = vec3(0.0);
    vec3 sunLightColor = vec3(1.0);
    
    if (dayFactor > 0.1) {
        // Calculate Kelvin sun color and extinction
        float sinAlpha = max(0.01, worldL.y);
        float alpha = asin(sinAlpha);
        float currentK = 1800.0 + 4000.0 * sqrt(sinAlpha);
        float airMass = 1.0 / (sinAlpha + 0.15 * pow(alpha * 57.29577951 + 3.885, -1.253));
        float extinction = exp(-airMass * 0.12);
        sunLightColor = kelvinToRGB(currentK) * extinction;
        
        float sunGlow = max(0.0, dotLight);
        // Sharp round procedural sun disk + soft scattering halo
        float sunDisk = smoothstep(0.9994, 0.9996, dotLight);
        float corona = pow(sunGlow, 180.0) * 0.95;
        float halo = pow(sunGlow, 10.0) * 0.25 * dayFactor;
        glowColor = sunLightColor * (sunDisk * 5.0 + corona + halo);
    } else {
        // Crisp sharp moon disk + moonlight scattering halo
        float dotMoon = dot(worldDir, -worldL);
        float moonGlow = max(0.0, dotMoon);
        float moonDisk = smoothstep(0.9996, 0.9998, dotMoon);
        float moonCorona = pow(moonGlow, 260.0) * 0.5;
        float moonHalo = pow(moonGlow, 14.0) * 0.12 * (1.0 - dayFactor);
        glowColor = vec3(0.85, 0.92, 1.0) * (moonDisk * 3.0 + moonCorona + moonHalo) * 0.5; // 2x Darker moon glow
    }
    
    glowColor *= (1.0 - rainStrength * 0.95);
    
    vec3 finalSky = baseSky + glowColor + baseSky * horizonGlow * 0.28;
    
    // 4. Procedural Volumetric 3D Clouds (on sky hemisphere)
    #ifdef PROCEDURAL_CLOUDS
    float cloudTime = frameTimeCounter * 0.05;
    vec4 volClouds = renderVolumetricClouds(worldDir, worldL, sunLightColor, cloudTime);
    finalSky = mix(finalSky, volClouds.rgb, volClouds.a);
    #endif
    
    colortex0 = vec4(finalSky, glcolor.a);
}
