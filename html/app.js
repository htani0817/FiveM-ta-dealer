// ta-dealer の NUI。左に一覧、右下に選んだ乗り物と塗装、試乗中は上に残り時間
'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
const $ = (id) => document.getElementById(id);
const yen = (n) => `${Math.round(Number(n) || 0).toLocaleString('ja-JP')}円`;

// 外から来る文字（車名・メーカー名）は、必ずこれを通してから HTML に入れる
function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function post(name, data) {
    if (!RES) return Promise.resolve(Preview.post(name, data || {}));
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => null);
}

const ui = {
    shop: $('shop'),
    stage: $('stage'),
    tabs: $('tabs'),
    search: $('search'),
    rows: $('rows'),
    empty: $('empty'),
    detail: $('detail'),
    chips: $('chips'),
    actions: $('actions'),
    confirm: $('confirm'),
    test: $('test'),
};

let S = null;          // 開いている店の情報（shop, categories, list, colors, money, test）
let cat = 'all';       // 選んでいるタブ
let query = '';
let sel = null;        // 選んでいるモデル名
let color = null;      // 選んでいる塗装番号
let spec = {};         // モデル名 → 性能（プレビューから届いた値）
let confirming = false;
let busy = false;
let selectTimer = null;
let selectToken = 0;

const PAY_TEXT = { cash: '現金で払います', bank: '銀行から払います' };

// 決めた順（現金→銀行）に、足りる口座。実際に払うのはサーバーが決める
function payFrom(price) {
    if (!S || !S.money) return null;
    if (S.money.cash >= price) return 'cash';
    if (S.money.bank >= price) return 'bank';
    return null;
}

function visible() {
    if (!S) return [];
    const q = query.trim().toLowerCase();
    return S.list.filter((v) => (cat === 'all' || v.category === cat)
        && (!q || v.name.toLowerCase().includes(q) || v.brand.toLowerCase().includes(q) || v.model.includes(q)));
}

const item = (model) => S && S.list.find((v) => v.model === model);
const colorOf = (id) => S && S.colors.find((c) => c.id === id);

// ================== 左: 一覧 ==================

function renderTabs() {
    const counts = {};
    S.list.forEach((v) => { counts[v.category] = (counts[v.category] || 0) + 1; });
    const tabs = [{ id: 'all', label: 'すべて' }, ...S.categories.filter((c) => counts[c.id])];
    // タブが 1 つしかない店（ボート）では出さない
    ui.tabs.classList.toggle('hidden', tabs.length <= 2);
    ui.tabs.innerHTML = tabs.map((t) => `<button class="tab${t.id === cat ? ' on' : ''}" data-cat="${esc(t.id)}">${esc(t.label)}</button>`).join('');
}

function renderRows() {
    const list = visible();
    $('shop-count').textContent = `${list.length} 台`;
    ui.empty.classList.toggle('hidden', list.length > 0);
    ui.rows.innerHTML = list.map((v) => `<li class="row${v.model === sel ? ' sel' : ''}" data-model="${esc(v.model)}" tabindex="-1">
            <div class="row-text">
                <div class="row-name">${esc(v.name)}</div>
                <div class="row-brand">${esc(v.brand)}</div>
            </div>
            <span class="row-price num">${yen(v.price)}</span>
        </li>`).join('');
}

function scrollToSel() {
    const el = ui.rows.querySelector('.row.sel');
    if (el) el.scrollIntoView({ block: 'nearest' });
}

// ================== 右下: 選んだ乗り物 ==================

function renderChips() {
    ui.chips.innerHTML = S.colors.map((c) => `<button class="chip${c.id === color ? ' on' : ''}" role="radio" aria-checked="${c.id === color}"
            aria-label="${esc(c.name)}" data-color="${c.id}" style="--c:${esc(c.hex)}">
            <span class="chip-swatch"></span><span class="chip-no">${c.id}</span>
        </button>`).join('');
    const c = colorOf(color);
    $('p-name').textContent = c ? c.name : '';
    $('p-no').textContent = c ? `No.${c.id}` : '';
}

