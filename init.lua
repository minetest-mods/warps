
--[[

Copyright (C) 2015 - Auke Kok <sofar@foo-projects.org>

"warps" is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as
published by the Free Software Foundation; either version 2.1
of the license, or (at your option) any later version.

--]]

local warps = {}
local warps_queue = {}
local queue_state = 0
local warps_freeze = 5
-- t = time in usec
-- p = player obj
-- w = warp name

local S = minetest.get_mod_storage()
assert(S, "mod_storage is required")

-- import warps or load
local function firstload()
	local store = S:get("warps")
	local worldpath = minetest.get_worldpath()
	if store then
		warps = minetest.deserialize(store)
		return
	end
	local fh,err = io.open(worldpath .. "/warps.txt", "r")
	if err then
		-- If it doesn't exist, we've never used this mod before.
		if not err:find("No such file or directory") then
			minetest.log("error", "[warps] Error trying to load warps.txt: " .. err)
		end
		return
	end
	while true do
		local line = fh:read()
		if line == nil then
			break
		end
		local paramlist = string.split(line, " ")
		local w = {
			name = paramlist[1],
			x = tonumber(paramlist[2]),
			y = tonumber(paramlist[3]),
			z = tonumber(paramlist[4]),
			yaw = tonumber(paramlist[5]),
			pitch = tonumber(paramlist[6])
		}
		table.insert(warps, w)
	end
	fh:close()
	minetest.log("action", "[warps] converted warps to mod_storage. Please delete 'warps.txt'.")
	S:set_string("warps", minetest.serialize(warps))
end

local function lookup_warp(name)
	for i = 1,table.getn(warps) do
		if warps[i].name == name then
			return warps[i]
		end
	end
end

local function round_digits(n, digits)
	digits = digits or 0

	local multi = math.pow(10, digits)
	n = n * multi
	if n > 0 then
		return math.floor(n + 0.5) / multi
	else
		return math.ceil(n - 0.5) / multi
	end
end

local warp = function(player, dest)
	local warp = lookup_warp(dest)
	if not warp then
		minetest.chat_send_player(player:get_player_name(), "Unknown warp \"" .. dest .. "\"")
		return
	end

	local pos = vector.new(warp)
	pos.y = pos.y + 0.5
	player:set_pos(pos)
	player:set_look_horizontal(warp.yaw)
	player:set_look_vertical(warp.pitch)
	minetest.chat_send_player(player:get_player_name(), "Warped to \"" .. dest .. "\"")
	minetest.log("action", player:get_player_name() .. " warped to \"" .. dest .. "\"")
	minetest.sound_play("warps_plop", {pos = pos})
end

local function do_warp_queue()
	if table.getn(warps_queue) == 0 then
		queue_state = 0
		return
	end
	local t = minetest.get_us_time()
	for i = table.getn(warps_queue),1,-1 do
		local e = warps_queue[i]
		if e.p:get_pos() then
			if vector.equals(e.p:get_pos(), e.pos) then
				if t > e.t then
					warp(e.p, e.w)
					table.remove(warps_queue, i)
				end
			else
				minetest.sound_stop(e.sh)
				minetest.chat_send_player(e.p:get_player_name(),
						"You have to stand still for " .. warps_freeze .. " seconds!")
				table.remove(warps_queue, i)
			end
		end
	end
	if table.getn(warps_queue) == 0 then
		queue_state = 0
		return
	end
	minetest.after(1, do_warp_queue)
end

local warp_queue_add = function(player, dest)
	table.insert(warps_queue, {
		t = minetest.get_us_time() + (warps_freeze * 1000000),
		pos = player:get_pos(),
		p = player,
		w = dest,
		sh = minetest.sound_play("warps_woosh", { pos = player:get_pos() })
	})
	minetest.chat_send_player(player:get_player_name(), "Don't move for " .. warps_freeze .. " seconds!")
	if queue_state == 0 then
		queue_state = 1
		minetest.after(1, do_warp_queue)
	end
	-- attempt to emerge the target area before the player gets there
	local pos = vector.new(lookup_warp(dest))
	minetest.get_voxel_manip():read_from_map(pos, pos)
	if not minetest.get_node_or_nil(pos) then
		minetest.emerge_area(vector.subtract(pos, 80), vector.add(pos, 80))
	end
	-- force mapblock send to player, if supported
	if player.send_mapblock then
		player:send_mapblock(vector.divide(pos, 16))
	end
end

minetest.register_privilege("warp_admin", {
	description = "Allows modification of warp points",
	give_to_singleplayer = true,
	default = false
})

minetest.register_privilege("warp_user", {
	description = "Allows use of warp points",
	give_to_singleplayer = true,
	default = true
})

