#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Fullscreen Composite Pass (GLSL 460 - Volumetric Clouds)
// ==============================================================================

#define SHADOWS             // [true false]
#define SHADOW_RES 2048     // [1024 2048 4096]
#define LIGHTMAP_WARMTH 2   // [1 2 3]
#define FOG_DENSITY_LEVEL 2 // [1 2 3]
#define PBR_LIGHTING        // [true false]
#define PBR_STRENGTH 2      // [1 2 3]
#define PROCEDURAL_CLOUDS   // [true false]
#define CLOUD_HEIGHT 2      // [1 2 3]
#define CLOUD_THICKNESS 2   // [1 2 3]

/* DRAWBUFFERS:0 */

uniform sampler2D colortex0; // Albedo / baked color from gbuffers
uniform sampler2D colortex1; // Lightmap coordinates, PBR Roughness (z), Metalness (w)
uniform sampler2D colortex2; // Normals (Packed in view space)
uniform sampler2D depthtex0; // World depth buffer
uniform sampler2D shadowtex0; // Shadow depth buffer

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 shadowLightPosition; // Active light source direction (Sun/Moon)
uniform vec3 cameraPosition;      // Player's actual world coordinates
uniform float frameTimeCounter;
uniform float rainStrength;
uniform int worldTime;

layout(location = 0) in vec2 texcoord;

// Declare explicit output for modern GLSL 460 compatibility
layout(location = 0) out vec4 colortex0Out;

// ==============================================================================
// HIGH-PERFORMANCE NOISE FOR VOLUMETRIC CLOUDS (GLSL 460 Integer Bitwise PCG-style)
// ==============================================================================
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

// ==============================================================================
// PHYSICALLY FLYABLE, SUN-REACTIVE 3D VOLUMETRIC CLOUDS
// ==============================================================================
vec4 renderVolumetricClouds(vec3 worldDir, vec3 lightDir, vec3 lightColor, float terrainDist, float dayFactor, float t) {
    // 1. Calculate user height and thickness settings
    float cloudMinY = 160.0;
    #if CLOUD_HEIGHT == 1
    cloudMinY = 110.0;
    #elif CLOUD_HEIGHT == 3
    cloudMinY = 240.0;
    #endif
    
    float cloudThickness = 80.0;
    #if CLOUD_THICKNESS == 1
    cloudThickness = 40.0;
    #elif CLOUD_THICKNESS == 3
    cloudThickness = 120.0;
    #endif
    
    float cloudMaxY = cloudMinY + cloudThickness;
    
    // 2. Perform intersection test with cloud horizontal planes in world coordinates
    float t_start = 0.0;
    float t_end = 0.0;
    
    if (abs(worldDir.y) > 0.001) {
        float t1 = (cloudMinY - cameraPosition.y) / worldDir.y;
        float t2 = (cloudMaxY - cameraPosition.y) / worldDir.y;
        t_start = min(t1, t2);
        t_end = max(t1, t2);
    } else {
        // Parallel horizontal rays
        if (cameraPosition.y >= cloudMinY && cameraPosition.y <= cloudMaxY) {
            t_start = 0.0;
            t_end = 2500.0;
        } else {
            return vec4(0.0); // Never intersects
        }
    }
    
    t_start = max(0.0, t_start);
    t_end = min(2500.0, t_end);
    
    // 3. Terrain Occlusion Check
    // If the cloud layer is behind a mountain/terrain, do not render
    if (t_start >= terrainDist) return vec4(0.0);
    t_end = min(t_end, terrainDist); // Clip ray at mountain surface
    
    if (t_start >= t_end) return vec4(0.0);
    
    // 4. Raymarching Loop (10 steps)
    float stepSize = (t_end - t_start) / 10.0;
    float transmission = 1.0;
    vec3 cloudLighting = vec3(0.0);
    
    for (int i = 0; i < 10; ++i) {
        float curr_t = t_start + (float(i) * stepSize);
        vec3 p = cameraPosition + worldDir * curr_t;
        
        // Wind drift animation
        vec2 uv = p.xz * 0.0018 + vec2(t * 0.12, t * 0.04);
        float d = fbm(uv);
        
        // Vertical density scaling
        float hFactor = clamp((p.y - cloudMinY) / cloudThickness, 0.0, 1.0);
        float heightProfile = hFactor * (1.0 - hFactor) * 4.0;
        
        // Rain/Storm density thresholding
        float cloudMin = mix(0.42, 0.18, rainStrength);
        float cloudMax = mix(0.68, 0.48, rainStrength);
        float stepDensity = smoothstep(cloudMin, cloudMax, d) * heightProfile * 0.32;
        
        if (stepDensity > 0.0) {
            // Light self-shadowing towards sun/moon (Beer's Law)
            vec3 lightPos = p + lightDir * 35.0;
            float dLight = fbm(lightPos.xz * 0.0018 + vec2(t * 0.12, t * 0.04));
            float shadowDensity = smoothstep(cloudMin, cloudMax, dLight);
            float shadow = exp(-shadowDensity * 3.5);
            
            // Clouds react dynamically to direct sun/moon light colors
            vec3 dayCloudLight = mix(vec3(0.12, 0.16, 0.24) * 0.65, lightColor * 0.9, shadow);
            vec3 stormyCloudLight = vec3(0.06, 0.07, 0.08); // Storm overcast
            vec3 stepLighting = mix(dayCloudLight, stormyCloudLight, rainStrength);
            
            // Mie scattering silver linings (Golden edge illumination)
            float sunGlint = pow(max(0.0, dot(worldDir, lightDir) * 0.5 + 0.5), 4.0);
            stepLighting += vec3(1.0, 0.92, 0.82) * sunGlint * stepDensity * 0.5 * (1.0 - rainStrength) * dayFactor;
            
            // Accumulate
            cloudLighting += stepLighting * stepDensity * transmission;
            transmission *= (1.0 - stepDensity);
            
            // Early-ray termination
            if (transmission < 0.02) {
                transmission = 0.0;
                break;
            }
        }
    }
    
    // Smooth horizon blending
    float horizonFade = smoothstep(0.0, 0.12, abs(worldDir.y));
    return vec4(cloudLighting, (1.0 - transmission) * horizonFade);
}

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position) {
    vec4 homPos = projectionMatrix * vec4(position, 1.0);
    return homPos.xyz / homPos.w;
}

