saturn.default_slot_color = "listcolors[#80808069;#00000069;#141318;#30434C;#FFF]"
saturn.MAX_ITEM_WEAR = 65535 -- Internal minetest constant and should not be changed
saturn.REPAIR_PRICE_PER_WEAR = 0.0001
saturn.saturn_spaceships = {}
saturn.players_info = {}
saturn.players_save_interval = 1000
saturn.save_timer = saturn.players_save_interval
saturn.market_update_interval = 100
saturn.market_update_timer = 1.0
saturn.market_items = {}
saturn.ore_market_items = {}
saturn.microfactory_market_items = {}
saturn.enemy_item_count = 0
saturn.enemy_items = {}
saturn.enemy_items_by_level = {}
saturn.ores = {}
saturn.hud_healthbar_id = -1
saturn.hud_energybar_id = -1
saturn.hud_energybar_filler_id = -1
saturn.hud_relative_velocity_id = -1
saturn.hud_attack_info_text_id = -1
saturn.hud_attack_info_frame_id = -1
saturn.hud_hotbar_cooldown = {}
saturn.hotbar_cooldown = {}
saturn.hud_radar_shelf = {}
saturn.hud_radar_text = {}
saturn.radars = {}
saturn.microfactory_nets = {}
saturn.recipe_outputs = {}

local fov = minetest.setting_get("fov")
local fov_x = fov*1.1
local fov_y = fov
local tan_fov_x = math.tan(math.pi*fov_x/360)
local tan_fov_y = math.tan(math.pi*fov_y/360)
local getVectorPitchAngle = saturn.get_vector_pitch_angle
local getVectorYawAngle = saturn.get_vector_yaw_angle

local find_target = function(self_pos, ignore_line_of_sight)
    local objs = minetest.get_objects_inside_radius(self_pos, 128)
    for k, obj in pairs(objs) do
	local lua_entity = obj:get_luaentity()
	if lua_entity then
	    if lua_entity.name == "saturn:spaceship" and not lua_entity.is_escape_pod then
		local is_clear, node_pos = minetest.line_of_sight(self_pos, obj:getpos(), 2)
		if is_clear or ignore_line_of_sight then
		    return obj
		end
	    end
	end
    end
    return nil
end

saturn.find_target = find_target

saturn.get_onscreen_coords_of_object = function(player, object) --highly inaccurate
	local look_dir=player:get_look_dir()
	local look_x=look_dir.x
	local look_y=look_dir.y
	local look_z=look_dir.z
	local look_yaw = player:get_look_horizontal()
	local look_pitch = player:get_look_vertical()
	local player_pos = player:getpos()
	local object_pos = nil
	if type(object) == "table" then
		object_pos = object
	else
		object_pos = object:getpos()
	end
	local vector_to_object = vector.subtract(object_pos, player_pos)
	local distance_to_object = vector.length(vector_to_object)
	local look_vector_extended_to_point_on_object_sphere = vector.multiply(look_dir, distance_to_object)
	local vector_between_extended_look_and_object = vector.subtract(vector_to_object, look_vector_extended_to_point_on_object_sphere)
	local vlb_x = vector_between_extended_look_and_object.x
	local vlb_y = vector_between_extended_look_and_object.y-1
	local vlb_z = vector_between_extended_look_and_object.z
	local screen_projection_width = tan_fov_x * distance_to_object
	local screen_projection_height = tan_fov_y * distance_to_object
	local cos_yaw = math.cos(look_yaw)
	local sin_yaw = math.sin(look_yaw)
	local x_offset = vlb_x*sin_yaw - vlb_z*cos_yaw
	local y_offset = (vlb_x*cos_yaw + vlb_z*sin_yaw)*look_y-vlb_y*math.cos(look_pitch)
	local xo_normal = x_offset/screen_projection_width
	local yo_normal = y_offset/screen_projection_height
	local x_pos = 0.5*xo_normal+0.5
	local y_pos = 0.5*yo_normal+0.5
	if vector.length(vector_between_extended_look_and_object) > distance_to_object then
		x_pos = 0.5*(xo_normal+saturn.sign_of_number(xo_normal))+0.5
	end
	local frame_type = 0
	if x_pos < 0 and y_pos < 0 then
		frame_type = 1
	elseif x_pos < 1 and y_pos < 0 then
		frame_type = 2
	elseif x_pos < 0 and y_pos < 1 then
		frame_type = 8
	elseif x_pos > 1 and y_pos < 0 then
		frame_type = 3
	elseif x_pos < 0 and y_pos > 1 then
		frame_type = 7
	elseif x_pos < 1 and y_pos > 1 then
		frame_type = 6
	elseif x_pos > 1 and y_pos < 1 then
		frame_type = 4
	elseif x_pos > 1 and y_pos > 1 then
		frame_type = 5
	end
	return {x=math.max(math.min(x_pos,0.98),0.02), y=math.max(math.min(y_pos,0.98),0.02), frame=frame_type}
end

saturn.get_escape_pod = function()
	local escape_pod = ItemStack("saturn:escape_pod")
	escape_pod:set_metadata(minetest.serialize({traction = 500,}))
	return escape_pod
end

saturn.release_delayed_power_and_try_to_shoot_again = function(ship_lua, amount, slot_number)
	local stop_sound = true
	local player = ship_lua.driver
	ship_lua['recharging_equipment_power_consumption'] = ship_lua['recharging_equipment_power_consumption'] - amount
	saturn.refresh_energy_hud(player)
	if player:get_wield_index() == slot_number then
		if player:get_player_control().LMB then
			local item_stack = player:get_wielded_item()
			if not item_stack:is_empty() then
				local on_use = item_stack:get_definition().on_use
				if on_use then
					ship_lua['ignore_cooldown'] = true
					player:set_wielded_item(on_use(item_stack, player, nil))
					stop_sound = false
				end
			end
		end
	end
	if stop_sound and ship_lua['weapon_sound_handler'] then
		minetest.sound_stop(ship_lua['weapon_sound_handler'])
		ship_lua['weapon_sound_handler'] = nil
	end