minetest.register_chatcommand("setwarp", {
	params = "name",
	description = "Set a warp location to the players location",
	privs = { warp_admin = true },
	func = function(name, param)
		param = param:gsub("%W", "")
		if param == "" then
			return false, "Cannot set warp: Name missing."
		end

		local h = "Created"
		for i = 1,table.getn(warps) do
			if warps[i].name == param then
				table.remove(warps, i)
				h = "Changed"
				break
			end
		end

		local player = minetest.get_player_by_name(name)
		local pos = vector.round(player:get_pos())
		table.insert(warps, {
			name = param,
			x = pos.x,
			y = pos.y,
			z = pos.z,
			yaw = round_digits(player:get_look_horizontal(), 3),
			pitch = round_digits(player:get_look_vertical(), 3)
		})
		S:set_string("warps", minetest.serialize(warps))

		minetest.log("action", name .. " " .. h .. " warp \"" .. param .. "\": " ..
				pos.x .. ", " .. pos.y .. ", " .. pos.z)
		return true, h .. " warp \"" .. param .. "\""
	end,
})

minetest.register_chatcommand("delwarp", {
	params = "name",
	description = "Set a warp location to the players location",
	privs = { warp_admin = true },
	func = function(name, param)
		for i = 1,table.getn(warps) do
			if warps[i].name == param then
				table.remove(warps, i)
				minetest.log("action", name .. " removed warp \"" .. param .. "\"")
				return true, "Removed warp \"" .. param .. "\""
			end
		end
		return false, "Unknown warp location \"" .. param .. "\""
	end,
})

minetest.register_chatcommand("listwarps", {
	params = "name",
	description = "List known warp locations",
	privs = { warp_user = true },
	func = function(name, param)
		local s = "List of known warp locations:\n"
		for i = 1,table.getn(warps) do
			s = s .. "- " .. warps[i].name .. "\n"
		end
		return true, s
	end
})

minetest.register_chatcommand("warp", {
	params = "name",
	description = "Warp to a warp location",
	privs = { warp_user = true },
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not minetest.check_player_privs(player, {warp_admin = true}) then
			warp_queue_add(player, param)
		else
			warp(player, param)
		end
	end
})

local function prepare_dropdown(x,y,w,h,curr_dest)
	local dd = string.format("dropdown[%f,%f;%f,%f;ddwarp;", x, y, w, h)
	local sel = 0
	for idx, warp in ipairs(warps) do
		local warpname = warp.name
		dd = dd .. minetest.formspec_escape(warpname) .. ","
		if curr_dest == warpname then
			sel = idx
		end
	end
	dd = dd .. ";"..tostring(sel).."]"
	return dd
end

local function prepare_formspec(dest)
	local custdest = ""
	if not lookup_warp(dest) then
		custdest = dest
	end
	return "size[4.5,3]label[0.7,0;Warp destination]"
		.."field[1,2.2;3,0.2;destination;Future destination;"
		..minetest.formspec_escape(custdest).."]"
		.."button_exit[0.7,2.7;3,0.5;proceed;Proceed]"
		..prepare_dropdown(0.7,0.4,3,1, dest)
end

minetest.register_node("warps:warpstone", {
	visual = "mesh",
	mesh = "warps_warpstone.obj",
	description = "A Warp Stone",
	tiles = { "warps_warpstone.png" },
	drawtype = "mesh",
	sunlight_propagates = true,
	walkable = false,
	paramtype = "light",
	groups = { choppy=3 },
	light_source = 8,
	diggable = false,
	selection_box = {
		type = "fixed",
		fixed = {-0.25, -0.5, -0.25,  0.25, 0.5, 0.25}
	},
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", prepare_formspec(""))
		meta:set_string("infotext", "Uninitialized Warp Stone")
	end,
	on_receive_fields = function(pos, formname, fields, sender)
		if not minetest.check_player_privs(sender:get_player_name(), {warp_admin = true}) then
			minetest.chat_send_player(sender:get_player_name(), "You do not have permission to modify warp stones")
			return false
		end
		if not (fields.destination and fields.quit) then
			return
		end

		local dest
		if fields.destination == "" and fields.ddwarp then
			dest = fields.ddwarp
		else
			dest = fields.destination
		end

		local meta = minetest.get_meta(pos)

		meta:set_string("formspec", prepare_formspec(dest))
		meta:set_string("infotext", "Warp stone to " .. dest)
		meta:set_string("warps_destination", dest)
		minetest.log("action", sender:get_player_name() .. " changed warp stone at "
			.. minetest.pos_to_string(pos) .. " to \"" .. dest .. "\"")
	end,
	on_punch = function(pos, node, puncher, pointed_thingo)
		if puncher:get_player_control().sneak and
				minetest.check_player_privs(puncher:get_player_name(), {warp_admin = true}) then
			minetest.remove_node(pos)
			minetest.chat_send_player(puncher:get_player_name(), "Warp stone removed!")
			return
		end

		local meta = minetest.get_meta(pos)
		local destination = meta:get_string("warps_destination")
		if destination == "" or lookup_warp(destination) == nil then
			minetest.chat_send_player(puncher:get_player_name(),
					"Unknown warp location for this warp stone, cannot warp!")
			return false
		end
		minetest.log("action", string.format("Going to warp player %s to waypoint %s",
			puncher:get_player_name(), destination
		))
		warp_queue_add(puncher, destination)
	end,
})

firstload()
