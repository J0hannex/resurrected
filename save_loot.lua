destroy_objects = {}
destroy_objects["mp_ammo_9x18_fmj"] 		= true
destroy_objects["ammo_gravi"] 				= true
destroy_objects["admin_m79"] 				= true
destroy_objects["wpn_rpg7"] 				= true
destroy_objects["grenade_gd-05"]			= true

ignore_save_loot = {}
ignore_save_loot["bolt"]		 	 		= true
ignore_save_loot["mp_wpn_knife"] 	 		= true
ignore_save_loot["device_pda"]		 		= true
ignore_save_loot["mp_device_torch"]  		= true
ignore_save_loot["mp_wpn_binoc"] 	 		= true
ignore_save_loot["wpn_addon_scope_none"] 	= true
ignore_save_loot["detector_simple"] 		= true
ignore_save_loot["torch_hider"] 			= true
local player_by_name = {}
local player_data = {}

local spawn_loot_queue_process_size = 10

local fact_boxes = {}
local agit_time = time_global() + 1000000
local root = getFS():update_path("$app_data_root$", "") local accounts = root.."accounts\\" local boxes = root.."boxes\\"
local packet = net_packet ()
game_object.accept = function (self, id) u_EventGen (packet, 1, self:id()) packet:w_u16 (id) u_EventSend (packet) end
game_object.reject = function (self, id) u_EventGen (packet, 3, self:id()) packet:w_u16 (id) u_EventSend (packet) end
game_object.destroy_object = function (self) u_EventGen (packet, 8, self:id()) u_EventSend (packet) end
game_object.set_hide_state = function (self, state, set) u_EventGen (packet, 46, self:id()) packet:w_u16 (state) packet:w_u8(set and 1 or 0) u_EventSend (packet) end
game_object.set_actor_position = function (self, pos) u_EventGen (packet, 29, self:id()) packet:w_vec3(pos) packet:w_vec3(self:direction()) SendBroadcast (packet) end
game_object.allow_sprint = function (self, allow_sprint) u_EventGen(packet, 47, self:id()) packet:w_u8(allow_sprint and -1 or 1) SendBroadcast (packet) end

function send_tip_server(text)
	for _, obj in pairs(player_by_name) do
		if obj:alive() then
			u_EventGen(packet, 107, obj:id())
			packet:w_stringZ("st_tip")
			packet:w_stringZ(text)
			packet:w_stringZ("ui_inGame2_Vibros")
			u_EventSend(packet)
		end
	end
end

function send_to_user(text, user)
	if user then
		u_EventGen(packet, 107, user)
		packet:w_stringZ("Server")
		packet:w_stringZ(text)
		packet:w_stringZ("ui_inGame2_PD_Otmecheniy_zonoy")
		u_EventSend(packet)
	end
end

function log_test(text) if xrLua then xrLua.log("$ " .. text) return end get_console():execute("cfg_load ~" .. text) end
function logf_test(fmt, ...) log_test(string.format(fmt, ...)) end
--[[
function get_item_table(item)
    local t = {}
    t.section = item:section()
    t.condition = item:condition()
    if item:clsid() == clsid.wpn_ammo_s then
        t.condition = nil
        if item:cost() / system_ini():r_u32(t.section, "cost") < 0.5 then
            return nil
        else
            return t
        end
    elseif t.section:find("wpn_") then
        t.addon_flags = (item:weapon_is_scope() and 1 or 0) + (item:weapon_is_silencer() and 4 or 0) + (item:weapon_is_grenadelauncher() and 2 or 0)
        return t
    elseif t.condition then
        if t.condition == 1.0 then t.condition = nil end
        return t
    else
        log_test("WTF? " .. item:section())
        item:destroy_object()
        return nil
    end
end
]]
local surge_status = nil
local safe_zone = nil
local surg_zone = nil
local surg_zone2 = nil

function check_player(obj)
    if not obj then return end
    if player_data[obj:name()].awaiting < time_global() then
        local binder = obj:binded_object()
        local safe_nickname = obj:name()
        local data = io.open(root .. "team_players.lua")
        if data then
            local tbl = loadstring(data:read("*a"))()
            data:close()
            if tbl then
                if tbl[obj:name()] then
                    if type(tbl[safe_nickname]) == "table" and tbl[safe_nickname].fact == binder.community then
                        binder.leader = true
                        obj:give_info_portion("make_leader")
                    elseif not binder.ignoring and tbl[safe_nickname] ~= binder.community then
                        get_console():execute("chat %c[0,183,0,20][FACTION-SYSTEM] " .. obj:name() .. " Не состоит в группировке " .. binder.community .. " - Обратитесь к лидеру...")
                        xrLua.KickPlayer(obj:id())
                        return
                    end
                end
            else
                log_test("Ошибка, список игроков пуст или поврежден !!!")
                return
            end
        end
        load_player_loot(obj)
        obj:set_fastcall(nil)
    end
end

function spawn_in_inv(sect, parent)
	local so_obj = alife():create(sect, db.actor:position(), db.actor:level_vertex_id(), db.actor:game_vertex_id())
	level.client_spawn_manager():add(so_obj.id, 0, spawn_in_inv_callback, {parent:id(), sect})
	return so_obj
end
--[[
function spawn_ammo(sect, parent, cnt)
	local so_obj = alife():create_ammo(sect, db.actor:position(), db.actor:level_vertex_id(), db.actor:game_vertex_id(), -1, cnt)
	level.client_spawn_manager():add(so_obj.id, 0, spawn_in_inv_callback, {parent:id(), sect})
end
]]
function spawn_in_inv_callback(data, id, obj)
	local new_parent = level.object_by_id(data[1])
	if new_parent then
		--if obj:parent() then obj:parent():reject(id) end
		new_parent:accept(id)
	end
end

function spawn_callback(obj, id, item) local par = obj:parent() obj:destroy_object() if par then spawn_in_inv_callback({par:id(), item:section()}, id, item) end end