end

saturn.get_item_weight = function(list_name, item_stack)
	local item_name = item_stack:get_name()
	local value = 1000
	if string.find(list_name,"^hangar") then
		value = 0
	else
		local stats = minetest.registered_items[item_name]
		if stats ~= nil then
			if stats['weight'] then
				value = stats['weight']
				local metadata = minetest.deserialize(item_stack:get_metadata())
				if metadata then
					if metadata['weight'] then
						value = value + metadata['weight']
					end
				end
			end
		end
	end
	return value
end

saturn.get_item_volume = function(list_name, item_stack)
	local item_name = item_stack:get_name()
	local value = 0.01
	if list_name == "ship_hull" or string.find(list_name,"^hangar") then
		value = 0
	else
		local stats = minetest.registered_items[item_name]
		if stats ~= nil then
			if stats['volume'] then
				value = stats['volume']
				local metadata = minetest.deserialize(item_stack:get_metadata())
				if metadata then
					if metadata['volume'] then
						value = value + metadata['volume']
					end
				end
			end
		end
	end
	return value
end

saturn.get_item_stat = function(item_stack, stat_name, default_value)
	local item_name = item_stack:get_name()
	local value = default_value
	local stats = minetest.registered_items[item_name]
	if stats ~= nil then
		if stats[stat_name] then
			value = stats[stat_name]
			local metadata = minetest.deserialize(item_stack:get_metadata())
			if metadata then
				if metadata[stat_name] then
					value = value + metadata[stat_name]
				end
			end
		end
	end
	return value
end

saturn.refresh_health_hud = function(player)
		local inv = player:get_inventory()
		local ship_hull_stack = inv:get_stack("ship_hull", 1)
		if not ship_hull_stack:is_empty() then
			local wear = ship_hull_stack:get_wear()
			local display_status = (saturn.MAX_ITEM_WEAR - wear) * 316 / saturn.MAX_ITEM_WEAR
			local display_color = 29-math.ceil((saturn.MAX_ITEM_WEAR - wear) * 29 / saturn.MAX_ITEM_WEAR)
			local picture = "saturn_hud_bar.png^[verticalframe:32:"..display_color
			player:hud_change(saturn.hud_healthbar_id, "number", display_status)
			player:hud_change(saturn.hud_healthbar_id, "text", picture)
		end
end

saturn.refresh_energy_hud = function(player)
		local ship_obj = player:get_attach()
		if ship_obj then
			local ship_lua = ship_obj:get_luaentity()
			if ship_lua and ship_lua['free_power'] > 0 then
				local display_status = (ship_lua['free_power'] - ship_lua['recharging_equipment_power_consumption']) * 316 / ship_lua['free_power']
				player:hud_change(saturn.hud_energybar_id, "number", display_status)
			end
		end
end

saturn.create_hit_effect = function(time, vel_range, object_pos)
	for i=1,16 do
		minetest.add_particlespawner({
			amount = i,
			time = i*time/16,
			minpos = object_pos,
			maxpos = object_pos,
			minvel = {x=-vel_range, y=-vel_range, z=-vel_range},
			maxvel = {x=vel_range, y=vel_range, z=vel_range},
			minacc = {x=0, y=0, z=0},
			maxacc = {x=0, y=0, z=0},
			minexptime = i*time/16,
			maxexptime = i*time/16,
			minsize = 6,
			maxsize = 6,
			collisiondetection = false,
			vertical = false,
			texture = "saturn_flame_particle.png^[verticalframe:16:"..i,
		})
	end
end

saturn.create_railgun_hit_effect = function(time, vel_range_, object_pos)
	local frame_index = math.random(4)
	minetest.add_particle({
		pos = object_pos,
		velocity = {x=0, y=0, z=0},
		acceleration = {x=0, y=0, z=0},
		expirationtime = 0.1,
		size = 10,
		collisiondetection = false,
		vertical = false,
		texture = "saturn_green_splashes.png^[verticalframe:4:"..frame_index,
	})
	local vel_range = 5
	minetest.add_particlespawner({
		amount = math.random(5)+10,
		time = 0.1,
		minpos = object_pos,
		maxpos = object_pos,
		minvel = {x=-vel_range, y=-vel_range, z=-vel_range},
		maxvel = {x=vel_range, y=vel_range, z=vel_range},
		minacc = {x=0, y=0, z=0},
		maxacc = {x=0, y=0, z=0},
		minexptime = 0.01,
		maxexptime = 0.07,
		minsize = 0.1,
		maxsize = 1,
		collisiondetection = false,
		vertical = false,
		texture = "saturn_cdbcemw_shoot_particle.png",
	})
end


saturn.create_gauss_hit_effect = function(time, _vel_range, object_pos)
	minetest.add_particle({
		pos = object_pos,
		velocity = {x=0, y=0, z=0},
		acceleration = {x=0, y=0, z=0},
		expirationtime = 0.1,
		size = 1,
		collisiondetection = false,
		vertical = false,
		texture = "saturn_gauss_shot_particle.png"
	})
	local vel_range = 1
	minetest.add_particlespawner({
		amount = math.random(5)+1,
		time = 0.3,
		minpos = object_pos,
		maxpos = object_pos,
		minvel = {x=-vel_range, y=-vel_range, z=-vel_range},
		maxvel = {x=vel_range, y=vel_range, z=vel_range},
		minacc = {x=0, y=0, z=0},
		maxacc = {x=0, y=0, z=0},
		minexptime = 0.01,
		maxexptime = 0.05,
		minsize = 0.1,
		maxsize = 0.5,
		collisiondetection = false,
		vertical = false,
		texture = "saturn_incandescent_gradient.png^[verticalframe:16:"..math.random(4),
	})
end

