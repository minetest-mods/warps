
--[[

Copyright (C) 2015 - Auke Kok <sofar@foo-projects.org>

"warps" is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as
published by the Free Software Foundation; either version 2.1
of the license, or (at your option) any later version.

--]]

warps = {}

local worldpath = minetest.get_worldpath()

local save = function ()
	local fh,err = io.open(worldpath .. "/warps.txt", "w")
	if err then
		print("No existing warps to read.")
		return
	end
	for i = 1,table.getn(warps) do
		local s = warps[i].name .. " " .. warps[i].x .. " " .. warps[i].y .. " " .. warps[i].z .. " " .. warps[i].yaw .. " " .. warps[i].pitch .. "\n"
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
		local h = "created"
		for i = 1,table.getn(warps) do
			if warps[i].name == param then
				table.remove(warps, i)
				h = "changed"
				break
			end
		end
		local player = minetest.get_player_by_name(name)
		local pos = player:getpos()
		table.insert(warps, { name = param, x = pos.x, y = pos.y, z = pos.z, yaw = player:get_look_yaw(), pitch = player:get_look_pitch() })
		save()
		minetest.log("action", "\"" .. name .. "\" " .. h .. " warp \"" .. param .. "\": " .. pos.x .. ", " .. pos.y .. ", " .. pos.z)
		return true, "\"" .. name .. "\" " .. h .. " warp \"" .. param .. "\""
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
				minetest.log("action", "\"" .. name .. "\" removed warp \"" .. param .. "\"")
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
		for i = 1,table.getn(warps) do
			if warps[i].name == param then
				local player = minetest.get_player_by_name(name)
				player:setpos({x = warps[i].x, y = warps[i].y, z = warps[i].z})
				player:set_look_yaw(warps[i].yaw)
				player:set_look_pitch(warps[i].pitch)
				minetest.log("action", "\"" .. name .. "\" warped \"" .. name .. "\" to \"" .. param .. "\" at " .. warps[i].x .. ", " .. warps[i].y .. ", " .. warps[i].z)
				return true, "Warped \"" .. name .. "\" to \"" .. param .. "\""
			end
		end
		return false, "Unknown warp \"" .. param .. "\""
	end
})

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
	light_source = 5,
	selection_box = {
		type = "fixed",
		fixed = {-0.25, -0.5, -0.25,  0.25, 0.5, 0.25}
	},
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec",
			"field[destination;Warp Destination;]")
		meta:set_string("Infotext", "Uninitialized Warp Stone")
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
		meta:set_string("warps_destination", fields.destination)
		minetest.log("action", sender:get_player_name() .. " changed warp stone to \"" .. fields.destination .. "\"")
	end,
	on_punch = function(pos, node, puncher, pointed_thingo)
		if puncher:get_player_control().sneak and minetest.check_player_privs(puncher:get_player_name(), {warp_admin = true}) then
			minetest.remove_node(pos)
			minetest.chat_send_player(puncher:get_player_name(), "Warp stone removed!")
			return
		end
		local meta = minetest.get_meta(pos)
		local destination = meta:get_string("warps_destination")
		if destination == "" then
			minetest.chat_send_player(puncher:get_player_name(), "Unknown warp location for this warp stone, cannot warp!")
			return false
		end
		for i = 1,table.getn(warps) do
			if warps[i].name == destination then
				puncher:setpos({x = warps[i].x, y = warps[i].y, z = warps[i].z})
				puncher:set_look_yaw(warps[i].yaw)
				puncher:set_look_pitch(warps[i].pitch)
				minetest.log("action", puncher:get_player_name() .. " used a warp stone to \"" .. destination .. "\"")
				minetest.chat_send_player(puncher:get_player_name(), "warped to \"" .. destination .. "\"")
				return true, "Warped \"" .. puncher:get_player_name() .. "\" to \"" .. destination .. "\""
			end
		end
		minetest.chat_send_player(puncher:get_player_name(), "Unknown warp location for this warp stone, cannot warp!")
		return false

	end,
})

-- load existing warps
load()