function process_spawn_loot(spawn_loot_queue)
    local process_spawn = function()
        local process_size = math.min(spawn_loot_queue_process_size, #spawn_loot_queue)
        for j = 1, process_size do
            local index = 1
            local t = spawn_loot_queue[index].loot_table
            local obj = level.object_by_id(spawn_loot_queue[index].parent_id)
            if obj and t and t.section then     
                local sobj = spawn_in_inv(t.section, obj)
                if sobj then
                    if t.addon_flags then
                        local tpk = get_weapon_data(sobj)
                        tpk.condition = t.condition
                        tpk.ammo_elapsed = 0
                        tpk.addon_flags = t.addon_flags
                        set_weapon_data(tpk, sobj)
                    elseif t.condition then
                        local tpk = get_item_data(sobj)
                        tpk.condition = t.condition
                        set_item_data(sobj)
                    end
                end
            end
            table.remove(spawn_loot_queue, index)
        end
        return #spawn_loot_queue == 0
    end
    level.add_call(process_spawn, function() end)
end

local saved_wpn = {}
function load_player_loot(obj)
	local binder = obj:binded_object()
	if binder.community == "zombied" then obj:allow_sprint(false) end
	spawn_in_inv("mp_device_torch", obj) spawn_in_inv("device_pda", obj) spawn_in_inv("wpn_addon_scope_none", obj) spawn_in_inv("torch_hider", obj)
	if saved_wpn[obj:name()] then spawn_in_inv(saved_wpn[obj:name()], obj) saved_wpn[obj:name()] = nil end
	local tbl = {}
	local data = io.open(accounts .. obj:name() ..  ".lua", "r")
	if data then tbl = loadstring(data:read("*a"))() data:close() end	

	if tbl["deaths"] then player_data[obj:name()]["deaths"] = tbl.deaths tbl.deaths = nil
	else player_data[obj:name()]["deaths"] = 0 end
	if tbl["kills"] then player_data[obj:name()]["kills"] = tbl.kills tbl.kills = nil
	else player_data[obj:name()]["kills"] = 0 end
	if tbl["position"] then obj:set_actor_position(vector():set(tbl.position.x, tbl.position.y, tbl.position.z)) tbl.position = nil
	else
		if binder.community == "greh" then
			if level.name() == "jupiter_stnet_v2" then
				local jupiter_spectrum_rpoint = math.random(1, 2)
				if jupiter_spectrum_rpoint == 1 then obj:set_actor_position(vector():set(356.0, 34.0, 336.0))
				elseif jupiter_spectrum_rpoint == 2 then obj:set_actor_position(vector():set(380, 4.0, 336.0)) end
			--[[elseif level.name() == "zaton" then
				local zaton_spectrum_rpoint = math.random(1, 5)
				if zaton_spectrum_rpoint == 1 then obj:set_actor_position(vector():set(-416.90, 24.20, -327.99)) end
				if zaton_spectrum_rpoint == 2 then obj:set_actor_position(vector():set(-337.02, 41.62, -398.52)) end
				if zaton_spectrum_rpoint == 3 then obj:set_actor_position(vector():set(-318.99, 41.60, -307.21)) end
				if zaton_spectrum_rpoint == 4 then obj:set_actor_position(vector():set(-414.37, 41.90, -306.83)) end
				if zaton_spectrum_rpoint == 5 then obj:set_actor_position(vector():set(-371.02, 41.55, -330.85)) end ]]
			end
		elseif binder.community == "inquisition" and level.name() == "jupiter_stnet_v2" then 
			if math.random(1, 2) == 1 then obj:set_actor_position(vector():set(-180.0, 12, -302.0))
			else obj:set_actor_position(vector():set(-180.0, 1.5, -270.0)) end
		elseif binder.community == "lastday" then
			obj:set_actor_position(vector():set(70, 5, 330.0))
		end
	end
	if tbl["health"] then
		local v = tbl.health
		if v < 0.3 then v = 0.3 end
		local timer = time_global()
		level.add_call(function() return timer < time_global() end, function() obj.health = v - obj.health end)
		tbl.health = nil
	end
	if tbl["money"] then obj:give_info_portion("money_add=" .. tbl.money) player_data[obj:name()]["money"] = tbl.money tbl.money = nil
	else obj:give_info_portion("money_add=" .. 10000) player_data[obj:name()]["money"] = 10000 end
	if tbl["gauss"] then binder.gauss = true tbl.gauss = nil end
	if #tbl ~= 0 then
		local spawn_loot_queue = {}
		for _, v in pairs(tbl) do
			local t = {}
			t.loot_table = v
			t.parent_id = obj:id()
			table.insert(spawn_loot_queue, t)
		end
		process_spawn_loot(spawn_loot_queue)
	end
end

function erase_loot(player)
	local loot_table = {}
	if player_data[player:name()]["money"] then loot_table["money"] = player_data[player:name()]["money"] end
	if player_data[player:name()]["deaths"] then loot_table["deaths"] = player_data[player:name()]["deaths"] end
	if player_data[player:name()]["kills"] then loot_table["kills"] = player_data[player:name()]["kills"] end
	if player:binded_object().gauss then loot_table["gauss"] = true end
	local script = print_tableg(loot_table, "player")
	script = script .. "return player \n"
	local file = io.open(accounts .. player:name() ..  ".lua", "w")
	if file then file:write(script) file:close() end
end
function save_player_loot(player)
	if not player:alive() then return end
	local loot_table = {}
	local function add_items (parent, item)
		local owner = item:parent()
		if not ignore_save_loot[item:section()] then		
			local section = item:section()
			local tbl = { ["section"] = section }
			if section:sub(0, 4) == "wpn_" then
				tbl.condition = item:condition()
				tbl.addon_flags = (item:weapon_is_scope() and 1 or 0) + (item:weapon_is_silencer() and 4 or 0) + (item:weapon_is_grenadelauncher() and 2 or 0)
			elseif section:find("outfit") then
				tbl.condition = item:condition()
			end
			table.insert(loot_table, tbl)
		end
	end
	player:iterate_inventory(add_items, player)
	local position = player:position()
	loot_table["position"] = {x=position.x, y=position.y + 0.2, z=position.z}
	loot_table["health"] = player.health
	-- loot_table["health"] = -0.7 - player.health
	if player_data[player:name()]["money"] then loot_table["money"] = player_data[player:name()]["money"] end
	if player_data[player:name()]["deaths"] then loot_table["deaths"] = player_data[player:name()]["deaths"] end
	if player_data[player:name()]["kills"] then loot_table["kills"] = player_data[player:name()]["kills"] end
	if player:binded_object().gauss then loot_table["gauss"] = true end
	local script = print_tableg(loot_table, "player")
	script = script .. "return player \n"
	local file = io.open(accounts .. player:name() ..  ".lua", "w")
	if file then file:write(script) file:close() end
end

function printfg(fmt,...) return string.format(fmt, ...) .. "\n" end
function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end
function print_tableg(table, sub)
	if not sub then sub = "" end
	if not table then table = _G sub = "_G" end
	local text = sub .. " = {}\n"
	for k,v in pairs(table) do
	if type(k) == "string" then k = [["]]..k..[["]] end
		if type(v) == "table" then text = text .. print_tableg(v, sub.."["..tostring(k).."]")
		elseif type(v) == "function" then text = text .. printfg(sub.."[%s] = function() end", tostring(k))
		elseif type(v) == "userdata" then text = text .. printfg(sub.."[%s] = userdata", tostring(k))
		elseif type(v) == "boolean" then
			if v == true then
					if(type(k)~="userdata") then text = text .. printfg(sub.."[%s] = true", tostring(k))
					else text = text .. printfg(sub.."userdata:true") end
			else
					if(type(k)~="userdata") then text = text .. printfg(sub.."[%s] = false", tostring(k))
					else text = text .. printfg(sub.."userdata:false") end
			end
		else
			if v ~= nil then
				if type(v) == "string" then text = text .. printfg(sub.."[%s] = [[%s]]", tostring(k),v)
				else text = text .. printfg(sub..[[[%s] = %s]], tostring(k),v) end
			else text = text .. printfg(sub..[[[%s] = nil]], tostring(k)) end
		end
	end
	return text
end

function death_callback(obj, npc, who)
	player_data[npc:name()]["deaths"] = player_data[npc:name()]["deaths"] + 1
	send_to_user("Смерти: ".. player_data[npc:name()]["deaths"], npc:id())
	local binder = npc:binded_object()
	if who and who:id() ~= npc:id() and player_by_name[who:name()] then
		player_data[who:name()]["kills"] = player_data[who:name()]["kills"] + 1
		local killer = who:binded_object().community
		local killed = binder.community
		if killer ~= "player" and killed ~= "player" and killer ~= killed then
			send_to_user("Получена награда.\nУбийства: ".. player_data[who:name()]["kills"], who:id())
			alife():create("money_5000rub", who:position(), who:level_vertex_id(), who:game_vertex_id(), who:id())
		end
		-- binder and binder.community ~= "zombied" and who:binded_object() and who:binded_object().community == "player" then
			-- xrLua.KickPlayer(who:id()) -- enable Anti-DM
		-- end
	end	
	if binder then binder:death_callback(obj, who) end
end

function drop_callback(npc, obj)
	if not npc:alive() then obj:destroy_object() return end
	local binder = npc:binded_object()
	if binder then
		binder:on_item_drop(obj)
	end
end

function take_callback(npc, obj)
	if not npc:alive() then return end
	if destroy_objects[obj:section()] or obj:section():find("ammo") then obj:destroy_object() return
	elseif ignore_save_loot[obj:section()] then return end
	
	if obj:section() == "admin_rp_psyhelm" then obj:give_info_portion("psy_protected") 
	elseif obj:section() == "wpn_gauss" and npc:binded_object().community ~= "monolith" and not npc:binded_object().gauss then
		obj:destroy_object()
		alife():create("pri_a17_gauss_rifle", npc:position(), npc:level_vertex_id(), npc:game_vertex_id(), npc:id())
	elseif obj:section() == "pri_a17_gauss_rifle" and (npc:binded_object().community == "monolith" or npc:binded_object().gauss) then
		obj:destroy_object()
		alife():create("wpn_gauss", npc:position(), npc:level_vertex_id(), npc:game_vertex_id(), npc:id())
	end
end

db.add_actor = function(obj)
	db.actor = obj
	db.actor_proxy:net_spawn( obj )
	db.add_obj(obj)
	if alife() then
		obj:set_fastcall(server_update, nil)
		obj:set_callback(callback.inventory_info, single_actor_info, obj)
	end
	safe_zone = db.zone_by_name["sr_safe_zone"]
	surg_zone = db.zone_by_name["sr_surge"]
	surg_zone2 = db.zone_by_name["sr_surge_forest"]
	
	logf_test("ZONES: Safe %s, Surge %s, Surge(forest) %s, Psy %s, Pois %s, Psy(sin) %s", 
		safe_zone and "+" or "-", surg_zone and "+" or "-", surg_zone2 and "+" or "-", 
		db.zone_by_name["monolith_psy_zone"] and "+" or "-", db.zone_by_name["sr_poison_lab"] and "+" or "-", db.zone_by_name["greh_psy_zone"] and "+" or "-")
	local timer = time_global() + 10000
	for sec, stor in pairs(bind_physic_object.fact_boxes) do
		level.add_call( function() return timer < time_global() end, function() 
			local stor = bind_physic_object.fact_boxes[sec]
			stor.obj = level.object_by_id(stor.id)
			if stor.obj and stor.obj:section() == sec then
				local data = io.open(boxes .. sec ..  ".lua")
				if data then
					local tbl = loadstring(data:read("*a"))()
					data:close()
					if tbl then for _, v in pairs(tbl) do alife():create(v, stor.obj:position(), stor.obj:level_vertex_id(), stor.obj:game_vertex_id(), stor.id) end end
				end
			end	
		end)
	end
end

local start_surge_time = nil
local end_surge_time = nil
local fact_updater = time_global() + 25000
function server_update()
	if level.is_wfx_playing() then --get_wfx_time()
		if not start_surge_time then
			start_surge_time = time_global()
			end_surge_time = time_global() + 190000
			send_tip_server("Выброс начнется через 1 минуту!")
		end
		if end_surge_time < time_global() then if surge_status then surge_status = nil end
		elseif start_surge_time + 60000 < time_global() and not surge_status then surge_status = 1
		elseif start_surge_time + 130000 < time_global() and surge_status == 1 then surge_status = 2 end
		for _, obj in pairs(player_by_name) do
			if obj and obj:alive() then
				local binder = obj:binded_object()
				if surge_status and not surg_zone:inside(obj:position()) and not surg_zone2:inside(obj:position()) and not safe_zone:inside(obj:position()) and not binder.no_surge then
					local h = hit()
					h.draftsman = obj
					h.type = surge_status == 1 and hit.radiation or hit.morale
					h.direction = vector():set(0, 1, 0)
					h.power = surge_status == 1 and 0.01 or 0.2
					h.impulse = 5
					obj:hit(h)
				end
			end
		end
	elseif not level.is_wfx_playing() and start_surge_time then
		start_surge_time = nil
		end_surge_time = nil
		send_tip_server("Выброс закончился!")
	end

	--[[ if agit_time < time_global() then get_console():execute("clear_memory")
		agit_time = time_global() + 1000000  --~16min
		local agait_table = {}
		for line in io.lines(root.."agait_manager.ltx") do if line then table.insert(agait_table, line) end end
		if #agait_table > 0 then get_console():execute("chat " .. agait_table[math.random(1, #agait_table)]) end
	end ]]

	if fact_updater < time_global() then
		for sec, stor in pairs(bind_physic_object.fact_boxes) do
			if stor.updater and stor.updater < time_global() then
				local loot_table = {}
				local counter = 1
				stor.obj:iterate_inventory_box( function(dummy, item)
					if counter < 36 then
						if not ignore_save_loot[item:section()] and item:clsid() ~= clsid.wpn_ammo_s then
							table.insert(loot_table, item:section())
							counter = counter + 1
						end
					end
				end )
				local script = print_tableg(loot_table, "box")
				script = script .. "return box \n"
				local file = io.open(boxes .. sec ..  ".lua", "w")
				if file then file:write(script) file:close() end
				stor.touched = false
			end
		end
		fact_updater = time_global() + 20000
	end
	return false
end

db.add_obj = function ( obj )
	if obj:section() == "mp_actor" and alife() then
		player_by_name[obj:name()] = obj
		player_data[obj:name()] = { ["awaiting"] = time_global() + 200 }
		obj:set_callback(callback.inventory_info, info_callback, obj)
		obj:set_callback(callback.on_item_take, take_callback, obj)
		obj:set_callback(callback.on_item_drop, drop_callback, obj)
		obj:set_callback(callback.death, death_callback, obj)
		--load_player_loot(obj)
		obj:set_fastcall(check_player, obj) 
	end
	db.storage[obj:id()].object = obj
end

function single_actor_info(self, obj, info)
	log_test("[ALIFE] " .. info)
	if info:find("player_flag_dead=") then db.actor:disable_info_portion(info)
		local expl = string_expl(info, "=")
		local body = level.object_by_id(tonumber(expl[2]))
		erase_loot(body)
		saved_wpn[body:name()] = expl[3]
		--[[
		if body:get_current_outfit() then
			local s_obj = alife():create(body:get_current_outfit():section(), body:position(), db.actor:level_vertex_id(), db.actor:game_vertex_id())		
			local tpk = get_item_data(s_obj)
			if tpk then tpk.condition = tpk.condition * 0.3 set_item_data(tpk, s_obj) end
		end	]]
	elseif info:find("MG=") then db.actor:disable_info_portion(info) 
	elseif info:find("heli_dead=") then db.actor:disable_info_portion(info) heli_combat.last_hiter = nil
		local victim = string_expl(info, "=")[2]
		if victim then
			get_console():execute("chat Вертолет сбит. Наибольший урон нанес - "  .. victim)
			spawn_in_inv("lootbox", player_by_name[victim])
		end
	elseif info:find("give_money=") then db.actor:disable_info_portion(info)
		local target = string_expl(info, "=")[2]
		local dengi = tonumber(string_expl(info, "=")[3])
		dengi = math.floor(dengi / 2)
		player_by_name[target]:give_info_portion("money_add=" .. dengi) player_data[target]["money"] = player_data[target]["money"] + dengi
	end
end

function info_callback (self, obj, id)
	local binder = obj:binded_object()
	if not binder then xrLua.KickPlayer(obj:id()) return end
	if id == "set_water" or id:find("add_player_to_my_list") then obj:disable_info_portion(id) return
	elseif id:sub(1, 5) == "trade" then xrLua.log("= " .. obj:name() .. " " .. id) obj:disable_info_portion(id) return
	elseif id == "save_loot" then obj:disable_info_portion(id) save_player_loot(obj) return
	elseif id:find("hit=") then obj:disable_info_portion(id) obj.health = -tonumber(string_expl(id, "=")[2])
	
	elseif id:find("list_command") and binder.leader then obj:disable_info_portion(id)
		log_test("[FACT] " .. obj:name() .. " " .. id)
		local cmd = id:sub(1, 3)
		if cmd == "upd" then
			local data = io.open(root.."team_players.lua", "r")
			if data then
				local tbl = loadstring(data:read("*a"))()
				if tbl then
					for player, info in pairs(tbl) do					
						if type(info) == "string" and info == binder.community then obj:give_info_portion("add_player_to_my_list=" .. player) end
					end
				end
				data:close()
			end
		elseif cmd == "add" then
			local name = tostring(string_expl(id, "=")[3]):gsub("'", ''):gsub('"', ''):gsub('?', '')
			local data = io.open(root.."team_players.lua")
			local tbl = {}
			if data then tbl = loadstring(data:read("*a"))() data:close() end
			if tbl then tbl[name] = tostring(string_expl(id, "=")[2]):gsub("'", '?'):gsub('"', '?') end
			local text = print_tableg(tbl, "tbl")
			text = text .. "return tbl \n"
			local data = io.open(root.."team_players.lua", "w")
			if data then data:write(text) data:close() end
		elseif cmd == "rem" then
			local name = tostring(string_expl(id, "=")[3]):gsub("'", ''):gsub('"', ''):gsub('?', '')
			local data = io.open(root.."team_players.lua")
			if data then
				local tbl = loadstring(data:read("*a"))()
				if tbl then tbl[name] = nil end
				data:close()
				local text = print_tableg(tbl, "tbl")
				text = text .. "return tbl \n"
				data = io.open(root.."team_players.lua", "w")
				if data then data:write(text) data:close() end
			end
		end
		return
	end
	log_test("[INFO] " .. obj:name() .. " " .. id)
	local id_expl = string_expl(id, "=")
	if id:find("delta_money=") and player_data[obj:name()] then obj:disable_info_portion(id)	
		player_data[obj:name()]["money"] = tonumber(id_expl[3])
		if tonumber(id_expl[2]) > 150000 then
			get_console():execute("chat %c[255,190,20,20][ANTI-CHEAT] " .. obj:name() .. " - Большая денежная транзакция. Читер? <" .. tonumber(id_expl[2]) .. "> Всего: " .. tonumber(id_expl[3]))
		end
	elseif id:find("repair_me=") then obj:disable_info_portion(id)		
		local tpk
		if id_expl[2]:find("wpn_") then tpk = get_weapon_data(alife():object(tonumber(id_expl[3])))
		else tpk = get_item_data(alife():object(tonumber(id_expl[3]))) end
		level.object_by_id(tonumber(id_expl[3])):destroy_object()
		local s_obj = spawn_in_inv(id_expl[2], obj)
		tpk.condition = 1.0
		if id_expl[2]:find("wpn_") then set_weapon_data(tpk, s_obj)
		else set_item_data(tpk, s_obj) end
	elseif id:find("net_cl") then obj:disable_info_portion(id)
	elseif id:find("FLYHACK") then obj:disable_info_portion(id) get_console():execute("chat %c[255,190,20,20][ANTI-CHEAT] " .. obj:name() .. " - Flyhack detected?")
	elseif id:find("anticheat_executed=") then obj:disable_info_portion(id)
		get_console():execute("chat %c[255,20,220,20][ANTI-CHEAT] " .. obj:name() .. " - Отключен за использование запрещенного программного обеспечения.")
		xrLua.KickPlayer(obj:id())	
	elseif id:find("under_ground") then obj:disable_info_portion(info)
		obj:set_actor_position(vector():set(-12.0, 4.0, 198.0))
	end
end

function string_lc(str)
	local _str = ""
	for i = 1, #str do
		local c = str:sub(i, i)
		local b = string.byte(c)
		if b >= 192 and b <= 223 or b >= 65 and b <= 90 then 
		    b = b + 32 
		    _str = _str .. string.char(b)
		else _str = _str .. c end
	end
	return _str
end

function string_expl(sStr, sDiv, Mode, bNoClear)
  sStr = tostring(sStr)
  if not (sStr ~= "nil" and sStr ~= '') then return {} end --> нечего разделять
  local tRet = {}
  local sPattern = '[%w%_]+' --> дефолтный патерн (разделение по 'словам')
  if type(sDiv) == "string" then --> если задан сепаратор: разделяем по нему
    if bNoClear then --> если НЕ указано 'чистить пробелы'
      sPattern = '([^'..sDiv..']+)'
    else --> иначе с чисткой пробелов
      sPattern = '%s*([^'..sDiv..']+)%s*'
    end
  end
  --* разделяем строку по патерну
  if Mode == nil then --> обычный массив
    for sValue in sStr:gmatch(sPattern) do
      table.insert(tRet, sValue)
    end
  else
    local sTypeMode = type(Mode)
    if sTypeMode == "boolean" then --> таблица '[значение] = true или false'
      for sValue in sStr:gmatch(sPattern) do
        tRet[sValue] = Mode
      end
    elseif sTypeMode == "number" then --> таблица '[idx] = число или стринг'
      for sValue in sStr:gmatch(sPattern) do
        tRet[#tRet+1] = tonumber(sValue) or sValue
      end
    end
  end
  return tRet --> возвращаем таблицу
end

function table.shift(array, amount)
  for i = 1, amount do
    local element = table.remove(array, 1)
    table.insert(array, element)
  end
end

-- stpk_utils
-- Alundaio

local stpk = net_packet()

function get_weapon_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_item_properties_packet(t,stpk)
	parse_cse_alife_item_weapon_properties_packet(t,stpk)
	return t
end

function set_weapon_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_item_properties_packet(t,stpk)
		fill_cse_alife_item_weapon_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_item_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	stpk:r_seek(2)

	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_item_properties_packet(t,stpk)
	return t
end

function set_item_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_item_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_ammo_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	stpk:r_seek(2)

	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_item_properties_packet(t,stpk)
	t.ammo_left = stpk:r_u16()
	return t
end

function set_ammo_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_item_properties_packet(t,stpk)
		stpk:w_u16(t.ammo_left)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_inv_box_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_inventory_box_properties_packet(t,stpk)
	return t
end

function set_inv_box_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_inventory_box_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_item_pda_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_item_properties_packet(t,stpk)
	t.original_owner = stpk:r_u16()
	t.specific_character = stpk:r_stringZ()
	t.info_portion = stpk:r_stringZ()
	return t
end

function set_item_pda_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_item_properties_packet(t,stpk)
		stpk:w_u16(t.original_owner)
		stpk:w_stringZ(t.specific_character)
		stpk:w_stringZ(t.info_portion)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_stalker_data(sobj)
	if not (sobj) then return end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_trader_abstract_properties_packet(t,stpk)
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_creature_abstract_properties_packet(t,stpk)
	parse_cse_alife_monster_abstract_properties_packet(t,stpk)
	parse_cse_alife_human_abstract_properties_packet(t,stpk)
	parse_cse_ph_skeleton_properties_packet(t,stpk)
	parse_se_stalker_properties_packet(t,stpk)
	return t
end

function set_stalker_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_trader_abstract_properties_packet(t,stpk)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_creature_abstract_properties_packet(t,stpk)
		fill_cse_alife_monster_abstract_properties_packet(t,stpk)
		fill_cse_alife_human_abstract_properties_packet(t,stpk)
		fill_cse_ph_skeleton_properties_packet(t,stpk)
		fill_se_stalker_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_monster_data(sobj)
	if sobj then
		stpk:w_begin(0)
		sobj:STATE_Write(stpk)
		
		stpk:r_seek(2)
		
		local t = {}
		parse_cse_alife_object_properties_packet(t,stpk)
		parse_cse_visual_properties_packet(t,stpk)
		parse_cse_alife_creature_abstract_properties_packet(t,stpk)
		parse_cse_alife_monster_abstract_properties_packet(t,stpk)
		parse_cse_ph_skeleton_properties_packet(t,stpk)
		parse_se_monster_properties_packet(t,stpk)
		return t
	end
end

function set_monster_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_creature_abstract_properties_packet(t,stpk)
		fill_cse_alife_monster_abstract_properties_packet(t,stpk)
		fill_cse_ph_skeleton_properties_packet(t,stpk)
		fill_se_monster_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_heli_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_motion_properties_packet(t,stpk)
	parse_cse_ph_skeleton_properties_packet(t,stpk)
	parse_cse_alife_helicopter_properties_packet(t,stpk)
	return t
end

function set_heli_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_motion_properties_packet(t,stpk)
		fill_cse_ph_skeleton_properties_packet(t,stpk)
		fill_cse_alife_helicopter_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function spawn_heli(section)
	local pos = db.actor:position()
	local se_obj = alife():create(section,vector():set(pos.x,pos.y,pos.z),db.actor:level_vertex_id(),db.actor:game_vertex_id())
	if (se_obj) then
		local data = get_heli_data(se_obj)
		if (data) then
			data.visual_name = [[dynamics\vehicles\ghost_train]]
			data.motion_name = [[test_ghost_train.anm]]
			data.startup_animation = "idle"
			data.skeleton_name = "idle"
			data.engine_sound = [[vehicles\ghost_train\ghost_train_01]]
			set_heli_data(data,se_obj)
		end
	end
	return se_obj
end

function get_anom_zone_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_shape_properties_packet(t,stpk)
	parse_cse_alife_space_restrictor_properties_packet(t,stpk)
	parse_cse_alife_custom_zone_properties_packet(t,stpk)
	parse_cse_alife_anomalous_zone_properties_packet(t,stpk)
	parse_se_zone_properties_packet(t,stpk)
	return t
end

function set_anom_zone_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_shape_properties_packet(t,stpk)
		fill_cse_alife_space_restrictor_properties_packet(t,stpk)
		fill_cse_alife_custom_zone_properties_packet(t,stpk)
		fill_cse_alife_anomalous_zone_properties_packet(t,stpk)
		fill_se_zone_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end
----------------------------------------------------------------------------
----------------------------------------------------------------------------
-- cse_shape_properties
function parse_cse_shape_properties_packet(ret,stpk)
	local shape_count = stpk:r_u8()
	ret.shapes = {}
	if (shape_count > 0) then
		for i = 1, shape_count do
			local shape_type = stpk:r_u8()
			ret.shapes[i] = {}
			ret.shapes[i].shtype = shape_type
			if shape_type == 0 then
				-- sphere
				ret.shapes[i].center = vector()
				stpk:r_vec3(ret.shapes[i].center)
				ret.shapes[i].radius = stpk:r_float()
			else
				-- box
				ret.shapes[i].v1 = vector()
				ret.shapes[i].v2 = vector()
				ret.shapes[i].v3 = vector()
				ret.shapes[i].offset = vector()
				stpk:r_vec3(ret.shapes[i].v1)
				stpk:r_vec3(ret.shapes[i].v2)
				stpk:r_vec3(ret.shapes[i].v3)
				stpk:r_vec3(ret.shapes[i].offset)
			end
		end
	end
	return ret
end

function fill_cse_shape_properties_packet(ret,stpk)
	local shape_count = table.getn(ret.shapes)
	stpk:w_u8(shape_count or 0)
	if (shape_count > 0) then
		for i = 1, shape_count do
			stpk:w_u8(ret.shapes[i].shtype)
			if ret.shapes[i].shtype == 0 then
				-- sphere
				stpk:w_vec3(ret.shapes[i].center)
				stpk:w_float(ret.shapes[i].radius)
			else
				-- box
				stpk:w_vec3(ret.shapes[i].v1)
				stpk:w_vec3(ret.shapes[i].v2)
				stpk:w_vec3(ret.shapes[i].v3)
				stpk:w_vec3(ret.shapes[i].offset)
			end
		end
	end
end

-- cse_visual_properties
function parse_cse_visual_properties_packet(ret,stpk)
	ret.visual_name = stpk:r_stringZ()
	ret.visual_flags = stpk:r_u8()
	return ret
end

function fill_cse_visual_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.visual_name)
	stpk:w_u8(ret.visual_flags)
end

-- cse_motion_properties
function parse_cse_motion_properties_packet(ret,stpk)
	ret.motion_name = stpk:r_stringZ()
	return ret
end

function fill_cse_motion_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.motion_name)
end