saturn.create_shooting_effect = function(shooter_pos, direction_to_target, shooter_size)
	local x_pos = shooter_pos.x+direction_to_target.x*shooter_size
	local y_pos = shooter_pos.y+direction_to_target.y*shooter_size
	local z_pos = shooter_pos.z+direction_to_target.z*shooter_size
	minetest.add_particle({
		pos = {x=x_pos, y=y_pos, z=z_pos},
		velocity = {x=0, y=0, z=0},
		acceleration = {x=0, y=0, z=0},
		expirationtime = 0.1,
		size = 6,
		collisiondetection = false,
		vertical = false,
		texture = "saturn_cdbcemw_shoot_particle.png"
	})
end

saturn.create_explosion_effect = function(explosion_pos)
	local x_pos = explosion_pos.x
	local y_pos = explosion_pos.y
	local z_pos = explosion_pos.z
	minetest.add_particle({
		pos = {x=x_pos, y=y_pos, z=z_pos},
		velocity = {x=0, y=0, z=0},
		acceleration = {x=0, y=0, z=0},
		expirationtime = 0.1,
		size = 100,
		collisiondetection = false,
		vertical = false,
		texture = "saturn_white_halo.png"
	})
	local v_1 = vector.new(1,1,1)
	local time = 1.0
	for i=1,16 do
		minetest.add_particlespawner({
			amount = i,
			time = i*time/16,
			minpos = vector.subtract(explosion_pos, v_1),
			maxpos = vector.add(explosion_pos, v_1),
			minvel = {x=-1, y=-1, z=-1},
			maxvel = {x=1, y=1, z=1},
			minacc = {x=-1, y=-1, z=-1},
			maxacc = {x=1, y=1, z=1},
			minexptime = i*time/16,
			maxexptime = i*time/16,
			minsize = 6,
			maxsize = 6,
			collisiondetection = false,
			vertical = false,
			texture = "saturn_flame_particle.png^[verticalframe:16:"..i,
		})
	end
end

saturn.create_node_explosion_effect = function(explosion_pos, node_name)
	local node_def = minetest.registered_nodes[node_name]
	local v_1 = vector.new(1,1,1)
	local time = 0.2
	minetest.add_particlespawner({
		amount = 32,
		time = time,
		minpos = vector.subtract(explosion_pos, v_1),
		maxpos = vector.add(explosion_pos, v_1),
		minvel = {x=-10, y=-10, z=-10},
		maxvel = {x=10, y=10, z=10},
		minacc = {x=-1, y=-1, z=-1},
		maxacc = {x=1, y=1, z=1},
		minexptime = 0.1,
		maxexptime = time,
		minsize = 0.1,
		maxsize = 1.0,
		collisiondetection = true,
		vertical = false,
		texture = node_def.tiles[1],
	})
end

saturn.punch_object = function(punched, puncher, damage)
	if punched:is_player() and damage then
		local inv = punched:get_inventory()
		local ship_hull_stack = inv:get_stack("ship_hull", 1)
		local hull_stats = saturn.get_item_stats(ship_hull_stack:get_name())
		if hull_stats then
			local forcefield_generator_stack = inv:get_stack("forcefield_generator", 1)
			local ship_lua = punched:get_attach():get_luaentity()
			local forcefield_protection = ship_lua['forcefield_protection']
			if forcefield_protection > 0 then
				local ffg_stats = saturn.get_item_stats(forcefield_generator_stack:get_name())
				forcefield_generator_stack:add_wear(saturn.MAX_ITEM_WEAR/ffg_stats['max_wear'])
				inv:set_stack("forcefield_generator", 1, forcefield_generator_stack)
			end
			if ship_lua.total_modificators['forcefield_protection'] then
				forcefield_protection = math.min(90, forcefield_protection + ship_lua.total_modificators['forcefield_protection'])
			end
			ship_hull_stack:add_wear(damage * saturn.MAX_ITEM_WEAR * (100-forcefield_protection)/100/hull_stats['max_wear'])
			if ship_hull_stack:is_empty() then
				for list_name,list in pairs(inv:get_lists()) do
					for listpos,stack in pairs(list) do
						if stack ~= nil and not stack:is_empty() then
							inv:remove_item(list_name, stack)
							if list_name ~= "ship_hull" then
								saturn.throw_item(stack, punched:get_attach(), punched:getpos())
							end
						end
					end
				end
				saturn.create_explosion_effect(punched:getpos())
				inv:set_stack("ship_hull", 1, saturn:get_escape_pod())
			else
				inv:set_stack("ship_hull", 1, ship_hull_stack)
			end
			saturn.refresh_health_hud(punched)
			local name = punched:get_player_name()
			punched:set_inventory_formspec(saturn.get_player_inventory_formspec(punched,ship_lua['current_gui_tab']))
			ship_lua.hit_effect_timer = 3.0
			ship_lua.last_attacker = puncher

		end
	else
		punched:punch(puncher, 1.0, {
		full_punch_interval=1.0,
		damage_groups={fleshy=damage,enemy=damage},
		}, nil)
	end
end

local on_throwed_step = function(self, dtime) -- Taken from PilzAdam Throwing mod with few changes from https://github.com/PilzAdam/throwing/
    self.age=self.age+dtime
    self.collision_timer = self.collision_timer +dtime
    local pos = self.object:getpos()
    local node = minetest:get_node(pos)
    local self_velocity = self.object:getvelocity()
    if self.collision_timer > 2.0 then
		local objs = minetest:get_objects_inside_radius({x=pos.x,y=pos.y,z=pos.z}, math.min(2,self.age))
		for k, obj in pairs(objs) do
			local collided = obj:get_luaentity()
			if collided then
				if collided.name ~= self.name and collided.name ~= "__builtin:item" then
					local damage = vector.length(vector.subtract(obj:getvelocity(), self_velocity)) * 0.1
					if damage > 1.0 then
						if collided.name == "saturn:spaceship" and collided.driver then 
							saturn.punch_object(collided.driver, self.object, damage)
						else
							saturn.punch_object(obj, self.object, damage)
						end
					end
					if damage < 10 then
						self.object:setvelocity(vector.add(obj:getvelocity(),vector.multiply(self_velocity, -0.5)))
					else
						self.itemstring = ''
						self.object:remove()
					end
					self.collision_timer = 0
					return
				end
			end
		end
    end
    local lastpos=self.lastpos
    if lastpos.x~=nil then
	if node.name ~= "air" and node.name ~= "saturn:fog" and node.name ~= "ignore" then
		self.object:setpos(self.lastpos)
		self.object:setvelocity(vector.multiply(self_velocity,-0.1))
	end
    end
    self.lastpos={x=pos.x, y=pos.y, z=pos.z}
