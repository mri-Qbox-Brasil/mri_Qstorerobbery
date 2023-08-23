local QBCore = exports['qb-core']:GetCoreObject()
local PlayerLoaded = false
local PlayerData = {}
local CurrentStore
local InRegZone, RegZoneID = false, nil
local TempStoreData = {}
local ox_inventory = exports.ox_inventory

local function Enter(self)
    InRegZone = true
    RegZoneID = self.regid
end

local function Alert()

end

local function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

local function EntityDamage(victim)
    if not CurrentStore then return end
    if not TempStoreData then return end
    local cfg = Config.Store[CurrentStore]
    if cfg.alerted then return end
    local damageCashier = false
    if next(TempStoreData) == nil then return end
    for _, v in pairs(TempStoreData.registar) do
        if v.entity == victim then
            damageCashier = true
            break
        end
    end
    if damageCashier then
        lib.callback("ran-storerobbery:server:registerAlert")
    end
end

local function Exit()
    InRegZone = false
    RegZoneID = nil
end

local function RobRegistar()
    if not CurrentStore then return end
    if not RegZoneID or not InRegZone then
        QBCore.Functions.Notify("You need to stand in front of cashier", "error")
        return
    end
    local ped = cache.ped
    local StoreConfig = Config.Store[CurrentStore]
    if not StoreConfig then return end
    local RegConfig = StoreConfig.registar[RegZoneID]
    if RegConfig.robbed then
        return QBCore.Functions.Notify("There is no money in here", "error")
    end
    if not RegConfig then return end
    if RegConfig.isusing then
        return QBCore.Functions.Notify("Somebody is in the register")
    end
    TriggerServerEvent("ran-storerobbery:server:setUse", CurrentStore, RegZoneID, true)
    local anim = "oddjobs@shop_robbery@rob_till"
    local animname = "loop"
    lib.requestAnimDict(anim)
    TaskPlayAnim(ped, anim, animname, 8.0, 8.0, -1, 3, 1.0, false, false, false)
    local prize = math.floor(math.random(Config.Prize.min, Config.Prize.max))
    local success = exports['ran-minigames']:MineSweep(prize, 10, 3, "left")
    if success then
        lib.callback("ran-houserobbery:server:getPrize", false, function(cb)
            QBCore.Functions.Notify(
                ("You got %s %s"):format(success,
                    Config.Prize.item and ox_inventory:Items(Config.Prize.item).label or "Cash"), "success")
        end, success, CurrentStore, RegZoneID)
    end
    TaskPlayAnim(ped, anim, "exit", 8.0, 8.0, -1, 0, 1.0, false, false, false)
    TriggerServerEvent("ran-storerobbery:server:setUse", CurrentStore, RegZoneID, false)
end

local EData = nil

local function SearchCombination(storeid, sid)
    local config = Config.Store[storeid]
    if not config then return end
    local searchLoc = config.search[sid]
    if not searchLoc then return end
    if config.combination then
        return QBCore.Functions.Notify("You already got the combination...")
    end
    if searchLoc.searched then
        return QBCore.Functions.Notify("You already search this place...")
    end

    if searchLoc.iscomputer then
        local animdict = 'anim@scripted@player@mission@tunf_bunk_ig3_nas_upload@'
        local anim     = 'normal_typing'
        lib.requestAnimDict(animdict)
        TaskPlayAnim(cache.ped, animdict, anim, 8.0, 8.0, -1, 1, 1.0, false, false, false)
        local minigame = exports['ran-minigames']:OpenTerminal()
        if minigame then
            lib.callback.await("ran-storerobbery:server:combination", false, storeid, sid, true)
            QBCore.Functions.Notify("You got the combination key")
        end
        ClearPedTasks(cache.ped)
    else
        QBCore.Functions.Progressbar('search-combination', 'Searching for combination', 5000, false, true,
            { -- Name | Label | Time | useWhileDead | canCancel
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            }, {
                animDict = 'mini@repair',
                anim = 'fixing_a_ped',
                flags = 16,
            }, {}, {}, function() -- Play When Done
                local canGet = math.random(1, 100) > 90 and true or false
                lib.callback.await("ran-storerobbery:server:combination", false, storeid, sid, canGet)
                if canGet then
                    QBCore.Functions.Notify("You got the combination key")
                else
                    QBCore.Functions.Notify("You didn't get anything")
                end
                ClearPedTasks(cache.ped)
            end, function() -- Play When Cancel
                ClearPedTasks(cache.ped)
            end)
    end
end

