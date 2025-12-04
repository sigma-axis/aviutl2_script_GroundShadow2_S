--[[
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
]]

--
-- VERSION: v1.04
--

--------------------------------

local GLShaderKit = require "GLShaderKit";

local obj, tonumber, math = obj, tonumber, math;

local function error_mod(message)
	message = "GroundShadow2_S.lua: "..message;
	debug_print(message);
	local function err_mes()
		obj.setfont("MS UI Gothic", 42, 3);
		obj.load("text", message);
	end
	return setmetatable({}, { __index = function(...) return err_mes end });
end
if not GLShaderKit.isInitialized() then return error_mod [=[このデバイスでは GLShaderKit が利用できません!]=];
else
	local function lexical_comp(a, b, ...)
		return a == nil and 0 or a < b and -1 or a > b and 1 or lexical_comp(...);
	end
	local version = GLShaderKit.version();
	local v1, v2, v3 = version:match("^(%d+)%.(%d+)%.(%d+)$");
	v1, v2, v3 = tonumber(v1), tonumber(v2), tonumber(v3);
	-- version must be at least v0.4.0.
	if not (v1 and v2 and v3) or lexical_comp(v1, 0, v2, 4, v3, 0) < 0 then
		debug_print([=[現在の GLShaderKit のバージョン: ]=]..version);
		return error_mod [=[この GLShaderKit のバージョンでは動作しません!]=];
	end
end

-- ref: https://github.com/Mr-Ojii/AviUtl-RotBlur_M-Script/blob/main/script/RotBlur_M.lua
local function script_path()
    return debug.getinfo(1).source:match("@?(.*[/\\])");
end
local shader_path = script_path().."GroundShadow2_S.frag";

-- cache constants.
local max_width, max_height = obj.getinfo("image_max");
local cache_name_obj = "cache:GroundShadow2_S/obj";

-- commonly used functions.
local function normalize(x, y, z)
	local l = (x ^ 2 + y ^ 2 + z ^ 2) ^ 0.5;
	return x / l, y / l, z / l;
end
local function cross_prod(x, y, z, X, Y, Z)
	return y * Z - z * Y, z *X - x * Z, x * Y - y * X;
end

---calculates the crossing point of a plane and a line.
---@param nx number defines the plane.
---@param ny number defines the plane.
---@param nz number defines the plane.
---@param nw number defines the plane.
---@param dx number defines the direction of the line.
---@param dy number defines the direction of the line.
---@param dz number defines the direction of the line.
---@param x0 number defines the starting point of the line.
---@param y0 number defines the starting point of the line.
---@param z0 number defines the starting point of the line.
---@return number? side +1, 0, or -1 representing which side is ray is crossing to the plane, or nil if it is parallel to the plane.
---@return number x, number y, number z the crossing point, or nothing when parallel.
local function plane_line_to_pt(nx, ny, nz, nw, dx, dy, dz, x0, y0, z0)
	local v0 = nx * x0 + ny * y0 + nz * z0 + nw;
	local dv = nx * dx + ny * dy + nz * dz;
---@diagnostic disable-next-line: missing-return-value
	if dv == 0 then return nil end
	local t = -v0 / dv;
	return t == 0 and 0 or t > 0 and 1 or -1,
		x0 + t * dx, y0 + t * dy, z0 + t * dz;
end
---orthogonally projects a line onto a plane.
---@param nx number defines the plane.
---@param ny number defines the plane.
---@param nz number defines the plane.
---@param nw number defines the plane.
---@param dx number defines the direction of the line.
---@param dy number defines the direction of the line.
---@param dz number defines the direction of the line.
---@param x0 number defines the origin of the line.
---@param y0 number defines the origin of the line.
---@param z0 number defines the origin of the line.
---@return number p_dx, number p_dy, number p_dz the direction of the projected line.
---@return number p_x0, number p_y0, number p_z0 the projected origin.
local function ortho_proj_line(nx, ny, nz, nw, dx, dy, dz, x0, y0, z0)
	local _, x1, y1, z1 = plane_line_to_pt(nx, ny, nz, nw,
		nx, ny, nz, x0, y0, z0);
	local _, x2, y2, z2 = plane_line_to_pt(nx, ny, nz, nw,
		nx, ny, nz, x0 + dx, y0 + dy, z0 + dz);
	return x2 - x1, y2 - y1, z2 - z1, x1, y1, z1;