end

local throwable_item_entity={
	initial_properties = {
		is_visible = false,
		physical = true,
		collisionbox = {-0.25,-0.25,-0.25,0.25,0.25,0.25},
		visual = "sprite",
		visual_size = {x = 0.4, y = 0.4},
		textures = {""},
		infotext = "",
	},
	physical = true,
	collision_timer = 2.0,
	age = 0,
	lastpos={},
	itemstring = '',

	on_step = on_throwed_step,

	set_item = function(self, itemstring)
		self.itemstring = itemstring
		local stack = ItemStack(itemstring)
		local count = stack:get_count()
		local max_count = stack:get_stack_max()
		if count > max_count then
			count = max_count
			self.itemstring = stack:get_name().." "..max_count
		end
		local s = 0.8 + 0.1 * (count / max_count)
		local c = s
		local itemtable = stack:to_table()
		local itemname = nil
		local description = ""
		if itemtable then
			itemname = stack:to_table().name
		end
		local item_texture = nil
		local item_type = ""
		local itemdef = core.registered_items[itemname]
		if itemdef then
			item_texture = itemdef.inventory_image
			item_type = itemdef.type
			description = itemdef.description
		end
		local prop = {
			is_visible = true,
			visual = "sprite",
			textures = {item_texture},
			visual_size = {x = s, y = s},
			automatic_rotate = math.pi * 0.5,
			infotext = description,
		}
		if item_type == "node" then
			prop.visual = "cube"
			prop.textures = itemdef.tiles
		end
		self.object:set_properties(prop)
	end,

	get_staticdata = function(self)
		return core.serialize({
			itemstring = self.itemstring,
			always_collect = self.always_collect,
			age = self.age,
			velocity = self.object:getvelocity()
		})
	end,

	on_activate = function(self, staticdata, dtime_s)
		if string.sub(staticdata, 1, string.len("return")) == "return" then
			local data = core.deserialize(staticdata)
			if data and type(data) == "table" then
				self.itemstring = data.itemstring
				self.always_collect = data.always_collect
				if data.age then
					self.age = data.age + dtime_s
				else
					self.age = dtime_s
				end
				self.object:setvelocity(data.velocity)
			end
		else
			self.itemstring = staticdata
		end
		self.object:set_armor_groups({immortal = 1})
		self:set_item(self.itemstring)
	end,

	on_punch = function(self, hitter)
		self.itemstring = ''
		self.object:remove()
	end,
}

minetest.register_entity("saturn:throwable_item_entity", throwable_item_entity)

local format_pos = function(format,pos)
	return "("..string.format(format,pos.x)..","..string.format(format,pos.y)..","..string.format(format,pos.z)..")"
end

local PROJECTION_XZ = 1
local PROJECTION_XY = 2
local scale_map = {1,2,4,8,16,32,64,128}

local get_map_scale_bar_formspec = function(scale)
    local x_pos = 0.2
    local y_pos = 4
    local bar_length = 8
    local formspec = "image_button["..x_pos..","..y_pos..
";0.5,0.5;"..minetest.formspec_escape("saturn_gui_icons.png^[verticalframe:8:1")..";set_map_scale_"..math.min(scale+1,bar_length)..";;false;false;"
..minetest.formspec_escape("saturn_gui_icons.png^[verticalframe:8:1").."]"..
	"image_button["..x_pos..","..(y_pos+bar_length*0.35+0.35)..
";0.5,0.5;"..minetest.formspec_escape("saturn_gui_icons.png^[verticalframe:8:2")..";set_map_scale_"..math.max(scale-1,1)..";;false;false;"
..minetest.formspec_escape("saturn_gui_icons.png^[verticalframe:8:2").."]"
    for i=1,bar_length do
	if i == scale then
		formspec = formspec .. "image_button["..x_pos..","..(y_pos+(bar_length-i+1)*0.35)..
";0.5,0.5;"..minetest.formspec_escape("saturn_gui_icons.png^[verticalframe:8:6")..";set_map_scale_"..i..";;false;false;"
..minetest.formspec_escape("saturn_gui_icons.png^[verticalframe:8:6").."]"
	else
		formspec = formspec .. "image_button["..x_pos..","..(y_pos+(bar_length-i+1)*0.35)..
";0.5,0.5;"..minetest.formspec_escape("saturn_gui_icons.png^[verticalframe:8:5")..";set_map_scale_"..i..";;false;false;"
..minetest.formspec_escape("saturn_gui_icons.png^[verticalframe:8:5").."]"
	end
    end
    return formspec
end


local get_map_mark_formspec = function(scale, projection, pos, player_pos, title, width, height)
    local scale_multiplier = scale_map[scale]
    local x_pos = ((pos.x - player_pos.x) * scale_multiplier + 31000) * width / 62000
    local y_pos = ((player_pos.z - pos.z) * scale_multiplier + 31000) * height / 62000
    if projection == PROJECTION_XY then
	y_pos = ((player_pos.y - pos.y) * scale_multiplier + 31000) * height / 62000
    end
    if x_pos > 0 and x_pos < width and y_pos > 0 and y_pos < height then
	return "image["..x_pos..","..(y_pos+1)..";0.5,0.5;saturn_arrows_and_frame_blue.png^[verticalframe:10:9]"..