local function SetupStore(id)
    if TempStoreData[id] then return end
    local cfg = Config.Store[id]
    if not cfg then return end
    EData = AddEventHandler('entityDamaged', EntityDamage)
    local interior = GetInteriorAtCoords(cfg.coords.x, cfg.coords.y, cfg.coords.z)
    RefreshInterior(interior)
    repeat
        Wait(500)
    until IsInteriorReady(interior)
    local function UpdateConfig()
        if not lib.table.matches(cfg, Config.Store[id]) then
            print("UPDATE CONFIG")
            cfg = Config.Store[id]
        end
    end
    TempStoreData.registar = {}
    for k, v in pairs(cfg.registar) do
        TempStoreData.registar[k] = {}
        TempStoreData.registar[k].zone = lib.zones.sphere({
            coords = v.coords.xyz,
            radius = 1.0,
            regid = k,
            onEnter = Enter,
            onExit = Exit
        })
    end
    local function Hack(self)
        local success = exports['ran-minigames']:MemoryCard()
        if success then
            TriggerServerEvent("ran-houserobbery:server:setHackedState", self.storeid)
        end
    end
    local function OpenPinPrompt()
        local input = lib.inputDialog("Pin", {
            {
                type = 'number',
                label = "Pin Number",
            }
        })
        if not input then return end
        if not input[1] then
            return QBCore.Functions.Notify("You need to fill the pin...", "error")
        end
        local num = tonumber(input[1])
        if num == cfg.combination then
            lib.callback.await("ran-storerobbery:server:setSafeState", false, CurrentStore, true)
            return QBCore.Functions.Notify("You unlocked the safe", "success")
        else
            return QBCore.Functions.Notify("Wrong pin number...", "error")
        end
    end
    local function InsideSafe(self)
        ---@type vector3
        local coords = self.coords
        if cfg.safe.isopened then
            DrawText3D(coords.x, coords.y, coords.z, "[~g~E~w~] Open Safe")
        else
            DrawText3D(coords.x, coords.y, coords.z, "[~r~E~w~] Try pin")
        end
        if IsControlJustPressed(0, 46) then
            if cfg.safe.isopened and cfg.safe.id then
                ox_inventory:openInventory("stash", cfg.safe.id)
            else
                OpenPinPrompt()
            end
        end
    end
    if cfg.hack then
        TempStoreData.hack = exports.ox_target:addBoxZone({
            coords = cfg.hack.coords,
            size = cfg.hack.size,
            rotation = cfg.hack.rotation,
            options = {
                {
                    label = "Hack",
                    canInteract = function()
                        return not cfg.hack.hacked
                    end,
                    storeid = id,
                    onSelect = Hack,
                    distance = 1.0,
                    icon = "fas fa-laptop"
                }
            }
        })
    end
    if cfg.search then
        TempStoreData.search = {}
        for k, v in pairs(cfg.search) do
            ---@type OxTargetOption[]
            local options = {}
            if v.iscomputer then
                options[#options + 1] = {
                    label = "Search for combination",
                    distance = 2.0,
                    icon = "fa-solid fa-magnifying-glass",
                    canInteract = function()
                        return not cfg.combination
                    end,
                    onSelect = function()
                        SearchCombination(CurrentStore, k)
                    end
                }
            else
                options[#options + 1] = {
                    label = "Search for combination",
                    distance = 1.0,
                    icon = "fa-solid fa-magnifying-glass",
                    canInteract = function()
                        return not cfg.combination
                    end,
                    onSelect = function()
                        SearchCombination(CurrentStore, k)
                    end
                }
            end
            TempStoreData.search[k] = exports.ox_target:addBoxZone({
                coords = v.coords,
                size = v.size,
                rotation = v.rotation,
                options = options,
                drawSprite = false
            })
        end
    end
    if cfg.safe then
        TempStoreData.safe = lib.zones.sphere({
            coords = cfg.safe.coords.xyz,
            radius = 1.0,
            inside = InsideSafe
        })
    end
    CreateThread(function()
        while CurrentStore == id do
            UpdateConfig()
            Wait(1000)
        end
    end)
end


local function ResetStore(id)
    if TempStoreData.hack then
        exports.ox_target:removeZone(TempStoreData.hack)
    end
    if TempStoreData.registar then
        for k, v in pairs(TempStoreData.registar) do
            if v.zone then
                v.zone:remove()
            end
            if v.entity then
                exports.ox_target:removeLocalEntity(v.entity)
            end
        end
    end
    if TempStoreData.search then
        for _, v in pairs(TempStoreData.search) do
            exports.ox_target:removeZone(v)
        end
    end
    if TempStoreData.safe then
        TempStoreData.safe:remove()
    end
    if EData then
        RemoveEventHandler(EData)
        EData = nil
    end
    table.wipe(TempStoreData)
    QBCore.Debug(TempStoreData)
end

---@diagnostic disable-next-line: param-type-mismatch
AddStateBagChangeHandler('isLoggedIn', nil, function(_bagName, _key, value, _reserved, _replicated)
    if value then
        PlayerData = QBCore.Functions.GetPlayerData()
        ox_inventory:displayMetadata({
            combination = "Combination"
        })
    else
        table.wipe(PlayerData)
    end
    PlayerLoaded = value
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName or not LocalPlayer.state.isLoggedIn then return end
    PlayerData = QBCore.Functions.GetPlayerData()
    PlayerLoaded = true
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(newPlayerData)
    local invokingResource = GetInvokingResource()
    if invokingResource and invokingResource ~= 'qb-core' then return end
    PlayerData = newPlayerData
end)

RegisterNetEvent("ran-storerobbery:client:setConfigs", function(cfg)
    Config.Store = cfg
end)

RegisterNetEvent("ran-storerobbery:client:setStoreConfig", function(id, cfg)
    if not id or not cfg then return end
    if not type(cfg) == "table" then return end
    if not Config.Store[id] then return end
    print("UPDATE STORE CONFIG")
    Config.Store[id] = cfg
end)

CreateThread(function()
    while true do
        if PlayerLoaded then
            local pos = GetEntityCoords(cache.ped)
            for k, v in pairs(Config.Store) do
                local pos2 = v.coords
                local dist = #(pos - pos2)
                if dist <= 20.0 and CurrentStore ~= k then
                    CurrentStore = k
                    SetupStore(k)
                elseif dist >= 20.0 and CurrentStore == k then
                    ResetStore(k)
                    table.wipe(TempStoreData)
                    CurrentStore = nil
                end
            end
        end
        Wait(1000)
    end
end)

CreateThread(function()
    exports.ox_target:addModel('prop_till_01', {
        label = "Grab Cash",
        canInteract = function(entity, distance, coords, name, bone)
            return entity and GetEntityHealth(entity) < 1000 and CurrentStore and not Config.Store[CurrentStore]
                .cooldown
        end,
        icon = "fa-solid fa-cash-register",
        onSelect = RobRegistar
    })
end)
