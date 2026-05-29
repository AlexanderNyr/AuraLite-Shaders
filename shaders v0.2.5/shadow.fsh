#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Shadow Fragment Shader (GLSL 460 - Enhanced)
// ==============================================================================
// [FIX v0.2.3] Replaced deprecated gl_FragData[0] with layout(location=0) out

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;

layout(location = 0) out vec4 fragColor;

void main() {
    vec4 tex = texture(gtexture, texcoord);
    if (tex.a < 0.1) {
        discard;
    }
    fragColor = tex * glcolor;
}