"label["..x_pos..","..(y_pos+1)..";"..title..format_pos("%d",pos).."]"
    else
	return ""
    end
end

local get_color_formspec_frame = function(x,y,w,h,color,thickness)
	local gap = 0.2
	return "box["..(x-thickness+gap)..","..(y-thickness)..";"..(w+thickness-0.2-gap*2)..","..(thickness)..";"..color.."]"..
"box["..(x+w-0.2)..","..(y-thickness+gap)..";"..(thickness)..","..(h+thickness-0.2-gap*2)..";"..color.."]"..
"box["..(x+gap)..","..(y+h-0.2)..";"..(w+thickness-0.2-gap*2)..","..(thickness)..";"..color.."]"..
"box["..(x-thickness)..","..(y+gap)..";"..(thickness)..","..(h+thickness-0.2-gap*2)..";"..color.."]"
end

saturn.get_color_formspec_frame = get_color_formspec_frame

local get_map_formspec = function(scale, projection, player)
    local form_width = 9
    local form_height = 9
    local coordinate_arrows = "saturn_map_zero_xz_mark.png"
    if projection == PROJECTION_XY then
	coordinate_arrows = "saturn_map_zero_xy_mark.png"
    end
    local formspec = get_map_mark_formspec(scale, projection, player:getpos(), player:getpos(), "YOU", form_width, form_height)..
	"image["..(form_width - 1.5)..","..(form_height - 1.5)..";1,1;"..coordinate_arrows.."]"..
	get_map_scale_bar_formspec(scale)..
	get_color_formspec_frame(0,0,form_width,form_height,"#041",0.05)
    for _,ss in ipairs(saturn.human_space_station) do
	formspec = formspec .. get_map_mark_formspec(scale, projection, ss, player:getpos(), "SS#".._, form_width, form_height)
    end
    for _,ess in ipairs(saturn.enemy_space_station) do
	formspec = formspec .. get_map_mark_formspec(scale, projection, ess, player:getpos(), "EMS#".._, form_width, form_height)
    end
    return formspec
end

local get_formspec_label_with_bg_color = function(x,y,w,h,color,text)
	return "box["..x..","..y..";"..w..","..h..";"..color.."]".."label["..x..","..(y-0.2)..";"..text.."]"
end


saturn.get_ship_equipment_formspec = function(player)
	local inv = player:get_inventory()
	local name = player:get_player_name()
	-- Hull
	local formspec = "list[current_player;ship_hull;0,0;1,1;]".."box[0,0;0.8,0.9;#FFFFFF]"..get_formspec_label_with_bg_color(0,1,0.8,0.2,"#FFFFFF","Hull")..
	"image_button[0.81,0;0.3,0.4;saturn_info_button_icon.png;item_info_player+"..name.."+ship_hull+1;]"
	if inv:get_size("engine") > 0 then
		formspec = formspec.."box[1,0;1.8,3.9;#FFA800]"..get_formspec_label_with_bg_color(0,1.4,0.8,0.2,"#FFA800","Engine")..
		"list[current_player;engine;1,0;2,4;]"
		for ix = 1, 2 do
			for iy = 0, math.ceil(inv:get_size("engine")/2)-1 do
				formspec = formspec.."image_button["..(ix+0.81)..","..(iy)..";0.3,0.4;saturn_info_button_icon.png;item_info_player+"..name.."+engine+"..(ix+2*iy)..";]"
			end
		end
	end
	if inv:get_size("power_generator") > 0 then
		formspec = formspec.."box[3,0;0.8,3.9;#FF2200]"..get_formspec_label_with_bg_color(0,1.8,0.8,0.2,"#FF2200","Power")..
		"list[current_player;power_generator;3,0;1,4;]"
		for iy = 0, inv:get_size("power_generator")-1 do
			formspec = formspec.."image_button[3.81,"..iy..";0.3,0.4;saturn_info_button_icon.png;item_info_player+"..name.."+power_generator+"..(iy+1)..";]"
		end
	end
	if inv:get_size("droid") > 0 then
		formspec = formspec.."box[4,0;0.8,3.9;#770000]"..get_formspec_label_with_bg_color(0,2.2,0.8,0.2,"#770000","Droids")..
		"list[current_player;droid;4,0;1,4;]"
		for iy = 0, inv:get_size("droid")-1 do
			formspec = formspec.."image_button[4.81,"..iy..";0.3,0.4;saturn_info_button_icon.png;item_info_player+"..name.."+droid+"..(iy+1)..";]"
		end
	end
	if inv:get_size("radar") > 0 then
		formspec = formspec.."box[5,0;0.8,0.9;#00FFF0]"..get_formspec_label_with_bg_color(0,2.6,0.8,0.2,"#00FFF0","Radar")..
		"list[current_player;radar;5,0;1,4;]"
		for iy = 0, inv:get_size("radar")-1 do
			formspec = formspec.."image_button[5.81,"..iy..";0.3,0.4;saturn_info_button_icon.png;item_info_player+"..name.."+radar+"..(iy+1)..";]"
		end
	end
	if inv:get_size("forcefield_generator") > 0 then
		formspec = formspec.."box[6,0;0.8,0.9;#A0A0FF]"..get_formspec_label_with_bg_color(0,3,0.8,0.2,"#A0A0FF","Forcefield")..
		"list[current_player;forcefield_generator;6,0;1,1;]"
		for iy = 0, inv:get_size("forcefield_generator")-1 do
			formspec = formspec.."image_button[6.81,"..iy..";0.3,0.4;saturn_info_button_icon.png;item_info_player+"..name.."+forcefield_generator+"..(iy+1)..";]"
		end
	end
	if inv:get_size("special_equipment") > 0 then
		formspec = formspec.."box[7,0;0.8,3.9;#A0FFA0]"..get_formspec_label_with_bg_color(0,3.4,0.8,0.2,"#A0FFA0","Special")..
		"list[current_player;special_equipment;7,0;1,4;]"
		for iy = 0, inv:get_size("special_equipment")-1 do
			formspec = formspec.."image_button[7.81,"..iy..";0.3,0.4;saturn_info_button_icon.png;item_info_player+"..name.."+special_equipment+"..(iy+1)..";]"
		end
	end
	return formspec
