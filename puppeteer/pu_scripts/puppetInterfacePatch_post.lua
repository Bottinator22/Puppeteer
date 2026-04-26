require "/scripts/terra_proxy.lua"

local oldInit = init
function init()
    local puppetId = config.getParameter("pu_puppetId")
    player = terra_proxy.setupProxy("player",puppetId)
    status = terra_proxy.setupProxy("status",puppetId)
    if oldInit then oldInit() end
end
