#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Final Post-Processing Pass Fragment Shader (GLSL 460)
// ==============================================================================

#define VIGNETTE // [true false]
#define EXPOSURE 2 // [1 2 3]
#define COLOR_SATURATION 2 // [1 2 3 4]
#define CONTRAST 2 // [1 2 3]

in vec2 texcoord;

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

// Explicit fragment output for modern GLSL 460
layout(location = 0) out vec4 fragColor;

// ACES Filmic Tonemapping (Filmic / Standard)
vec3 ACESFilm(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// Custom Vibrant Saturation controller
vec3 applyVibrancy(vec3 color, float amount) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(color, vec3(luma), amount);
}

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;
    
    // 1. Calibrated exposure levels
    float expFactor = 1.0; // Balanced / Default
    #if EXPOSURE == 1
    expFactor = 0.75;      // Muted / Moody / Dark
    #elif EXPOSURE == 3
    expFactor = 1.35;      // Sunny / Vibrant / Bright
    #endif
    
    color *= expFactor;
    
    // 2. Contrast Modes
    #if CONTRAST == 1
    // Soft Contrast
    color = clamp(mix(color, ACESFilm(color), 0.45), 0.0, 1.0);
    #elif CONTRAST == 2
    // Standard Filmic ACES Contrast
    color = ACESFilm(color);
    #elif CONTRAST == 3
    // High / Intense Contrast
    color = ACESFilm(color);
    color = clamp(pow(color, vec3(1.12)), 0.0, 1.0);
    #endif
    
    // 3. Gamma correction (linear -> sRGB)
    color = pow(color, vec3(1.0 / 2.2));
    
    // 4. Vignette
    #ifdef VIGNETTE
    vec2 uv = texcoord - 0.5;
    float vignette = 1.0 - dot(uv, uv) * 0.38;
    color *= clamp(vignette, 0.0, 1.0);
    #endif
    
    // 5. Custom Color Saturation Level
    float vibAmount = -0.06; // Balanced
    #if COLOR_SATURATION == 1
    vibAmount = 0.15;        // Muted
    #elif COLOR_SATURATION == 3
    vibAmount = -0.16;       // Colorful
    #elif COLOR_SATURATION == 4
    vibAmount = -0.28;       // Vivid
    #endif
    color = applyVibrancy(color, vibAmount);
    
    fragColor = vec4(color, 1.0);
}