function renderDetail() {
    const v = item(sel);
    ui.detail.classList.toggle('hidden', !v);
    if (!v) return;
    const sp = spec[v.model];
    const catLabel = (S.categories.find((c) => c.id === v.category) || {}).label || '';
    $('d-kicker').textContent = [v.brand, catLabel].filter(Boolean).join(' · ');
    $('d-name').textContent = v.name;
    $('d-speed').textContent = sp && sp.ok ? sp.speed : '—';
    $('d-seats').textContent = sp && sp.ok ? sp.seats : '—';
    $('d-class').textContent = sp && sp.ok && sp.class ? sp.class : '—';
    ui.detail.classList.toggle('loading', !sp);
    $('d-price').textContent = yen(v.price);
    const from = payFrom(v.price);
    const pay = $('d-pay');
    pay.textContent = from ? PAY_TEXT[from] : 'お金が足りません';
    pay.classList.toggle('short', !from);
    $('buy-btn').disabled = !from || busy;
    $('confirm-btn').textContent = from === 'bank' ? '銀行から払って購入' : '現金で払って購入';
    $('test-len').textContent = S.test && S.test.seconds ? `${Math.round(S.test.seconds / 60)}分` : '';
    ui.actions.classList.toggle('hidden', confirming);
    ui.confirm.classList.toggle('hidden', !confirming);
}

// 選んだら、少し待ってからプレビューを頼む（矢印キーで流したときに毎回読み込まない）
function choose(model, immediate) {
    if (!model || model === sel) return;
    sel = model;
    confirming = false;
    renderRows();
    renderDetail();
    scrollToSel();
    clearTimeout(selectTimer);
    const token = ++selectToken;
    const run = () => post('select', { model, color }).then((r) => {
        if (token !== selectToken) return;
        spec[model] = r && r.ok ? r : { ok: false };
        renderDetail();
    });
    if (immediate) run(); else selectTimer = setTimeout(run, 160);
}

function move(step) {
    const list = visible();
    if (!list.length) return;
    const i = list.findIndex((v) => v.model === sel);
    const next = list[Math.max(0, Math.min(list.length - 1, (i < 0 ? 0 : i + step)))];
    choose(next.model, false);
}

// ================== 開く・閉じる ==================

function open(data) {
    S = {
        shop: data.shop,
        categories: data.categories || [],
        list: data.list || [],
        colors: data.colors || [],
        money: data.money || { cash: 0, bank: 0 },
        test: data.test || {},
    };
    cat = 'all';
    query = '';
    ui.search.value = '';
    sel = null;
    spec = {};
    confirming = false;
    busy = false;
    color = S.colors.length ? S.colors[0].id : 0;
    $('shop-name').textContent = S.shop.label;
    renderTabs();
    renderChips();
    ui.shop.classList.remove('hidden');
    if (S.list.length) choose(S.list[0].model, true);
    renderRows();
}

function hide() {
    ui.shop.classList.add('hidden');
    S = null;
    sel = null;
    clearTimeout(selectTimer);
}

function close() {
    if (!S) return;
    hide();
    post('close');
}

// ================== 操作 ==================

ui.tabs.addEventListener('click', (e) => {
    const b = e.target.closest('[data-cat]');
    if (!b) return;
    cat = b.dataset.cat;
    renderTabs();
    renderRows();
    const list = visible();
    if (list.length && !list.some((v) => v.model === sel)) choose(list[0].model, true);
});

ui.search.addEventListener('input', () => {
    query = ui.search.value;
    renderRows();
});

ui.rows.addEventListener('click', (e) => {
    const r = e.target.closest('[data-model]');
    if (r) choose(r.dataset.model, true);
});

ui.chips.addEventListener('click', (e) => {
    const b = e.target.closest('[data-color]');
    if (!b) return;
    color = Number(b.dataset.color);
    renderChips();
    post('color', { color });
});

