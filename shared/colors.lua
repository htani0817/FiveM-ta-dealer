-- ta-dealer 色見本帳（client / server の両方から読み込まれる）
-- id は GTA の塗装番号（https://docs.fivem.net/docs/game-references/vehicle-references/vehicle-colors/ で名前のある番号から選んだ）
-- 車体の 1 色目と 2 色目の両方にこの番号を塗る（単色）
-- hex は画面のチップに出すだけの近い色。本当の色は、プレビューの実物で見る
Colors = {
    { id = 0,   name = 'ブラック',           hex = '#0d1116' },
    { id = 147, name = 'カーボンブラック',   hex = '#15171b' },
    { id = 1,   name = 'グラファイト',       hex = '#1f2124' },
    { id = 3,   name = 'ダークスチール',     hex = '#3c3f43' },
    { id = 4,   name = 'シルバー',           hex = '#a3a7ad' },
    { id = 111, name = 'アイスホワイト',     hex = '#f1f1ee' },
    { id = 107, name = 'クリーム',           hex = '#d9ccad' },
    { id = 27,  name = 'レッド',             hex = '#b5111b' },
    { id = 28,  name = 'トリノレッド',       hex = '#d01a1c' },
    { id = 143, name = 'ワインレッド',       hex = '#5f1a25' },
    { id = 38,  name = 'オレンジ',           hex = '#e9781a' },
    { id = 88,  name = 'イエロー',           hex = '#f2c524' },
    { id = 90,  name = 'ブロンズ',           hex = '#8f643c' },
    { id = 96,  name = 'チョコレートブラウン', hex = '#33241a' },
    { id = 49,  name = 'ダークグリーン',     hex = '#16332c' },
    { id = 50,  name = 'レーシンググリーン', hex = '#1b4232' },
    { id = 92,  name = 'ライムグリーン',     hex = '#8fc02a' },
    { id = 61,  name = 'ギャラクシーブルー', hex = '#1e2a47' },
    { id = 64,  name = 'ブルー',             hex = '#21509b' },
    { id = 70,  name = 'ウルトラブルー',     hex = '#1364c8' },
    { id = 74,  name = 'ライトブルー',       hex = '#62a6d0' },
    { id = 71,  name = 'シャフターパープル', hex = '#352c55' },
    { id = 135, name = 'ホットピンク',       hex = '#e2318f' },
    { id = 158, name = 'ピュアゴールド',     hex = '#b88f4e' },
}

-- 番号から引く表
ColorById = {}
for i = 1, #Colors do
    ColorById[Colors[i].id] = Colors[i]
end
