
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
		line = fh:read()
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

-- load existing warps
load()

