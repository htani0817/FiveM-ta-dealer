-- client/*.lua を FiveM の疑似環境で動かすテスト（fengari / Lua 5.3）
-- native は呼ばれた記録を残すだけ。窓口から開く流れ・プレビュー・NUI から来た値の扱いを確かめる
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; io.write('NG: ' .. msg .. '\n') end
end

local V = {}
V.__index = V
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
function vec4(x, y, z, w)
  local v = setmetatable({ x = x, y = y, z = z, w = w }, V)
  v.xyz = vec3(x, y, z)
  return v
end
function joaat(s) return #s * 1000 end

assert(load(SOURCES['config.lua']))()
assert(load(SOURCES['shared/colors.lua']))()

-- ---- 記録 ----
local log = {}
local function rec(name) return function(...) log[#log + 1] = { name = name, args = { ... } } end end
local function count(name)
  local n = 0
  for _, l in ipairs(log) do if l.name == name then n = n + 1 end end
  return n
end
local function last(name)
  for i = #log, 1, -1 do if log[i].name == name then return log[i] end end
end

-- ---- FiveM ----
local threads, events, handlers, nuiCb, commands = {}, {}, {}, {}, {}
function CreateThread(fn) threads[#threads + 1] = fn end
function Wait() end
function RegisterNetEvent(name, fn) events[name] = fn end
function AddEventHandler(name, fn) handlers[name] = fn end
function RegisterNUICallback(name, fn) nuiCb[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
RegisterKeyMapping = rec('RegisterKeyMapping')
TriggerServerEvent = rec('TriggerServerEvent')
local nuiMsgs = {}
function SendNUIMessage(m) nuiMsgs[#nuiMsgs + 1] = m end
local focus = false
function SetNuiFocus(a) focus = a end
function IsNuiFocused() return focus end
function IsPauseMenuActive() return false end
local dead = false
function IsEntityDead() return dead end
function GetCurrentResourceName() return 'ta-dealer' end
function IsScreenFadedOut() return false end
function IsScreenFadingOut() return true end
DoScreenFadeIn = rec('DoScreenFadeIn')
DoScreenFadeOut = rec('DoScreenFadeOut')
function AddBlipForCoord() return 1 end
SetBlipSprite, SetBlipColour, SetBlipScale, SetBlipAsShortRange = rec('b'), rec('b'), rec('b'), rec('b')
BeginTextCommandSetBlipName, AddTextComponentSubstringPlayerName, EndTextCommandSetBlipName, RemoveBlip = rec('b'), rec('b'), rec('b'), rec('b')
function CreateCamWithParams() return 77 end
SetCamActive = rec('SetCamActive')
RenderScriptCams = rec('RenderScriptCams')
DestroyCam = rec('DestroyCam')
SetCamCoord = rec('SetCamCoord')
PointCamAtCoord = rec('PointCamAtCoord')
SetFocusPosAndVel = rec('SetFocusPosAndVel')
ClearFocus = rec('ClearFocus')
local known = { [6000] = true, [5000] = true } -- blista（6 文字）と panto（5 文字）だけ読み込める
function IsModelInCdimage(h) return known[h] == true end
function IsModelAVehicle(h) return known[h] == true end
local vehicles, nextVeh = {}, 500
function CreateVehicle(h, x, y, z, w, net, mission)
  nextVeh = nextVeh + 1
  vehicles[nextVeh] = { hash = h, net = net }
  log[#log + 1] = { name = 'CreateVehicle', args = { h, x, y, z, w, net, mission } }
  return nextVeh
end
function DoesEntityExist(e) return vehicles[e] ~= nil end
function DeleteEntity(e) vehicles[e] = nil; log[#log + 1] = { name = 'DeleteEntity', args = { e } } end
SetModelAsNoLongerNeeded, SetVehicleOnGroundProperly, FreezeEntityPosition = rec('x'), rec('SetVehicleOnGroundProperly'), rec('x')
SetEntityInvincible, SetVehicleDoorsLocked, SetVehicleDirtLevel = rec('x'), rec('x'), rec('x')
SetVehicleColours = rec('SetVehicleColours')
function GetModelDimensions() return vec3(-1, -2, -0.5), vec3(1, 2, 1) end
function GetOffsetFromEntityInWorldCoords(_, x, y, z) return vec3(x, y, z) end
function GetVehicleClassFromName() return 0 end
function GetVehicleModelNumberOfSeats() return 4 end
function GetVehicleModelEstimatedMaxSpeed() return 44.0 end

-- ---- ox_lib・ox_target・okokNotify ----
cache = { ped = 1, vehicle = false }
local cbResults, cbCalls = {}, {}
local points = {}
local createdPeds = {}
function CreatePed(_, h, x, y, z, w, net)
  nextVeh = nextVeh + 1
  vehicles[nextVeh] = { hash = h, ped = true }
  createdPeds[#createdPeds + 1] = { id = nextVeh, x = x, y = y, z = z, w = w, net = net }
  return nextVeh
end
SetBlockingOfNonTemporaryEvents, SetPedCanRagdoll = rec('x'), rec('x')
lib = {
  points = { new = function(p) points[#points + 1] = p; return p end },
  requestModel = function(h) return h end,
  callback = {
    await = function(name, _, ...)
      cbCalls[#cbCalls + 1] = { name = name, args = { ... } }
      return cbResults[name]
    end,
  },
}
local zones = {}
local entityTargets = {} -- NPC → ox_target の選択肢
local notifies = {}
exports = {
  ox_target = {
    addSphereZone = function(_, z) zones[#zones + 1] = z end,
    addLocalEntity = function(_, ent, options) entityTargets[ent] = options end,
    removeLocalEntity = function(_, ent) entityTargets[ent] = nil end,
  },
  okokNotify = { Alert = function(_, title, msg, ms, kind) notifies[#notifies + 1] = { msg = msg, kind = kind } end },
}

assert(load(SOURCES['client/preview.lua']))()
assert(load(SOURCES['client/testdrive.lua']))()
assert(load(SOURCES['client/main.lua']))()
for _, t in ipairs(threads) do t() end
threads = {}

local function nuiCall(name, data)
  local out
  nuiCb[name](data, function(r) out = r end)
  return out
end
local function zoneFor(id)
  for _, z in ipairs(zones) do
    if z.options[1].name == 'ta-dealer:' .. id then return z end
  end
  for _, options in pairs(entityTargets) do
    if options[1].name == 'ta-dealer:' .. id then return { options = options } end
  end
end

-- ================== 窓口 ==================
-- 車の店は NPC、ボートと航空機は ped を書いていないので円
ok(#zones == 2 and zoneFor('boat') and zoneFor('air'), 'ped の無い店は円の窓口')
ok(zoneFor('boat').coords == Config.Shops.boat.counter, '円の位置は config の counter')
ok(#points == 2 and points[1].distance == Config.PedDistance, 'NPC の店（車・武装車両）は近づいたときに出す')
ok(zoneFor('car') == nil, '近づく前は NPC を出さない')
-- 車の店の NPC の点を先頭にする（pairs の順は決まっていない）
table.sort(points, function(a, b)
  return a.coords.x == Config.Shops.car.ped.coords.x and b.coords.x ~= Config.Shops.car.ped.coords.x
end)
points[2].onEnter()
ok(zoneFor('armed') and zoneFor('armed').options[1].label == '武装車両を見る', '武装車両の店員には「武装車両を見る」')
points[2].onExit()
createdPeds = {}
points[1].onEnter()
local pc = Config.Shops.car.ped.coords
local cp = createdPeds[1]
ok(cp and cp.x == pc.x and cp.z == pc.z and cp.w == pc.w and cp.net == false, 'config の vec4 の位置と向きに、ローカルの NPC を出す')
ok(zoneFor('car') ~= nil and zoneFor('car').options[1].label == '乗り物を見る', 'NPC に「乗り物を見る」を付ける')
ok(Config.Shops.car.counter.x == pc.x and Config.Shops.car.counter.y == pc.y, 'NPC の足元が窓口（距離の確認に使う）')
points[1].onEnter()
ok(#createdPeds == 1, '二重には出さない')
points[1].onExit()
ok(zoneFor('car') == nil and vehicles[cp.id] == nil, '離れたら NPC を消す')
points[1].onEnter()

-- 一覧が届かなければ開かない
cbResults['ta-dealer:catalog'] = { ok = false, message = '窓口から離れています' }
zoneFor('car').options[1].onSelect()
ok(not focus and notifies[#notifies].msg == '窓口から離れています', '断られたら開かない')

-- 開く
cbResults['ta-dealer:catalog'] = { ok = true, list = { { model = 'panto', name = 'Panto', brand = 'Benefactor', price = 850000, category = 'compacts' } }, money = { cash = 1, bank = 2 } }
zoneFor('car').options[1].onSelect()
local open = nuiMsgs[#nuiMsgs]
ok(focus and open.action == 'open', '開くと NUI に渡す')
ok(open.shop.id == 'car' and #open.colors == #Colors and open.categories == Config.Shops.car.categories, '店・色・タブを渡す')
ok(open.test.seconds == Config.TestDrive.seconds, '試乗の時間を渡す')
ok(count('RenderScriptCams') == 1, 'カメラに切り替える')

-- ================== プレビュー ==================
local r = nuiCall('select', { model = 'panto', color = 27 })
ok(r.ok and r.seats == 4 and r.speed == 158 and r.class == 'コンパクト', '性能は native の値（44 m/s → 158 km/h）')
local cv = last('CreateVehicle')
ok(cv.args[6] == false, 'プレビューの車両はネットワークに出さない')
ok(last('SetVehicleColours').args[2] == 27 and last('SetVehicleColours').args[3] == 27, '選んだ色で塗る（単色）')
local first = nextVeh
r = nuiCall('select', { model = 'blista', color = 27 })
ok(r.ok and vehicles[first] == nil, '選び直すと前の車両を消す')
r = nuiCall('select', { model = 'nothing', color = 27 })
ok(r.ok == false and r.message ~= nil, '読み込めないモデルは断る')
r = nuiCall('select', { model = 123 })
ok(r.ok == false, '文字でないモデルは断る')
local paints = count('SetVehicleColours')
nuiCall('color', { color = 5 })
ok(count('SetVehicleColours') == paints, '見本帳に無い色では塗らない')
nuiCall('color', { color = 64 })
ok(last('SetVehicleColours').args[2] == 64, '見本帳の色で塗り替える')
local cams = count('SetCamCoord')
nuiCall('rotate', { dx = 10, dy = 0 })
nuiCall('zoom', { delta = 100 })
ok(count('SetCamCoord') == cams + 2, '回す・寄るでカメラが動く')

-- ================== 購入 ==================
cbResults['ta-dealer:buy'] = { ok = false, message = 'お金が足りません' }
r = nuiCall('buy', { model = 'panto', color = 64 })
ok(r.ok == false and focus, '断られたら開いたまま')
local bc = cbCalls[#cbCalls]
ok(bc.name == 'ta-dealer:buy' and bc.args[1] == 'car' and bc.args[2] == 'panto' and bc.args[3] == 64, '店・モデル・色をサーバーへ')
r = nuiCall('buy', { model = 'panto', color = 999 })
ok(cbCalls[#cbCalls].args[3] == nil, '見本帳に無い色は送らない（サーバーが断る）')
cbResults['ta-dealer:buy'] = { ok = true, message = 'Panto を購入しました' }
r = nuiCall('buy', { model = 'panto', color = 64 })
ok(r.ok and not focus and nuiMsgs[#nuiMsgs].action == 'close', '買えたら閉じる')
ok(not Preview.active(), '買えたらカメラを戻す')

-- ================== 試乗 ==================
zoneFor('car').options[1].onSelect()
cbResults['ta-dealer:testDrive'] = { ok = true }
r = nuiCall('test', { model = 'panto', color = 0 })
ok(r.ok and not focus and not Preview.active(), '試乗に出るときは画面とカメラを閉じる')
ok(cbCalls[#cbCalls].name == 'ta-dealer:testDrive' and cbCalls[#cbCalls].args[1] == 'car', '試乗をサーバーへ頼む')
events['ta-dealer:testStarted']({ name = 'Panto', seconds = 180, key = 'F7' })
ok(TestDrive.active and nuiMsgs[#nuiMsgs].action == 'test', '試乗中の表示')
cbResults['ta-dealer:catalog'] = { ok = true, list = {}, money = {} }
local calls = #cbCalls
zoneFor('car').options[1].onSelect()
ok(#cbCalls == calls, '試乗中は窓口を開かない')
commands['tadealer_endtest']()
ok(last('TriggerServerEvent').args[1] == 'ta-dealer:endTest', 'キーでやめる')
dead = true
for _, t in ipairs(threads) do t() end
ok(count('TriggerServerEvent') == 2, '倒れたらサーバーへ知らせる')
dead = false
events['ta-dealer:testEnded']('time')
ok(not TestDrive.active and nuiMsgs[#nuiMsgs].action == 'testEnd', '終わったら表示を消す')
ok(notifies[#notifies].msg == '試乗の時間が終わりました', '時間切れを知らせる')

-- 試乗を断られた
cbResults['ta-dealer:catalog'] = { ok = true, list = { { model = 'panto', name = 'Panto', brand = '', price = 1, category = 'compacts' } }, money = {} }
zoneFor('car').options[1].onSelect()
cbResults['ta-dealer:testDrive'] = { ok = false, message = '次の試乗まであと 30 秒です' }
local fades = count('DoScreenFadeIn')
nuiCall('test', { model = 'panto', color = 0 })
ok(count('DoScreenFadeIn') == fades + 1 and notifies[#notifies].kind == 'error', '断られたら画面を明るくして知らせる')

io.write(('合格 %d / 失敗 %d\n'):format(pass, fail))
if fail > 0 then error('テスト失敗') end