end

saturn.get_main_inventory_formspec = function(player, vertical_offset)
    local default_formspec = "list[current_player;main;0,"..vertical_offset..";8,1;]"..
		"list[current_player;main;0,"..(vertical_offset+1.25)..";8,3;8]"..
		saturn.default_slot_color
    if player then
    local name = player:get_player_name()
	for ix = 1, 8 do
		for iy = 0, 3 do
			if iy==0 then
				default_formspec = default_formspec.."image_button["..(ix-0.19)..","..vertical_offset..";0.3,0.4;saturn_info_button_icon.png;item_info_player+"..name.."+main+"..(ix+8*iy)..";]"
			else
				default_formspec = default_formspec.."image_button["..(ix-0.19)..","..(iy+vertical_offset+0.25)..";0.3,0.4;saturn_info_button_icon.png;item_info_player+"..name.."+main+"..(ix+8*iy)..";]"
			end
		end
	end
    end
    return default_formspec
end

saturn.get_player_inventory_formspec = function(player, tab)
	local name = player:get_player_name()
	local default_formspec = "tabheader[0,0;tabs;Status,Hull,Map;"..tab..";true;false]"
	local hull = player:get_inventory():get_stack("ship_hull", 1)
	local hull_stats = saturn.get_item_stats(hull:get_name())
	if hull_stats then
		if tab == 1 then
			local hull_max_wear = hull_stats['max_wear'] or saturn.MAX_ITEM_WEAR
			local hull_wear = hull:get_wear()
			local display_status = hull_wear * hull_max_wear / saturn.MAX_ITEM_WEAR
			local max_volume = hull_stats['free_space']
			local ship = player:get_attach()
			local ship_lua = ship:get_luaentity()
			local velocity = vector.length(ship:getvelocity())
			local traction = ship_lua['traction']
			local traction_bonus = ship_lua.total_modificators['traction']
			if traction_bonus then
				traction = traction + traction_bonus
			end
			local forcefield_protection = ship_lua['forcefield_protection']
			local forcefield_protection_bonus = ship_lua.total_modificators['forcefield_protection']
			if forcefield_protection_bonus then
				forcefield_protection = forcefield_protection + forcefield_protection_bonus
			end
			return "size[8,8.6]"..
				default_formspec..
				"label[0,0;"..minetest.formspec_escape("Hull damage: ")..string.format ('%4.0f',display_status).."/"..hull_max_wear.."]"..
				"label[0,0.25;"..minetest.formspec_escape("Money: ")..string.format ('%4.0f',saturn.players_info[name]['money']).." Cr.]"..
				"label[0,0.5;"..minetest.formspec_escape("Occupied hold volume: ")..string.format ('%4.2f',ship_lua['volume']).."/"..max_volume.." m3]"..
				"label[0,0.75;"..minetest.formspec_escape("Total ship weight: ")..string.format ('%4.0f',ship_lua['weight']).." kg]"..
				"label[0,1.0;"..minetest.formspec_escape("Traction: ")..string.format ('%4.1f',traction/1000).." kN]"..
				"label[0,1.25;"..minetest.formspec_escape("Forcefield damage absorption: ")..string.format ('%4.1f',forcefield_protection).." %]"..
				"label[0,1.5;"..minetest.formspec_escape("Max acceleration: ")..string.format ('%4.1f',traction/ship_lua['weight']).." m/s2]"..
				"label[0,1.75;"..minetest.formspec_escape("Free power: ")..string.format ('%4.0f',ship_lua['free_power']).." MW]"..
				"button[0,2;4,1;abandon_ship;Abandon ship]"..
				saturn.get_main_inventory_formspec(player,4.25)
		elseif tab == 2 then
			return "size[8,8.6]"..default_formspec..saturn.get_ship_equipment_formspec(player)..
				saturn.get_main_inventory_formspec(player,4.25)
		elseif tab == 3 then
			local ship = player:get_attach()
			local ship_lua = ship:get_luaentity()
			local map_scale = ship_lua['map_scale'] or 1
			local map_projection = ship_lua['map_projection'] or 1
			return "size[9,8.6]"..default_formspec..get_map_formspec(map_scale, map_projection, player)
		end
	end
	return default_formspec
end

saturn.get_item_info_formspec = function(item_stack)
	local item_name = item_stack:get_name()
	local formspec = "size[8,8.6]"..
		"item_image[0,0;1,1;"..item_name.."]"..
		"label[1,0.0;"..item_name.."]"..
		"image_button[6.5,0.1;1.5,0.4;saturn_back_button_icon.png;ii_return;Back  ;false;false;saturn_back_button_icon.png]"
	local row_step = 0.3
	local row = 1
	formspec = formspec.."label[0,"..row..";Basic properties:]"
	row = row + 0.1
	if minetest.registered_items[item_name] then
		for key,value in pairs(minetest.registered_items[item_name]) do
			if not saturn.localisation_and_units[key] then
				error("Missing localisation for "..key)
				return
			end
			if not saturn.localisation_and_units[key].hidden then
				row = row + row_step
				local localisation = saturn.localisation_and_units[key]
				local string_value
				if localisation.format_normal == "date" then
					string_value = saturn.date_to_string(value) .." ".. localisation.units
				elseif type(value) == "number" then
					string_value = string.format(localisation.format_normal,value) .." ".. localisation.units
				else
					string_value = tostring(value)
				end
				formspec = formspec.."label[0,"..row..";"..localisation.name..": "..string_value.."]"
			end
		end
	end
	local metadata = minetest.deserialize(item_stack:get_metadata())
	if metadata then
		row = row + row_step*2
		formspec = formspec.."label[0,"..row..";Special properties:]"
		row = row + 0.1
		for key,value in pairs(metadata) do
			if not saturn.localisation_and_units[key] then
				error("Missing localisation for "..key)
				return
			end
			if not saturn.localisation_and_units[key].hidden then
				row = row + row_step
				local localisation = saturn.localisation_and_units[key]
				local string_value
				if localisation.format_special == "date" then
					string_value = saturn.date_to_string(value) .." ".. localisation.units
				elseif type(value) == "number" then
					string_value = string.format(localisation.format_special,value) .." ".. localisation.units
				else
					string_value = tostring(value)
				end
				formspec = formspec.."label[0,"..row..";"..localisation.name..": "..string_value.."]"
			end
		end
	end
	return formspec
