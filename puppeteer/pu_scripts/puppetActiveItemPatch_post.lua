require "/scripts/terra_proxy.lua"

local oldInit = init
function init()
    if player then
        sb.logWarn("Puppet activeitem player already defined! Patching is broken!")
    else
        player = terra_proxy.setupProxy("player",entity.id())
        activeItem.interact = player.interact
    end
    if oldInit then oldInit() end
end
