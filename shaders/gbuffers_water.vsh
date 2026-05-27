#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Water Vertex Shader (GLSL 460 Optimized)
// ==============================================================================

#define WATER_WAVES // [true false]
#define WIND_SPEED 2 // [1 2 3]

out vec2 texcoord;
out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;

uniform float frameTimeCounter;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    glcolor = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    
    vec4 position = gl_Vertex;
    
    #ifdef WATER_WAVES
    if (gl_Normal.y > 0.5) {
        float speedFactor = 1.0;
        #if WIND_SPEED == 1
        speedFactor = 0.55;
        #elif WIND_SPEED == 3
        speedFactor = 1.65;
        #endif
        
        float t = frameTimeCounter * 1.6 * speedFactor;
        
        // Fused Multiply-Add (FMA) wave optimization
        float wave = sin(fma(position.x, 2.2, fma(position.z, 1.8, t))) * 0.04
                   + cos(fma(position.x, 1.2, fma(-position.z, 2.2, t * 0.9))) * 0.02;
        position.y += wave;
    }
    #endif
    
    vec4 viewPosition = gl_ModelViewMatrix * position;
    viewPos = viewPosition.xyz;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
