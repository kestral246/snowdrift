-- Parameters

local YWATER = 1 -- Normally set this to world's water level
				-- Particles are timed to disappear at this y
				-- Particles are not spawned for players below this y
				-- Rain sound is not played for players below this y
local YMIN = -48 -- Normally set this to deepest ocean
local YMAX = 120 -- Normally set this to cloud level
					-- Weather does not occur for players outside this y range
local PRECTIM = 300 -- Precipitation noise 'spread'
					-- Time scale for precipitation variation, in seconds
local PRECTHR = 0.2 -- Precipitation noise threshold, -1 to 1:
				-- -1 = precipitation all the time
				-- 0 = precipitation half the time
				-- 1 = no precipitation
local FLAKLPOS = 32 -- Snowflake light-tested positions per 0.5s cycle
				-- Maximum number of snowflakes spawned per 0.5s
local DROPLPOS = 64 -- Raindrop light-tested positions per 0.5s cycle
local DROPPPOS = 2 -- Number of raindrops spawned per light-tested position
local RAINGAIN = 0.2 -- Rain sound volume
local NISVAL = 39 -- Overcast sky RGB value at night (brightness)
local DASVAL = 159 -- Overcast sky RGB value in daytime (brightness)
local FLAKRAD = 16 -- Radius in which flakes are created
local DROPRAD = 16 -- Radius in which drops are created

local SB_INTERVAL = 2 -- Overcast skybox update interval, [1,2,…)
local FREEZE_STEP = 1 -- Rain/snow transition step size (in heat/humid units)
local DRY_STEP = 1 -- Dry desert transition step size (in heat/humid units)
local CLOUD_STEP = 1  -- Cloud density step size (in percent)

-- Precipitation noise

local np_prec = {
	offset = 0,
	scale = 1,
	spread = {x = PRECTIM, y = PRECTIM, z = PRECTIM},
	seed = 813,
	octaves = 1,
	persist = 0,
	lacunarity = 2.0,
	flags = "defaults"
}

-- Enabling debug adds a HUD to display snowdrift state
local debug = false

-- Valleys mapgen support (also must match world parameters)
local altitude_chill = false
local altitude_dry = false
local alt_chill_dist = 90

-- Snow/rain transition
local freeze_pt = 35   -- valleys with altitude_* seems to like 32
local freeze_step = FREEZE_STEP

-- Desert transition
local dry_step = DRY_STEP

-- Cloud density change step (in hundredths)
local cl_step = CLOUD_STEP

-- End parameters

-- Do files
dofile(minetest.get_modpath("snowdrift") .. "/debug.lua")

-- Some stuff

local difsval = DASVAL - NISVAL
local grad = 14 / 95
local yint = 1496 / 95
local yint_offset = dry_step * 93.9849250811  -- 95 * sqrt(95^2/(95^2+14^2))

-- Initialise noise objects to nil

local nobj_prec = nil

-- Player tables

local rain_level = {}
local handles = {}
local skybox = {} -- true/false. To not turn off skyboxes of other mods


-- Globalstep function

local os_time_0 = os.time()
local t_offset = math.random(0, 300000)

local timer = 0
local cloud_state = {}

minetest.register_on_joinplayer(function(player)
		local player_name = player:get_player_name()
		cloud_state[player_name] = { prlev=0, setval=44 }
end)

minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.5 then
		return
	end

	timer = 0

	for _, player in ipairs(minetest.get_connected_players()) do
		local player_name = player:get_player_name()
		local ppos = player:get_pos()
		-- Point just above player head, to ensure precipitation when swimming
		local pposy = math.floor(ppos.y) + 2
		if pposy >= YMIN and pposy <= YMAX then
			local pposx = math.floor(ppos.x)
			local pposz = math.floor(ppos.z)
			local ppos = {x = pposx, y = pposy, z = pposz}

			-- Heat, humidity and precipitation noises

			-- Time in seconds.
			-- Add the per-server-session random time offset to avoid identical behaviour
			-- each server session.
			local time = os.difftime(os.time(), os_time_0) - t_offset

			local nobj_prec = nobj_prec or minetest.get_perlin(np_prec)

			local nval_temp = minetest.get_heat(ppos)
			local nval_humid = minetest.get_humidity(ppos)
			local nval_prec = nobj_prec:get_2d({x = time, y = 0})

			-- valleys mapgen adjustments to temp and humidity based on elevation
			local elev = pposy - 2
			while elev > 0 and minetest.get_node({x=pposx, y=elev, z=pposz}).name == "air" do
				elev = elev - 1
			end
			if altitude_chill then
				nval_temp = nval_temp - (20 * elev / alt_chill_dist)
			end
			if altitude_dry then
				nval_humid = nval_humid - (10 * elev / alt_chill_dist)
			end

			-- Default Minetest Game biome system:
			-- Frozen biomes below heat 35
			-- deserts below line 14 * t - 95 * h = -1496
			-- h = (14 * t + 1496) / 95
			-- h = 14/95 * t + 1496/95
			-- where 14/95 is gradient and 1496/95 is 'y-intersection'
			-- h - 14/95 * t = 1496/95
			-- so area above line is
			-- h - 14/95 * t > 1496/95

			--local freeze = nval_temp < 35
			--local precip = nval_prec > PRECTHR and
			--	nval_humid - grad * nval_temp > yint
			local precip = nval_prec > PRECTHR

			-- Create transition between precipitation levels
			-- (0 = dry, to 4 = full precip)
			-- Uses parallel desert lines spaced dry_step apart.
			local heat_humid = 190*nval_humid - 28*nval_temp
			local pr_maxlev
			if heat_humid <= 2992 - 3 * yint_offset then
				pr_maxlev = 0
			elseif heat_humid <= 2992 - yint_offset then
				pr_maxlev = 1
			elseif heat_humid <= 2992 + yint_offset then
				pr_maxlev = 2
			elseif heat_humid <= 2992 + 3 * yint_offset then
				pr_maxlev = 3
			else
				pr_maxlev = 4
			end

			-- define cloud density threshholds for each precip level
			local pr_to_cl = function(i)
				local table = { [0]=50, [1]=60, [2]=70, [3]=90, [4]=100 }
				return table[i]
			end

			-- define non-precip cloud density based on local humidity
			local hum_den = nval_humid * 0.4 + 20  -- cden = 20% - 60%

			-- aliases for cloud state variables
			local pr_level = cloud_state[player_name].prlev
			local cl_setval = cloud_state[player_name].setval

			if precip then -- increase or continue precip, unless pr_maxlev dropped
				if pr_level < pr_maxlev then
					if cl_setval < pr_to_cl(pr_level + 1) then
						cloud_state[player_name].setval = cl_setval + cl_step
					else
						cloud_state[player_name].prlev = pr_level + 1  -- bump to next state
					end
				elseif pr_level > pr_maxlev then  -- entered dryer region
					if cl_setval > pr_to_cl(pr_level - 1) then
						cloud_state[player_name].setval = cl_setval - cl_step
					else
						cloud_state[player_name].prlev = pr_level - 1  -- drop state down
					end
				end
			else -- gradually stop precip across the board
				if pr_level > 0 then
					if cl_setval > pr_to_cl(pr_level - 1) and cl_setval > hum_den then
						cloud_state[player_name].setval = cl_setval - cl_step
					else
						cloud_state[player_name].prlev = pr_level - 1  -- drop state down
					end
				else  -- precip is done, gradually transition to non-precip cloud density
					if cl_setval > hum_den + 1 then
						cloud_state[player_name].setval = cl_setval - cl_step
					elseif cl_setval < hum_den - 1 then
						cloud_state[player_name].setval = cl_setval + cl_step
					end
				end
			end

			-- update aliases, in case either changed
			pr_level = cloud_state[player_name].prlev
			cl_setval = cloud_state[player_name].setval

			-- clouds during precip max of precip value or humid-based value
			-- no precip just uses humid-based value
			-- local cur_den
			local cloud_table = {}
			if pr_level > 0 then  -- still have precip falling
				cloud_table.density = math.max(cl_setval, hum_den) * 0.01
			else
				cloud_table.density = cl_setval * 0.01
			end
			player:set_clouds(cloud_table)

			-- Create blending transition between all snow (freeze=0)
			-- and all rain (freeze=4).
			-- Uses freeze_pt and freeze_step to define.
			local freeze
			if nval_temp >= freeze_pt + 1.5*freeze_step then
				freeze = 4
			elseif nval_temp <= freeze_pt - 1.5*freeze_step then
				freeze = 0
			else
				freeze = math.ceil((nval_temp - freeze_pt + 1.5*freeze_step)/freeze_step)
			end

			-- Set sky
			if pr_level == 4 then
				-- check sky brightness
				local sval
				local time = minetest.get_timeofday()
				if time >= 0.5 then
					time = 1 - time
				end
				-- Sky brightness transitions:
				-- First transition (24000 -) 4500, (1 -) 0.1875
				-- Last transition (24000 -) 5750, (1 -) 0.2396
				if time <= 0.1875 then
					sval = NISVAL
				elseif time >= 0.2396 then
					sval = DASVAL
				else
					sval = math.floor(NISVAL +
						((time - 0.1875) / 0.0521) * difsval)
				end
				-- Set overcast sky only during max precip and if normal
				if not skybox[player_name] or math.abs(skybox[player_name] - sval) >= SB_INTERVAL then
					player:set_sky({["base_color"]=sval*0x010101+16; ["type"]="plain"; ["clouds"]=false})
					player:set_sun({["visible"]=false, ["sunrise_visible"]=false})
					player:set_moon({["visible"]=false})
					player:set_stars({["visible"]=false})
					skybox[player_name] = sval
				end
			elseif pr_level ~= 4 and skybox[player_name] then
				-- Set normal sky only if skybox
				player:set_sky()  -- default
				player:set_sun()
				player:set_moon()
				player:set_stars()
				skybox[player_name] = nil
			end

			-- Stop looping sound.
			-- Stop sound if head below water level.
			if freeze == 0 or pr_level == 0 or pposy < YWATER then
				if handles[player_name] then
					minetest.sound_stop(handles[player_name])
					handles[player_name] = nil
				end
			end

			-- Display debug HUD
			if debug then
				local tenths = function(x)
					return math.floor(10 * x + .5) / 10
				end
				local spn = 'nil'
				if skybox[player_name] then spn = skybox[player_name] end
				player:hud_change(snowdrift_debug[player_name].id, "text",
					tenths(nval_temp)..'°, '..tenths(nval_humid)..
					'%, alt='..elev..', frz='..freeze..
					', prlev='..pr_level..' / '..pr_maxlev..
					', clden='..cl_setval/100 ..
					', skybox='..spn..
					'  '..snowdrift_disp_biomes(nval_temp, nval_humid, elev, 2.5))
			end

			-- Particles and sounds.
			-- Only if head above water level.
			if pr_level > 0 and pposy >= YWATER then
				if freeze <= 3 then
					-- Snowfall particles
					for lpos = 1, ((4-freeze)/4)*(pr_level/4)*FLAKLPOS do
						local lposx = pposx - FLAKRAD +
							math.random(0, FLAKRAD * 2)
						local lposz = pposz - FLAKRAD +
							math.random(0, FLAKRAD * 2)
						if minetest.get_node_light(
								{x = lposx, y = pposy + 10, z = lposz},
								0.5) == 15 then
							-- Any position above light-tested position is also
							-- light level 15.
							-- Spawn Y randomised to avoid particles falling
							-- in separated layers.
							-- Random range = speed * cycle time
							local spawny = pposy + 10 + math.random(0, 10) / 10
							local extime = math.min((spawny - YWATER) / 2, 10)

							minetest.add_particle({
								pos = {x = lposx, y = spawny, z = lposz},
								velocity = {x = 0, y = -2.0, z = 0},
								acceleration = {x = 0, y = 0, z = 0},
								expirationtime = extime,
								size = 2.8,
								collisiondetection = true,
								collision_removal = true,
								vertical = false,
								texture = "snowdrift_snowflake" ..
									math.random(1, 12) .. ".png",
								playername = player:get_player_name()
							})
						end
					end
				end
				if freeze >= 1 then
					-- Rainfall particles
					for lpos = 1, (freeze/4)*(pr_level/4)*DROPLPOS do
						local lposx = pposx - DROPRAD +
							math.random(0, DROPRAD * 2)
						local lposz = pposz - DROPRAD +
							math.random(0, DROPRAD * 2)
						if minetest.get_node_light(
								{x = lposx, y = pposy + 10, z = lposz},
								0.5) == 15 then
							for drop = 1, DROPPPOS do
								local spawny = pposy + 10 + math.random(0, 60) / 10
								local extime = math.min((spawny - YWATER) / 12, 2)
								local spawnx = lposx - 0.4 + math.random(0, 8) / 10
								local spawnz = lposz - 0.4 + math.random(0, 8) / 10

								minetest.add_particle({
									pos = {x = spawnx, y = spawny, z = spawnz},
									velocity = {x = 0.0, y = -12.0, z = 0.0},
									acceleration = {x = 0, y = 0, z = 0},
									expirationtime = extime,
									size = 2.8,
									collisiondetection = true,
									collision_removal = true,
									vertical = true,
									texture = "snowdrift_raindrop.png",
									playername = player:get_player_name()
								})
							end
						end
					end
					-- Start looping sound
					-- if not handles[player_name] then
					if not handles[player_name] then  -- new sound
						local handle = minetest.sound_play(
							"snowdrift_rain",
							{
								to_player = player_name,
								gain = RAINGAIN * (freeze * pr_level / 16),
								loop = true,
							}
						)
						if handle then
							handles[player_name] = handle
							rain_level[player_name] = freeze*pr_level
						end
					elseif rain_level[player_name] ~= freeze * pr_level then  -- volume change
						minetest.sound_stop(handles[player_name])
						local handle = minetest.sound_play(
							"snowdrift_rain",
							{
								to_player = player_name,
								gain = RAINGAIN * (freeze * pr_level / 16),
								loop = true,
							}
						)
						if handle then
							handles[player_name] = handle
							rain_level[player_name] = freeze*pr_level
						end
					end
				end
			end
		else
			-- Player outside y limits.
			-- Stop sound if playing.
			if handles[player_name] then
				minetest.sound_stop(handles[player_name])
				handles[player_name] = nil
			end
			-- Set normal sky if skybox
			if skybox[player_name] then
				player:set_sky()  -- default
				player:set_sun()
				player:set_moon()
				player:set_stars()
				skybox[player_name] = nil
			end
		end
	end
end)


-- On leaveplayer function

minetest.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	if rain_level[player_name] then
		rain_level[player_name] = nil
	end
	-- Stop sound if playing and remove handle
	if handles[player_name] then
		minetest.sound_stop(handles[player_name])
		handles[player_name] = nil
	end
	-- Remove skybox bool if necessary
	if skybox[player_name] then
		skybox[player_name] = nil
	end
	if cloud_state[player_name] then
		cloud_state[player_name] = nil
	end
end)
