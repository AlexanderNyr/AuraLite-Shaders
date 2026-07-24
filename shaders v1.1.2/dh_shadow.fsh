#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Shadow Fragment Shader
// ==============================================================================
// [NEW v1.1.2] Writes DH LOD chunk depth into the same shadow map used by
// shadow.fsh, so far-away DH terrain casts shadows onto nearby normal terrain
// (e.g. a distant mountain silhouette shadowing the valley at sunset) and vice
// versa, instead of a shadow-map hole wherever only LOD geometry exists.

in vec4 glcolor;

layout(location = 0) out vec4 fragColor;

void main() {
    if (glcolor.a < 0.05) discard;
    fragColor = glcolor;
}
