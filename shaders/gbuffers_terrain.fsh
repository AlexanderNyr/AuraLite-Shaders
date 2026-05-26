#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Terrain Fragment Shader (GLSL 460 - PBR sampling)
// ==============================================================================

// PBR Triggers to tell Iris / OptiFine to bind normal & specular maps!
#define MC_NORMAL_MAP
#define MC_SPECULAR_MAP
#define MC_TEXTURE_FORMAT_LAB_PBR

/* DRAWBUFFERS:012 */

uniform sampler2D gtexture;
uniform sampler2D normals;  // Normal maps (LabPBR)
uniform sampler2D specular; // Specular maps (LabPBR)

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;
in vec3 tangent;
in vec3 binormal;

// Declare explicit outputs for modern GLSL 460 compatibility!
layout(location = 0) out vec4 colortex0;
layout(location = 1) out vec4 colortex1;
layout(location = 2) out vec4 colortex2;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * glcolor;
    if (albedo.a < 0.1) {
        discard;
    }
    
    // Reconstruct TBN matrix
    mat3 tbn = mat3(normalize(tangent), normalize(binormal), normalize(normal));
    
    // Sample normal map (PBR)
    vec4 normalMap = texture(normals, texcoord);
    vec3 bumpedNormal = normalMap.xyz * 2.0 - 1.0;
    vec3 finalNormal = normalize(tbn * bumpedNormal);
    
    // Sample specular map (PBR)
    // Red: Smoothness (1.0 - Roughness), Green: Metalness, Blue: Emissive
    vec4 specData = texture(specular, texcoord);
    float roughness = clamp(1.0 - specData.r, 0.0, 1.0);
    float metalness = clamp(specData.g, 0.0, 1.0);
    
    colortex0 = albedo;
    // Pack lightmap and PBR roughness/metalness into colortex1
    colortex1 = vec4(lmcoord, roughness, metalness);
    colortex2 = vec4(finalNormal * 0.5 + 0.5, 1.0);
}