document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b || !S) return;
    const act = b.dataset.act;
    if (act === 'close') close();
    else if (act === 'buy') { confirming = true; renderDetail(); }
    else if (act === 'cancel') { confirming = false; renderDetail(); }
    else if (act === 'confirm') buy();
    else if (act === 'test') test();
});

function buy() {
    if (busy || !sel) return;
    busy = true;
    $('confirm-btn').disabled = true;
    post('buy', { model: sel, color }).then((r) => {
        busy = false;
        $('confirm-btn').disabled = false;
        if (r && r.ok) { hide(); return; }
        confirming = false;
        if (S) renderDetail();
    });
}

function test() {
    if (busy || !sel) return;
    busy = true;
    const model = sel;
    hide();
    post('test', { model, color }).then(() => { busy = false; });
}

// ドラッグで回す。送るのは 1 コマに 1 回まで
let drag = null;
let pending = { dx: 0, dy: 0 };
let frame = 0;
function flushRotate() {
    frame = 0;
    if (!pending.dx && !pending.dy) return;
    post('rotate', pending);
    pending = { dx: 0, dy: 0 };
}

ui.stage.addEventListener('pointerdown', (e) => {
    drag = { x: e.clientX, y: e.clientY };
    ui.stage.setPointerCapture(e.pointerId);
    ui.stage.classList.add('dragging');
});

ui.stage.addEventListener('pointermove', (e) => {
    if (!drag) return;
    pending.dx += e.clientX - drag.x;
    pending.dy += e.clientY - drag.y;
    drag = { x: e.clientX, y: e.clientY };
    if (!frame) frame = requestAnimationFrame(flushRotate);
});

const endDrag = () => { drag = null; ui.stage.classList.remove('dragging'); };
ui.stage.addEventListener('pointerup', endDrag);
ui.stage.addEventListener('pointercancel', endDrag);

ui.stage.addEventListener('wheel', (e) => {
    post('zoom', { delta: e.deltaY });
}, { passive: true });

document.addEventListener('keydown', (e) => {
    if (!S) return;
    if (e.key === 'Escape') {
        if (confirming) { confirming = false; renderDetail(); } else close();
        e.preventDefault();
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        move(e.key === 'ArrowDown' ? 1 : -1);
        e.preventDefault();
    }
});

// ================== 試乗中 ==================

