fx_version 'cerulean'
game 'gta5'

name 'Eclipse Homeless'
author 'Eclipse RP'
description 'Homeless RP'
version '1.2.0'

shared_scripts { 'config.lua' }

client_scripts { 'client.lua' }

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies {
    'qb-core',
    'ox_target',
    'qb-inventory',
    'eclipse-chat'
}
