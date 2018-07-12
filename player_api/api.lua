-- Minetest 0.4 mod: player
-- See README.txt for licensing and other information.

player_api = {}

-- Player animation blending
-- Note: This is currently broken due to a bug in Irrlicht, leave at 0
local animation_blend = 0

player_api.registered_models = { }
player_api.registered_skins = { }
-- Local for speed.
local models = player_api.registered_models
local skins = player_api.registered_skins
local registered_skin_modifiers = {}
local registered_on_skin_change = {}

function player_api.register_model(name, def)
	models[name] = def
end

function player_api.register_skin(name, def)
	def.skin_key = name
	skins[name] = def
end

function player_api.register_skin_modifier(modifier_func)
	table.insert(registered_skin_modifiers, modifier_func)
end

function player_api.register_on_skin_change(modifier_func)
	table.insert(registered_on_skin_change, modifier_func)
end

-- Player stats and animations
local player_model = {}
local player_textures = {}
local skin_textures = {}
local player_skin = {}
local player_anim = {}
local player_sneak = {}
player_api.player_attached = {}

function player_api.get_animation(player)
	local name = player:get_player_name()
	return {
		model = player_model[name],
		textures = player_textures[name],
		skin_textures = skin_textures[name],
		animation = player_anim[name],
	}
end

-- Called when a player's appearance needs to be updated
function player_api.set_model(player, model_name)
	local name = player:get_player_name()
	local model = model_name and models[model_name]
	if not model then
		model_name = player_api.default_model
		model = models[model_name]
	end

	if player_model[name] == model_name then
		return
	end
	player:set_properties({
		mesh = model_name,
		textures = player_textures[name] or model.textures,
		visual = model.visual or "mesh",
		visual_size = model.visual_size or {x = 1, y = 1},
		collisionbox = model.collisionbox or {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
		stepheight = model.stepheight or 0.6,
		eye_height = model.eye_height or 1.47,
	})
	player_api.set_animation(player, "stand")
	player_model[name] = model_name
end

-- Apply textures to player model
function player_api.update_textures(player)
	local name = player:get_player_name()
	local model = models[player_model[name]]

	local textures = skin_textures[name] or (model and model.textures)

	local new_textures
	if type(textures) == 'string' then
		new_textures = { textures }
	else
		new_textures = table.copy(textures)
	end

	for _, modifier_func in ipairs(registered_skin_modifiers) do
		new_textures = modifier_func(new_textures, player, player_model[name], player_skin[name]) or new_textures
	end

	if model.skin_modifier then
		new_textures = model:skin_modifier(new_textures, player, player_model[name], player_skin[name]) or new_textures
	end
print("set skin textures", dump(new_textures))
	player_textures[name] = new_textures
	player:set_properties({textures = new_textures })
end

-- Called when a player's skin is changed
function player_api.set_skin(player, skin_name, is_default)
	local name = player:get_player_name()
	local skin = skins[skin_name]
	if not skin then
		skin_name = player_api.default_skin
		skin = skins[skin_name]
	end

	if player_skin[name] == skin_name then
		return
	end

	-- Handle skin model
	player_api.set_model(player, skin.model_name)

	-- Handle skin textures
	player_skin[name] = skin_name
	skin_textures[name] = skin.textures

	player_api.update_textures(player)

	if not is_default then
		player:set_attribute("player_api:skin", skin_name)
	end

	for _, modifier_func in ipairs(registered_on_skin_change) do
		modifier_func(player, player_model[name], skin_name)
	end
end

-- Get the skin on join. Can be used as hook
function player_api.get_skin(player)
	local assigned_skin = player:get_attribute("player_api:skin")
	if assigned_skin then
		return assigned_skin, false
	else
		return player_api.default_skin, true
	end
end

function player_api.set_animation(player, anim_name, speed)
	local name = player:get_player_name()
	if player_anim[name] == anim_name then
		return
	end
	local model = player_model[name] and models[player_model[name]]
	if not (model and model.animations and model.animations[anim_name]) then
		return
	end
	local anim = model.animations[anim_name]
	player_anim[name] = anim_name
	player:set_animation(anim, speed or model.animation_speed, animation_blend)
end

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	player_model[name] = nil
	player_anim[name] = nil
	player_textures[name] = nil
	skin_textures[name] = nil
	player_skin[name] = nil
end)

-- Localize for better performance.
local player_set_animation = player_api.set_animation
local player_attached = player_api.player_attached

-- Check each player and apply animations
minetest.register_globalstep(function(dtime)
	for _, player in pairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local model_name = player_model[name]
		local model = model_name and models[model_name]
		if model and not player_attached[name] then
			local controls = player:get_player_control()
			local walking = false
			local animation_speed_mod = model.animation_speed or 30

			-- Determine if the player is walking
			if controls.up or controls.down or controls.left or controls.right then
				walking = true
			end

			-- Determine if the player is sneaking, and reduce animation speed if so
			if controls.sneak then
				animation_speed_mod = animation_speed_mod / 2
			end

			-- Apply animations based on what the player is doing
			if player:get_hp() == 0 then
				player_set_animation(player, "lay")
			elseif walking then
				if player_sneak[name] ~= controls.sneak then
					player_anim[name] = nil
					player_sneak[name] = controls.sneak
				end
				if controls.LMB then
					player_set_animation(player, "walk_mine", animation_speed_mod)
				else
					player_set_animation(player, "walk", animation_speed_mod)
				end
			elseif controls.LMB then
				player_set_animation(player, "mine")
			else
				player_set_animation(player, "stand", animation_speed_mod)
			end
		end
	end
end)
