
--[[

Copyright (C) 2015 - Auke Kok <sofar@foo-projects.org>

"warps" is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as
published by the Free Software Foundation; either version 2.1
of the license, or (at your option) any later version.

--]]

warps = {}
warps_queue = {}
queue_state = 0
local warps_freeze = 5
-- t = time in usec
-- p = player obj
-- w = warp name
local players = {}

local get_player_warps = function(player)
	if not player then
		return false
	end
	local t = {}
	local att = player:get_attribute("warps")
	if not att then
		player:set_attribute("warps", minetest.serialize(t))
	else
		t = minetest.deserialize(att)
	end
	return t
end

local show_warp_ui = function(player)
	players[player:get_player_name()].warp_index = 1
	local s_string = ""
	local o = {}
	for k, v in pairs(get_player_warps(player)) do
		if not v["name"] then
			minetest.log("error",
					"[warps] Faulty warps in player data.")
			return player:set_attribute("warps", nil),
					minetest.chat_send_player(player, "Faulty warps in player data.")
		end
		o[#o + 1] = v
		s_string = s_string .. v["name"] .. ","
	end
	player:set_attribute("warps", minetest.serialize(o))
	minetest.show_formspec(player:get_player_name(), "warps:warpstone", --TODO
			"size[7,5]" ..
			default.gui_bg_img ..
			"label[-0.11,-0.12;Manage Warps]" ..
			"field[0.15,0.58;4.86,1;new;;]" ..
			"button[4.69,0.25;1.2,1;save;Save]" ..
			"button[5.85,0.25;1.2,1;delete;Delete]" ..
			"table[-0.15,1.15;7,4;warp_idx;" ..
					s_string:sub(1, -2) .. ";1]" ..
			""
	)
end

local function lookup_warp(name, player)
	for i = 1,table.getn(warps) do
		if warps[i].name == name then
			return warps[i]
		end
	end
	local player_warps = get_player_warps(player)
	for i=1, #player_warps do
		if player_warps[i].name == name then
			return player_warps[i]
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
	local warp = lookup_warp(dest, player)
	if not warp then
		minetest.chat_send_player(player:get_player_name(), "Unknown warp \"" .. dest .. "\"")
		return
	end

	local pos = vector.new(warp)
	pos.y = pos.y + 0.5
	player:setpos(pos)
	player:set_look_horizontal(warp.yaw)
	player:set_look_vertical(warp.pitch)
	minetest.chat_send_player(player:get_player_name(), "Warped to \"" .. dest .. "\"")
	minetest.log("action", player:get_player_name() .. " warped to \"" .. dest .. "\"")
	minetest.sound_play("warps_plop", {pos = pos})
end

do_warp_queue = function()
	if table.getn(warps_queue) == 0 then
		queue_state = 0
		return
	end
	local t = minetest.get_us_time()
	for i = table.getn(warps_queue),1,-1 do
		local e = warps_queue[i]
		if e.p:getpos() then
			if vector.equals(e.p:getpos(), e.pos) then
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
		pos = player:getpos(),
		p = player,
		w = dest,
		sh = minetest.sound_play("warps_woosh", { pos = player:getpos() })
	})
	minetest.chat_send_player(player:get_player_name(), "Don't move for " .. warps_freeze .. " seconds!")
	if queue_state == 0 then
		queue_state = 1
		minetest.after(1, do_warp_queue)
	end
	-- attempt to emerge the target area before the player gets there
	local pos = vector.new(lookup_warp(dest, player))
	minetest.get_voxel_manip():read_from_map(pos, pos)
	if not minetest.get_node_or_nil(pos) then
		minetest.emerge_area(vector.subtract(pos, 80), vector.add(pos, 80))
	end
end

local worldpath = minetest.get_worldpath()