-- cse_ph_skeleton_properties
function parse_cse_ph_skeleton_properties_packet(ret,stpk)
	ret.skeleton_name = stpk:r_stringZ()
	ret.skeleton_flags = stpk:r_u8()
	ret.source_id = stpk:r_u16()
	return ret
end

function fill_cse_ph_skeleton_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.skeleton_name)
	stpk:w_u8(ret.skeleton_flags)
	stpk:w_u16(ret.source_id)
end

-- cse_alife_object_properties
function parse_cse_alife_object_properties_packet(ret,stpk)
	ret.game_vertex_id = stpk:r_u16()
	ret.distance = stpk:r_float()
	ret.direct_control = stpk:r_s32()
	ret.level_vertex_id = stpk:r_s32()
	ret.object_flags = stpk:r_s32()
	ret.custom_data = stpk:r_stringZ()
	ret.story_id = stpk:r_s32()
	ret.spawn_story_id = stpk:r_s32()
	return ret
end

function fill_cse_alife_object_properties_packet(ret,stpk)
	stpk:w_u16(ret.game_vertex_id)
	stpk:w_float(ret.distance)
	stpk:w_s32(ret.direct_control)
	stpk:w_s32(ret.level_vertex_id)
	stpk:w_s32(ret.object_flags)
	stpk:w_stringZ(ret.custom_data)
	stpk:w_s32(ret.story_id)
	stpk:w_s32(ret.spawn_story_id)
