#version 460 compatibility
// AuraLite Shaders v1.0.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Shadow Vertex Shader (GLSL 460 - Enhanced)
// ==============================================================================

out vec2 texcoord;
out vec4 glcolor;

// Shadow distortion: increases near-camera shadow resolution without increasing map size
vec3 distortShadowClipPos(vec3 clipPos) {
    float distortFactor = length(clipPos.xy) + 0.1;
    clipPos.xy /= distortFactor;
    clipPos.z *= 0.5; // Compress Z range to reduce depth fighting
    return clipPos;
}

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    glcolor = gl_Color;

    vec4 clipPos = ftransform();
    clipPos.xyz = distortShadowClipPos(clipPos.xyz);
    gl_Position = clipPos;
}