local save = function ()
	local fh,err = io.open(worldpath .. "/warps.txt", "w")
	if err then
		print("No existing warps to read.")
		return
	end
	for i = 1,table.getn(warps) do
		local s = warps[i].name .. " " .. warps[i].x .. " " .. warps[i].y .. " " ..
				warps[i].z .. " " .. warps[i].yaw .. " " .. warps[i].pitch .. "\n"
		fh:write(s)
	end
	fh:close()
end

local load = function ()
	local fh,err = io.open(worldpath .. "/warps.txt", "r")
	if err then
		minetest.log("action", "[warps] loaded ")
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
	minetest.log("action", "[warps] loaded " .. table.getn(warps) .. " warp location(s)")
end

minetest.register_on_joinplayer(function(player)
	players[player:get_player_name()] = {
		warp_index = 1,
	}
end)
minetest.register_on_leaveplayer(function(player)
	players[player:get_player_name()] = nil
end)

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
		local pos = vector.round(player:getpos())
		table.insert(warps, {
			name = param,
			x = pos.x,
			y = pos.y,
			z = pos.z,
			yaw = round_digits(player:get_look_horizontal(), 3),
			pitch = round_digits(player:get_look_vertical(), 3)
		})
		save()

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

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if not player then
		return
	end
	if formname ~= "warps:warpstone" then
		return
	end
	local idx, type, index, cell = nil, "", 1, 0
	local t = get_player_warps(player)
	local name = player:get_player_name()
	if fields.warp_idx then
		idx = fields.warp_idx
		type = idx:sub(1, 3)
		index = idx:sub(5, 5)
		cell = idx:sub(7, 7)
		players[name].warp_index = index
	elseif fields.save then
		local new = fields.new
		if not new then
			minetest.chat_send_player(player, "Cannot set warp: Name missing.")
		elseif new == "" then
			minetest.chat_send_player(player, "Cannot set warp: Name missing.")
		else
			for i = 1, #get_player_warps(player) do
				if get_player_warps(player)[i].name == new then
					-- TODO Make it simply change the warp to new location?
					return minetest.chat_send_player(player, "Pick a new name.")
				end
			end
			new = new:gsub("%W", "")
			local pos = vector.round(player:getpos())
			t[#t + 1] = {
				name = new,
				x = pos.x,
				y = pos.y,
				z = pos.z,
				yaw = round_digits(player:get_look_horizontal(), 3),
				pitch = round_digits(player:get_look_vertical(), 3)
			}
		end
		player:set_attribute("warps", minetest.serialize(t))
		show_warp_ui(player)
	elseif fields.delete then
		idx = tonumber(players[name].warp_index)
		t[idx] = nil
		player:set_attribute("warps", minetest.serialize(t))
		show_warp_ui(player)
	end
end)

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
	selection_box = {
		type = "fixed",
		fixed = {-0.25, -0.5, -0.25,  0.25, 0.5, 0.25}
	},
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec",
			"field[destination;Warp Destination;]")
		meta:set_string("infotext", "Uninitialized Warp Stone")
	end,
	on_use = function(itemstack, user, pointed_thing)
		show_warp_ui(user)
	end,
	on_receive_fields = function(pos, formname, fields, sender)
		if not minetest.check_player_privs(sender:get_player_name(), {warp_admin = true}) then
			minetest.chat_send_player(sender:get_player_name(), "You do not have permission to modify warp stones")
			return false
		end
		if not fields.destination then
			return
		end
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec",
			"field[destination;Warp Destination;" .. fields.destination .. "]")
		meta:set_string("infotext", "Warp stone to " .. fields.destination)
		meta:set_string("warps_destination", fields.destination)
		minetest.log("action", sender:get_player_name() .. " changed warp stone to \"" .. fields.destination .. "\"")
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
		if destination == "" then
			minetest.chat_send_player(puncher:get_player_name(),
					"Unknown warp location for this warp stone, cannot warp!")
			return false
		end
		warp_queue_add(puncher, destination)
	end,
})

-- load existing warps
load()

