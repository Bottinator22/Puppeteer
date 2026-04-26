
-- create list of all techs mapped to directories
local techEffectBaseConfig = assets.json("/pu_scripts/baseTechEffect.json")
local techs = assets.byExtension("tech")
local dirs = {}
for k,v in next, techs do
  local tech = assets.json(v)
  local dir = string.match(v, "(.*/)")
  dirs[tech.name] = dir
  local effect = sb.jsonMerge({},techEffectBaseConfig)
  effect.name = "pu_tech_"..tech.name
  local animation = tech.animator
  if animation then
    if type(animation) == "string" then
      if string.sub(animation,1,1) ~= "/" then
          -- path isn't absolute
          animation = dir..animation
      end
    end
    effect.animationConfig = animation
    effect.effectConfig.techName = tech.name
    local fname = string.gsub(tech.name,"[%s:?/]","_")
    assets.add(string.format("/stats/effects/pu_techs/%s.statuseffect",fname),effect)
  end
end
assets.add("/pu_scripts/techDirectories.json", dirs)
