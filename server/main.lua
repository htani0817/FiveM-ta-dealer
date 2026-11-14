-- ta-dealer サーバー側（カタログと購入）
-- 値段・扱う車種・色・距離の判定はすべてここで行う。クライアントから来た値は信じない

-- qbx_vehicles はサーバーだけのリソースなので、fxmanifest の dependencies ではなくここで確かめる
-- （qbx_vehicleshop と同じ方法・同じ版）
assert(lib.checkDependency('qbx_vehicles', '1.4.1'), 'ta-dealer には qbx_vehicles 1.4.1 以上が必要です')

Dealer = {}

local PAY_LABEL = { cash = '現金', bank = '銀行' }

local function yen(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end
Dealer.yen = yen

local function fail(message) return { ok = false, message = message } end
Dealer.fail = fail

-- ================== カタログ ==================

local catalogs = nil -- 店 ID → { list = { ... }, byModel = { model → 行 } }

local function buildCatalogs()
    local vehicles = exports.qbx_core:GetVehiclesByName() or {}
    local result = {}
    for shopId, shop in pairs(Config.Shops) do
        local cats = {}
        for _, c in ipairs(shop.categories) do cats[c.id] = true end
        local allow = nil
        if shop.models then
            allow = {}
            for _, m in ipairs(shop.models) do allow[m] = true end
        end
        local deny = {}
        for _, m in ipairs(shop.exclude or {}) do deny[m] = true end
        local list, byModel = {}, {}
        for model, v in pairs(vehicles) do
            local price = tonumber(v.price)
            if cats[v.category] and not Config.Blocklist[model] and not deny[model]
                and (not allow or allow[model]) and price and price > 0 then
                local row = {
                    model = model,
                    name = v.name or model,
                    brand = v.brand or '',
                    price = math.floor(price),
                    category = v.category,
                }
                list[#list + 1] = row
                byModel[model] = row
            end
        end
        -- 安い順。同じ値段なら名前の順
        table.sort(list, function(a, b)
            if a.price ~= b.price then return a.price < b.price end
            return a.name < b.name
        end)
        result[shopId] = { list = list, byModel = byModel }
    end
    return result
end

function Dealer.catalog(shopId)
    if not catalogs then catalogs = buildCatalogs() end
    return catalogs[shopId]
end

function Dealer.item(shopId, model)
    local c = Dealer.catalog(shopId)
    return c and type(model) == 'string' and c.byModel[model] or nil
end

-- ================== 共通の確認 ==================

-- 店を使ってよいか。よければ shop と player を返す
function Dealer.check(src, shopId)
    local shop = type(shopId) == 'string' and Config.Shops[shopId] or nil
    if not shop then return nil, 'その店はありません' end
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil, 'プレイヤーの情報がありません' end
    local md = player.PlayerData.metadata or {}
    if md.isdead or md.inlaststand then return nil, '倒れている間は使えません' end
    if md.ishandcuffed then return nil, '手錠をされている間は使えません' end
    if Dealer.inTest(src) then return nil, '試乗中は使えません' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil, 'プレイヤーの情報がありません' end
    if #(GetEntityCoords(ped) - shop.counter) > Config.CounterRange then return nil, '窓口から離れています' end
    return shop, player
end

function Dealer.color(colorId)
    return ColorById[tonumber(colorId) or -1]
end

-- 鍵を渡して、開けた状態にする（施錠状態を付けないと、乗り直すとき qbx_vehiclekeys が 75% で鍵を掛ける）
function Dealer.giveKeys(src, veh)
    if GetResourceState('qbx_vehiclekeys') ~= 'started' then return end
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh, true) end)
    pcall(function() exports.qbx_vehiclekeys:SetLockState(veh, 'unlock') end)
end

-- いつもの空間（bucket 0）で、まわりに乗り物が無いか。試乗中の車両は別の空間にいるので数えない
local function isClear(coords, radius)
    local vehicles = GetAllVehicles()
    for i = 1, #vehicles do
        local v = vehicles[i]
        if GetEntityRoutingBucket(v) == 0 and #(GetEntityCoords(v) - coords.xyz) < radius then
            return false
        end
    end
    return true
end

local function clearSpot(shop)
    for _, spot in ipairs(shop.deliver) do
        if isClear(spot, shop.clearRadius or 3.0) then return spot end
    end
end

