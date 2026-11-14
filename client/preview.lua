-- ta-dealer クライアント側（プレビュー）
-- 店の preview の場所に、自分にだけ見えるローカルの車両を出し、そのまわりを回るカメラで写す
Preview = {}

local CLASS_LABEL = {
    [0] = 'コンパクト', [1] = 'セダン', [2] = 'SUV', [3] = 'クーペ', [4] = 'マッスル', [5] = 'クラシック',
    [6] = 'スポーツ', [7] = 'スーパー', [8] = 'バイク', [9] = 'オフロード', [10] = '産業用', [11] = '作業用',
    [12] = 'バン', [13] = '自転車', [14] = 'ボート', [15] = 'ヘリ', [16] = '飛行機', [17] = 'サービス',
    [18] = '緊急車両', [19] = '軍用', [20] = '商用', [21] = '鉄道', [22] = 'オープンホイール',
}

local st = {
    shop = nil,
    cam = nil,
    veh = nil,
    color = 0,
    token = 0,     -- 選び直したとき、古い読み込みを捨てる印
    center = nil,  -- カメラが見る点
    yaw = 0.0,
    pitch = 12.0,
    dist = 6.0,
    minDist = 3.0,
    maxDist = 12.0,
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- 角度（yaw は GTA の向きと同じく北が 0 で反時計回り）と距離からカメラを置く
local function placeCam()
    if not st.cam or not st.center then return end
    local yaw, pitch = math.rad(st.yaw), math.rad(st.pitch)
    local c = st.center
    local flat = st.dist * math.cos(pitch)
    local x = c.x - flat * math.sin(yaw)
    local y = c.y + flat * math.cos(yaw)
    local z = c.z + st.dist * math.sin(pitch)
    SetCamCoord(st.cam, x, y, z)
    PointCamAtCoord(st.cam, c.x, c.y, c.z)
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0) -- カメラのまわりを読み込ませる
end

local function deleteVehicle()
    if st.veh and DoesEntityExist(st.veh) then DeleteEntity(st.veh) end
    st.veh = nil
end

function Preview.active()
    return st.cam ~= nil
end

function Preview.start(shop)
    Preview.stop(true)
    st.shop = shop
    local p = shop.preview
    st.center = vec3(p.x, p.y, p.z + 1.0)
    st.yaw = p.w + Config.Camera.yawOffset
    st.pitch = Config.Camera.pitch
    st.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.x, p.y + 6.0, p.z + 2.0, 0.0, 0.0, 0.0, Config.Camera.fov, false, 2)
    SetCamActive(st.cam, true)
    RenderScriptCams(true, true, 600, true, true)
    placeCam()
end

-- モデルを出して、性能の表示に使う値を返す。読み込めなければ nil
function Preview.show(model, colorId)
    if not st.shop then return nil end
    st.token = st.token + 1
    local token = st.token
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    local loaded = pcall(lib.requestModel, hash, 10000)
    if not loaded or token ~= st.token or not st.shop then return nil end

    deleteVehicle()
    local p = st.shop.preview
    local veh = CreateVehicle(hash, p.x, p.y, p.z, p.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    if st.shop.kind ~= 'boat' then SetVehicleOnGroundProperly(veh) end
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleColours(veh, colorId, colorId)
    st.veh = veh
    st.color = colorId

    -- 大きさから、ちょうど収まる距離を決める（大型機でも画面に入る）
    local mn, mx = GetModelDimensions(hash)
    local half = #(mx - mn) / 2.0
    local fit = half / math.tan(math.rad(Config.Camera.fov / 2.0))
    st.center = GetOffsetFromEntityInWorldCoords(veh, (mn.x + mx.x) / 2.0, (mn.y + mx.y) / 2.0, (mn.z + mx.z) / 2.0)
    st.dist = fit * Config.Camera.fit
    st.minDist = fit * 0.6
    st.maxDist = fit * 1.8
    placeCam()

    local class = GetVehicleClassFromName(hash)
    return {
        ok = true,
        seats = GetVehicleModelNumberOfSeats(hash),
        speed = math.floor(GetVehicleModelEstimatedMaxSpeed(hash) * 3.6 + 0.5), -- m/s → km/h
        class = CLASS_LABEL[class] or '',
    }
end

function Preview.setColor(colorId)
    st.color = colorId
    if st.veh and DoesEntityExist(st.veh) then SetVehicleColours(st.veh, colorId, colorId) end
end

-- ドラッグの量（画面の px）で回す
function Preview.rotate(dx, dy)
    st.yaw = st.yaw - dx * 0.3
    st.pitch = clamp(st.pitch + dy * 0.2, -5.0, 60.0)
    placeCam()
end

-- ホイール。上で寄る、下で引く
function Preview.zoom(delta)
    st.dist = clamp(st.dist * (delta > 0 and 1.1 or 0.9), st.minDist, st.maxDist)
    placeCam()
end

-- instant = true は切り替えの途中（ゆっくり戻さない）
function Preview.stop(instant)
    st.token = st.token + 1
    deleteVehicle()
    if st.cam then
        RenderScriptCams(false, not instant, instant and 0 or 500, true, true)
        DestroyCam(st.cam, false)
        st.cam = nil
    end
    ClearFocus()
    st.shop = nil
end
