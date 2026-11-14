-- ta-dealer サーバー側（試乗）
-- プレイヤーごとに専用の空間（routing bucket）へ移して試乗車を出す。時間切れ・途中終了・切断・停止で必ず片付ける

local sessions = {}  -- src → { shopId, bucket, from, veh, ending }
local cooldowns = {} -- src → この時刻（os.time）までは次の試乗をしない

function Dealer.inTest(src)
    return sessions[src] ~= nil
end

local function teleport(ped, c)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    SetEntityHeading(ped, c.w)
end

-- 試乗を終える。dropped は切断したとき（もう戻す相手がいない）
local function finish(src, reason)
    local s = sessions[src]
    if not s or s.ending then return end
    s.ending = true

    if reason ~= 'dropped' and reason ~= 'stopped' then
        TriggerClientEvent('ta-dealer:testEnding', src)
        Wait(400) -- 画面が暗くなるのを待ってから動かす
    end

    if s.veh and DoesEntityExist(s.veh) then
        if reason ~= 'dropped' and GetResourceState('qbx_vehiclekeys') == 'started' then
            pcall(function() exports.qbx_vehiclekeys:RemoveKeys(src, s.veh, true) end)
        end
        DeleteEntity(s.veh)
    end

    if reason ~= 'dropped' then
        exports.qbx_core:SetPlayerBucket(src, 0)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then teleport(ped, s.from) end
        TriggerClientEvent('ta-dealer:testEnded', src, reason)
    end

    sessions[src] = nil
    -- 出せなかったときと切断したときは、次の試乗を待たせない
    if reason == 'dropped' or reason == 'failed' then
        cooldowns[src] = nil
    else
        cooldowns[src] = os.time() + Config.TestDrive.cooldown
    end
end

local function start(src, shopId, model, colorId)
    local shop, err = Dealer.check(src, shopId)
    if not shop then return Dealer.fail(err) end
    local item = Dealer.item(shopId, model)
    if not item then return Dealer.fail('この店では扱っていません') end
    local color = Dealer.color(colorId)
    if not color then return Dealer.fail('その色は選べません') end
    local wait = (cooldowns[src] or 0) - os.time()
    if wait > 0 then return Dealer.fail(('次の試乗まであと %d 秒です'):format(wait)) end

    -- 終わったら、いま立っている所（窓口の前）へ戻す
    local ped = GetPlayerPed(src)
    local here = GetEntityCoords(ped)
    local bucket = Config.TestDrive.bucketBase + src
    local session = { shopId = shopId, bucket = bucket, from = vec4(here.x, here.y, here.z, GetEntityHeading(ped)) }
    sessions[src] = session

    -- 専用の空間へ移す。車や歩行者は出さない
    exports.qbx_core:SetPlayerBucket(src, bucket)
    SetRoutingBucketPopulationEnabled(bucket, false)

    -- 先に試乗地点へ移す（遠くに車両を出すと、持ち主が決まらずに出せない）
    local at = shop.testDrive
    teleport(ped, at)
    pcall(lib.waitFor, function()
        if #(GetEntityCoords(ped) - at.xyz) < 50.0 then return true end
    end, nil, 5000)

    local plate = ('TEST%04d'):format(math.random(0, 9999))
    local okSpawn, netId, veh = pcall(qbx.spawnVehicle, {
        model = model,
        spawnSource = at,
        warp = ped,
        bucket = bucket,
        props = { plate = plate, color1 = color.id, color2 = color.id, fuelLevel = 100.0 },
    })
    if not okSpawn or not netId or netId == 0 or not veh or veh == 0 then
        print(('[ta-dealer] 試乗車を出せませんでした src=%s model=%s %s'):format(src, model, tostring(netId)))
        finish(src, 'failed')
        return Dealer.fail('試乗車を出せませんでした')
    end

    session.veh = veh
    Dealer.giveKeys(src, veh)

    local seconds = Config.TestDrive.seconds
    SetTimeout(seconds * 1000, function()
        if sessions[src] == session then finish(src, 'time') end
    end)

    TriggerClientEvent('ta-dealer:testStarted', src, {
        name = item.name,
        seconds = seconds,
        netId = netId,
        key = Config.TestDrive.endKey,
    })
    return { ok = true }
end

lib.callback.register('ta-dealer:testDrive', function(src, shopId, model, colorId)
    if sessions[src] then return Dealer.fail('試乗中です') end
    local ok, res = pcall(start, src, shopId, model, colorId)
    if not ok then
        print('[ta-dealer] 試乗でエラー: ' .. tostring(res))
        if sessions[src] then finish(src, 'failed') end
        return Dealer.fail('試乗を始められませんでした')
    end
    return res
end)

-- 途中でやめる（キー）・倒れた（クライアントが知らせる）
RegisterNetEvent('ta-dealer:endTest', function()
    local src = source
    if sessions[src] then finish(src, 'cancel') end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if sessions[src] then finish(src, 'dropped') end
    cooldowns[src] = nil
end)

-- リソースを止めたときは、試乗中の人を全員もとの空間と店の前へ戻す
AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for src in pairs(sessions) do finish(src, 'stopped') end
end)
