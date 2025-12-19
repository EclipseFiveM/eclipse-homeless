local QBCore = exports['qb-core']:GetCoreObject()

local ActiveInside = {} -- [source] = warehouseKey

local function IsPolice(Player)
    if not Player then return false end
    local job = Player.PlayerData.job
    return job and job.name and Config.PoliceJobNames[job.name] == true
end

local function IsHomeless(Player)
    if not Player then return false end
    local meta = Player.PlayerData.metadata or {}
    return meta[Config.HomelessMetaKey] == true
end

local function TodayStr()
    return os.date('%Y-%m-%d')
end

local function GetHomelessRow(cid)
    return MySQL.single.await('SELECT * FROM eclipse_homeless WHERE citizenid = ?', { cid })
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    if not Player then return end
    local cid = Player.PlayerData.citizenid
    local row = GetHomelessRow(cid)
    if row and tonumber(row.is_homeless) == 1 then
        Player.Functions.SetMetaData(Config.HomelessMetaKey, true)
    end
end)

-- squat DB
local function GetRecord(warehouseKey)
    return MySQL.single.await('SELECT * FROM qb_squatters WHERE warehouse = ?', { warehouseKey })
end

local function EnsureRecord(warehouseKey, cid)
    local rec = GetRecord(warehouseKey)
    if rec then return rec end
    MySQL.insert.await(
        'INSERT INTO qb_squatters (warehouse, citizenid, status, minutes) VALUES (?, ?, "squatting", 0)',
        { warehouseKey, cid }
    )
    return GetRecord(warehouseKey)
end

QBCore.Functions.CreateCallback('eclipse-homeless:server:GetWarehouseStatus', function(source, cb, warehouseKey)
    if not Config.Warehouses[warehouseKey] then return cb({ ok = false, msg = 'Invalid warehouse' }) end
    local rec = GetRecord(warehouseKey)
    if not rec then
        return cb({ ok = true, claimed = false, status = nil, minutes = 0, ownerCid = nil })
    end
    cb({ ok = true, claimed = true, status = rec.status, minutes = rec.minutes, ownerCid = rec.citizenid })
end)

RegisterNetEvent('eclipse-homeless:server:RegisterHomeless', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if IsHomeless(Player) then
        TriggerClientEvent('QBCore:Notify', src, 'You are already classified as homeless.', 'primary')
        return
    end

    local cid = Player.PlayerData.citizenid
    Player.Functions.SetMetaData(Config.HomelessMetaKey, true)

    MySQL.update.await(
        'INSERT INTO eclipse_homeless (citizenid, is_homeless, last_welfare_date) VALUES (?, 1, NULL) ' ..
        'ON DUPLICATE KEY UPDATE is_homeless = 1',
        { cid }
    )

    TriggerClientEvent('QBCore:Notify', src, 'You are now classified as homeless. You may access squatter locations.', 'success')
end)

RegisterNetEvent('eclipse-homeless:server:Welfare', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not Config.Welfare.enabled then
        TriggerClientEvent('QBCore:Notify', src, 'Welfare is disabled.', 'error')
        return
    end
    if not IsHomeless(Player) then
        TriggerClientEvent('QBCore:Notify', src, 'You must be classified as homeless to receive welfare.', 'error')
        return
    end

    local cid = Player.PlayerData.citizenid
    local row = GetHomelessRow(cid)
    local today = TodayStr()

    if Config.Welfare.oncePerRealDay and row and row.last_welfare_date == today then
        TriggerClientEvent('QBCore:Notify', src, 'You already received welfare today. Come back tomorrow.', 'error')
        return
    end

    local amt = tonumber(Config.Welfare.amount) or 600
    local account = (Config.Welfare.account == 'bank') and 'bank' or 'cash'
    Player.Functions.AddMoney(account, amt, 'homeless-welfare')

    MySQL.update.await(
        'INSERT INTO eclipse_homeless (citizenid, is_homeless, last_welfare_date) VALUES (?, 1, ?) ' ..
        'ON DUPLICATE KEY UPDATE is_homeless = 1, last_welfare_date = ?',
        { cid, today, today }
    )

    TriggerClientEvent('QBCore:Notify', src, ('You received a welfare check of $%d.'):format(amt), 'success')
end)

