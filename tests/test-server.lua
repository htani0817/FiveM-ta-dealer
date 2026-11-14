-- server/main.lua と server/testdrive.lua を FiveM の疑似環境で動かすテスト（fengari / Lua 5.3）
-- qbx_core・qbx_vehicles・qbx_vehiclekeys の動きは、使っている export だけを本物の引数に合わせて疑似する
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; io.write('NG: ' .. msg .. '\n') end
end

-- ---- ベクトル（vec3 / vec4 の引き算と長さ） ----
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

-- ---- 読み込み（config と色見本は本物） ----
assert(load(SOURCES['config.lua']))()
assert(load(SOURCES['shared/colors.lua']))()

-- ---- FiveM ----
local events, handlers, timers, sent, printed = {}, {}, {}, {}, {}
function RegisterNetEvent(name, fn) events[name] = fn end
function AddEventHandler(name, fn) handlers[name] = fn end
function SetTimeout(ms, fn) timers[#timers + 1] = { ms = ms, fn = fn } end
function Wait() end
function TriggerClientEvent(name, src, ...) sent[#sent + 1] = { name = name, src = src, args = { ... } } end
function GetCurrentResourceName() return 'ta-dealer' end
function GetResourceState() return 'started' end
function print(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
source = nil
local now = 1000
os.time = function() return now end

local peds = {}       -- src → { coords, heading }
local vehicles = {}   -- 車両 → { coords, bucket, model }
local buckets = {}    -- src → bucket
local nextVeh = 100
function GetPlayerPed(src) return peds[src] and src or 0 end
function GetEntityCoords(e)
  if vehicles[e] then return vehicles[e].coords end
  return peds[e].coords
end
function SetEntityCoords(e, x, y, z) peds[e].coords = vec3(x, y, z) end
function SetEntityHeading(e, h) peds[e].heading = h end
function GetEntityHeading(e) return peds[e].heading end
function GetAllVehicles()
  local list = {}
  for v in pairs(vehicles) do list[#list + 1] = v end
  return list
end
function GetEntityRoutingBucket(e) return vehicles[e] and vehicles[e].bucket or 0 end
local population = {}
function SetRoutingBucketPopulationEnabled(b, on) population[b] = on end
function DoesEntityExist(e) return vehicles[e] ~= nil end
local deleted = {}
function DeleteEntity(e) vehicles[e] = nil; deleted[#deleted + 1] = e end
local statebags = {}
function Entity(e) return { state = { set = function(_, k, v) statebags[e] = statebags[e] or {}; statebags[e][k] = v end } } end

-- ---- ox_lib ----
local callbacks = {}
local depChecks = {}
lib = {
  callback = { register = function(name, fn) callbacks[name] = fn end },
  checkDependency = function(name, ver) depChecks[#depChecks + 1] = name .. '@' .. ver; return true end,
  waitFor = function(cb, msg, timeout)
    local v = cb()
    if not v then error(msg or 'timeout') end
    return v
  end,
}
local function call(name, src, ...) return callbacks[name](src, ...) end

-- ---- oxmysql ----
local sqls = {}
MySQL = { update = { await = function(q, p) sqls[#sqls + 1] = { q = q, p = p }; return 1 end } }

-- ---- qbx_core ----
local VEHICLES = {
  blista = { name = 'Blista', brand = 'Dinka', price = 1600000, category = 'compacts' },
  panto = { name = 'Panto', brand = 'Benefactor', price = 850000, category = 'compacts' },
  asea = { name = 'Asea', brand = 'Declasse', price = 1250000, category = 'sedans' },
  police = { name = 'Police', brand = 'Vapid', price = 5000000, category = 'sedans' },          -- Blocklist
  oppressor = { name = 'Oppressor', brand = 'Pegassi', price = 9000000, category = 'motorcycles' }, -- Blocklist
  zentorno = { name = 'Zentorno', brand = 'Pegassi', price = 72500000, category = 'super' },    -- 車の店のタブに無い
  free = { name = 'Free', brand = '', price = 0, category = 'compacts' },                       -- 値段なし
  dinghy = { name = 'Dinghy', brand = 'Nagasaki', price = 1660000, category = 'boats' },
  frogger = { name = 'Frogger', brand = 'Maibatsu', price = 130000000, category = 'helicopters' },
  luxor = { name = 'Luxor', brand = 'Buckingham', price = 162500000, category = 'planes' },
  akula = { name = 'Akula', brand = 'Buckingham', price = 599000000, category = 'helicopters' }, -- 空の店の models に無い
}

local players, money, moneyLog = {}, {}, {}
local function addPlayer(src, cash, bank, coords)
  players[src] = { PlayerData = { source = src, citizenid = 'CID' .. src, metadata = {} } }
  money[src] = { cash = cash, bank = bank }
  peds[src] = { coords = coords, heading = 0 }
end

local qbxCore = {}
function qbxCore:GetVehiclesByName() return VEHICLES end
function qbxCore:GetPlayer(src) return players[src] end
function qbxCore:GetMoney(src, kind) return money[src][kind] end
function qbxCore:RemoveMoney(src, kind, n, reason)
  if money[src][kind] < n then return false end
  money[src][kind] = money[src][kind] - n
  moneyLog[#moneyLog + 1] = { op = 'remove', src = src, kind = kind, n = n, reason = reason }
  return true
end
function qbxCore:AddMoney(src, kind, n, reason)
  money[src][kind] = money[src][kind] + n
  moneyLog[#moneyLog + 1] = { op = 'add', src = src, kind = kind, n = n, reason = reason }
  return true
end
function qbxCore:SetPlayerBucket(src, b) buckets[src] = b; return true end

-- qbx_vehicles
local created, createMode, nextId = {}, 'ok', 1
local dbVehicles = {}
local qbxVehicles = {}
function qbxVehicles:CreatePlayerVehicle(req)
  if createMode == 'nil' then return nil, { code = 'hook_cancelled' } end
  if createMode == 'error' then error('db down') end
  created[#created + 1] = req
  local id = nextId
  nextId = nextId + 1
  local props = { plate = 'ABC' .. id, color1 = req.props.color1, color2 = req.props.color2, fuelLevel = 100 }
  dbVehicles[id] = { id = id, modelName = req.model, props = props }
  return id
end
function qbxVehicles:GetPlayerVehicle(id) return dbVehicles[id] end

-- qbx_vehiclekeys（呼ばれた順を残す）
local keyLog = {}
local qbxKeys = {}
function qbxKeys:GiveKeys(src, veh) keyLog[#keyLog + 1] = 'give:' .. src .. ':' .. veh end
function qbxKeys:SetLockState(veh, st) keyLog[#keyLog + 1] = 'lock:' .. veh .. ':' .. st end
function qbxKeys:RemoveKeys(src, veh) keyLog[#keyLog + 1] = 'remove:' .. src .. ':' .. veh end

exports = { qbx_core = qbxCore, qbx_vehicles = qbxVehicles, qbx_vehiclekeys = qbxKeys }

-- qbx.spawnVehicle（@qbx_core/modules/lib.lua）
local spawns, spawnFail = {}, false
qbx = {}
function qbx.spawnVehicle(p)
  if spawnFail then error('unable to successfully spawn vehicle after 3 attempts') end
  spawns[#spawns + 1] = p
  nextVeh = nextVeh + 1
  local c = p.spawnSource
  vehicles[nextVeh] = { coords = vec3(c.x, c.y, c.z), bucket = p.bucket or 0, model = p.model }
  return nextVeh + 5000, nextVeh
end

assert(load(SOURCES['server/main.lua']))()
assert(load(SOURCES['server/testdrive.lua']))()

local CAR = Config.Shops.car.counter
local AIR = Config.Shops.air.counter
local function lastSent(name)
  for i = #sent, 1, -1 do if sent[i].name == name then return sent[i] end end
end
local function runTimers()
  local list = timers
  timers = {}
  for _, t in ipairs(list) do t.fn() end
end

-- ================== 起動 ==================
ok(depChecks[1] == 'qbx_vehicles@1.4.1', 'qbx_vehicles はサーバー側で確かめる')

-- ================== カタログ ==================
local car = Dealer.catalog('car')
ok(car.byModel.blista and car.byModel.panto and car.byModel.asea, '車の店にタブの車種が並ぶ')
ok(not car.byModel.police and not car.byModel.oppressor, 'Blocklist の車種は並ばない')
ok(not car.byModel.zentorno, 'タブに無い種類（super）は並ばない')
ok(not car.byModel.free, '値段の無い車種は並ばない')
ok(not car.byModel.dinghy and not car.byModel.frogger, '船・空は車の店に並ばない')
ok(car.list[1].model == 'panto' and car.list[#car.list].model == 'blista', '安い順')
local air = Dealer.catalog('air')
ok(air.byModel.frogger and air.byModel.luxor, '空の店に models の機体が並ぶ')
ok(not air.byModel.akula, '空の店は models に無い機体を並べない')
ok(Dealer.catalog('boat').byModel.dinghy ~= nil, 'ボートの店')

addPlayer(1, 2000000, 50000000, vec3(CAR.x, CAR.y, CAR.z))
local r = call('ta-dealer:catalog', 1, 'car')
ok(r.ok and #r.list == 3 and r.money.cash == 2000000 and r.money.bank == 50000000, '一覧と所持金を返す')
ok(call('ta-dealer:catalog', 1, 'nope').ok == false, '無い店は断る')
addPlayer(2, 0, 0, vec3(0, 0, 0))
r = call('ta-dealer:catalog', 2, 'car')
ok(r.ok == false and r.message == '窓口から離れています', '窓口から離れていると開けない')

-- ================== 購入 ==================
r = call('ta-dealer:buy', 1, 'car', 'zentorno', 27)
ok(r.ok == false and r.message == 'この店では扱っていません', '店に無い車種は買えない')
r = call('ta-dealer:buy', 1, 'car', 'frogger', 27)
ok(r.ok == false, 'ほかの店の車種は買えない')
r = call('ta-dealer:buy', 1, 'car', 'blista', 5)
ok(r.ok == false and r.message == 'その色は選べません', '見本帳に無い色は選べない')
r = call('ta-dealer:buy', 1, 'car', 'blista', 'abc')
ok(r.ok == false and r.message == 'その色は選べません', '数字でない色は断る')
ok(#moneyLog == 0, 'ここまでお金は動かない')

-- 現金で足りる
r = call('ta-dealer:buy', 1, 'car', 'panto', 27)
ok(r.ok == true and r.message:find('現金払い 850,000円', 1, true) ~= nil, '現金で買える: ' .. tostring(r.message))
ok(money[1].cash == 2000000 - 850000 and money[1].bank == 50000000, '値段はサーバーの値で現金から引く')
ok(created[1].model == 'panto' and created[1].citizenid == 'CID1', 'DB に持ち主付きで登録')
ok(created[1].props.color1 == 27 and created[1].props.color2 == 27, '色は 1 色目と 2 色目に同じ番号')
local sp = spawns[#spawns]
ok(sp.props.plate == 'ABC1' and sp.props.color1 == 27, 'DB のナンバーと色で出す')
ok(sp.warp == 1 and sp.spawnSource == Config.Shops.car.deliver[1], '1 番目の受け渡し場所に出して乗せる')
local veh1 = #spawns > 0 and (nextVeh) or nil
ok(statebags[veh1] and statebags[veh1].vehicleid == 1, '車両に vehicleid を付ける')
ok(keyLog[1] == 'give:1:' .. veh1 and keyLog[2] == 'lock:' .. veh1 .. ':unlock', '鍵を渡してから開けた状態にする')

-- 1 番目がふさがっていたら 2 番目
r = call('ta-dealer:buy', 1, 'car', 'asea', 0)
ok(r.ok and spawns[#spawns].spawnSource == Config.Shops.car.deliver[2], 'ふさがっていたら次の場所')
-- 現金が足りなければ銀行
local bankBefore, cashNow = money[1].bank, money[1].cash
r = call('ta-dealer:buy', 1, 'car', 'blista', 111)
ok(r.ok and r.message:find('銀行払い 1,600,000円', 1, true) ~= nil, '現金が足りなければ銀行から')
ok(money[1].bank == bankBefore - 1600000 and money[1].cash == cashNow, '銀行からだけ引く')

-- お金が足りない
addPlayer(3, 100, 100, vec3(CAR.x, CAR.y, CAR.z))
local before = #created
r = call('ta-dealer:buy', 3, 'car', 'panto', 0)
ok(r.ok == false and r.message == 'お金が足りません' and #created == before, 'お金が足りなければ登録しない')

-- 受け渡し場所が全部ふさがっている（ほかの空間の車両は数えない）
for k in pairs(vehicles) do vehicles[k] = nil end
for i, spot in ipairs(Config.Shops.car.deliver) do vehicles[900 + i] = { coords = spot.xyz, bucket = 0 } end
local cashBefore = money[1].cash
r = call('ta-dealer:buy', 1, 'car', 'panto', 0)
ok(r.ok == false and r.message:find('ふさがって', 1, true) ~= nil and money[1].cash == cashBefore, '場所が無ければ代金を取らない')
vehicles[901].bucket = 4201
r = call('ta-dealer:buy', 1, 'car', 'panto', 0)
ok(r.ok and spawns[#spawns].spawnSource == Config.Shops.car.deliver[1], '試乗の空間の車両は場所をふさがない')
for k in pairs(vehicles) do vehicles[k] = nil end

-- 登録に失敗したら返金（ここからは現金で払える額を持たせる）
money[1].cash = 10000000
createMode = 'nil'
cashBefore = money[1].cash
r = call('ta-dealer:buy', 1, 'car', 'panto', 0)
ok(r.ok == false and money[1].cash == cashBefore, '登録できなければ返金（nil）')
ok(moneyLog[#moneyLog].op == 'add' and moneyLog[#moneyLog].kind == 'cash', '払った口座に返す')
createMode = 'error'
r = call('ta-dealer:buy', 1, 'car', 'panto', 0)
ok(r.ok == false and money[1].cash == cashBefore, '登録でエラーが出ても返金')
createMode = 'ok'

-- 出せなかったときは登録だけ（返金しない）
spawnFail = true
cashBefore = money[1].cash
r = call('ta-dealer:buy', 1, 'car', 'panto', 0)
ok(r.ok == true and r.message:find('ガレージから', 1, true) ~= nil and money[1].cash == cashBefore - 850000, '出せなくても登録は残る')
spawnFail = false

-- garageId
Config.Shops.car.garageId = 'pdm_lot'
r = call('ta-dealer:buy', 1, 'car', 'panto', 0)
ok(sqls[#sqls] and sqls[#sqls].p[1] == 'pdm_lot', 'garageId があれば garage_id を書く')
Config.Shops.car.garageId = nil
for k in pairs(vehicles) do vehicles[k] = nil end

-- 倒れている・手錠
players[1].PlayerData.metadata.isdead = true
ok(call('ta-dealer:buy', 1, 'car', 'panto', 0).ok == false, '倒れていると買えない')
players[1].PlayerData.metadata.isdead = nil
players[1].PlayerData.metadata.ishandcuffed = true
ok(call('ta-dealer:catalog', 1, 'car').ok == false, '手錠中は開けない')
players[1].PlayerData.metadata.ishandcuffed = nil

-- ================== 試乗 ==================
addPlayer(5, 0, 0, vec3(AIR.x, AIR.y, AIR.z))
r = call('ta-dealer:testDrive', 5, 'air', 'luxor', 64)
ok(r.ok == true, 'お金が無くても試乗できる')
ok(buckets[5] == Config.TestDrive.bucketBase + 5, '専用の空間へ移す')
ok(population[Config.TestDrive.bucketBase + 5] == false, '専用の空間には車や歩行者を出さない')
sp = spawns[#spawns]
ok(sp.bucket == Config.TestDrive.bucketBase + 5 and sp.warp == 5, '試乗車は同じ空間に出して乗せる')
ok(sp.props.plate:sub(1, 4) == 'TEST' and sp.props.color1 == 64 and sp.props.color2 == 64, 'ナンバーは TEST、色は選んだ色')
ok(sp.spawnSource == Config.Shops.air.testDrive, '試乗地点に出す')
local tveh = nextVeh
local st = lastSent('ta-dealer:testStarted')
ok(st and st.src == 5 and st.args[1].seconds == Config.TestDrive.seconds and st.args[1].name == 'Luxor', '始まったことを知らせる')
ok(Dealer.inTest(5), '試乗中')
r = call('ta-dealer:buy', 5, 'air', 'luxor', 64)
ok(r.ok == false and r.message == '試乗中は使えません', '試乗中は買えない')
r = call('ta-dealer:testDrive', 5, 'air', 'luxor', 64)
ok(r.ok == false and r.message == '試乗中です', '2 台目は出さない')

-- 時間切れ
runTimers()
ok(not Dealer.inTest(5), '時間切れで終わる')
ok(vehicles[tveh] == nil, '試乗車を消す')
ok(keyLog[#keyLog] == 'remove:5:' .. tveh, '仮の鍵を外す')
ok(buckets[5] == 0, 'いつもの空間へ戻す')
ok(peds[5].coords.x == AIR.x and peds[5].coords.y == AIR.y and peds[5].heading == 0, '始めたときに立っていた所（窓口の前）へ戻す')
st = lastSent('ta-dealer:testEnded')
ok(st and st.src == 5 and st.args[1] == 'time', '終わった理由を知らせる')
ok(#created == 0 or created[#created].model ~= 'luxor', '試乗車は DB に入らない')

-- クールダウン
peds[5].coords = vec3(AIR.x, AIR.y, AIR.z)
r = call('ta-dealer:testDrive', 5, 'air', 'luxor', 64)
ok(r.ok == false and r.message:find('次の試乗まで', 1, true) ~= nil, '続けては試乗できない')
now = now + Config.TestDrive.cooldown + 1
r = call('ta-dealer:testDrive', 5, 'air', 'frogger', 0)
ok(r.ok == true, '時間が空けば試乗できる')

-- 途中でやめる
source = 5
events['ta-dealer:endTest']()
ok(not Dealer.inTest(5) and buckets[5] == 0, 'キーで途中でやめられる')
ok(lastSent('ta-dealer:testEnded').args[1] == 'cancel', 'やめた理由')
-- 前の時間切れのタイマーが後から来ても、何もしない
local sentBefore = #sent
runTimers()
ok(#sent == sentBefore, '終わった試乗のタイマーは何もしない')

-- 切断
now = now + 100
peds[5].coords = vec3(AIR.x, AIR.y, AIR.z)
call('ta-dealer:testDrive', 5, 'air', 'luxor', 0)
tveh = nextVeh
buckets[5] = Config.TestDrive.bucketBase + 5
source = 5
handlers['playerDropped']()
ok(not Dealer.inTest(5) and vehicles[tveh] == nil, '切断したら試乗車を消す')
ok(buckets[5] == Config.TestDrive.bucketBase + 5, '切断した人の空間は触らない')

-- 試乗車を出せなかった
spawnFail = true
peds[5].coords = vec3(AIR.x, AIR.y, AIR.z)
r = call('ta-dealer:testDrive', 5, 'air', 'luxor', 0)
ok(r.ok == false and r.message == '試乗車を出せませんでした', '出せなければ断る')
ok(not Dealer.inTest(5) and buckets[5] == 0, '出せなければいつもの空間へ戻す')
spawnFail = false
r = call('ta-dealer:testDrive', 5, 'air', 'luxor', 0)
ok(r.ok == true, '出せなかったあとは待たずに試乗できる')

-- リソースを止める
addPlayer(6, 0, 0, vec3(CAR.x, CAR.y, CAR.z))
call('ta-dealer:testDrive', 6, 'car', 'blista', 0)
handlers['onResourceStop']('ta-dealer')
ok(not Dealer.inTest(5) and not Dealer.inTest(6), '止めたら全員の試乗を終える')
ok(buckets[5] == 0 and buckets[6] == 0, '止めたら全員をいつもの空間へ')

io.write(('合格 %d / 失敗 %d\n'):format(pass, fail))
if fail > 0 then error('テスト失敗') end