end

-- cse_alife_inventory_box_properties
function parse_cse_alife_inventory_box_properties_packet(ret,stpk)
	ret.unk1_u8 = stpk:r_u8()
	ret.unk2_u8 = stpk:r_u8()
	ret.tip = stpk:r_stringZ()
	return ret
end

function fill_cse_alife_inventory_box_properties_packet(ret,stpk)
	stpk:w_u8(ret.unk1_u8)
	stpk:w_u8(ret.unk2_u8)
	stpk:w_stringZ(ret.tip)
end

-- cse_alife_helicopter_properties
function parse_cse_alife_helicopter_properties_packet(ret,stpk)
	ret.startup_animation = stpk:r_stringZ()
	ret.engine_sound = stpk:r_stringZ()
	return ret
end

function fill_cse_alife_helicopter_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.startup_animation or "idle")
	stpk:w_stringZ(ret.engine_sound)
end

-- cse_alife_creature_abstract_properties
function parse_cse_alife_creature_abstract_properties_packet(ret,stpk)
	ret.g_team = stpk:r_u8()
	ret.g_squad = stpk:r_u8()
	ret.g_group = stpk:r_u8()
	ret.health = stpk:r_float()
	ret.dynamic_out_restrictions = read_chunk(stpk, stpk:r_s32(), "u16")
	ret.dynamic_in_restrictions = read_chunk(stpk, stpk:r_s32(), "u16")
	ret.killer_id = stpk:r_u16()
	ret.game_death_time = read_chunk(stpk, 8, "u8")
	return ret
