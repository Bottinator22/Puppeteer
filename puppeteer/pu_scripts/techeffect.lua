require "/scripts/terra_proxy.lua"

function init()
  local name = config.getParameter("techName")
  terra_proxy.setupReceiveMessages("pu_tech_"..name.."_animator",animator)
end

function update(dt)
end

function uninit()

end
