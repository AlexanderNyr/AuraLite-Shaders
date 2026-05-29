#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Sky Vertex Shader (GLSL 460 Optimized)
// ==============================================================================

out vec4 glcolor;
out vec3 viewPos;

void main() {
    glcolor = gl_Color;
    vec4 position = gl_ModelViewMatrix * gl_Vertex;
    viewPos = position.xyz;
    gl_Position = gl_ProjectionMatrix * position;
}