end

saturn.save_players = function()
    local file = io.open(minetest.get_worldpath().."/saturn_players", "w")
    file:write(minetest.serialize(saturn.players_info))
    file:close()
end

saturn.load_players = function()
    local file = io.open(minetest.get_worldpath().."/saturn_players", "r")
    if file ~= nil then
	local text = file:read("*a")
        file:close()
	if text and text ~= "" then
	    saturn.players_info = minetest.deserialize(text)
	end
    end
end

saturn.throw_item = function(stack, ship, pos)
	local velocity = vector.new(math.random()-0.5,math.random()-0.5,math.random()-0.5)
	if ship then
		local ship_velocity = ship:getvelocity()
		if ship_velocity then
			local ship_velocity_module = vector.length(ship_velocity)
			if ship_velocity_module ~= 0 then
				velocity = vector.add(vector.add(ship_velocity, vector.normalize(ship_velocity)),velocity)
			end
		end
	end
	local start_pos = {x=pos.x+velocity.x, y=pos.y+velocity.y, z=pos.z+velocity.z}
	local obj = minetest:add_entity(start_pos, "saturn:throwable_item_entity")
	obj:setvelocity(velocity)
	obj:get_luaentity():set_item(stack:to_string())
end

saturn.get_item_stats = function(item_name)
	return minetest.registered_items[item_name]
end

saturn.get_item_price = function(item_name)
	local stats = minetest.registered_items[item_name]
	if stats ~= nil then
		local value = stats['price']
		if value ~= nil then
			return value
		end
	end
	return 0
end