RegisterNetEvent('eclipse-homeless:server:StartSquatting', function(warehouseKey)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    if not Config.Warehouses[warehouseKey] then return end

    if not IsHomeless(Player) then
        TriggerClientEvent('QBCore:Notify', src, 'Talk to the outreach worker to be classified as homeless first.', 'error')
        return
    end

    local cid = Player.PlayerData.citizenid
    local rec = GetRecord(warehouseKey)
    if rec and rec.citizenid ~= cid then
        TriggerClientEvent('QBCore:Notify', src, 'Someone else already controls this spot.', 'error')
        return
    end

    EnsureRecord(warehouseKey, cid)
    TriggerClientEvent('QBCore:Notify', src, 'You have started squatting. Time only counts while you are inside.', 'success')
end)

QBCore.Functions.CreateCallback('eclipse-homeless:server:CanEnter', function(source, cb, warehouseKey)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false, 'Player not found') end
    if not Config.Warehouses[warehouseKey] then return cb(false, 'Invalid warehouse') end

    if Config.PoliceOverride and IsPolice(Player) then return cb(true) end
    if not IsHomeless(Player) then return cb(false, 'You must be classified as homeless first.') end

    local rec = GetRecord(warehouseKey)
    if not rec then return cb(false, 'Start squatting first.') end
    if rec.citizenid ~= Player.PlayerData.citizenid then return cb(false, 'No access.') end

    cb(true)
end)

RegisterNetEvent('eclipse-homeless:server:Enter', function(warehouseKey)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local wh = Config.Warehouses[warehouseKey]
    if not wh then return end

    ActiveInside[src] = warehouseKey

    local bucket = (GetHashKey(warehouseKey) % 60000) + 1000
    SetPlayerRoutingBucket(src, bucket)

    TriggerClientEvent('eclipse-homeless:client:DoEnter', src, warehouseKey, wh.interior, wh.exit, wh.stash)
end)

RegisterNetEvent('eclipse-homeless:server:Exit', function()
    local src = source
    ActiveInside[src] = nil
    SetPlayerRoutingBucket(src, 0)
end)

AddEventHandler('playerDropped', function()
    ActiveInside[source] = nil
end)

CreateThread(function()
    while true do
        Wait(Config.TickMinutes * 60000)
        for src, warehouseKey in pairs(ActiveInside) do
            local Player = QBCore.Functions.GetPlayer(src)
            if Player then
                local rec = GetRecord(warehouseKey)
                if rec and rec.citizenid == Player.PlayerData.citizenid and rec.status == 'squatting' then
                    local newMinutes = rec.minutes + Config.TickMinutes
                    local status = 'squatting'
                    local owned_at = nil
                    if newMinutes >= Config.MinutesToOwn then
                        status = 'owned'
                        owned_at = os.date('%Y-%m-%d %H:%M:%S')
                    end
                    MySQL.update.await(
                        'UPDATE qb_squatters SET minutes = ?, status = ?, owned_at = COALESCE(owned_at, ?) WHERE warehouse = ? AND citizenid = ?',
                        { newMinutes, status, owned_at, warehouseKey, Player.PlayerData.citizenid }
                    )
                    if status == 'owned' then
                        TriggerClientEvent('QBCore:Notify', src, 'You have earned squatters rights. This warehouse is now yours.', 'success')
                    end
                end
            end
        end
    end
end)

