#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Shadow Fragment Shader (GLSL 460 Optimized)
// ==============================================================================

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;

void main() {
    vec4 tex = texture(gtexture, texcoord);
    if (tex.a < 0.1) {
        discard;
    }
    gl_FragData[0] = tex * glcolor;
}
