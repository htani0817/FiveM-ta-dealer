-- ta-dealer クライアント側（店の入口と画面）
-- 窓口（ox_target）で一覧を開き、NUI からの操作をプレビューとサーバーに渡す。判定はすべてサーバー側

local open = false
local busy = false -- サーバーの返事を待っている間は次の操作を送らない
local shopId = nil

local function notify(msg, kind)
    exports['okokNotify']:Alert('販売店', msg, 5000, kind or 'info')
end

local function nui(action, data)
    data = data or {}
    data.action = action
    data.scale = Config.UiScale
    SendNUIMessage(data)
end

local function canOpen()
    if open or busy or TestDrive.active then return false end
    if IsPauseMenuActive() or IsNuiFocused() then return false end
    if IsEntityDead(cache.ped) or cache.vehicle then return false end
    return true
end

local function closeShop(instant)
    if not open then return end
    open = false
    shopId = nil
    SetNuiFocus(false, false)
    nui('close')
    Preview.stop(instant)
end

local function openShop(id)
    if not canOpen() then return end
    local shop = Config.Shops[id]
    if not shop then return end
    busy = true
    local res = lib.callback.await('ta-dealer:catalog', false, id)
    busy = false
    if not res or not res.ok then
        notify(res and res.message or '応答がありません', 'error')
        return
    end
    if #res.list == 0 then
        notify('いまは売っている乗り物がありません', 'error')
        return
    end
    open = true
    shopId = id
    Preview.start(shop)
    SetNuiFocus(true, true)
    nui('open', {
        shop = { id = id, label = shop.label, kind = shop.kind },
        categories = shop.categories,
        list = res.list,
        colors = Colors,
        money = res.money,
        test = { seconds = Config.TestDrive.seconds },
    })
end

-- ================== 窓口と地図の印 ==================

local blips = {}

CreateThread(function()
    for id, shop in pairs(Config.Shops) do
        if shop.blip then
            local b = AddBlipForCoord(shop.blip.coords.x, shop.blip.coords.y, shop.blip.coords.z)
            SetBlipSprite(b, shop.blip.sprite)
            SetBlipColour(b, shop.blip.color)
            SetBlipScale(b, 0.8)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(shop.label)
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
        exports.ox_target:addSphereZone({
            coords = shop.counter,
            radius = 1.5,
            debug = Config.Debug,
            options = {
                {
                    name = 'ta-dealer:' .. id,
                    icon = shop.kind == 'boat' and 'fa-solid fa-ship' or shop.kind == 'air' and 'fa-solid fa-plane' or 'fa-solid fa-car',
                    label = '乗り物を見る',
                    distance = 2.5,
                    onSelect = function() openShop(id) end,
                },
            },
        })
    end
end)

-- ================== NUI からの操作 ==================

local function colorOf(data)
    local id = type(data) == 'table' and tonumber(data.color) or nil
    return id and ColorById[id] and id or nil
end

RegisterNUICallback('close', function(_, cb)
    closeShop(false)
    cb({})
end)

RegisterNUICallback('select', function(data, cb)
    local model = type(data) == 'table' and data.model or nil
    local color = colorOf(data) or 0
    if not open or type(model) ~= 'string' then return cb({ ok = false }) end
    cb(Preview.show(model, color) or { ok = false, message = 'このモデルは読み込めませんでした' })
end)

RegisterNUICallback('color', function(data, cb)
    local color = colorOf(data)
    if open and color then Preview.setColor(color) end
    cb({})
end)

RegisterNUICallback('rotate', function(data, cb)
    if open and type(data) == 'table' then
        Preview.rotate(tonumber(data.dx) or 0, tonumber(data.dy) or 0)
    end
    cb({})
end)

RegisterNUICallback('zoom', function(data, cb)
    if open and type(data) == 'table' then Preview.zoom(tonumber(data.delta) or 0) end
    cb({})
end)

RegisterNUICallback('buy', function(data, cb)
    if not open or busy or type(data) ~= 'table' then return cb({ ok = false, busy = true }) end
    busy = true
    local res = lib.callback.await('ta-dealer:buy', false, shopId, data.model, colorOf(data))
        or { ok = false, message = '応答がありません' }
    busy = false
    if res.ok then closeShop(true) end
    notify(res.message, res.ok and 'success' or 'error')
    cb(res)
end)

RegisterNUICallback('test', function(data, cb)
    if not open or busy or type(data) ~= 'table' then return cb({ ok = false, busy = true }) end
    local id, model, color = shopId, data.model, colorOf(data)
    busy = true
    cb({ ok = true })
    closeShop(true)
    DoScreenFadeOut(300)
    Wait(350)
    local res = lib.callback.await('ta-dealer:testDrive', false, id, model, color)
        or { ok = false, message = '応答がありません' }
    busy = false
    if not res.ok then
        TestDrive.fadeIn()
        notify(res.message, 'error')
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    if open then
        SetNuiFocus(false, false)
        Preview.stop(true)
    end
    if TestDrive.active then DoScreenFadeIn(0) end
    for _, b in ipairs(blips) do RemoveBlip(b) end
end)