-- 決めた順に、足りる口座から全額を払う。払えたら口座の名前を返す
local function charge(src, price, reason)
    for _, kind in ipairs(Config.Payment) do
        if (tonumber(exports.qbx_core:GetMoney(src, kind)) or 0) >= price then
            if exports.qbx_core:RemoveMoney(src, kind, price, reason) then return kind end
            return nil
        end
    end
    return nil
end

-- ================== コールバック ==================

lib.callback.register('ta-dealer:catalog', function(src, shopId)
    local shop, err = Dealer.check(src, shopId)
    if not shop then return fail(err) end
    local c = Dealer.catalog(shopId)
    return {
        ok = true,
        list = c.list,
        money = {
            cash = tonumber(exports.qbx_core:GetMoney(src, 'cash')) or 0,
            bank = tonumber(exports.qbx_core:GetMoney(src, 'bank')) or 0,
        },
    }
end)

local buying = {} -- 手続き中のプレイヤー（二重に押されても 1 台だけ）

local function buy(src, shopId, model, colorId)
    local shop, player = Dealer.check(src, shopId)
    if not shop then return fail(player) end
    local item = Dealer.item(shopId, model)
    if not item then return fail('この店では扱っていません') end
    local color = Dealer.color(colorId)
    if not color then return fail('その色は選べません') end

    local spot = clearSpot(shop)
    if not spot then return fail('受け渡しの場所がふさがっています。少し待ってください') end

    local kind = charge(src, item.price, ('ta-dealer 購入 %s'):format(model))
    if not kind then return fail('お金が足りません') end

    -- 代金を引いたあとなので、ここで止まっても必ず返金できるよう pcall で包む
    local okCreate, vehicleId = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model = model,
            citizenid = player.PlayerData.citizenid,
            props = { color1 = color.id, color2 = color.id },
        })
    end)
    if not okCreate or not vehicleId then
        exports.qbx_core:AddMoney(src, kind, item.price, ('ta-dealer 返金 %s'):format(model))
        print(('[ta-dealer] 登録に失敗したので返金しました src=%s model=%s'):format(src, model))
        return fail('登録に失敗しました。代金は返しました')
    end

    if shop.garageId then
        local okDb = pcall(function()
            MySQL.update.await('UPDATE player_vehicles SET garage_id = ? WHERE id = ?', { shop.garageId, vehicleId })
        end)
        if not okDb then print(('[ta-dealer] garage_id を書けませんでした id=%s'):format(vehicleId)) end
    end

    print(('[ta-dealer] 購入 %s src=%s model=%s color=%s %s円（%s） id=%s'):format(
        player.PlayerData.citizenid, src, model, color.id, item.price, kind, vehicleId))

    -- DB に入ったナンバーと色で出す（qbx.spawnVehicle は props に plate があるときだけ props を当てる）
    local okGet, saved = pcall(function() return exports.qbx_vehicles:GetPlayerVehicle(vehicleId) end)
    local props = okGet and saved and saved.props or nil
    local paid = ('%s払い %s円'):format(PAY_LABEL[kind] or kind, yen(item.price))
    local registered = ('%s を登録しました（%s）。出せなかったので、ガレージから出してください'):format(item.name, paid)
    -- ナンバーが分からないまま出すと DB と違う車になるので、出さずにガレージへ回す
    if not props or not props.plate then return { ok = true, message = registered } end

    local okSpawn, netId, veh = pcall(qbx.spawnVehicle, {
        model = model,
        spawnSource = spot,
        warp = GetPlayerPed(src),
        props = props,
    })
    if not okSpawn or not netId or netId == 0 or not veh or veh == 0 then
        print(('[ta-dealer] 出庫に失敗 id=%s %s'):format(vehicleId, tostring(netId)))
        return { ok = true, message = registered }
    end

    Entity(veh).state:set('vehicleid', vehicleId, false)
    Dealer.giveKeys(src, veh)
    return { ok = true, message = ('%s を購入しました（%s）'):format(item.name, paid) }
end

lib.callback.register('ta-dealer:buy', function(src, shopId, model, colorId)
    if buying[src] then return fail('手続き中です') end
    buying[src] = true
    local ok, res = pcall(buy, src, shopId, model, colorId)
    buying[src] = nil
    if not ok then
        print('[ta-dealer] 購入でエラー: ' .. tostring(res))
        return fail('手続きに失敗しました')
    end
    return res
end)

AddEventHandler('playerDropped', function()
    buying[source] = nil
end)
