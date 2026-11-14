-- ta-dealer 設定ファイル（client / server の両方から読み込まれる）
Config = {}

-- ================== 画面 ==================

-- 画面の大きさの倍率。縦1080pxの画面を基準に、画面の高さに合わせて自動で拡大・縮小したうえで掛ける
Config.UiScale = 1.0

-- 窓口の円や位置を確かめるとき true（ox_target の円が見える）
Config.Debug = false

-- ================== 店 ==================

-- 窓口から何 m 以内なら、一覧を開く・買う・試乗できるか（サーバーで確かめる）
Config.CounterRange = 8.0

-- 店ごとの設定
--   kind       店の種類。'car' / 'boat' / 'air'
--   counter    窓口。ここに ox_target の円を置く
--   categories 一覧のタブ。qbx_core の shared/vehicles.lua の category と、画面に出す名前。並びはこの順
--   models     書いたときは、このモデルだけを売る（書かなければ categories に合う車両をすべて売る）
--   preview    実物を見せる場所（ローカルの車両なので、ほかのプレイヤーには見えない）
--   deliver    買った乗り物を出す場所。上から順に、空いている所を使う
--   clearRadius deliver が空いているとみなす半径（m）
--   testDrive  試乗を始める場所。専用の空間（routing bucket）なので、ほかのプレイヤーはいない
--              試乗が終わったら、始めたときに立っていた場所（窓口の前）へ戻す
--   garageId   jg-advancedgarages のガレージ ID。書いたときは、買った乗り物の garage_id をこれにする
--              （書かなければ jg の既定のまま。船・空は専用ガレージの ID を /garageadmin で見て書く）
Config.Shops = {
    car = {
        label = 'Premium Deluxe Motorsport',
        kind = 'car',
        counter = vec3(-29.53, -1103.67, 26.42),
        blip = { coords = vec3(-45.67, -1098.34, 26.42), sprite = 326, color = 3 },
        categories = {
            { id = 'compacts', label = 'コンパクト' },
            { id = 'sedans', label = 'セダン' },
            { id = 'coupes', label = 'クーペ' },
            { id = 'suvs', label = 'SUV' },
            { id = 'muscle', label = 'マッスル' },
            { id = 'sportsclassics', label = 'クラシック' },
            { id = 'offroad', label = 'オフロード' },
            { id = 'vans', label = 'バン' },
            { id = 'motorcycles', label = 'バイク' },
            { id = 'cycles', label = '自転車' },
            -- スポーツカーやスーパーカーも売るときは、下の行の先頭の -- を外す
            -- { id = 'sports', label = 'スポーツ' },
            -- { id = 'super', label = 'スーパー' },
        },
        preview = vec4(-45.65, -1093.66, 25.44, 69.5),
        deliver = {
            vec4(-61.35, -1110.31, 25.86, 71.01),
            vec4(-59.61, -1104.74, 25.85, 70.13),
            vec4(-52.96, -1113.49, 25.87, 71.53),
            vec4(-52.34, -1107.93, 25.87, 71.63),
            vec4(-44.27, -1116.36, 25.87, 71.7),
            vec4(-41.75, -1111.49, 25.87, 71.5),
        },
        clearRadius = 3.0,
        testDrive = vec4(-1617.49, -3086.17, 13.94, 329.2), -- ロスサントス国際空港（LSIA）
        garageId = nil,
    },

    boat = {
        label = 'ボート販売店',
        kind = 'boat',
        counter = vec3(-738.25, -1334.38, 1.6),
        blip = { coords = vec3(-738.25, -1334.38, 1.6), sprite = 410, color = 3 },
        categories = {
            { id = 'boats', label = 'ボート' },
        },
        preview = vec4(-741.53, -1349.7, 0.0, 229.5),
        deliver = {
            vec4(-727.87, -1353.1, -0.17, 137.09),
        },
        clearRadius = 6.0,
        testDrive = vec4(-727.87, -1353.1, -0.17, 137.09), -- 販売店の前の海
        garageId = nil,
    },

    air = {
        label = '航空機販売店',
        kind = 'air',
        counter = vec3(-1652.76, -3143.4, 13.99),
        blip = { coords = vec3(-1652.76, -3143.4, 13.99), sprite = 251, color = 3 },
        categories = {
            { id = 'helicopters', label = 'ヘリ' },
            { id = 'planes', label = '飛行機' },
        },
        -- 今まで qbx_vehicleshop が売っていた民間機だけ。軍用機などはここに足さない限り売らない
        models = {
            'buzzard2', 'frogger', 'frogger2', 'maverick', 'swift', 'swift2', 'seasparrow', 'seasparrow2',
            'seasparrow3', 'supervolito', 'supervolito2', 'volatus', 'havok',
            'duster', 'luxor', 'luxor2', 'stunt', 'mammatus', 'velum', 'velum2', 'shamal', 'vestra',
            'dodo', 'howard', 'alphaz1', 'nimbus', 'conada',
        },
        preview = vec4(-1668.53, -3152.56, 12.99, 303.22),
        deliver = {
            vec4(-1617.49, -3086.17, 13.94, 329.2),
        },
        clearRadius = 12.0,
        testDrive = vec4(-1617.49, -3086.17, 13.94, 329.2), -- LSIA の誘導路。滑走路まで自分で走る
        garageId = nil,
    },
}

-- どの店でも売らないモデル
-- 今まで qbx_vehicleshop が売っていなかったもの（パトカーと、luxury 店あつかいで出ていなかった 2 台）
Config.Blocklist = {
    police = true,
    police2 = true,
    police3 = true,
    police4 = true,
    oppressor = true,
    cheetah2 = true,
}

-- 支払いに使う口座。上から順に、足りる所から全額を払う（qbx_vehicleshop と同じ）
Config.Payment = { 'cash', 'bank' }

-- ================== 試乗 ==================

Config.TestDrive = {
    seconds = 180,      -- 試乗できる時間（秒）
    cooldown = 60,      -- 試乗が終わってから、次の試乗までに空ける時間（秒）
    bucketBase = 4200,  -- 専用空間の番号の始まり。プレイヤーの ID を足して使う（ほかのスクリプトと重ならない数にする）
    endKey = 'F7',      -- 途中でやめるキー（FiveM のキー設定に「試乗をやめる」として登録される）
}

-- ================== カメラ ==================

Config.Camera = {
    fov = 40.0,       -- 画角
    fit = 1.15,       -- 乗り物がちょうど収まる距離に掛ける倍率。大きいほど引いて写す
    pitch = 12.0,     -- 見下ろす角度の初期値（度）
    yawOffset = 35.0, -- 乗り物の正面から何度まわした所から写し始めるか
}
