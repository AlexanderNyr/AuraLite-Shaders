#version 460 compatibility
// AuraLite Shaders v1.1.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Terrain Fragment Shader
// ==============================================================================
// DH LOD chunks have no texture/UV/LabPBR maps. Their vertex colour is the
// albedo and dhMaterialId is a coarse mini-ID. We translate that data into the
// regular colortex0/1/2 layout so composite.fsh can share lighting, fog, PBR,
// clouds and TAA with vanilla terrain.
//
// [v1.1.4] Uses a hard, deterministic vanilla→DH hand-off at `far`. The former
// screen-door seam discarded random LOD fragments in a 16m band; on DH 3.2 this
// exposed sky/white holes whenever vanilla geometry did not fill the same pixel.

/* DRAWBUFFERS:012 */

uniform float frameTimeCounter;
uniform float far;

in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;
in vec2 lmcoord;
flat in int dhMatId;

layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

void main() {
    float distToCamera = length(viewPos);

    // Do not overlap the vanilla render radius. A clean hard boundary is less
    // cinematic than screen-door blending but never punches stochastic holes in
    // the LOD terrain when DH/vanilla depth coverage differs.
    if (distToCamera < far) discard;

    vec4 albedo = glcolor;
    if (albedo.a < 0.05) discard;

    // Approximate LabPBR data from Iris/DH mini-IDs. DH exposes no per-block
    // texture maps, so values are intentionally broad material classes.
    float roughness = 0.88;
    float metalness = 0.0;
    float materialMask = 1.0;

    if (dhMatId == DH_BLOCK_METAL) {
        roughness = 0.35;
        metalness = 0.65;
    } else if (dhMatId == DH_BLOCK_STONE || dhMatId == DH_BLOCK_DEEPSLATE || dhMatId == DH_BLOCK_NETHER_STONE) {
        roughness = 0.85;
    } else if (dhMatId == DH_BLOCK_WOOD) {
        roughness = 0.78;
    } else if (dhMatId == DH_BLOCK_DIRT) {
        roughness = 0.96;
    } else if (dhMatId == DH_BLOCK_SAND) {
        roughness = 0.92;
    } else if (dhMatId == DH_BLOCK_TERRACOTTA) {
        roughness = 0.82;
    } else if (dhMatId == DH_BLOCK_SNOW) {
        roughness = 0.55;
    } else if (dhMatId == DH_BLOCK_LEAVES) {
        // DH_BLOCK_LEAVES also covers bamboo/cactus. Tag it as foliage so the
        // shared foliage classification can still apply detailed vanilla rules.
        roughness = 0.88;
        materialMask = 0.62;
    } else if (dhMatId == DH_BLOCK_LAVA) {
        float pulse = sin(frameTimeCounter * 0.8) * 0.10 + 1.0;
        albedo.rgb *= pulse;
        colortex0 = albedo;
        colortex1 = vec4(lmcoord, 0.05, 0.0);
        colortex2 = vec4(normalize(normal) * 0.5 + 0.5, 0.1);
        return;
    } else if (dhMatId == DH_BLOCK_ILLUMINATED) {
        // Keep DH illuminated blocks distinct from portals/lava. 0.24 is a
        // dedicated HDR-safe material tag; composite treats it as self-emissive
        // regardless of hue, so neutral/cyan distant lamps remain visible.
        albedo.rgb *= 1.50;
        colortex0 = albedo;
        colortex1 = vec4(lmcoord, 0.5, 0.0);
        colortex2 = vec4(normalize(normal) * 0.5 + 0.5, 0.24);
        return;
    }

    colortex0 = albedo;
    colortex1 = vec4(lmcoord, roughness, metalness);
    colortex2 = vec4(normalize(normal) * 0.5 + 0.5, materialMask);
}
