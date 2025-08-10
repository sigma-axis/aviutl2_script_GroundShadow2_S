/*
MIT License
Copyright (c) 2025 sigma-axis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

https://mit-license.org/
*/

//
// VERSION: v1.00
//

////////////////////////////////
#version 460 core

in vec2 TexCoord;

layout(location = 0) out vec4 FragColor;

uniform sampler2D texture0;
uniform ivec2 size_dst, size_src;
uniform float alpha1;
uniform vec2 ofs_src;
uniform vec3 cam;
uniform vec4 plane;
uniform vec3 l_dir, l_ddir0, l_ddir1;
uniform int N;

vec4 pick_color(vec2 pos)
{
	vec2 t = clamp(min(pos, size_src - pos) + 0.5, 0, 1);
	return t.x * t.y * texture(texture0, pos / size_src);
}

void main()
{
	vec3 pt = vec3(TexCoord * size_dst, 0);
	if (cam.z < 0) {
		vec3 ray = pt - cam;
		float t = dot(plane.xyz, ray), v = dot(plane, vec4(cam, 1));
		if ((t <= 0 && v < 0) || (t >= 0 && v > 0)) discard;
		pt = cam - (v == 0 ? 0 : v / t) * ray;
	}
	else {
		if (plane.z == 0) discard;
		float v = dot(plane, vec4(pt, 1));
		pt.z = -v / plane.z;
	}
	const vec2 XY = pt.xy + ofs_src; const float Z = pt.z;

	vec4 color = vec4(0.0);
	const int Q = N * N;
	for (int i = -N; i <= N; i++) {
		for (int j = -N; j <= N; j++) {
			if (i * i + j * j > Q) continue;

			const vec3 l = l_dir + i * l_ddir0 + j * l_ddir1;
			vec4 col = l.z == 0 ? vec4(0.0) : pick_color(XY - (Z / l.z) * l.xy);
			col.rgb *= col.a;
			color += col;
		}
	}
	color.rgb /= max(color.a, 1.0 / 512);
	color.a *= alpha1;
	FragColor = clamp(color, 0, 1);
}
