#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Terrain Vertex Shader
// ==============================================================================
// [NEW v1.1.2] Without this pair of dh_terrain.vsh/.fsh files Iris marks the whole
// shader pack as "incompatible" with Distant Horizons and falls back to NOT
// drawing DH's simplified LOD chunks through the pack at all — this is the exact
// cause of "shader works but DH chunks don't render". See:
// https://github.com/IrisShaders/ShaderDoc/blob/master/dh-support.md
//
// DH geometry has no textures/UVs — each LOD quad only carries a flat vertex
// color (gl_Color), a normal and a coarse "mini material ID" (dhMaterialId).
// We map that data into the SAME colortex0/1/2 layout used by gbuffers_terrain.fsh
// so the existing lighting/fog/shadow/cloud code in composite.fsh treats LOD
// terrain identically to normal terrain, with zero changes required there.

out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;
out vec2 lmcoord;
flat out int dhMatId;

// [DH] Distant Horizons supplies its own near/far projection matrix; using the
// normal gl_ProjectionMatrix here would clip/mis-scale LOD geometry because DH's
// far plane extends far beyond the vanilla render distance.
uniform mat4 dhProjection;

void main() {
    glcolor = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);

    // [FIX v1.1.2] Do NOT reuse gl_MultiTexCoord2 as a 0-240 vanilla-style
    // lightmap coordinate. ShaderDoc only guarantees gl_MultiTexCoord2 EXISTS
    // for DH programs — it is not guaranteed to carry meaningful sky/block
    // light data in the same range/format as a normal terrain vertex, and in
    // practice it reads as ~(0,0) here, which zeroed out skyLight in
    // composite.fsh and made all DH terrain render almost pitch black
    // (both direct sun/moon lighting and daytime ambient are multiplied by
    // skyLight there). DH only ever renders exterior heightmap-based LOD
    // surface (no interior/cave data exists at LOD distances), so it is both
    // safe and correct to hardcode "always under open sky, no baked torch
    // light": skyLight = 1.0, blockLight = 0.0. Actual light-emitting blocks
    // (DH_BLOCK_ILLUMINATED) already bypass this via the emissive fast path.
    lmcoord = vec2(0.0, 1.0);

    dhMatId = dhMaterialId;

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    viewPos = viewPosition.xyz;
    gl_Position = dhProjection * viewPosition;
}
