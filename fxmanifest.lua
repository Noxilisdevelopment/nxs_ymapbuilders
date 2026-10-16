fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Noxil'
description 'In-Game Prop Placer & YMAP Generator'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'gizmo/dataview.lua',
    'gizmo/gizmo.lua',
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/img/**/*',
    'gizmo/dataview.lua'
}
