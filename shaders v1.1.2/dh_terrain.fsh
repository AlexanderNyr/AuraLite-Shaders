#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Distant Horizons LOD Terrain Fragment Shader
// ==============================================================================
// [NEW v1.1.2] Minimal-but-correct DH compatibility pass. Distant Horizons LOD
// chunks have no textures, so the flat per-vertex color (glcolor) IS the albedo.
// We write the same colortex0/1/2 layout as gbuffers_terrain.fsh so every
// lighting/fog/shadow/cloud/PBR computation in composite.fsh applies to LOD
// terrain exactly like normal terrain — no changes needed anywhere else.
//
// dhMaterialId gives coarse "mini" material categories instead of mc_Entity
// (real per-block IDs are NOT available for DH geometry, see ShaderDoc).

/* DRAWBUFFERS:012 */

uniform float frameTimeCounter; // Needed for the animated lava pulse (matches gbuffers_terrain.fsh)
uniform float far; // [FIX v1.1.2] Needed for overdraw prevention (see below)

in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;
in vec2 lmcoord;
flat in int dhMatId;

layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

void main() {
    // ==============================================================================
    // [FIX v1.1.2] DH / VANILLA OVERDRAW PREVENTION
    // ------------------------------------------------------------------------------
    // Distant Horizons always renders its simplified LOD geometry for the ENTIRE
    // loaded world, including the area already covered by normal, fully-detailed
    // vanilla chunks. dh_terrain runs BEFORE normal terrain (per ShaderDoc), so
    // without this cutoff both the low-detail LOD copy of the ground and the real
    // detailed terrain get drawn at the same screen position and fight for the
    // same depth/G-buffer pixel — this is exactly the "blocks visible through
    // other blocks, water/ice missing, shadows/godrays acting like the block
    // doesn't exist" symptom, because two conflicting geometries (with two
    // different depths/normals) are both writing to colortex0/1/2 for the same
    // pixel. We discard LOD fragments that fall within the normal render
    // distance so only the real chunk geometry ever occupies that region; DH
    // only contributes pixels beyond `far`, where no normal chunk exists.
    // A small margin (one extra chunk, 16m) avoids a hard seam right at the edge.
    // ==============================================================================
    float distToCamera = length(viewPos);
    if (distToCamera < far + 16.0) {
        discard;
    }

    vec4 albedo = glcolor;
    if (albedo.a < 0.05) discard;

    // Coarse roughness/metalness per DH mini-material — approximated since DH
    // LOD geometry carries no LabPBR specular map.
    float roughness = 0.92;
    float metalness = 0.0;
    float materialMask = 1.0;

    if (dhMatId == DH_BLOCK_METAL) {
        roughness = 0.35;
        metalness = 0.65;
    } else if (dhMatId == DH_BLOCK_STONE || dhMatId == DH_BLOCK_DEEPSLATE || dhMatId == DH_BLOCK_NETHER_STONE) {
        roughness = 0.85;
    } else if (dhMatId == DH_BLOCK_WOOD) {
        roughness = 0.78;
    } else if (dhMatId == DH_BLOCK_SNOW) {
        roughness = 0.55;
    } else if (dhMatId == DH_BLOCK_LEAVES) {
        // Tag as foliage (matches the 0.62 material mask used by gbuffers_terrain.fsh)
        // so composite.fsh's FOLIAGE_SSS subsurface-scattering term also applies to
        // distant LOD tree canopies instead of them looking flat/dead.
        roughness = 0.88;
        materialMask = 0.62;
    } else if (dhMatId == DH_BLOCK_LAVA) {
        // Tag as lava (0.1) so final.fsh's heat-shimmer detection and composite.fsh's
        // emissive fast path pick up distant lava lakes the same way as near ones.
        float pulse = sin(frameTimeCounter * 0.8) * 0.10 + 1.0;
        albedo.rgb *= pulse;
        colortex0 = albedo;
        colortex1 = vec4(lmcoord, 0.05, 0.0);
        colortex2 = vec4(normalize(normal) * 0.5 + 0.5, 0.1);
        return;
    } else if (dhMatId == DH_BLOCK_ILLUMINATED) {
        // Emissive fast path (alpha < 0.5) — glowstone/lanterns/etc. rendered by DH.
        colortex0 = albedo;
        colortex1 = vec4(lmcoord, 0.5, 0.0);
        colortex2 = vec4(normalize(normal) * 0.5 + 0.5, 0.0);
        return;
    }

    colortex0 = albedo;
    colortex1 = vec4(lmcoord, roughness, metalness);
    colortex2 = vec4(normalize(normal) * 0.5 + 0.5, materialMask);
}
