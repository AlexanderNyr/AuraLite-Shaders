#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Final Post-Processing Pass Fragment Shader (GLSL 460)
// ==============================================================================

#define VIGNETTE // [true false]
#define EXPOSURE 2 // [1 2 3]

in vec2 texcoord;

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

// Explicit fragment output for modern GLSL 460
layout(location = 0) out vec4 fragColor;

// ACES Filmic Tonemapping
vec3 ACESFilm(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;
    
    // Calibrated exposure levels: Low setting (1) is now beautifully dark & moody!
    float expFactor = 1.0; // Balanced / Default
    #if EXPOSURE == 1
    expFactor = 0.75;      // Muted / Moody / Dark
    #elif EXPOSURE == 3
    expFactor = 1.35;      // Sunny / Vibrant / Bright
    #endif
    
    color *= expFactor;
    
    // 1. Tonemapping
    color = ACESFilm(color);
    
    // 2. Gamma correction
    color = pow(color, vec3(1.0 / 2.2));
    
    // 3. Vignette
    #ifdef VIGNETTE
    vec2 uv = texcoord - 0.5;
    float vignette = 1.0 - dot(uv, uv) * 0.38;
    color *= clamp(vignette, 0.0, 1.0);
    #endif
    
    fragColor = vec4(color, 1.0);
}