let testTimer = null;
function startTest(m) {
    clearInterval(testTimer);
    const ends = Date.now() + (Number(m.seconds) || 0) * 1000;
    $('t-name').textContent = m.name || '';
    $('t-key').textContent = m.key || '';
    const tick = () => {
        const left = Math.max(0, Math.ceil((ends - Date.now()) / 1000));
        const t = $('t-time');
        t.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`;
        t.classList.toggle('low', left <= 30);
        if (left === 0) clearInterval(testTimer);
    };
    tick();
    testTimer = setInterval(tick, 250);
    ui.test.classList.remove('hidden');
}

function endTest() {
    clearInterval(testTimer);
    ui.test.classList.add('hidden');
}

// ================== メッセージ ==================

let uiScale = 1;
function applyScale() {
    const base = window.innerHeight / 1080;
    document.documentElement.style.setProperty('--scale', (base * (Number(uiScale) || 1)).toFixed(3));
}
window.addEventListener('resize', applyScale);
applyScale();

window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    if (m.scale != null) {
        uiScale = Number(m.scale) || 1;
        applyScale();
    }
    if (m.action === 'open') open(m);
    else if (m.action === 'close') hide();
    else if (m.action === 'test') startTest(m);
    else if (m.action === 'testEnd') endTest();
});

// ================== ブラウザ単体の確認用 ==================
// FiveM の外（RES が無いとき）だけ使う。値はそれらしい見本で、実際の店の値ではない

const Preview = {
    specs: {
        blista: { seats: 4, speed: 158, class: 'コンパクト' },
        kuruma: { seats: 4, speed: 186, class: 'スポーツ' },
        sultan: { seats: 4, speed: 178, class: 'セダン' },
        baller: { seats: 4, speed: 164, class: 'SUV' },
        dominator: { seats: 2, speed: 190, class: 'マッスル' },
    },
    post(name, data) {
        if (name === 'select') {
            const s = this.specs[data.model] || { seats: 2, speed: 172, class: 'クーペ' };
            return Object.assign({ ok: true }, s);
        }
        if (name === 'buy') return { ok: false, message: '見本の画面では買えません' };
        return {};
    },
    data() {
        const cars = [
            ['blista', 'Blista', 'Dinka', 'compacts', 1600000],
            ['issi2', 'Issi', 'Weeny', 'compacts', 1800000],
            ['panto', 'Panto', 'Benefactor', 'compacts', 850000],
            ['asea', 'Asea', 'Declasse', 'sedans', 1250000],
            ['sultan', 'Sultan', 'Karin', 'sedans', 2400000],
            ['schafter2', 'Schafter', 'Benefactor', 'sedans', 3100000],
            ['tailgater', 'Tailgater', 'Obey', 'sedans', 2900000],
            ['oracle', 'Oracle XS', 'Übermacht', 'coupes', 3500000],
            ['felon', 'Felon', 'Lampadati', 'coupes', 4200000],
            ['baller', 'Baller', 'Gallivanter', 'suvs', 4600000],
            ['granger', 'Granger', 'Declasse', 'suvs', 3800000],
            ['dominator', 'Dominator', 'Vapid', 'muscle', 3500000],
            ['gauntlet', 'Gauntlet', 'Bravado', 'muscle', 3200000],
            ['bati', 'Bati 801', 'Pegassi', 'motorcycles', 1450000],
            ['bmx', 'BMX', '', 'cycles', 16000],
        ].map(([model, name, brand, category, price]) => ({ model, name, brand, category, price }));
        cars.sort((a, b) => a.price - b.price);
        return {
            shop: { id: 'car', label: 'Premium Deluxe Motorsport', kind: 'car' },
            categories: [
                { id: 'compacts', label: 'コンパクト' }, { id: 'sedans', label: 'セダン' }, { id: 'coupes', label: 'クーペ' },
                { id: 'suvs', label: 'SUV' }, { id: 'muscle', label: 'マッスル' }, { id: 'sportsclassics', label: 'クラシック' },
                { id: 'offroad', label: 'オフロード' }, { id: 'vans', label: 'バン' }, { id: 'motorcycles', label: 'バイク' },
                { id: 'cycles', label: '自転車' },
            ],
            list: cars,
            colors: [
                [0, 'ブラック', '#0d1116'], [147, 'カーボンブラック', '#15171b'], [1, 'グラファイト', '#1f2124'], [3, 'ダークスチール', '#3c3f43'],
                [4, 'シルバー', '#a3a7ad'], [111, 'アイスホワイト', '#f1f1ee'], [107, 'クリーム', '#d9ccad'], [27, 'レッド', '#b5111b'],
                [28, 'トリノレッド', '#d01a1c'], [143, 'ワインレッド', '#5f1a25'], [38, 'オレンジ', '#e9781a'], [88, 'イエロー', '#f2c524'],
                [90, 'ブロンズ', '#8f643c'], [96, 'チョコレートブラウン', '#33241a'], [49, 'ダークグリーン', '#16332c'], [50, 'レーシンググリーン', '#1b4232'],
                [92, 'ライムグリーン', '#8fc02a'], [61, 'ギャラクシーブルー', '#1e2a47'], [64, 'ブルー', '#21509b'], [70, 'ウルトラブルー', '#1364c8'],
                [74, 'ライトブルー', '#62a6d0'], [71, 'シャフターパープル', '#352c55'], [135, 'ホットピンク', '#e2318f'], [158, 'ピュアゴールド', '#b88f4e'],
            ].map(([id, name, hex]) => ({ id, name, hex })),
            money: { cash: 2850000, bank: 18400000 },
            test: { seconds: 180 },
        };
    },
};

if (!RES) {
    document.body.classList.add('preview');
    const p = new URLSearchParams(location.search);
    if (p.get('view') === 'test') startTest({ name: 'Sultan', seconds: 161, key: 'F7' });
    else open(Preview.data());
}