-- Stash open (qb-inventory safe)
RegisterNetEvent('eclipse-homeless:server:OpenStash', function(warehouseKey)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    if not Config.Warehouses[warehouseKey] then return end

    print(('[eclipse-homeless] OpenStash click | src=%s wh=%s'):format(src, tostring(warehouseKey)))

    -- Access control
    if not (Config.PoliceOverride and IsPolice(Player)) then
        if not IsHomeless(Player) then
            print('[eclipse-homeless] OpenStash denied: not homeless')
            TriggerClientEvent('QBCore:Notify', src, 'You must be classified as homeless first.', 'error')
            return
        end

        local rec = GetRecord(warehouseKey)
        if not rec then
            print('[eclipse-homeless] OpenStash denied: no warehouse record')
            TriggerClientEvent('QBCore:Notify', src, 'Start squatting first.', 'error')
            return
        end

        if rec.citizenid ~= Player.PlayerData.citizenid then
            print('[eclipse-homeless] OpenStash denied: not owner')
            TriggerClientEvent('QBCore:Notify', src, 'No access.', 'error')
            return
        end
    end

    local rec = GetRecord(warehouseKey)
    local cid = Player.PlayerData.citizenid
    local stashId = ('squat_%s_%s'):format(warehouseKey, (rec and rec.citizenid) or cid)
    local stashLabel = ('Squat Stash (%s)'):format(warehouseKey)

    local ox = GetResourceState('ox_inventory') == 'started'
    local qb = GetResourceState('qb-inventory') == 'started'
    local ps = GetResourceState('ps-inventory') == 'started'

    print(('[eclipse-homeless] Inventory state | ox=%s qb=%s ps=%s'):format(tostring(ox), tostring(qb), tostring(ps)))

    -- 1) ox_inventory
    if ox then
        -- Many ox_inventory setups need the stash to be registered server-side
        if exports.ox_inventory and exports.ox_inventory.RegisterStash then
            exports.ox_inventory:RegisterStash(stashId, stashLabel, Config.Stash.slots, Config.Stash.weight, false)
            print('[eclipse-homeless] ox_inventory: RegisterStash OK')
        else
            print('[eclipse-homeless] ox_inventory: RegisterStash export missing (still attempting open)')
        end

        TriggerClientEvent('ox_inventory:openInventory', src, 'stash', stashId)
        print('[eclipse-homeless] ox_inventory: openInventory event fired')
        return
    end

    -- 2) qb-inventory
    if qb and exports['qb-inventory'] then
        if exports['qb-inventory'].RegisterStash then
            exports['qb-inventory']:RegisterStash(stashId, stashLabel, Config.Stash.slots, Config.Stash.weight)
            print('[eclipse-homeless] qb-inventory: RegisterStash OK')
        end

        -- Newer qb-inventory: OpenInventory(source, type, identifier)
        if exports['qb-inventory'].OpenInventory then
            exports['qb-inventory']:OpenInventory(src, 'stash', stashId)
            print('[eclipse-homeless] qb-inventory: OpenInventory export used')
            return
        end

        -- Classic qb/ps inventory events
        TriggerClientEvent('inventory:client:SetCurrentStash', src, stashId)
        TriggerClientEvent('inventory:client:OpenInventory', src, {
            type = 'stash',
            id = stashId,
            title = stashLabel
        }, {
            maxweight = Config.Stash.weight,
            slots = Config.Stash.slots
        })
        print('[eclipse-homeless] qb-inventory: classic open events fired')
        return
    end

    -- 3) ps-inventory (usually uses the same classic events)
    if ps then
        TriggerClientEvent('inventory:client:SetCurrentStash', src, stashId)
        TriggerClientEvent('inventory:client:OpenInventory', src, {
            type = 'stash',
            id = stashId,
            title = stashLabel
        }, {
            maxweight = Config.Stash.weight,
            slots = Config.Stash.slots
        })
        print('[eclipse-homeless] ps-inventory: classic open events fired')
        return
    end

    print('[eclipse-homeless] OpenStash failed: no supported inventory detected')
    TriggerClientEvent('QBCore:Notify', src, 'Inventory system not detected for stash opening.', 'error')
end)