saturn.generate_random_enemy_item = function()
	local item_name = saturn.enemy_items[math.random(#saturn.enemy_items)]
	local item_stack = ItemStack(item_name)
	local item_stats = minetest.registered_items[item_name]
	local possible_modifications = item_stats.possible_modifications
	if possible_modifications then 
		local modifications = {}
		for key,value in pairs(possible_modifications) do
			local median = (value[1] + value[2])/2
			local scale = value[2] - median
			local modification_power = saturn.get_pseudogaussian_random(median, scale)
			if math.abs(modification_power) > scale then
				if modification_power < 0 and item_stats[key] then
					modifications[key] = math.max(scale*0.1 - item_stats[key], modification_power)
				else
					modifications[key] = modification_power
				end
				
			end
		end
		item_stack:set_metadata(minetest.serialize(modifications))
	end
	return item_stack
end

saturn.generate_random_leveled_enemy_item = function(loot_level, loot_modifications_scale)
	local item_name = saturn.enemy_items_by_level[loot_level][math.random(#saturn.enemy_items_by_level[loot_level])]
	local item_stack = ItemStack(item_name)
	local item_stats = minetest.registered_items[item_name]
	local possible_modifications = item_stats.possible_modifications
	if possible_modifications then 
		local modifications = {}
		for key,value in pairs(possible_modifications) do
			local median = (value[1] + value[2])/2
			local scale = (value[2] - median) * loot_modifications_scale
			local modification_power = saturn.get_pseudogaussian_random(median, scale)
			if math.abs(modification_power) > scale then
				if modification_power < 0 and item_stats[key] then
					modifications[key] = math.max(scale*0.1 - item_stats[key], modification_power)
				else
					modifications[key] = modification_power
				end
				
			end
		end
		item_stack:set_metadata(minetest.serialize(modifications))
	end
	return item_stack
end

local get_closest_player = function(pos)
    local last_dsq = 1e9
    local ret_player = nil
    for _,player in ipairs(minetest.get_connected_players()) do
	local ppos = player:getpos()
	local dsq = (pos.x-ppos.x)*(pos.x-ppos.x) +
		    (pos.y-ppos.y)*(pos.y-ppos.y) +
   		    (pos.z-ppos.z)*(pos.z-ppos.z)
	if dsq < last_dsq then
	    ret_player = player
	end
    end
    return ret_player
end

minetest.register_globalstep(function(dtime)
    saturn.save_timer = saturn.save_timer - 1
    if saturn.save_timer <= 0 then
	saturn.save_timer = saturn.players_save_interval
	saturn.save_players()
    end
    saturn.market_update_timer = saturn.market_update_timer - dtime
    if saturn.market_update_timer <= 0 then
	saturn.market_update_timer = saturn.market_update_interval
	for _indx=1,saturn.NUMBER_OF_SPACE_STATIONS do
	    saturn.update_space_station(_indx)
	end
    end
    local current_handled_enemy = saturn.current_handled_enemy
    if current_handled_enemy > #saturn.virtual_enemy then
	current_handled_enemy = 1
    end
    local current_handled_loaded_enemy = saturn.current_handled_loaded_enemy
    local next_handled_loaded_enemy, lee = next(saturn.loaded_enemy_entity, current_handled_loaded_enemy)
    if lee and not lee.object:getpos() then
	table.insert(saturn.virtual_enemy, lee.ve)
	saturn.loaded_enemy_entity[lee.uid] = nil
	next_handled_loaded_enemy, lee = next(saturn.loaded_enemy_entity)
    end
    saturn.current_handled_loaded_enemy = next_handled_loaded_enemy
    local ert = saturn.enemy_respawn_timer - dtime
    if ert < 0.0 then
	ert = 90
	for _indx,ess in ipairs(saturn.enemy_space_station) do
	    if not ess.is_destroyed then
		local node = minetest.get_node(ess)
	    	if node.name == "air" then
		    local entity_name = "saturn:enemy_01"
		    for elevation, name in pairs(saturn.enemy_spawn_conditions) do
			entity_name = name
			break
		    end
		    local entity = minetest.add_entity(ess, entity_name)
		    if entity then
		    	local direction_velocity = vector.new(5,0,0)
		    	entity:setvelocity(direction_velocity)
		    	entity:set_bone_position("Head", {x=0,y=1,z=0}, {x=0,y=0,z=90})
		    end
	    	else
		    table.insert(saturn.virtual_enemy,{
		    	x=ess.x,
		    	y=ess.y,
		    	z=ess.z,
		    	vel_x=math.random(10)-5,
		    	vel_y=math.random(10)-5,
		    	vel_z=math.random(10)-5,})
	    	end
	    end
	end
    end
    saturn.enemy_respawn_timer = ert
    if #saturn.virtual_enemy > 0 then
	for i=1,256 do
	    local ve = saturn.virtual_enemy[current_handled_enemy]	
	    if ve then
		local vel_x = ve.vel_x
		local vel_y = ve.vel_y
		local vel_z = ve.vel_z
		local pos_x = ve.x + vel_x
		local pos_y = ve.y + vel_y
		local pos_z = ve.z + vel_z
		if saturn.player_ship_ref then
			local psp = saturn.player_ship_ref:getpos()
			vel_x = math.max(math.min((psp.x - pos_x)/100,10),-10)
			vel_y = math.max(math.min((psp.y - pos_y)/100,10),-10)
			vel_z = math.max(math.min((psp.z - pos_z)/100,10),-10)
		else
			if pos_x < -30000 or
			   pos_z < -30000 or
			   pos_y < -30000 or
			   pos_x > 30000 or
			   pos_z > 30000 or
			   pos_y > 30000 then
				local ss
				if pos_y < 0 then
					ss = saturn.enemy_space_station[1]
				else
					ss = saturn.enemy_space_station[2]
				end
				vel_x = math.max(math.min((ss.x - pos_x)/100,10),-10)
				vel_y = math.max(math.min((ss.y - pos_y)/100,10),-10)
				vel_z = math.max(math.min((ss.z - pos_z)/100,10),-10)
			end
		end
		ve.x=pos_x
		ve.y=pos_y
		ve.z=pos_z
		ve.vel_x=vel_x
		ve.vel_y=vel_y
		ve.vel_z=vel_z
		local node = minetest.get_node(ve)
		if node.name == "air" then
		    table.remove(saturn.virtual_enemy, current_handled_enemy)
		    local entity_name = "saturn:enemy_01"
		    for elevation, name in pairs(saturn.enemy_spawn_conditions) do
			if math.abs(pos_y) >= elevation then
				entity_name = name
			end
		    end
	   	    local entity = minetest.add_entity(ve, ve.entity_name or entity_name)
		    if entity then
			local direction_velocity = vector.new(vel_x,vel_y,vel_z)
			local closest_player = get_closest_player(ve)
			if closest_player and closest_player:get_attach() then
				local psv = closest_player:get_attach():getvelocity()
				direction_velocity = vector.add(direction_velocity,psv)
			end
			entity:setvelocity(direction_velocity)
			local yaw = -getVectorYawAngle(direction_velocity)
			local pitch = -getVectorPitchAngle(direction_velocity)
			entity:set_bone_position("Head", {x=0,y=1,z=0}, {x=pitch*180/3.14159,y=0,z=yaw*180/3.14159})
		    end
		    for p_name, radar in pairs(saturn.radars) do
			local lua_e = radar.obj:get_luaentity()
			if lua_e.radar_object_state[ve] then --purge radar list is fastest way to get rid from loaded enemy
			    lua_e.radar_object_state = {}
			    lua_e.radar_object_list = {}
			end
		    end
		else
		    for p_name, radar in pairs(saturn.radars) do
			local radar_pos = radar.obj:getpos()
			local radar_range = radar.radius
			if radar_pos and pos_x > radar_pos.x - radar_range and
				pos_x < radar_pos.x + radar_range and
				pos_y > radar_pos.y - radar_range and
				pos_y < radar_pos.y + radar_range and
				pos_z > radar_pos.z - radar_range and
				pos_z < radar_pos.z + radar_range then
			    local lua_e = radar.obj:get_luaentity()
			    if #lua_e.radar_object_list < 8 and not lua_e.radar_object_state[ve] then
				table.insert(lua_e.radar_object_list,ve)
				lua_e.radar_object_state[ve] = true
			    end
			end
		    end
		end
		current_handled_enemy = current_handled_enemy + 1
	    else
		break
	    end
	end
	saturn.current_handled_enemy = current_handled_enemy
    end
    for _,player in ipairs(minetest.get_connected_players()) do
	local player_inv = player:get_inventory()
	local name = player:get_player_name()
	local ship_obj = player:get_attach()
	local ship_cooldown_mod = 0
	if ship_obj and ship_obj:get_luaentity() then
		ship_cooldown_mod = ship_obj:get_luaentity().total_modificators['cooldown'] or 0
	end
	for i=1,8 do
	   local cooldown = saturn.hotbar_cooldown[name][i]
	   if cooldown > 0 then
		local stack = player_inv:get_stack("main", i)
		local number = 0
		if stack:is_empty() then
			cooldown = 0
		else
			cooldown = cooldown - dtime
			number = 44 * cooldown / math.max(0.2,saturn.get_item_stat(stack, 'cooldown', 88) + ship_cooldown_mod)
		end
		player:hud_change(saturn.hud_hotbar_cooldown[name][i], "number", number)
		saturn.hotbar_cooldown[name][i] = cooldown
	   end
	end
    end
end)

minetest.register_on_shutdown(function()
	saturn.save_players()
	saturn.save_enemy_info()
	saturn.save_human_space_station()
end)