end
---converts from object-coordinate to camera-coordinate.
---@param camera_pos number[] the camera position.
---@param camera_fov number the field of view of the camera.
---@param x number defines a point in object-coordinate.
---@param y number defines a point in object-coordinate.
---@param z number defines a point in object-coordinate.
---@return number? x, number y the point in camera coordinate. nil if the point is beyond the back side of the camera.
local function to_camera(camera_pos, camera_fov, x, y, z)
	local Z = 1 + camera_fov * z / 1024;
---@diagnostic disable-next-line: missing-return-value
	if Z <= 0 then return nil end
	local p = 1 / Z;
	return p * x + (1 - p) * camera_pos[1], p * y + (1 - p) * camera_pos[2];
end
---determines the direction to extend to contain backward ray.
---@param camera_pos number[] the camera position.
---@param camera_fov number the field of view of the camera.
---@param dx number defines the direction of the line.
---@param dy number defines the direction of the line.
---@param dz number defines the direction of the line.
---@param x number defines the origin of the line.
---@param y number defines the origin of the line.
---@param z number defines the origin of the line.
---@return number x, number y the extension bound.
local function to_back_camera(camera_pos, camera_fov, dx, dy, dz, x, y, z)
	if dz == 0 then return 0, 0 end
	if dz < 0 then dx, dy, dz = -dx, -dy, -dz end

	x, y = x - camera_pos[1], y - camera_pos[2];
	if camera_fov > 0 then
		local t = (z + 1024 / camera_fov) / dz;
		dx, dy = t * dx, t * dy;
	else
		if dx ~= 0 then x = 0 end
		if dy ~= 0 then y = 0 end
	end
	x, y = x - dx, y - dy;
	return
		x == 0 and 0 or x < 0 and -max_width or max_width,
		y == 0 and 0 or y < 0 and -max_height or max_height;
end
---calculates the vanishing point of a line.
---@param camera_pos number[] the camera position.
---@param camera_fov number the field of view of the camera.
---@param dx number defines the direction of the line.
---@param dy number defines the direction of the line.
---@param dz number defines the direction of the line.
---@return number x, number y one vanishing point, whicn is infinitely far from the camera.
local function vanishing_pts(camera_pos, camera_fov, dx, dy, dz)
	if camera_fov <= 0 or dz == 0 then
		return
			dx == 0 and 0 or dx < 0 and -max_width or max_width,
			dy == 0 and 0 or dy < 0 and -max_height or max_height;
	else
		local p = 1024 / (camera_fov * dz);
		local px, py = p * dx + camera_pos[1], p * dy + camera_pos[2];
		return
			math.min(math.max(px, -max_width), max_width),
			math.min(math.max(py, -max_height), max_height);
	end
end

