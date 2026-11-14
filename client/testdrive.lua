-- ta-dealer クライアント側（試乗）
-- 始める・終えるのはサーバーが決める。ここは残り時間の表示と、途中でやめるキーと、倒れたときの知らせだけ
TestDrive = { active = false }

local function fadeIn()
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(500) end
end
TestDrive.fadeIn = fadeIn

RegisterNetEvent('ta-dealer:testStarted', function(data)
    TestDrive.active = true
    SendNUIMessage({ action = 'test', scale = Config.UiScale, name = data.name, seconds = data.seconds, key = data.key })
    fadeIn()
    CreateThread(function()
        while TestDrive.active do
            if IsEntityDead(cache.ped) then
                TriggerServerEvent('ta-dealer:endTest')
                break
            end
            Wait(500)
        end
    end)
end)

-- 店の前へ戻す直前。先に暗くする
RegisterNetEvent('ta-dealer:testEnding', function()
    DoScreenFadeOut(300)
end)

RegisterNetEvent('ta-dealer:testEnded', function(reason)
    local wasActive = TestDrive.active
    TestDrive.active = false
    SendNUIMessage({ action = 'testEnd' })
    Wait(300)
    fadeIn()
    if not wasActive then return end -- 出せなかったときは、呼び出した側が知らせる
    local msg = reason == 'time' and '試乗の時間が終わりました' or '試乗を終えました'
    exports['okokNotify']:Alert('販売店', msg, 4000, 'info')
end)

RegisterCommand('tadealer_endtest', function()
    if TestDrive.active then TriggerServerEvent('ta-dealer:endTest') end
end, false)
RegisterKeyMapping('tadealer_endtest', '試乗をやめる', 'keyboard', Config.TestDrive.endKey)
