fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ta-dealer'
description 'Car, boat and aircraft dealer with a live preview, private test drives and single-colour paint'
author 'Tani'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua',
    'shared/colors.lua'
}

client_scripts {
    'client/preview.lua',
    'client/testdrive.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/testdrive.lua'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_target',
    'qbx_core',
    'qbx_vehicles',
    'qbx_vehiclekeys'
}