local function GroundShadow2_S(ground_angle, light_angle, light_slope, rotation, col, col_alpha, ground_pos, camera_pos, camera_fov, alpha, front_alpha, conic_blur, edge_blur, len, tip_blur, pos, quality, max_w, max_h)
	-- default parameters.
	ground_angle = tonumber(ground_angle) or 0;
	light_angle = tonumber(light_angle) or -45;
	light_slope = tonumber(light_slope) or 0;
	rotation = tonumber(rotation) or 0;
	col = tonumber(col) or 0x000000;
	col_alpha = tonumber(col_alpha) or 100;
	ground_pos = ground_pos or { 0, 200, 0 };
	camera_pos = camera_pos or { 0, -200 };
	camera_fov = tonumber(camera_fov) or 100;
	alpha = tonumber(alpha) or 50;
	front_alpha = tonumber(front_alpha) or 0;
	conic_blur = tonumber(conic_blur) or 5;
	edge_blur = tonumber(edge_blur) or 4;
	len = tonumber(len) or 0;
	tip_blur = tonumber(tip_blur) or 0;
	pos = pos or { 0, 0 };
	quality = tonumber(quality) or 529;
	max_w = tonumber(max_w) or max_width;
	max_h = tonumber(max_h) or max_height;

	-- normalize paramters.
	ground_angle = math.pi / 180 * (ground_angle % 360);
	light_angle = math.pi / 180 * (light_angle % 360);
	light_slope = light_slope / 100;
	rotation = math.pi / 180 * (rotation % 360);
	camera_fov = math.max(camera_fov / 100, 0);
	col = math.floor(col) % 2 ^ 24;
	col_alpha = math.min(math.max(col_alpha / 100, 0), 1);
	alpha = math.min(math.max(alpha / 100, 0), 1);
	front_alpha = math.min(math.max(1 - front_alpha / 100, 0), 1);
	conic_blur = math.max(conic_blur / 100, 0);
	len = math.max(len, 0)
	tip_blur = math.min(math.max(math.floor(0.5 + tip_blur), 0), 2000);
	quality = math.floor((math.max(quality, 1) ^ 0.5 - 1) / 2);
	max_w = math.min(math.max(max_w, 0), max_width);
	max_h = math.min(math.max(max_h, 0), max_height);

	-- further calculation of parameters.
	local w, h = obj.getpixel();
	local cos_rot, sin_rot = math.cos(rotation), math.sin(rotation);
	local g_nx, g_ny, g_nz, g_nw = 0, math.cos(ground_angle), math.sin(ground_angle); -- defines the plane of the ground.
	local l_dx, l_dy, l_dz, l_ddx0, l_ddy0, l_ddz0 do -- direction of the light and range of the conic blur.
		local cos_lit, sin_lit = math.cos(light_angle), math.sin(light_angle);
		l_dx, l_dy, l_dz = normalize(light_slope, -sin_lit, cos_lit);
		l_ddy0, l_ddz0 = -- multiply conic_blur / sqrt(2) here.
			2 ^ -0.5 * conic_blur * cos_lit, 2 ^ -0.5 * conic_blur * sin_lit;

		-- apply rotation.
		g_nx, g_ny = -sin_rot * g_ny, cos_rot * g_ny;
		g_nw = -(g_nx * ground_pos[1] + g_ny * ground_pos[2] + g_nz * ground_pos[3]);

		l_dx, l_dy =
			cos_rot * l_dx - sin_rot * l_dy,
			sin_rot * l_dx + cos_rot * l_dy;
		l_ddx0, l_ddy0 = -sin_rot * l_ddy0, cos_rot * l_ddy0;
	end
	local l_ddx1, l_ddy1, l_ddz1 = cross_prod(l_ddx0, l_ddy0, l_ddz0, l_dx, l_dy, l_dz);
	-- rotate by pi / 4. note that 1 / sqrt(2) was multiplied beforehand.
	l_ddx0, l_ddy0, l_ddz0, l_ddx1, l_ddy1, l_ddz1 =
		l_ddx0 + l_ddx1, l_ddy0 + l_ddy1, l_ddz0 + l_ddz1,
		l_ddx0 - l_ddx1, l_ddy0 - l_ddy1, l_ddz0 - l_ddz1;

	-- backup the current image.
	if front_alpha > 0 then obj.copybuffer(cache_name_obj, "obj") end

	-- apply coloring.
	if col_alpha > 0 then
		obj.effect("単色化", "輝度を保持する", 0, "強さ", 100 * col_alpha, "color", col);
	end

	-- apply `len` and `tip_blur`
	if len > 0 then
		local L, rot = math.min(math.floor(0.5 + len), tip_blur), 180 / math.pi * rotation;
		obj.effect("斜めクリッピング",
			"中心X", ground_pos[1] - (len - L / 2) * sin_rot,
			"中心Y", ground_pos[2] + (len - L / 2) * cos_rot,
			"角度", rot, "ぼかし", L);
		obj.effect("斜めクリッピング",
			"中心X", ground_pos[1] + (len - L / 2) * sin_rot,
			"中心Y", ground_pos[2] - (len - L / 2) * cos_rot,
			"角度", rot + 180, "ぼかし", L);
	end

	-- apply blurring
	if edge_blur > 0 then
		local i, f = math.modf(edge_blur);
		obj.effect("ぼかし", "範囲", i);
		if f > 0 then
			local W, H = obj.getpixel();
			obj.setoption("dst", "tmp", W + 2, H + 2);
			obj.setoption("blend", "alpha_add");
			obj.draw(0, 0, 0, 1, 1 - f);
			obj.effect("ぼかし", "範囲", 1);
			obj.draw(0, 0, 0, 1, f);
			obj.copybuffer("obj", "tmp");
		end
	end

	-- calculate the bounds.
	local w1, h1, w2, h2, x2, y2, ray_range = nil, nil, nil, nil, nil, nil, 0 do
		w1, h1 = obj.getpixel();

		-- determine corners.
		local corners do
			local L, T, R, B = -w / 2, -h / 2, w / 2, h / 2;
			if len > 0 then
				-- find the minimum rectangle containing area where is not clipped off.
				local lx, ly = -len * sin_rot, len * cos_rot;
				if cos_rot ~= 0 then
					local tan_rot = sin_rot / cos_rot;
					local Y1, Y2, Y3, Y4 =
						(ground_pos[2] + ly) - tan_rot * (ground_pos[1] + lx - R),
						(ground_pos[2] + ly) - tan_rot * (ground_pos[1] + lx - L),
						(ground_pos[2] - ly) - tan_rot * (ground_pos[1] - lx - R),
						(ground_pos[2] - ly) - tan_rot * (ground_pos[1] - lx - L);
					if Y1 > Y2 then Y1, Y2 = Y2, Y1 end
					if Y3 > Y4 then Y3, Y4 = Y4, Y3 end
					T = math.max(T, math.min(Y1, Y3));
					B = math.min(B, math.max(Y2, Y4));
				end
				if sin_rot ~= 0 then
					local cot_rot = cos_rot / sin_rot;
					local X1, X2, X3, X4 =
						(ground_pos[1] + lx) - cot_rot * (ground_pos[2] + ly - B),
						(ground_pos[1] + lx) - cot_rot * (ground_pos[2] + ly - T),
						(ground_pos[1] - lx) - cot_rot * (ground_pos[2] - ly - B),
						(ground_pos[1] - lx) - cot_rot * (ground_pos[2] - ly - T);
					if X1 > X2 then X1, X2 = X2, X1 end
					if X3 > X4 then X3, X4 = X4, X3 end
					L = math.max(L, math.min(X1, X3));
					R = math.min(R, math.max(X2, X4));
				end
			end
			if edge_blur > 0 then
				local sz = math.ceil(edge_blur);
				L, T, R, B = L - sz, T - sz, R + sz, B + sz;
			end
			corners = { { L, T }, { R, T }, { R, B }, { L, B } };
		end

		-- collect rays.
		local rays if conic_blur <= 0 then rays = { { l_dx, l_dy, l_dz } };
		else
			-- four rays to test.
			-- rays = {
			-- 	{ l_dx + l_ddx0 + l_ddx1, l_dy + l_ddy0 + l_ddy1, l_dz + l_ddz0 + l_ddz1 },
			-- 	{ l_dx - l_ddx0 + l_ddx1, l_dy - l_ddy0 + l_ddy1, l_dz - l_ddz0 + l_ddz1 },
			-- 	{ l_dx - l_ddx0 - l_ddx1, l_dy - l_ddy0 - l_ddy1, l_dz - l_ddz0 - l_ddz1 },
			-- 	{ l_dx + l_ddx0 - l_ddx1, l_dy + l_ddy0 - l_ddy1, l_dz + l_ddz0 - l_ddz1 },
			-- };

			-- eight rays to test.
			local d = 0.41421356237309505; -- tan(pi/8).
			rays = {
				{ l_dx + l_ddx0 + d * l_ddx1, l_dy + l_ddy0 + d * l_ddy1, l_dz + l_ddz0 + d * l_ddz1 },
				{ l_dx + d * l_ddx0 + l_ddx1, l_dy + d * l_ddy0 + l_ddy1, l_dz + d * l_ddz0 + l_ddz1 },

				{ l_dx - d * l_ddx0 + l_ddx1, l_dy - d * l_ddy0 + l_ddy1, l_dz - d * l_ddz0 + l_ddz1 },
				{ l_dx - l_ddx0 + d * l_ddx1, l_dy - l_ddy0 + d * l_ddy1, l_dz - l_ddz0 + d * l_ddz1 },

				{ l_dx - l_ddx0 - d * l_ddx1, l_dy - l_ddy0 - d * l_ddy1, l_dz - l_ddz0 - d * l_ddz1 },
				{ l_dx - d * l_ddx0 - l_ddx1, l_dy - d * l_ddy0 - l_ddy1, l_dz - d * l_ddz0 - l_ddz1 },

				{ l_dx + d * l_ddx0 - l_ddx1, l_dy + d * l_ddy0 - l_ddy1, l_dz + d * l_ddz0 - l_ddz1 },
				{ l_dx + l_ddx0 - d * l_ddx1, l_dy + l_ddy0 - d * l_ddy1, l_dz + l_ddz0 - d * l_ddz1 },
			};
			-- rays are chosen so they consist of a convex figure containing the cone of the light.
		end

		-- test rays.
		local L, T, R, B = nil, nil, nil, nil;
		for j = 1, 4 do
			local corner = corners[j];
			local pt_tail = { plane_line_to_pt(g_nx, g_ny, g_nz, g_nw,
				rays[#rays][1], rays[#rays][2], rays[#rays][3], corner[1], corner[2], 0) };
			local prev_sgn, l, t, r, b = pt_tail[1], nil, nil, nil, nil;
			for i = 1, #rays do
				local ray = rays[i];
				local X1, Y1, X2, Y2;
				local pt = i == #rays and pt_tail or
					{ plane_line_to_pt(g_nx, g_ny, g_nz, g_nw,
						ray[1], ray[2], ray[3], corner[1], corner[2], 0) };
				if pt[1] == nil or (prev_sgn ~= nil and pt[1] * prev_sgn < 0) then
					-- overflowing beyond horizon. calcaute the vanishing points.
					local p_dx, p_dy, p_dz, p_x0, p_y0, p_z0 = ortho_proj_line(g_nx, g_ny, g_nz, g_nw,
						ray[1], ray[2], ray[3], corner[1], corner[2], 0);
					X1, Y1 = vanishing_pts(camera_pos, camera_fov, p_dx, p_dy, p_dz);
					X2, Y2 = to_back_camera(camera_pos, camera_fov, p_dx, p_dy, p_dz, p_x0, p_y0, p_z0);
					if X1 > X2 then X1, X2 = X2, X1 end
					if Y1 > Y2 then Y1, Y2 = Y2, Y1 end
					ray_range = max_w + max_h; -- assume indefinite range.
				else
					X1, Y1 = to_camera(camera_pos, camera_fov, pt[2], pt[3], pt[4]);
					if not X1 then
						X1, Y1 = to_back_camera(camera_pos, camera_fov,
							ortho_proj_line(g_nx, g_ny, g_nz, g_nw,
								ray[1], ray[2], ray[3], corner[1], corner[2], 0));
						ray_range = max_w + max_h; -- assume indefinite range.
					end
					X2, Y2 = X1, Y1;
				end
				l, r = math.min(l or X1, X1), math.max(r or X2, X2);
				t, b = math.min(t or Y1, Y1), math.max(b or Y2, Y2);
				prev_sgn = pt[1];
			end
			ray_range = math.max(ray_range, r - l, b - t);
			L, R = math.min(L or l, l), math.max(R or r, r);
			T, B = math.min(T or t, t), math.max(B or b, b);
		end

		-- reposition.
		L, T, R, B = L + pos[1], T + pos[2], R + pos[1], B + pos[2];

		-- convert to the extension length.
		L, R = math.ceil(math.max(-L - w / 2, 0)), math.ceil(math.max(R - w / 2, 0));
		T, B = math.ceil(math.max(-T - h / 2, 0)), math.ceil(math.max(B - h / 2, 0));

		-- cap the bounds to the maximum size.
		if L + w + R > max_w then
			if L + w / 2 <= max_w / 2 then R = max_w - (L + w);
			elseif w / 2 + R <= max_w / 2 then L = max_w - (w + R);
			else R = math.floor((max_w - w) / 2); L = max_w - (w + R) end
		end
		if T + h + B > max_h then
			if T + h / 2 <= max_h / 2 then B = max_h - (T + h);
			elseif h / 2 + B <= max_h / 2 then T = max_h - (h + B);
			else B = math.floor((max_h - h) / 2); T = max_h - (h + B) end
		end

		-- determine the final size and position.
		w2, h2 = L + w + R, T + h + B;
		x2, y2 = (L - R) / 2, (T - B) / 2;
	end

	if alpha > 0 then
		-- prepare shader context.
		GLShaderKit.activate()
		GLShaderKit.setPlaneVertex(1);
		GLShaderKit.setShader(shader_path, false);

		-- send image buffer to gpu.
		GLShaderKit.setTexture2D(0, obj.getpixeldata());

		-- resize the canvas.
		obj.setoption("dst", "tmp", w2, h2);
		obj.copybuffer("obj", "tmp");

		-- send uniform variables.
		GLShaderKit.setInt("size_dst", w2, h2);
		GLShaderKit.setInt("size_src", w1, h1);
		local ofs_x2, ofs_y2 = w2 / 2 + x2 + pos[1], h2 / 2 + y2 + pos[2];
		local N, alpha1 = math.min(quality, math.ceil((ray_range - 1) / 2)), alpha;
		if N > 0 then
			l_ddx0, l_ddy0, l_ddz0, l_ddx1, l_ddy1, l_ddz1 =
				l_ddx0 / N, l_ddy0 / N, l_ddz0 / N,
				l_ddx1 / N, l_ddy1 / N, l_ddz1 / N;
			local cnt = 0;
			for x = 1, N - 1 do
				cnt = cnt + math.floor((N ^ 2 - x ^ 2) ^ 0.5);
			end
			cnt = 4 * (cnt + N) + 1; -- number of rays to sum up.
			alpha1 = alpha1 / cnt;
		end
		GLShaderKit.setFloat("alpha1", alpha1);
		GLShaderKit.setFloat("ofs_src", w1 / 2 - ofs_x2, h1 / 2 - ofs_y2);
		GLShaderKit.setFloat("cam",
			camera_pos[1] + ofs_x2, camera_pos[2] + ofs_y2, camera_fov > 0 and -1024 / camera_fov or 0);
		GLShaderKit.setFloat("plane", g_nx, g_ny, g_nz, g_nw - g_nx * ofs_x2 - g_ny * ofs_y2);
		GLShaderKit.setFloat("l_dir", l_dx, l_dy, l_dz);
		GLShaderKit.setFloat("l_ddir0", l_ddx0, l_ddy0, l_ddz0);
		GLShaderKit.setFloat("l_ddir1", l_ddx1, l_ddy1, l_ddz1);
		GLShaderKit.setInt("N", N);

		-- invoke the shader.
		local data = obj.getpixeldata("work");
		GLShaderKit.draw("TRIANGLES", data, w2, h2);

		-- close the shader context.
		GLShaderKit.deactivate();

		-- put back the result.
		obj.putpixeldata(data);
		obj.copybuffer("tmp", "obj");
	else obj.setoption("dst", "tmp", w2, h2) end

	-- combine the images.
	if front_alpha > 0 then
		obj.copybuffer("obj", cache_name_obj);
		obj.setoption("blend", 0);
		obj.draw(x2, y2, 0, 1, front_alpha);
	end
	obj.copybuffer("obj", "tmp");

	-- adjust the center.
	obj.cx, obj.cy = obj.cx + x2, obj.cy + y2;
end

return {
	GroundShadow2_S = GroundShadow2_S;
};