float sampleShadow(vec3 shadowScreenPos) {
    if (shadowScreenPos.x < 0.0 || shadowScreenPos.x > 1.0 ||
        shadowScreenPos.y < 0.0 || shadowScreenPos.y > 1.0 ||
        shadowScreenPos.z < 0.0 || shadowScreenPos.z > 1.0) {
        return 1.0;
    }

    float shadow = 0.0;
    float texelSize = 1.0 / float(SHADOW_RES);
    
    // 3x3 PCF filter
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            vec2 offset = vec2(x, y) * texelSize;
            float depth = texture(shadowtex0, shadowScreenPos.xy + offset).r;
            shadow += step(shadowScreenPos.z, depth);
        }
    }
    return shadow / 9.0;
}

void main() {
    float depth = texture(depthtex0, texcoord).r;
    vec4 albedoData = texture(colortex0, texcoord);
    
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
    
    // Sunlight / Moonlight base colors (Calibrated to prevent flat overexposure)
    vec3 baseLightColor = mix(vec3(0.08, 0.12, 0.22) * 0.45, vec3(1.0, 0.95, 0.85) * 1.95, dayFactor);
    vec3 warmColor = vec3(1.05, 0.42, 0.1) * 2.1; // Rich, golden sunset
    vec3 currentLightColor = mix(baseLightColor, warmColor, sunsetFactor * dayFactor);
    
    currentLightColor *= (1.0 - rainStrength * 0.92);
    
    vec3 L = normalize(shadowLightPosition);
    
    // Calculate world space view direction
    vec3 viewDir = normalize(projectAndDivide(gbufferProjectionInverse, vec3(texcoord.xy, depth) * 2.0 - 1.0));
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewDir);
    vec3 worldL = normalize(mat3(gbufferModelViewInverse) * L);
    
    // Rebuild view space distance (terrain block distance)
    vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
    vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
    float terrainDist = length(viewPos);
    
    if (depth >= 1.0) {
        // Sky or void - just draw the sky but blend our gorgeous volumetric clouds on top!
        vec3 finalColor = albedoData.rgb;
        #ifdef PROCEDURAL_CLOUDS
        float cloudTime = frameTimeCounter * 0.05;
        vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, 2500.0, dayFactor, cloudTime);
        finalColor = mix(finalColor, volClouds.rgb, volClouds.a);
        #endif
        colortex0Out = vec4(finalColor, albedoData.a);
        return;
    }
    
    float shadow = 1.0;
    #ifdef SHADOWS
    // Project to shadow space
    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
    vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
    shadowClipPos.z -= 0.0014;
    vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
    vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;
    
    shadow = sampleShadow(shadowScreenPos);
    #endif
    
    // Attributes, Lightmaps & PBR Data
    vec3 normal = normalize(texture(colortex2, texcoord).xyz * 2.0 - 1.0);
    vec4 lmData = texture(colortex1, texcoord);
    float blockLight = lmData.r;
    float skyLight = lmData.g;
    
    // Lambert Shading
    float NdotL = max(0.0, dot(normal, L));
    
    float shadowFactor = mix(mix(0.25, 1.0, shadow), shadow, dayFactor);
    vec3 directLighting = currentLightColor * NdotL * skyLight * shadowFactor;
    
    // Torch lighting (Block light) with custom warmth setting
    float blockIntensity = pow(blockLight, 3.2);
    vec3 torchColor = vec3(1.0, 0.55, 0.15) * 2.3;
    #if LIGHTMAP_WARMTH == 1
    torchColor = vec3(1.0, 0.5, 0.1) * 1.8;
    #elif LIGHTMAP_WARMTH == 3
    torchColor = vec3(1.0, 0.6, 0.22) * 2.7;
    #endif
    vec3 torchLighting = torchColor * blockIntensity;
    
    // Ambient Shading (Beautiful blue sky bounce during the day)
    vec3 baseAmbient = mix(vec3(0.015, 0.02, 0.04), vec3(0.12, 0.18, 0.28) * 0.7, skyLight);
    vec3 dayAmbient = mix(baseAmbient, vec3(0.38, 0.48, 0.6) * 0.8, skyLight);
    vec3 ambientColor = mix(baseAmbient, dayAmbient, dayFactor);
    
    // Darken and grey ambient light during rain
    vec3 stormyAmbient = vec3(0.06, 0.07, 0.08) * skyLight;
    ambientColor = mix(ambientColor, stormyAmbient, rainStrength * 0.85);
    
    // Lighting execution
    vec3 albedo = pow(albedoData.rgb, vec3(2.2));
    vec3 finalLight = directLighting + torchLighting + ambientColor;
    vec3 shadedTerrain = albedo * finalLight;
    
    // PBR Microfacet Specular shading (LabPBR support)
    #ifdef PBR_LIGHTING
    float roughness = lmData.z;
    float metalness = lmData.w;
    if (roughness > 0.001 || metalness > 0.001) {
        vec3 V = normalize(-viewPos);
        vec3 H = normalize(L + V);
        
        float shininess = mix(120.0, 2.0, roughness);
        float specFactor = pow(max(0.0, dot(normal, H)), shininess);
        
        float pbrStrengthMult = 1.0;
        #if PBR_STRENGTH == 1
        pbrStrengthMult = 0.45;
        #elif PBR_STRENGTH == 3
        pbrStrengthMult = 2.05;
        #endif
        
        vec3 F0 = mix(vec3(0.04), albedo, metalness);
        vec3 specColor = F0 * specFactor * (1.0 - roughness) * skyLight * shadowFactor * pbrStrengthMult;
        
        shadedTerrain += specColor * currentLightColor;
    }
    #endif
    
    // Fog calculations with custom density level
    vec3 dayFog = vec3(0.55, 0.68, 0.82);
    vec3 nightFog = vec3(0.01, 0.02, 0.04);
    vec3 sunsetFog = vec3(0.8, 0.38, 0.12);
    
    vec3 currentFogColor = mix(nightFog, dayFog, dayFactor);
    currentFogColor = mix(currentFogColor, sunsetFog, sunsetFactor * dayFactor);
    
    vec3 rainFogColor = vec3(0.14, 0.16, 0.18);
    currentFogColor = mix(currentFogColor, rainFogColor, rainStrength);
    
    float baseDensity = 0.0013;
    #if FOG_DENSITY_LEVEL == 1
    baseDensity = 0.0008;
    #elif FOG_DENSITY_LEVEL == 3
    baseDensity = 0.0025;
    #endif
    
    float fogDensity = mix(baseDensity, baseDensity * 5.0, rainStrength);
    float fogFactor = 1.0 - exp(-terrainDist * fogDensity);
    fogFactor = clamp(fogFactor, 0.0, 1.0);
    
    vec3 finalColor = mix(shadedTerrain, currentFogColor, fogFactor);
    
    // Blend our gorgeous volumetric clouds in front of distant fog, but behind mountains!
    #ifdef PROCEDURAL_CLOUDS
    float cloudTime = frameTimeCounter * 0.05;
    vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, terrainDist, dayFactor, cloudTime);
    finalColor = mix(finalColor, volClouds.rgb, volClouds.a);
    #endif
    
    colortex0Out = vec4(finalColor, albedoData.a);
}
