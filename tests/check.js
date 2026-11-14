// Lua の構文と、未定義のグローバル参照を調べる（ta-jobswitch の check.js と同じ方法）
// node check.js <リソースのフォルダ>
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
const dir = process.argv[2];
const files = ['fxmanifest.lua', 'config.lua', 'shared/colors.lua', 'server/main.lua', 'server/testdrive.lua',
  'client/preview.lua', 'client/testdrive.lua', 'client/main.lua'];
const known = new Set((
  // このリソースのグローバル
  'Config Colors ColorById Dealer Preview TestDrive ' +
  // ox_lib・qbx_core・oxmysql・FiveM の Lua
  'lib cache qbx exports json source MySQL vec3 vec4 joaat Entity Player ' +
  'print pairs ipairs type tostring tonumber math table string os next select error assert pcall setmetatable ' +
  'CreateThread Wait SetTimeout GetGameTimer TriggerClientEvent TriggerServerEvent TriggerEvent AddEventHandler RegisterNetEvent ' +
  'RegisterCommand RegisterKeyMapping GetCurrentResourceName GetResourceState ' +
  // server の native
  'GetPlayerPed GetEntityCoords GetAllVehicles GetEntityRoutingBucket SetRoutingBucketPopulationEnabled SetEntityCoords SetEntityHeading GetEntityHeading ' +
  'DoesEntityExist DeleteEntity ' +
  // client の native
  'SendNUIMessage RegisterNUICallback SetNuiFocus IsNuiFocused IsPauseMenuActive IsEntityDead ' +
  'IsScreenFadedOut IsScreenFadingOut DoScreenFadeIn DoScreenFadeOut ' +
  'AddBlipForCoord SetBlipSprite SetBlipColour SetBlipScale SetBlipAsShortRange BeginTextCommandSetBlipName ' +
  'AddTextComponentSubstringPlayerName EndTextCommandSetBlipName RemoveBlip ' +
  'CreatePed SetBlockingOfNonTemporaryEvents SetPedCanRagdoll ' +
  'CreateCamWithParams SetCamActive RenderScriptCams DestroyCam SetCamCoord PointCamAtCoord SetFocusPosAndVel ClearFocus ' +
  'IsModelInCdimage IsModelAVehicle CreateVehicle SetModelAsNoLongerNeeded SetVehicleOnGroundProperly FreezeEntityPosition ' +
  'SetEntityInvincible SetVehicleDoorsLocked SetVehicleDirtLevel SetVehicleColours GetModelDimensions ' +
  'GetOffsetFromEntityInWorldCoords GetVehicleClassFromName GetVehicleModelNumberOfSeats GetVehicleModelEstimatedMaxSpeed ' +
  // fxmanifest
  'fx_version game lua54 name description author version ui_page files shared_scripts client_scripts server_scripts dependencies'
).split(/\s+/));
let bad = 0;
for (const f of files) {
  const src = fs.readFileSync(path.join(dir, f), 'utf8');
  if (src.charCodeAt(0) === 0xfeff) { console.log(f, 'BOM あり'); bad++; }
  if (src.includes('\r')) { console.log(f, 'CR あり'); bad++; }
  let ast;
  try {
    ast = luaparse.parse(src, { scope: true, luaVersion: '5.3' });
  } catch (e) { console.log(f, '構文エラー', e.message); bad++; continue; }
  const globals = new Set();
  (function walk(n) {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) return n.forEach(walk);
    if (n.type === 'Identifier' && n.isLocal === false && !known.has(n.name)) globals.add(n.name);
    for (const k in n) if (k !== 'type') walk(n[k]);
  })(ast.body);
  if (globals.size) bad++;
  console.log(f, 'OK', globals.size ? '未知のグローバル: ' + [...globals].join(', ') : '');
}
// fxmanifest の dependencies はクライアントでも確かめられる。サーバーだけのリソースを書くと接続できなくなる
// （1.0.0 で qbx_vehicles を書いて、接続時に「Couldn't start resource ta-dealer」になった）
const SERVER_ONLY = ['qbx_vehicles'];
const manifest = fs.readFileSync(path.join(dir, 'fxmanifest.lua'), 'utf8');
const deps = (manifest.match(/dependencies\s*\{([^}]*)\}/) || [, ''])[1];
for (const r of SERVER_ONLY) {
  if (deps.includes(`'${r}'`)) { console.log('fxmanifest.lua', `dependencies にサーバーだけのリソース ${r} がある`); bad++; }
}
// NUI のファイルも BOM と CR を調べる
for (const f of ['html/index.html', 'html/style.css', 'html/app.js']) {
  const src = fs.readFileSync(path.join(dir, f), 'utf8');
  if (src.charCodeAt(0) === 0xfeff) { console.log(f, 'BOM あり'); bad++; }
  if (src.includes('\r')) { console.log(f, 'CR あり'); bad++; }
}
process.exit(bad ? 1 : 0);
