#version 450
struct Light { vec4 opts, pos, dir, color; };
layout(std140,set=0,binding=0) uniform Uniforms {
  mat4 mvp, model, normalMatrix;
  vec4 color, diffuse, specular, ambient, emission, options, eye, opacityMod, params;
  Light lights[8];
} u;
layout(set=0,binding=1) uniform sampler2D texture0;
layout(location=0) in vec3 worldPos;
layout(location=1) in vec3 worldNormal;
layout(location=2) in vec4 vertexColor;
layout(location=3) in vec2 uv;
layout(location=0) out vec4 outputColor;
void main() {
  vec2 tc=uv;
  if (u.params.z>0.5) tc.y=1.0-tc.y;
  vec4 texel = u.params.y>0.5 ? texture(texture0,tc) : vec4(1.0);
  vec4 c;
  if(u.params.x<0.5) c=u.color*vertexColor;
  else if(u.params.x<1.5) c=vertexColor;
  else {
    vec3 n=normalize(worldNormal);
    vec3 eye=normalize(u.eye.xyz-worldPos);
    vec3 lit=u.ambient.rgb+u.emission.rgb;
    for(int i=0;i<8;i++) {
      Light l=u.lights[i];
      if(l.opts.x<0.5) continue;
      vec3 d=l.opts.x<1.5 ? normalize(-l.dir.xyz) : normalize(l.pos.xyz-worldPos);
      float attenuation=1.0;
      if(l.opts.x>2.5) {
        float spot=dot(-d,normalize(l.dir.xyz));
        attenuation=spot>=l.opts.y ? pow(max(spot,0.0),max(l.opts.z,0.0)) : 0.0;
      }
      float diffuse=max(dot(n,d),0.0);
      float spec=diffuse>0.0 ? pow(max(dot(reflect(-d,n),eye),0.0),max(u.options.x,1.0)) : 0.0;
      lit+=(u.diffuse.rgb*diffuse+u.specular.rgb*spec)*l.color.rgb*attenuation;
    }
    c=vec4(lit,u.diffuse.a)*vertexColor;
  }
  c.a*=u.opacityMod.x;
  c.rgb*=c.a;
  // FMX bitmap and render-target textures already contain premultiplied pixels.
  // Modulate their RGB without multiplying by the texture alpha a second time.
  if(u.params.x>0.5 && u.params.y>0.5) c*=texel;
  outputColor=c;
}