end

function fill_cse_alife_creature_abstract_properties_packet(ret,stpk)
	stpk:w_u8(ret.g_team)
	stpk:w_u8(ret.g_squad)
	stpk:w_u8(ret.g_group)
	stpk:w_float(ret.health)

	stpk:w_s32(#ret.dynamic_out_restrictions)
	write_chunk(stpk, ret.dynamic_out_restrictions, "u16")

	stpk:w_s32(#ret.dynamic_in_restrictions)
	write_chunk(stpk, ret.dynamic_in_restrictions, "u16")

	stpk:w_u16(ret.killer_id)
	write_chunk(stpk, ret.game_death_time, "u8")
end

-- cse_alife_monster_abstract_properties
function parse_cse_alife_monster_abstract_properties_packet(ret,stpk)
	ret.base_out_restrictors = stpk:r_stringZ()
	ret.base_in_restrictors = stpk:r_stringZ()
	ret.smart_terrain_id = stpk:r_u16()
	ret.smart_terrain_task_active = stpk:r_u8()
	return ret
end

function fill_cse_alife_monster_abstract_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.base_out_restrictors)
	stpk:w_stringZ(ret.base_in_restrictors)
	stpk:w_u16(ret.smart_terrain_id)
	stpk:w_u8(ret.smart_terrain_task_active)
end

-- cse_alife_trader_abstract_properties
function parse_cse_alife_trader_abstract_properties_packet(ret,stpk)
	ret.money = stpk:r_u32()
	ret.specific_character = stpk:r_stringZ()
	ret.trader_flags = stpk:r_s32()
	ret.character_profile = stpk:r_stringZ()
	ret.community_index = stpk:r_s32()
	ret.rank = stpk:r_s32()
	ret.reputation = stpk:r_s32()
	ret.character_name = stpk:r_stringZ()
	ret.dead_body_can_take = stpk:r_u8()
	ret.dead_body_closed = stpk:r_u8()
	return ret
end

function fill_cse_alife_trader_abstract_properties_packet(ret,stpk)
	stpk:w_u32(ret.money)
	stpk:w_stringZ(ret.specific_character)
	stpk:w_s32(ret.trader_flags)
	stpk:w_stringZ(ret.character_profile)
	stpk:w_s32(ret.community_index)
	stpk:w_s32(ret.rank)
	stpk:w_s32(ret.reputation)
	stpk:w_stringZ(ret.character_name)
	stpk:w_u8(ret.dead_body_can_take)
	stpk:w_u8(ret.dead_body_closed)
end

-- cse_alife_human_abstract_properties
function parse_cse_alife_human_abstract_properties_packet(ret,stpk)
	ret.equipment_preferences = read_chunk(stpk, stpk:r_s32(), "u8")
	ret.weapon_preferences = read_chunk(stpk, stpk:r_s32(), "u8")
end

function fill_cse_alife_human_abstract_properties_packet(ret,stpk)
	stpk:w_s32(#ret.equipment_preferences)
	write_chunk(stpk, ret.equipment_preferences, "u8")

	stpk:w_s32(#ret.weapon_preferences)
	write_chunk(stpk, ret.weapon_preferences, "u8")
end

-- se_stalker_properties
function parse_se_stalker_properties_packet(ret,stpk)
	if data_left(stpk) then
		ret.old_lvid = stpk:r_stringZ()
		ret.active_section = stpk:r_stringZ()
		ret.death_droped = stpk:r_bool()
	end
	return ret
end

function fill_se_stalker_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.old_lvid)
	stpk:w_stringZ(ret.active_section)
	stpk:w_bool(ret.death_droped)
end

-- se_monster_properties
function parse_se_monster_properties_packet(ret,stpk)
	ret.off_level_vertex_id = stpk:r_stringZ()
	ret.active_section = stpk:r_stringZ()
	return ret
end

function fill_se_monster_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.off_level_vertex_id)
	stpk:w_stringZ(ret.active_section)
end

-- cse_alife_space_restrictor_properties
function parse_cse_alife_space_restrictor_properties_packet(ret,stpk)
	-- [0] = "NONE default restrictor", [1] = "OUT default restrictor", [2] = "IN default restrictor", [3] = "NOT A restrictor"
	ret.restrictor_type = stpk:r_u8()
end

function fill_cse_alife_space_restrictor_properties_packet(ret,stpk)
	stpk:w_u8(ret.restrictor_type)
end

-- cse_alife_custom_zone_properties
function parse_cse_alife_custom_zone_properties_packet(ret,stpk)
	ret.max_power = stpk:r_float()
	ret.owner_id = stpk:r_s32()
	ret.enabled_time = stpk:r_s32()
	ret.disabled_time = stpk:r_s32()
	ret.start_time_shift = stpk:r_s32()
end

function fill_cse_alife_custom_zone_properties_packet(ret,stpk)
	stpk:w_float(ret.max_power)
	stpk:w_s32(ret.owner_id)
	stpk:w_s32(ret.enabled_time)
	stpk:w_s32(ret.disabled_time)
	stpk:w_s32(ret.start_time_shift)
end

-- cse_alife_anomalous_zone_properties
function parse_cse_alife_anomalous_zone_properties_packet(ret,stpk)
	ret.offline_interactive_radius = stpk:r_float()
	ret.artefact_spawn_count = stpk:r_u16()
	ret.artefact_position_offset = stpk:r_s32()
end

function fill_cse_alife_anomalous_zone_properties_packet(ret,stpk)
	stpk:w_float(ret.offline_interactive_radius)
	stpk:w_u16(ret.artefact_spawn_count)
	stpk:w_s32(ret.artefact_position_offset)
end

-- se_zone_properties
function parse_se_zone_properties_packet(ret,stpk)
	if data_left(stpk) then
		ret.last_spawn_time = stpk:r_u8()
		if ret.last_spawn_time == 1 then
			if data_left(stpk) then
				ret.c_time = utils.r_CTime(stpk)
			end
		end
	end
end

function fill_se_zone_properties_packet(ret,stpk)
	if ret.last_spawn_time ~= nil then
		stpk:w_u8(ret.last_spawn_time)
		if ret.last_spawn_time == 1 then
			utils.w_CTime(stpk, ret.c_time)
		end
	else
		stpk:w_u8(0)
	end
end

-- cse_alife_item_properties
function parse_cse_alife_item_properties_packet(ret,stpk)
	ret.condition = stpk:r_float()
	ret.upgrades = readvu32stringZ(stpk)
end

function fill_cse_alife_item_properties_packet(ret,stpk)
	stpk:w_float(ret.condition)
	writevu32stringZ(stpk,ret.upgrades)
end

-- cse_alife_item_weapon_properties
function parse_cse_alife_item_weapon_properties_packet(ret,stpk)
	ret.ammo_current = stpk:r_u16()
	ret.ammo_elapsed = stpk:r_u16()
	ret.weapon_state = stpk:r_u8()
	ret.addon_flags = stpk:r_u8()
	ret.ammo_type = stpk:r_u8()
	ret.xz1 = stpk:r_u8()
	return ret
end

function fill_cse_alife_item_weapon_properties_packet(ret,stpk)
	stpk:w_u16(ret.ammo_current)
	stpk:w_u16(ret.ammo_elapsed)
	stpk:w_u8(ret.weapon_state)
	stpk:w_u8(ret.addon_flags)
	stpk:w_u8(ret.ammo_type)
	stpk:w_u8(ret.xz1)
	return ret
end

------------------------------------------------------------------
------------------------------------------------------------------
function data_left(stpk) return (stpk:r_elapsed() ~= 0) end

function read_chunk(stpk, length, c_type)
	local tab = {}
	for i = 1, length do
		if c_type == "u8" then tab[i] = stpk:r_u8()
		elseif c_type == "u16" then tab[i] = stpk:r_u16()
		elseif c_type == "u32" then tab[i] = stpk:r_u32()
		elseif c_type == "s32" then tab[i] = stpk:r_s32()
		elseif c_type == "float" then tab[i] = stpk:r_float()
		elseif c_type == "string" then tab[i] = stpk:r_stringZ()
		elseif c_type == "bool" then tab[i] = stpk:r_bool() end
	end
	return tab
end
function write_chunk(stpk, tab, c_type)
	if tab == nil then return end
	for k, v in ipairs(tab) do
		if c_type == "u8" then stpk:w_u8(v)
		elseif c_type == "u16" then stpk:w_u16(v)
		elseif c_type == "u32" then stpk:w_u32(v)
		elseif c_type == "s32" then stpk:w_s32(v)
		elseif c_type == "float" then stpk:w_float(v)
		elseif c_type == "string" then stpk:w_stringZ(v)
		elseif c_type == "bool" then stpk:w_bool(v) end
	end
end

function readvu32stringZ(stpk)
	local v = {}
	local cnt = stpk:r_s32()
	for i=1,cnt do
		v[i] = stpk:r_stringZ()
	end
	return v
end
function writevu32stringZ(pk,v)
	v = v or {}
	local len = #v
	pk:w_s32(len)
	for i=1,len do
		pk:w_stringZ(v[i])
	end
end
--/-------------------------------------------------------------------
--/ Строковые функции
--/-------------------------------------------------------------------
--/ для правильного парсинга запрещены комментарии!!!
function parse_custom_data(str)
	local t = {}
	if str then
		for section, section_data in string.gmatch(str,"%s*%[([^%]]*)%]%s*([^%[%z]*)%s*") do
			t[section] = {}
			for line in string.gmatch(section_data, "([^\n]*)\n*") do
				if string.find(line," = ") ~= nil then
					for k, v in string.gmatch(line, "([^=]-)%s*=%s*(.*)") do
						if k ~= nil and k ~= "" and v ~= nil then
							t[section][k] = v
						end
					end
				else
					for k, v in string.gmatch(line, "(.*)") do
						if k ~= nil and k ~= "" then
							t[section][k] = "<<no_value>>"
						end
					end
				end
			end
		end
	end
	return t
end

function gen_custom_data(tbl)
	local str = ""
	for key, value in pairs(tbl) do
		str = str.."\n["..key.."]\n"
		for k, v in pairs(value) do
			if v ~= "<<no_value>>" then
				if type(v) == "table" then
					store_table(v, "ABORT:["..key.."]>>")
					abort("TABLE NOT ALLOWED IN PARSE TABLE")
				end
				str = str..k.." = "..v.."\n"
			else
				str = str..k.."\n"
			end
		end
	end
	return str
end