#version 450
layout(location=0) in vec3 Position;
layout(location=1) in vec3 Normal;
layout(location=2) in vec4 Color;
layout(location=3) in vec2 TexCoord;
struct Light { vec4 opts, pos, dir, color; };
layout(std140,set=0,binding=0) uniform Uniforms {
  mat4 mvp, model, normalMatrix;
  vec4 color, diffuse, specular, ambient, emission, options, eye, opacityMod, params;
  Light lights[8];
} u;
layout(location=0) out vec3 worldPos;
layout(location=1) out vec3 worldNormal;
layout(location=2) out vec4 vertexColor;
layout(location=3) out vec2 uv;
void main() {
  gl_Position = u.mvp * vec4(Position, 1.0);
  gl_Position.y = -gl_Position.y;
  gl_PointSize = 1.0;
  worldPos = (u.model * vec4(Position, 1.0)).xyz;
  worldNormal = mat3(u.normalMatrix) * Normal;
  vertexColor = Color;
  uv = TexCoord;
}
