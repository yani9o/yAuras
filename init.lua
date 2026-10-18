local _, localization = ...
local L = localization.L
local addonName, A = ...
_G.yAuras = A
A.name, A.frames, A.enabled = addonName, {}, true
A.title = "|cff4b7dccy|r|cffffffffAuras|r"
A.draggers = {}
A.defaults = {name="",enabled=1,type="Buff",unit="Player",myCast=0,invert=0,showCD="Always",autodetect=1,
 texture="Interface\\Icons\\INV_Misc_QuestionMark",scale=1,xpos=0,ypos=0,duration=1,stacks=0,dual=0,
 inCombat=1,outCombat=1,inParty=0,inRaid=0,onlyWithTarget=0,targetType="Any",lowduration=0,lowdurationvalue=0,
 auracolor={1,1,1,1},lowdurationcolor={1,0,0,1}}
function A:AuraUnit(rule)
 if rule.unit=="Friendly" or rule.unit=="Enemy" then return "target" end
 return rule.unit:lower()
end
function A:MatchesAuraUnit(rule)
 if rule.type=="Cooldown" then return true end
 local unit=self:AuraUnit(rule)
 if not UnitExists(unit) then return false end
 local fn=rule.unit=="Friendly" and UnitCanAssist or rule.unit=="Enemy" and UnitCanAttack
 if not fn then return rule.unit~="Friendly" and rule.unit~="Enemy" end
 local ok,value=pcall(fn,"player",unit)
 return ok and self:Public(value) and value==true
end
function A:ZoomIcons()
 return yAurasDB and yAurasDB.zoomIcons==true or false
end
function A:SetZoomIcons(value)
 yAurasDB.zoomIcons=value==true
 self:InvalidateAll()
 if self.gui and self.gui:IsShown() and self.gui.auraEdit then self:EditAura(self.gui.auraEdit) end
 self:Refresh()
end
function A:Copy(t)
 local out={} for k,v in pairs(t) do out[k]=type(v)=="table" and self:Copy(v) or v end return out
end
function A:Msg(s) print(self.title .. ": " .. s) end
function A:Public(v) return not (issecretvalue and issecretvalue(v)) end
function A:Normalize(t)
 local out=self:Copy(self.defaults)
 for k,default in pairs(self.defaults) do
  local v=t[k]
  if type(v)==type(default) then
   if type(v)=="table" then
    for i=1,4 do if type(v[i])=="number" then out[k][i]=math.max(0,math.min(1,v[i])) end end
   else out[k]=v end
  end
 end
 out.scale=math.max(.1,math.min(10,out.scale)); out.lowdurationvalue=math.max(0,out.lowdurationvalue)
 if out.type~="Buff" and out.type~="Debuff" and out.type~="Cooldown" then out.type="Buff" end
 local units={Player=true,Target=true,Friendly=true,Enemy=true,Focus=true,TargetTarget=true,Pet=true}
 if not units[out.unit] then out.unit="Player" end
 if out.showCD~="Always" and out.showCD~="CD" and out.showCD~="No CD" then out.showCD="Always" end
 if out.targetType~="Any" and out.targetType~="Friendly" and out.targetType~="Enemy" and out.targetType~="None" then out.targetType="Any" end
 out.onlyWithTarget=out.onlyWithTarget==1 and 1 or 0
 return out
end
-- Native auxiliary slots are visible hit targets unless mouse input is disabled
-- explicitly, even when they only render inline texture artwork.
function A:DisableAuraInteraction(button)
 button:EnableMouse(false)
 if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
 if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
 if button.SetCancelAuraButtons then button:SetCancelAuraButtons(nil) end
end
function A:SetEnabled(value)
 self.enabled=value
 if self.loaded then yAurasDB.enabled=value; self:Refresh() end
 if self.settingsPanel and self.settingsPanel.RefreshForm then self.settingsPanel.RefreshForm() end
end
-- Standalone lifecycle: the settings page can nest under yTools without
-- registering an entry in its module list.
-- yTools dispatches commands from a separate table. A command-only owner
-- supplies its dispatcher methods without registering a listed module.
if yTools and yTools.commands and not yTools.commands.auras then
 local owner={id="yAuras",IsEnabled=function() return true end,GetTitle=function() return "yAuras" end}
 yTools.commands.auras={module=owner,callback=function() A:OpenEditor() end,help=L.OPEN_YAURAS_EDITOR}
end
local loader=CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED"); loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent",function(_,event,name)
 if event=="ADDON_LOADED" and name==addonName then
  -- Use only yAuras saved settings.
  yAurasDB=type(yAurasDB)=="table" and yAurasDB or {}
  yAurasDB.refresh=nil; yAurasDB.approximate=nil
  A:SpellCache()
  yAurasDB.auras=type(yAurasDB.auras)=="table" and yAurasDB.auras or {}
  for i,t in ipairs(yAurasDB.auras) do yAurasDB.auras[i]=A:Normalize(type(t)=="table" and t or {}) end
  A.loaded=true; A.SettingsLoaded=true; A.enabled=yAurasDB.enabled~=false
  A.nativeDirty=true
 elseif event=="PLAYER_LOGIN" then
  A:RegisterSettings(); A:Refresh()
 end
end)
SLASH_YAURAS1="/yauras"; SLASH_YAURAS2="/sa"
SlashCmdList.YAURAS=function() A:OpenEditor() end

function A:LocalizeValue(value)
 local keys = {
  ["Buff"] = "VALUE_BUFF",
  ["Debuff"] = "VALUE_DEBUFF",
  ["Cooldown"] = "VALUE_COOLDOWN",
  ["Player"] = "VALUE_PLAYER",
  ["Target"] = "VALUE_TARGET",
  ["Friendly"] = "VALUE_FRIENDLY",
  ["Enemy"] = "VALUE_ENEMY",
  ["Any"] = "VALUE_ANY",
  ["None"] = "VALUE_NONE",
  ["Focus"] = "VALUE_FOCUS",
  ["TargetTarget"] = "VALUE_TARGET_TARGET",
  ["Pet"] = "VALUE_PET",
  ["Always"] = "VALUE_ALWAYS",
  ["CD"] = "VALUE_CD",
  ["No CD"] = "VALUE_NO_CD",
  ["on"] = "VALUE_ON",
  ["off"] = "VALUE_OFF",
  ["enabled"] = "VALUE_ENABLED",
  ["disabled"] = "VALUE_DISABLED",
  ["native"] = "VALUE_NATIVE",
  ["fallback"] = "VALUE_FALLBACK",
 }
 return keys[value] and L[keys[value]] or value
end

-- Blizzard addon-compartment entry.
function yAuras_OnAddonCompartmentClick()
 A:OpenEditor()
end
