local QBCore = exports['qb-core']:GetCoreObject()

local npc
local insideWarehouse = false
local currentWarehouse

-- store ids/names returned by ox_target so removal works
local interiorZone = { exit = nil, stash = nil }

-- --------- ox_target compatibility wrapper ---------
local function oxAddSphereZone(opts)
    -- New ox_target API expects a single table
    local ok, zoneId = pcall(function()
        return exports.ox_target:addSphereZone(opts)
    end)
    if ok and zoneId then
        return zoneId
    end

    -- Older ox_target API (some forks) expects: addSphereZone(name, coords, radius, options)
    -- We map what we can.
    local name = opts.name or ('eh_zone_' .. math.random(100000, 999999))
    local coords = opts.coords
    local radius = opts.radius or 1.5
    local options = opts.options or {}

    local ok2, zoneId2 = pcall(function()
        return exports.ox_target:addSphereZone(name, coords, radius, { options = options, debug = opts.debug or false })
    end)
    if ok2 and zoneId2 then
        return zoneId2
    end

    print('[eclipse-homeless] ERROR: ox_target addSphereZone failed (API mismatch).')
    return nil
end

local function oxRemoveZone(idOrName)
    if not idOrName then return end
    pcall(function()
        exports.ox_target:removeZone(idOrName)
    end)
end
-- ---------------------------------------------------

local function openHomelessChat()
    local nodes = {
        start = {
            text = "You look like you could use a hand. What do you need?",
            options = {
                [1] = { label = "I need to be classified as homeless.", desc = "Get registered for services.", next = "register" },
                [2] = { label = "Can I get my welfare check?", desc = "Once per real day.", close = true, action = "welfare" },
                [3] = { label = "Never mind.", desc = "End conversation.", close = true }
            }
        },
        register = {
            text = "Alright. This will mark you as homeless in the system. You can then access squatter locations.",
            options = {
                [1] = { label = "Yes, register me.", desc = "Confirm classification.", close = true, action = "register" },
                [2] = { label = "Back.", desc = "Return.", next = "start" }
            }
        }
    }

    exports['eclipse-chat']:open({
        start = 'start',
        nodes = nodes,
        payload = { badge = 'ECLIPSE', title = 'Outreach', subtitle = 'Services & Support' }
    })
end

AddEventHandler('eclipse-chat:choice:eclipse-homeless', function(data)
    if not data or not data.option then return end
    local action = data.option.action
    if action == 'register' then
        TriggerServerEvent('eclipse-homeless:server:RegisterHomeless')
    elseif action == 'welfare' then
        TriggerServerEvent('eclipse-homeless:server:Welfare')
    end
end)

