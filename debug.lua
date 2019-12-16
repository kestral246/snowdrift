-- Debug code

-- Global variable to store Hud IDs.
snowdrift_debug = {}

-- Minetest game biome mapping, but no skyrealms
local biome_vals = {{heat=0,  humid=73, ymin=-8,   ymax=31000, name="icesheet"},
			{heat=0,  humid=73, ymin=-112, ymax=-9,    name="icesheet_ocean"},
			{heat=0,  humid=40, ymin=47,   ymax=31000, name="tundra_highland"},
			{heat=0,  humid=40, ymin=2,    ymax=46,    name="tundra"},
			{heat=0,  humid=40, ymin=-3,   ymax=1,     name="tundra_beach"},
			{heat=0,  humid=40, ymin=-112, ymax=-4,    name="tundra_ocean"},
			{heat=25, humid=70, ymin=4,    ymax=31000, name="taiga"},
			{heat=25, humid=70, ymin=-112, ymax=3,     name="taiga_ocean"},
			{heat=20, humid=35, ymin=4,    ymax=31000, name="snowy_grassland"},
			{heat=20, humid=35, ymin=-112, ymax=3,     name="snowy_grassland_ocean"},
			{heat=50, humid=35, ymin=6,    ymax=31000, name="grassland"},
			{heat=50, humid=35, ymin=4,    ymax=5,     name="grassland_dunes"},
			{heat=50, humid=35, ymin=-112, ymax=3,     name="grassland_ocean"},
			{heat=45, humid=70, ymin=6,    ymax=31000, name="coniferous_forest"},
			{heat=45, humid=70, ymin=4,    ymax=5,     name="coniferous_forest_dunes"},
			{heat=45, humid=70, ymin=-112, ymax=3,     name="coniferous_forest_ocean"},
			{heat=60, humid=68, ymin=1,    ymax=31000, name="deciduous_forest"},
			{heat=60, humid=68, ymin=-1,   ymax=0,     name="deciduous_forest_shore"},
			{heat=60, humid=68, ymin=-112, ymax=-2,    name="deciduous_forest_ocean"},
			{heat=92, humid=16, ymin=4,    ymax=31000, name="desert"},
			{heat=92, humid=16, ymin=-112, ymax=3,     name="desert_ocean"},
			{heat=60, humid=0,  ymin=4,    ymax=31000, name="sandstone_desert"},
			{heat=60, humid=0,  ymin=-112, ymax=3,     name="sandstone_desert_ocean"},
			{heat=40, humid=0,  ymin=4,    ymax=31000, name="cold_desert"},
			{heat=40, humid=0,  ymin=-112, ymax=3,     name="cold_desert_ocean"},
			{heat=89, humid=42, ymin=1,    ymax=31000, name="savanna"},
			{heat=89, humid=42, ymin=-1,   ymax=0,     name="savanna_shore"},
			{heat=89, humid=42, ymin=-112, ymax=-2,    name="savanna_ocean"},
			{heat=86, humid=65, ymin=1,    ymax=31000, name="rainforest"},
			{heat=86, humid=65, ymin=-1,   ymax=0,     name="rainforest_swamp"},
			{heat=86, humid=65, ymin=-112, ymax=-2,    name="rainforest_ocean"}}

local square = function(x)
	return x*x
end

local biome_dists = function(heat, humid, elev)
	local newtbl = {}
	local dist
	for i,v in pairs(biome_vals) do
		if elev >= v.ymin and elev <= v.ymax then
			dist = math.sqrt(square(heat - v.heat) + square(humid - v.humid))
			table.insert(newtbl, {dist=dist, name=v.name})
		end
	end
	return newtbl
end

local nearest_biomes = function(heat, humid, elev, thresh)
	local close_biomes = {}
	local closest = biome_dists(heat, humid, elev)
	local mind = 9999
	for i,v in pairs(closest) do    -- find minimum distance
		if v.dist < mind then
			mind = v.dist
		end
	end
	for i,v in pairs(closest) do     -- find all distances within thresh of min
		if v.dist <= mind + thresh then
			table.insert(close_biomes, v.name)
		end
	end
	return close_biomes
end

snowdrift_disp_biomes = function(heat, humid, elev, thresh)
	local close_biomes = nearest_biomes(heat, humid, elev, thresh)
	local output = "{"
	for i,v in pairs(close_biomes) do
		if i == 1 then
			output = output.." "..v
		else
			output = output.." • "..v
		end
	end
	output = output.." }"
	return output
end

minetest.register_on_joinplayer(function(player)
		local pname = player:get_player_name()
		snowdrift_debug[pname] = {id = player:hud_add({hud_elem_type = "text",
				position = {x=0.5, y=0.1},
				text = " ",
				number = 0xFF0000}),  -- red text
		}
end)

minetest.register_on_leaveplayer(function(player)
	local pname = player:get_player_name()
	if snowdrift_debug[pname] then
		snowdrift_debug[pname] = nil
	end
end)
