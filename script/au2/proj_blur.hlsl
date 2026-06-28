Texture2D src : register(t0);
cbuffer constant0 : register(b0) {
	float2 size_src, ofs_src;
	float3 cam;
	float alpha1;
	float4 plane;
	float3 l_dir; float quality;
	float3 l_ddir0, l_ddir1;
};
SamplerState s : register(s0);

float4 pick_color(float2 pos)
{
	return src.Sample(s, pos / size_src);
}
float4 proj_blur(float4 pos : SV_Position) : SV_Target
{
	float3 pt = float3(pos.xy, 0);
	if (cam.z < 0) {
		float3 ray = pt - cam;
		float t = dot(plane.xyz, ray), v = dot(plane, float4(cam, 1));
		if ((t <= 0 && v < 0) || (t >= 0 && v > 0)) discard;
		pt = cam - (v == 0 ? 0 : v / t) * ray;
	}
	else {
		if (plane.z == 0) discard;
		float v = dot(plane, float4(pt, 1));
		pt.z = -v / plane.z;
	}
	const float2 XY = pt.xy + ofs_src; const float Z = pt.z;

	float4 color = 0.0;
	const int N = int(quality), Q = N * N;
	for (int i = -N; i <= N; i++) {
		for (int j = -N; j <= N; j++) {
			if (i * i + j * j > Q) continue;

			const float3 l = l_dir + i * l_ddir0 + j * l_ddir1;
			color += l.z == 0 ? 0 : pick_color(XY - (Z / l.z) * l.xy);
		}
	}
	return saturate(alpha1 * color);
}