local function spawnNPC()
    local model = joaat(Config.HomelessNPC.model)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    local c = Config.HomelessNPC.coords
    npc = CreatePed(0, model, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityAsMissionEntity(npc, true, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    FreezeEntityPosition(npc, true)

    exports.ox_target:addLocalEntity(npc, {
        {
            name = 'eclipse_homeless_talk',
            icon = 'fa-solid fa-comments',
            label = 'Talk (Outreach)',
            distance = Config.HomelessNPC.targetRadius or 2.0,
            onSelect = openHomelessChat
        }
    })
end

local function notifyWarehouseStatus(warehouseKey)
    QBCore.Functions.TriggerCallback('eclipse-homeless:server:GetWarehouseStatus', function(data)
        if not data or not data.ok then
            QBCore.Functions.Notify((data and data.msg) or 'Error', 'error')
            return
        end
        if not data.claimed then
            QBCore.Functions.Notify('No one is squatting here yet.', 'primary')
            return
        end
        QBCore.Functions.Notify(
            ('Status: %s | Minutes: %d / %d'):format(data.status, data.minutes, Config.MinutesToOwn),
            'primary'
        )
    end, warehouseKey)
end

local function clearInteriorTargets()
    oxRemoveZone(interiorZone.exit)
    oxRemoveZone(interiorZone.stash)
    interiorZone.exit = nil
    interiorZone.stash = nil
end

local function addInteriorTargets(warehouseKey, exitVec4, stashVec3)
    clearInteriorTargets()

    -- Small delay so the player is fully placed inside (prevents rare init edge-cases)
    Wait(250)

    interiorZone.exit = oxAddSphereZone({
        name = 'eh_exit_' .. warehouseKey,
        coords = vec3(exitVec4.x, exitVec4.y, exitVec4.z),
        radius = 1.6,
        debug = false,
        options = {
            {
                name = 'eh_exit_opt_' .. warehouseKey,
                icon = 'fa-solid fa-door-open',
                label = 'Exit Warehouse',
                onSelect = function()
                    local wh = Config.Warehouses[warehouseKey]
                    if not wh then return end

                    DoScreenFadeOut(200)
                    Wait(350)
                    SetEntityCoords(PlayerPedId(), wh.entry.x, wh.entry.y, wh.entry.z, false, false, false, true)
                    SetEntityHeading(PlayerPedId(), wh.entry.w)
                    TriggerServerEvent('eclipse-homeless:server:Exit')

                    insideWarehouse = false
                    currentWarehouse = nil
                    clearInteriorTargets()

                    Wait(200)
                    DoScreenFadeIn(200)
                end
            }
        }
    })

    interiorZone.stash = oxAddSphereZone({
        name = 'eh_stash_' .. warehouseKey,
        coords = vec3(stashVec3.x, stashVec3.y, stashVec3.z),
        radius = 1.6,
        debug = false,
        options = {
            {
                name = 'eh_stash_opt_' .. warehouseKey,
                icon = 'fa-solid fa-box-open',
                label = 'Open Stash',
                onSelect = function()
                    TriggerServerEvent('eclipse-homeless:server:OpenStash', warehouseKey)
                end
            }
        }
    })

    print(('[eclipse-homeless] Interior targets created | exit=%s stash=%s'):format(
        tostring(interiorZone.exit), tostring(interiorZone.stash)
    ))
end

CreateThread(function()
    spawnNPC()

    for k, wh in pairs(Config.Warehouses) do
        oxAddSphereZone({
            name = 'eh_entry_' .. k,
            coords = vec3(wh.entry.x, wh.entry.y, wh.entry.z),
            radius = 2.0,
            debug = false,
            options = {
                {
                    name = 'eh_status_' .. k,
                    icon = 'fa-solid fa-circle-info',
                    label = ('%s: Check Status'):format(wh.label),
                    onSelect = function() notifyWarehouseStatus(k) end
                },
                {
                    name = 'eh_start_' .. k,
                    icon = 'fa-solid fa-person-shelter',
                    label = ('%s: Start Squatting'):format(wh.label),
                    onSelect = function() TriggerServerEvent('eclipse-homeless:server:StartSquatting', k) end
                },
                {
                    name = 'eh_enter_' .. k,
                    icon = 'fa-solid fa-door-open',
                    label = ('%s: Enter'):format(wh.label),
                    onSelect = function()
                        QBCore.Functions.TriggerCallback('eclipse-homeless:server:CanEnter', function(ok, msg)
                            if not ok then
                                QBCore.Functions.Notify(msg or 'No access', 'error')
                                return
                            end
                            TriggerServerEvent('eclipse-homeless:server:Enter', k)
                        end, k)
                    end
                }
            }
        })
    end
end)

RegisterNetEvent('eclipse-homeless:client:DoEnter', function(warehouseKey, interiorVec4, exitVec4, stashVec3)
    insideWarehouse = true
    currentWarehouse = warehouseKey

    DoScreenFadeOut(200)
    Wait(350)
    SetEntityCoords(PlayerPedId(), interiorVec4.x, interiorVec4.y, interiorVec4.z, false, false, false, true)
    SetEntityHeading(PlayerPedId(), interiorVec4.w)
    Wait(200)
    DoScreenFadeIn(200)

    addInteriorTargets(warehouseKey, exitVec4, stashVec3)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearInteriorTargets()
    if npc and DoesEntityExist(npc) then DeleteEntity(npc) end
end)
