---
title: ta-dealer（車・船・飛行機のディーラー）
date: 2026-11-14
tags:
  - コーディング/fivem
status: 実装済み（FiveM 実機は未確認）
aliases:
  - ta-dealer
related:
  - "[[FiveM-Script/README|FiveM-Script 目次]]"
---

# ta-dealer（車・船・飛行機のディーラー）

Qbox サーバー向けの乗り物の販売店。窓口で一覧を開いて車種を選ぶと、ショールームに実物が出る。ドラッグで回して見られ、塗装は 24 色の見本から 1 色を選ぶ。そのまま買うこともできるし、専用の空間で試乗することもできる。

qbx_vehicleshop の 3 店（Premium Deluxe Motorsport・ボート販売店・航空機販売店）を置き換える。場所は今と同じで、売る車種もできるだけ今に揃えた（[売る車種](#売る車種)）。

> [!WARNING]
> **FiveM 実機は未確認**
>
> サーバー側とクライアント側の流れは疑似環境で、画面はブラウザで確かめた（[テスト](#テスト)）。ゲーム内での確認はまだしていない。確かめたいことは [実機で確かめること](#実機で確かめること) にまとめた。

## 使い方

| 操作 | 内容 |
| --- | --- |
| 窓口で ox_target「乗り物を見る」 | 一覧を開く。カメラがショールームに切り替わる |
| 一覧の行をクリック、`↑` `↓` | 車種を選ぶ。選んだ車種の実物が出る |
| 何もない所をドラッグ | 乗り物のまわりを回る |
| ホイール | 寄る・引く |
| 塗装のチップ | 色を選ぶ。実物がその場で塗り替わる |
| 購入 → 支払って購入 | 2 回押すと買える。1 回目で「現金で払って購入」などに変わる |
| 試乗 | 専用の空間で 3 分走らせる |
| `F7`（試乗中） | 試乗をやめる |
| `Esc` | 閉じる。確認中なら確認をやめる |

- 支払いは現金で足りれば現金、足りなければ銀行から全額（qbx_vehicleshop と同じ）。ローンは無い
- 買った乗り物は店の前の受け渡し場所に出て、そのまま乗った状態になる。鍵も渡す
- 塗装は 1 色目と 2 色目に同じ番号を塗る（単色）。DB の `mods` に `color1` と `color2` が残るので、ガレージから出し直しても色は変わらない
- 倒れている間（`isdead` / `inlaststand`）、手錠中（`ishandcuffed`）、試乗中は使えない

## 画面

方向は「夜のショールームと塗装の見本帳」。主役はゲーム内の実物の乗り物なので、パネルは左（一覧）と右下（選んだ乗り物）に寄せ、中央を空けてある。灰色の土台は ta-jobswitch・ta-fishing と同じ。色を持つのは塗装のチップだけで、差し色の真鍮は購入ボタンと選んでいる行の印にだけ使う。チップの下には GTA の塗装番号を添えた。

- 性能の欄（最高速・座席・種類）は、ゲームの native（`GetVehicleModelEstimatedMaxSpeed` など）から取った値をそのまま出す。最高速はゲームの推定値
- 大きさは「画面の高さ / 1080 × `Config.UiScale`」
- 試乗中は画面の上に「試乗 車名 残り時間 F7 やめる」を出す。残り 30 秒で時間が赤くなる
- ブラウザで `html/index.html` を開くと見本が出る（値は見本で、実際の店の値ではない）。`?view=test` で試乗中の表示

## 導入

1. このフォルダを `resources/[standalone]/ta-dealer` に置く（`tests/` は要らない）。server.cfg は `ensure [standalone]` で読み込まれるので変更不要
2. qbx_vehicleshop を止める（`resources/[qbx]/qbx_vehicleshop` を `resources/[disabled]/` へ移す）。止めないと同じ場所に店が 2 つできる
3. 船・空の買った乗り物を専用ガレージに入れたいときは、`/garageadmin` でガレージの ID を見て `Config.Shops.boat.garageId` と `air.garageId` に書く
4. サーバーを再起動する

> [!WARNING]
> **qbx_vehicleshop を止めると無くなるもの**
>
> - `/transfervehicle`（乗り物を人に譲る）
> - ローン（分割払い）の支払い。すでにローンで買った人がいると、残りの支払いが止まる
> - managed 店（cardealer のジョブが売る店）。今の設定では使っていない
>
> 止める前に、ローン中の乗り物（`vehicle_financing` の表）が無いか確かめる。

依存: ox_lib、oxmysql、ox_target、qbx_core（`@qbx_core/modules/lib.lua` の `qbx.spawnVehicle`）、qbx_vehicles 1.4.1 以上、qbx_vehiclekeys、okokNotify。燃料は lc_fuel が `fuelLevel` を読むので、満タンで出る。qbx_vehicles はサーバーだけのリソースでクライアントに配られないので、`fxmanifest.lua` の `dependencies` には書かず、`server/main.lua` の `lib.checkDependency` で確かめる（`dependencies` に書くと、接続時に「Couldn't start resource ta-dealer」で入れなくなる）。

> [!NOTE]
> **キーの割り当て**
>
> `Config.TestDrive.endKey` は、まだこのキーを割り当てていないプレイヤーにだけ効く（FiveM の `RegisterKeyMapping` の仕様）。あとで変えた場合、すでに遊んだプレイヤーは「設定 → キー割り当て → FiveM → 試乗をやめる」で各自変える。

## 設定（config.lua）

| 項目 | 既定 | 内容 |
| --- | --- | --- |
| `UiScale` | `1.0` | 画面の大きさの倍率 |
| `Debug` | `false` | ox_target の円を見えるようにする |
| `CounterRange` | `8.0` | 窓口から何 m 以内なら開く・買う・試乗できるか（サーバーで確かめる） |
| `Shops` | 3 店 | 店ごとの設定（下の表） |
| `Blocklist` | 6 台 | どの店でも売らないモデル |
| `Payment` | `{ 'cash', 'bank' }` | 支払いに使う口座の順 |
| `TestDrive.seconds` | `180` | 試乗の時間（秒） |
| `TestDrive.cooldown` | `60` | 試乗が終わってから次の試乗までの間（秒） |
| `TestDrive.bucketBase` | `4200` | 試乗の空間の番号の始まり。プレイヤー ID を足して使う |
| `TestDrive.endKey` | `'F7'` | 試乗をやめるキー |
| `Camera` | 4 項目 | 画角・引き具合・見下ろす角度・写し始める向き |

`Shops` の中身:

| 項目 | 内容 |
| --- | --- |
| `label` | 店の名前（一覧の見出しと地図） |
| `kind` | `'car'` / `'boat'` / `'air'`。船はプレビューで地面に合わせない |
| `counter` | 窓口。ox_target の円（半径 1.5m）を置く |
| `blip` | 地図の印 |
| `categories` | 一覧のタブ。qbx_core の `category` と表示名。並びはこの順 |
| `models` | 書いたときは、このモデルだけを売る |
| `preview` | 実物を出す場所。自分にだけ見える |
| `deliver` | 買った乗り物を出す場所。上から順に空いている所 |
| `clearRadius` | `deliver` が空いているとみなす半径（m） |
| `testDrive` | 試乗を始める場所 |
| `garageId` | jg-advancedgarages のガレージ ID。書いたら買った乗り物の `garage_id` をこれにする |

### 売る車種

値段は qbx_core の `shared/vehicles.lua`（円に直したもの）をそのまま使う。

- 車の店: qbx_vehicleshop の pdm と同じ 10 種類（コンパクト・セダン・クーペ・SUV・マッスル・クラシック・オフロード・バン・バイク・自転車）。スポーツとスーパーは今も売っていないので、`categories` でコメントにしてある
- ボートの店: `boats` の全部
- 航空機の店: qbx_vehicleshop で売っていた民間機 27 機（`models`）。軍用機などは足さない限り売らない
- `Blocklist`: パトカー 4 台と、qbx_vehicleshop では luxury 店あつかいで出ていなかった `oppressor` と `cheetah2`

## 仕組み

値段・扱う車種・色・距離の判定はすべてサーバー側。クライアントから来た値は信じない。

| コールバック・イベント | 内容 |
| --- | --- |
| `ta-dealer:catalog(shopId)` | 窓口の近くか確かめて、一覧と所持金を返す |
| `ta-dealer:buy(shopId, model, color)` | 支払い → `CreatePlayerVehicle`（props に `color1`・`color2`）→ `qbx.spawnVehicle` → `GiveKeys` → `SetLockState('unlock')` |
| `ta-dealer:testDrive(shopId, model, color)` | 専用の空間へ移して試乗車を出す |
| `ta-dealer:endTest`（client → server） | `F7` か、試乗中に倒れたとき |

購入の流れで気を付けていること:

- 受け渡し場所が全部ふさがっていたら、代金を取る前に断る。ふさがりは、いつもの空間（bucket 0）の車両だけで数える
- DB への登録が失敗・エラーになったら、払った口座へ返金する
- 登録はできたのに出せなかったときは返金しない。「ガレージから出してください」と知らせる
- 鍵を渡したあとに開けた状態を付ける。付けないと、乗り直すときに qbx_vehiclekeys が 75% で鍵を掛ける（qbox-server の PR #35 と同じ理由）
- 二重に押されても 1 台だけ（手続き中は次を断る）

試乗の流れ:

1. 立っている場所を覚えて、プレイヤーを専用の空間（`bucketBase + ID`）へ移す。その空間には車や歩行者を出さない
2. 試乗地点へ移してから、同じ空間に試乗車を出して乗せる（遠くに車両を出すと、持ち主が決まらず出せないため）。ナンバーは `TEST` で始まり、DB には入らない
3. 時間切れ・`F7`・倒れたときは、画面を暗くして、試乗車と仮の鍵を消し、いつもの空間の、試乗を始めた場所（窓口の前）へ戻す
4. 切断したときは試乗車だけ消す。リソースを止めたときは、試乗中の全員を戻す

試乗地点の既定は、車と空がロスサントス国際空港（航空機販売店の前の誘導路）、船が販売店の前の海。車も空港で走らせる。

プレビューは `CreateVehicle(..., isNetwork = false)` のローカル車両で、ほかのプレイヤーには見えない。カメラの距離は `GetModelDimensions` から決めるので、大型機でも画面に収まる。

## テスト

`tests/` に、ta-jobswitch と同じ方法のテストがある。

```sh
npm i fengari luaparse          # 作業用のフォルダで（NODE_PATH をそこへ向ける）
node tests/check.js .           # Lua の構文・未定義のグローバル、BOM と CR
node tests/run-test.js . tests/test-server.lua
node tests/run-test.js . tests/test-client.lua
node tests/ui-shot.js "file:///<このフォルダ>/html/index.html" <出力先> "wait:500,shot:open" 1920x1080
```

- `test-server.lua`: カタログの絞り込み、店に無い車種・見本帳に無い色・窓口から遠い・お金が足りない・倒れている・手錠を断る、現金 → 銀行の順、DB に色が入る、鍵のあとに解錠、受け渡し場所のふさがり（試乗の空間の車両は数えない）、登録失敗とエラーで返金、出せなくても登録は残る、`garageId`、試乗の空間・時間切れ・やめる・切断・停止・出せなかったとき・クールダウン（2026-11-14 時点で 68 件）。`check.js` は、`dependencies` にサーバーだけのリソースが無いかも見る
- `test-client.lua`: 窓口から開く流れ、プレビューの車両はネットワークに出さない、選んだ色で塗る、見本帳に無い色は使わない、買えたら閉じる、試乗中は窓口を開かない、倒れたら知らせる（30 件）
- `ui-shot.js`: ヘッドレス Chromium で画面を撮る。1920×1080 と 1280×720 で確かめた

## 実機で確かめること

- 3 店それぞれで、窓口の円の位置（`counter`）とプレビューの場所。大型機（Luxor・Nimbus など）が画面に収まるか、船が水面に浮いて見えるか
- 選んだ色が実物に出るか。チップの色はゲームの色に近づけた目安
- 買ったあと、鍵が使えて、ガレージに入れて出し直しても色が残るか
- 試乗中、ほかのプレイヤーから見えないこと。時間切れと `F7` で窓口の前へ戻ること
- 車で空港を試乗するときに、走りにくくないか

## 既知の制約

- プレビューの最高速は、ゲームの推定値（`GetVehicleModelEstimatedMaxSpeed`）。改造やハンドリングの違いは入らない
- 試乗中にキャラクターを切り替える（ログアウトする）と、試乗車は時間切れまで残る。時間切れで消える
- jg-advancedgarages の `in_garage` は既定の `1` のまま（qbx_vehicleshop で買ったときと同じ）

## ライセンス

MIT License（`LICENSE`）
