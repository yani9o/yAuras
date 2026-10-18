local _,A=...
local floor,max=math.floor,math.max
local question="Interface\\Icons\\INV_Misc_QuestionMark"
local function public(v) return A:Public(v) end
local function safe(fn,...) if not fn then return nil,false end local ok,v=pcall(fn,...); if ok then return v,true end return nil,false end
function A:Spell(key)
 local identifier=tonumber(key) or key
 local info=safe(C_Spell and C_Spell.GetSpellInfo,identifier)
 if info and public(info.spellID) then return info.spellID,info.iconID,info.name end
 return nil
end
function A:DetectedTexturePath(icon)
 if not public(icon) then return nil end
 if type(icon)=="string" and icon:find("[\\/]") then return icon end
 local id=tonumber(icon)
 if not id then return nil end
 local path=safe(C_Texture and C_Texture.GetFilenameFromFileDataID,id)
 -- Some clients return an ID string rather than an actual filename.
 if not public(path) or type(path)~="string" or not path:find("[\\/]") then
  path=self.iconPaths and self.iconPaths[id]
 end
 if not path then return nil end
 if GetFileIDFromPath then
  local fileID=safe(GetFileIDFromPath,path)
  if public(fileID) and type(fileID)=="number" and fileID~=id then return nil end
 end
 return path
end
function A:UpdateDetectedTexture(rule)
 if rule.autodetect~=1 or rule.name=="" then return end
 local id,icon=self:Spell(rule.name)
 if not icon and self.ResolveIDs then
  for known in pairs(self:ResolveIDs(rule)) do local _,found=self:Spell(known);if found then id,icon=known,found;break end end
 end
 local texture=safe(C_Spell and C_Spell.GetSpellTexture,id or tonumber(rule.name) or rule.name)
 if public(texture) and (type(texture)=="number" or type(texture)=="string") then icon=texture end
 if public(icon) and (type(icon)=="number" or type(icon)=="string") then
  local value=self:DetectedTexturePath(icon) or tostring(icon)
  if rule.texture~=value then rule.texture=value;self.nativeDirty=true end
 end
end
function A:TextureSource(rule,icon)
 return rule.autodetect==1 and (icon or tonumber(rule.texture) or rule.texture) or tonumber(rule.texture) or rule.texture
end
function A:Scan(unit,filter,onlyMine)
 local list={}; local complete=true
 local api=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
 if not api then return list,false end
 if onlyMine then filter=filter.."|PLAYER" end
 for i=1,255 do
  local d,ok=safe(api,unit,i,filter)
  if not ok then return list,false end
  if not public(d) then return list,false end
  if not d then break end
  if not public(d.name) or not public(d.spellId) then complete=false
  else list[#list+1]=d; if self.RememberAura then self:RememberAura(d,unit) end end
 end
 return list,complete
end
local function unpackAura(d,now,unit)
 if not d or not public(d) then return false,nil,nil,nil,true end
 local rem
 if public(d.expirationTime) and type(d.expirationTime)=="number" and d.expirationTime>0 then rem=max(0,d.expirationTime-now) end
 local stacks=public(d.applications) and d.applications or nil
 return true,public(d.icon) and d.icon or nil,rem,stacks,false,A:AuraDuration(unit,d),rem and d.expirationTime or nil
end
local function matchesAuraOptions(d,rule)
 local kind
 if rule.type=="Debuff" then kind=d.isHarmful else kind=d.isHelpful end
 if not public(kind) or kind~=true then return false end
 if rule.myCast==1 then
  local source=d.sourceUnit
  if not public(source) or (source~="player" and source~="pet" and source~="vehicle") then return false end
 end
 return true
end
function A:ReadAura(rule,cache,now)
 local unit=A:AuraUnit(rule)
 if not self:MatchesAuraUnit(rule) or self:IsDeadAuraUnit(rule) then return false,nil,nil,nil,false end
 if not UnitExists(unit) then return false,nil,nil,nil,false end
 local filter=rule.type=="Debuff" and "HARMFUL" or "HELPFUL"
 if rule.myCast==1 then filter=filter.."|PLAYER" end
 -- Non-secret player auras may still support exact spell-ID lookup while
 -- enumeration is blocked. Never infer presence from hidden data or old scans.
 if unit=="player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
  local ids=self:ResolveIDs(rule)
  for id in pairs(ids) do
   local key="playerID:"..id
   if not cache[key] then
    local d,ok=safe(C_UnitAuras.GetPlayerAuraBySpellID,id)
    cache[key]={data=d,ok=ok}
   end
   local result=cache[key];local d=result.data
   if result.ok and public(d) and type(d)=="table" and matchesAuraOptions(d,rule) then
    self:RememberAura(d,unit)
    return unpackAura(d,now,unit)
   end
  end
 end
 local direct=C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
 if direct and not tonumber(rule.name) then
  local d,ok=safe(direct,unit,rule.name,filter)
  if ok and public(d) and d then self:RememberAura(d,unit);return unpackAura(d,now,unit) end
  local ids=self:ResolveIDs(rule)
  if ok and public(d) and not d and next(ids) and not self:IsAuraRestricted(ids) then return false,nil,nil,nil,false end
 end
 local key=unit..filter
 if not cache[key] then local list,complete=self:Scan(unit,filter,false); cache[key]={list,complete} end
 local list,complete=unpack(cache[key]); local wanted=tonumber(rule.name)
 for _,d in ipairs(list) do
  if (wanted and d.spellId==wanted) or (not wanted and d.name==rule.name) then return unpackAura(d,now,unit) end
 end
 return false,nil,nil,nil,not complete
end
A.gcdFlags={}; A.cooldownSnapshots={}; A.castSinceWand={}
function A:CaptureCooldownFlags()
 local visited={}
 for _,rule in ipairs(yAurasDB.auras) do
  if rule.type=="Cooldown" then
   local id=self:Spell(rule.name)
   if id and not visited[id] then
    visited[id]=true
    local info=safe(C_Spell.GetSpellCooldown,id)
    self.gcdFlags[id]=info and public(info) and public(info.isOnGCD) and type(info.isOnGCD)=="boolean" and info.isOnGCD or nil
    -- Preserve false explicitly: false means a real cooldown, nil means unknown.
    if info and public(info) and public(info.isOnGCD) and info.isOnGCD==false then self.gcdFlags[id]=false end
   end
  end
 end
end
function A:NoteOwnCast(id)
 if not public(id) or type(id)~="number" then return end
 if id==5019 then self.wandAt=GetTime(); self.castSinceWand={}
 else self.castSinceWand[id]=true end
end
function A:ReadCooldown(rule,cache,now)
 local key="cd:"..rule.name
 if cache[key] then return unpack(cache[key],1,8) end
 local id,icon=self:Spell(rule.name)
 if not id then return false,nil,nil,nil,true end
 -- Forever can expose Shoot's timer for unrelated spells. Keep their actual
 -- pre-shot end time instead of replacing it with the wand timer.
 if id~=5019 and self.wandAt and now-self.wandAt<3 and not self.castSinceWand[id] then
  local old=self.cooldownSnapshots[id]
  if not old then return false,icon,nil,nil,true end
  local rem=old[7] and max(0,old[7]-now) or nil
  return rem and rem>0 or (not rem and old[1]),icon,rem,old[4],old[5],old[6],old[7]
 end
 local object=safe(C_Spell.GetSpellCooldownDuration,id,true)
 local d,ok=safe(C_Spell and C_Spell.GetSpellCooldown,id)
 if not ok or not public(d) or not d then return false,icon,nil,nil,true,object end
 local rem,ending,active,unknown=nil,nil,false,false
 local onGCD=self.gcdFlags[id]
 if onGCD==nil and public(d.isOnGCD) and type(d.isOnGCD)=="boolean" then onGCD=d.isOnGCD end
 -- A duration object can still contain the GCD on Forever despite ignoreGCD.
 -- Filter the public GCD-only signal before trusting IsZero or raw timings.
 if onGCD==true then
  object=nil
 elseif public(d.duration) and public(d.startTime) and type(d.duration)=="number" and type(d.startTime)=="number" then
  local duration,start=d.duration,d.startTime
  local gcd=safe(C_Spell.GetSpellCooldown,61304)
  local gcdOnly=gcd and public(gcd) and public(gcd.startTime) and public(gcd.duration) and gcd.duration>0 and gcd.startTime==start and gcd.duration==duration
  if duration>0 and start>0 and not gcdOnly then ending=start+duration;rem=max(0,ending-now);active=rem>0 else object=nil end
 else
  local zero,zeroOK=safe(object and object.IsZero,object)
  if zeroOK and public(zero) and type(zero)=="boolean" then active=not zero
  elseif public(d.isActive) and type(d.isActive)=="boolean" and not d.isActive then active=false;object=nil
  elseif onGCD~=nil and public(d.isActive) and type(d.isActive)=="boolean" then active=d.isActive and not onGCD
  else unknown=true end
  if not active and not unknown then object=nil end
 end
 local charges=safe(C_Spell and C_Spell.GetSpellCharges,id)
 local count,chargeState
 if charges and public(charges) then
  if public(charges.currentCharges) and type(charges.currentCharges)=="number" and public(charges.maxCharges) then
   count=charges.currentCharges; active=count==0;unknown=false
   if count<charges.maxCharges then
    object=safe(C_Spell.GetSpellChargeDuration,id)
    if public(charges.cooldownStartTime) and public(charges.cooldownDuration) then ending=charges.cooldownStartTime+charges.cooldownDuration;rem=max(0,ending-now) else ending=nil;rem=nil end
   else object=nil;ending=nil;rem=nil end
  else
   unknown=true;chargeState={count=charges.currentCharges}
   object=safe(C_Spell.GetSpellChargeDuration,id) or object
  end
 elseif charges then unknown=true end
 local result={active,icon,rem,count or 0,unknown,object,ending,chargeState}; cache[key]=result
 local snapshot=self:Copy({[1]=active,[4]=count or 0,[5]=unknown,[7]=ending})
 if object and object.Copy then snapshot[6]=safe(object.Copy,object) else snapshot[6]=object end
 self.cooldownSnapshots[id]=snapshot
 return unpack(result,1,8)
end
function A:MatchesTargetCondition(rule)
 if rule.onlyWithTarget~=1 then return true end
 local exists,ok=safe(UnitExists,"target")
 if not ok or not public(exists) or type(exists)~="boolean" then return false end
 if rule.targetType=="None" then return not exists end
 if not exists then return false end
 if rule.targetType=="Any" then return true end
 local fn=rule.targetType=="Friendly" and UnitCanAssist or rule.targetType=="Enemy" and UnitCanAttack
 if not fn then return false end
 local matches,valid=safe(fn,"player","target")
 return valid and public(matches) and matches==true
end
function A:Conditions(rule)
 if not self:MatchesTargetCondition(rule) then return false end
 if not self:MatchesAuraUnit(rule) then return false end
 local combat=self.combatState
 if combat==nil then combat=UnitAffectingCombat("player") end
 local raid=IsInRaid and IsInRaid() or false
 local party=IsInGroup and IsInGroup() and not raid
 if rule.inCombat~=1 and rule.outCombat~=1 and rule.inRaid~=1 and rule.inParty~=1 then return false end
 local combatOK=(rule.inCombat~=1 and rule.outCombat~=1) or (combat and rule.inCombat==1) or (not combat and rule.outCombat==1)
 local groupOK=(rule.inRaid~=1 and rule.inParty~=1) or (raid and rule.inRaid==1) or (party and rule.inParty==1)
 return combatOK and groupOK
end
function A:IsDeadAuraUnit(rule)
 if rule.type=="Cooldown" or (self:AuraUnit(rule)~="target" and self:AuraUnit(rule)~="focus" and self:AuraUnit(rule)~="targettarget") then return false end
 local dead,ok=safe(UnitIsDeadOrGhost,A:AuraUnit(rule))
 return ok and public(dead) and dead==true
end
-- Crop the baked-in rounded/bevelled edges of spell icons; custom aura art
-- keeps its full UV range. Border pieces use physical pixels, not aura scale.
function A:IsSpellIcon(rule,source)
 return rule.autodetect==1 or type(source)=="number" or
  (type(source)=="string" and source:lower():gsub("\\","/"):match("^interface/icons/"))
end
function A:IconPixelSize(owner)
 if PixelUtil and PixelUtil.GetPixelToUIUnitFactor and owner.GetEffectiveScale then
  return PixelUtil.GetPixelToUIUnitFactor()/owner:GetEffectiveScale()
 end
 return 1
end
function A:StyleTexture(owner,texture,rule,mirror,source)
 local isIcon=self:IsSpellIcon(rule,source)
 local zoom=isIcon and A:ZoomIcons()
 local lo,hi=zoom and .08 or 0,zoom and .92 or 1
 texture:SetTexCoord(mirror and hi or lo,mirror and lo or hi,lo,hi)
 if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(isIcon) end
 if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
 -- The default action-button frame has chamfered corners. A square icon
 -- behind it exposes its baked-in dark rim outside the normal border.
 if isIcon and not zoom and not texture.defaultIconMask and owner.CreateMaskTexture and texture.AddMaskTexture then
  local mask=owner:CreateMaskTexture(nil,"ARTWORK")
  local ok=mask.SetAtlas and pcall(mask.SetAtlas,mask,"UI-HUD-ActionBar-IconFrame-Mask",true)
  if ok then
   texture.defaultIconMask=mask
   texture.iconMaskWidth=mask:GetWidth();texture.iconMaskHeight=mask:GetHeight()
  end
 end
 if texture.defaultIconMask then
  local mask=texture.defaultIconMask
  mask:ClearAllPoints();mask:SetPoint("CENTER",texture,"CENTER",0,0)
  local factor=self:AuraDisplaySize(rule)/45
  mask:SetSize(texture.iconMaskWidth*factor,texture.iconMaskHeight*factor)
  if isIcon and not zoom and not texture.iconMaskApplied then
   texture:AddMaskTexture(texture.defaultIconMask);texture.iconMaskApplied=true
  elseif (not isIcon or zoom) and texture.iconMaskApplied then
   texture:RemoveMaskTexture(texture.defaultIconMask);texture.iconMaskApplied=false
  end
 end
 if isIcon and not texture.iconBorder then
  local border=CreateFrame("Frame",nil,owner)
  border:SetAllPoints(owner);border:EnableMouse(false)
  texture.iconBorderFrame=border
  texture.defaultIconBorder=border:CreateTexture(nil,"OVERLAY",nil,6)
  local defaultBorder=texture.defaultIconBorder
  local ok=defaultBorder.SetAtlas and pcall(defaultBorder.SetAtlas,defaultBorder,"UI-HUD-ActionBar-IconFrame",false)
  if not ok then
   defaultBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
   defaultBorder:SetTexCoord(.2,.8,.2,.8)
  end
  if defaultBorder.SetSnapToPixelGrid then defaultBorder:SetSnapToPixelGrid(true) end
  if defaultBorder.SetTexelSnappingBias then defaultBorder:SetTexelSnappingBias(0) end
  texture.iconBorder={}
  for i=1,4 do
   local edge=border:CreateTexture(nil,"OVERLAY",nil,7)
   if edge.SetSnapToPixelGrid then edge:SetSnapToPixelGrid(true) end
   if edge.SetTexelSnappingBias then edge:SetTexelSnappingBias(0) end
   edge:SetColorTexture(0,0,0,1);texture.iconBorder[i]=edge
  end
 end
 if texture.iconBorder then
  local pixel=self:IconPixelSize(owner)
  -- Above the native/fallback swipe, within this rule's reserved level band.
  texture.iconBorderFrame:SetFrameLevel(owner:GetFrameLevel()+2)
  texture.iconBorderFrame:SetShown(not not isIcon)
  local defaultBorder=texture.defaultIconBorder
  defaultBorder:ClearAllPoints()
  defaultBorder:SetPoint("TOPLEFT",texture,"TOPLEFT",0,0)
  -- Blizzard's 45-unit action button uses a 46 x 45 normal border atlas.
  local size=self:AuraDisplaySize(rule)
  defaultBorder:SetSize(size*46/45,size)
  defaultBorder:SetShown(isIcon and not zoom)
  for i,edge in ipairs(texture.iconBorder) do
   edge:ClearAllPoints()
   -- Outside the artwork: never cover the outer row/column of icon pixels.
   if i==1 then
    edge:SetPoint("BOTTOMLEFT",texture,"TOPLEFT",-pixel,0);edge:SetPoint("BOTTOMRIGHT",texture,"TOPRIGHT",pixel,0);edge:SetHeight(pixel)
   elseif i==2 then
    edge:SetPoint("TOPLEFT",texture,"BOTTOMLEFT",-pixel,0);edge:SetPoint("TOPRIGHT",texture,"BOTTOMRIGHT",pixel,0);edge:SetHeight(pixel)
   elseif i==3 then
    edge:SetPoint("TOPRIGHT",texture,"TOPLEFT");edge:SetPoint("BOTTOMRIGHT",texture,"BOTTOMLEFT");edge:SetWidth(pixel)
   else
    edge:SetPoint("TOPLEFT",texture,"TOPRIGHT");edge:SetPoint("BOTTOMLEFT",texture,"BOTTOMRIGHT");edge:SetWidth(pixel)
   end
   edge:SetShown(not not zoom)
  end
 end
end
-- Reserve a band for each rule, including native buttons and colour helpers.
-- Earlier list entries appear above later entries.
function A:AuraFrameLevel(id)
 return 128+math.max(0,#yAurasDB.auras-(id or 1))*16
end
function A:StopAuraDrag()
 local drag=self.activeAuraDrag
 if not drag then return end
 self.activeAuraDrag=nil
 local frame=drag.frame
 frame:StopMovingOrSizing();frame.dragging=false
 if drag.preview then frame:SetMovable(false) end
 local x,y=frame:GetCenter();local cx,cy=UIParent:GetCenter()
 local rule=yAurasDB.auras[drag.id]
 if rule and x and y and cx and cy then
  rule.xpos=floor(x-cx+.5);rule.ypos=floor(y-cy+.5)
  frame:ClearAllPoints();frame:SetPoint("CENTER",UIParent,"CENTER",rule.xpos,rule.ypos)
  local gui=self.gui
  if gui and gui.editor and gui.auraEdit==drag.id then
   gui.editor.x:SetText(rule.xpos);gui.editor.y:SetText(rule.ypos)
   if self.TestAuraDual and self.TestAuraDual:IsVisible() then self:AnchorPreview(self.TestAuraDual,-rule.xpos,rule.ypos) end
  end
  self:InvalidateRule(drag.id)
 end
end
function A:StartAuraDrag(frame,id,preview)
 if not (self.preview or self.moveAuras) or not yAurasDB.auras[id] then return end
 self:StopAuraDrag()
 self.activeAuraDrag={frame=frame,id=id,preview=preview}
 frame:SetMovable(true);frame:StartMoving();frame.dragging=true
end
function A:MakeFrame()
 local f=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
 f:SetFrameStrata("BACKGROUND"); f:SetFrameLevel(128); f:SetMovable(true); f:SetClampedToScreen(true)
 f.artworkParent=CreateFrame("Frame",nil,f)
 f.texture=f.artworkParent:CreateTexture(nil,"ARTWORK"); f.texture:SetAllPoints(f)
 f.timer=f:CreateFontString(nil,"OVERLAY"); self:CenterAuraTimer(f.timer,f)
 f.stacks=f:CreateFontString(nil,"OVERLAY"); f.stacks:SetPoint("BOTTOMRIGHT",-2,2)
 f:RegisterForDrag("LeftButton")
 f:SetScript("OnDragStart",function(self) A:StartAuraDrag(self,self.id,false) end)
 f:SetScript("OnDragStop",function(self)
  if A.activeAuraDrag and A.activeAuraDrag.frame==self then A:StopAuraDrag();A:Refresh() end
 end)
 f:SetScript("OnHide",function(self)
  if A.activeAuraDrag and A.activeAuraDrag.frame==self then A:StopAuraDrag() end
 end)
 f:Hide(); return f
end
function A:Paint(f,rule,icon,remaining,stacks,mirror,durationObject,endTime,cooldownActive)
 f:SetFrameLevel(self:AuraFrameLevel(f.id)+4)
 local scale=rule.scale
 if not f.dragging then f:ClearAllPoints(); f:SetPoint("CENTER",UIParent,"CENTER",(mirror and -1 or 1)*rule.xpos,rule.ypos) end
 local size=self:AuraDisplaySize(rule);f:SetSize(size,size)
 local source=self:TextureSource(rule,icon) or question
 f.texture:SetTexture(source)
 self:StyleTexture(f,f.texture,rule,mirror,source)
 local low=remaining and remaining>0 and remaining<=rule.lowdurationvalue
 local c=(low and rule.lowduration==1) and rule.lowdurationcolor or rule.auracolor
 local dim=1 -- The swipe provides cooldown shading; preserve configured colours.
 f.texture:SetVertexColor(c[1]*dim,c[2]*dim,c[3]*dim,c[4])
 local preview=self.preview or (self.gui and self.gui:IsShown() and not self.gui.editor)
 self:SetTimer(f,rule,durationObject,endTime,remaining,preview)
 self:SetIconSwipe(f,rule,source,durationObject or (endTime and f.localDuration),preview)
 if preview then self:ClearTextureDuration(f) else self:SetTextureDuration(f,rule,durationObject,endTime,remaining,dim) end
 f.stacks:SetFont("Fonts\\FRIZQT__.TTF",self:AuraTextSize(rule,true),"OUTLINE")
 self:AnchorAuraStacks(f.stacks,f,rule)
 f.stacks:SetText(rule.stacks==1 and stacks and stacks>1 and stacks or "")
 f.stacks:SetTextColor(1,1,1,c[4]); f:EnableMouse((self.preview or self.moveAuras) and not mirror or false)
 if self.preview or self.moveAuras then f:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1}); f:SetBackdropBorderColor(0,1,0,.7) else f:SetBackdrop(nil) end
 f:Show()
end
function A:Refresh()
 if not self.loaded then return end
 for _,rule in ipairs(yAurasDB.auras) do self:UpdateDetectedTexture(rule) end
 self:PrepareNative()
 local now,cache=GetTime(),{}; self.unavailable=0
 for _,pair in pairs(self.frames) do pair.main.used=false; if pair.dual then pair.dual.used=false end end
 for i,rule in ipairs(yAurasDB.auras) do
  local show,icon,remaining,stacks,durationObject,endTime,cooldownActive,cooldownUnknown,chargeState=false,nil,nil,nil,nil,nil,nil,false,nil
  if self.enabled and rule.enabled==1 and rule.name~="" then
   if self.preview or (self.gui and self.gui:IsShown() and not self.gui.editor) then local _,tex=self:Spell(rule.name); show,icon,remaining,stacks=true,tex,600,20
   elseif self:Conditions(rule) and not self:IsDeadAuraUnit(rule) and not (self.gui and self.gui:IsShown() and self.gui.editor) then
    local present,unknown
    if rule.type=="Cooldown" then
     present,icon,remaining,stacks,unknown,durationObject,endTime,chargeState=self:ReadCooldown(rule,cache,now)
     cooldownActive=present
     cooldownUnknown=unknown
     show=rule.showCD=="Always" or
      (unknown and self:CanGateCooldown(durationObject,chargeState)) or
      (not unknown and ((present and rule.showCD=="CD") or (not present and rule.showCD=="No CD")))
    else
     local native,inverted=self:UseNative(i,rule)
     if native then
      show=inverted; if inverted then local _,tex=self:Spell(rule.name); icon=tex end
     else
     present,icon,remaining,stacks,unknown,durationObject,endTime=self:ReadAura(rule,cache,now)
     if unknown and self:UseNative(i,rule,true) then unknown=false;show=false
     else show=not unknown and (rule.invert==1 and not present or rule.invert~=1 and present) and UnitExists(A:AuraUnit(rule)) end
     end
    end
    if unknown then self.unavailable=self.unavailable+1 end
   end
  end
  if show then
   if not self.frames[i] then self.frames[i]={main=self:MakeFrame()} end
   local pair=self.frames[i]; pair.main.id=i; pair.main.used=true
   self:Paint(pair.main,rule,icon,remaining,stacks,false,durationObject,endTime,cooldownActive)
   self:SetCooldownGate(pair.main,rule,durationObject,cooldownUnknown,chargeState)
   if rule.dual==1 and rule.type~="Cooldown" then
    pair.dual=pair.dual or self:MakeFrame(); pair.dual.id=i;pair.dual.used=true; self:Paint(pair.dual,rule,icon,remaining,stacks,true,durationObject,endTime)
   end
  end
 end
 for _,pair in pairs(self.frames) do if not pair.main.used then self:ClearCooldownGate(pair.main);self:ClearTimer(pair.main);self:ClearTextureDuration(pair.main); pair.main:Hide() end; if pair.dual and not pair.dual.used then self:ClearTimer(pair.dual);self:ClearTextureDuration(pair.dual); pair.dual:Hide() end end
 self:HideUnusedNative()
 self:Schedule()
end
local events=CreateFrame("Frame")
for _,ev in ipairs({"UNIT_AURA","UNIT_HEALTH","UNIT_FLAGS","UNIT_TARGET","PLAYER_TARGET_CHANGED","PLAYER_FOCUS_CHANGED","SPELL_UPDATE_COOLDOWN","SPELL_UPDATE_CHARGES","SPELLS_CHANGED","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED","GROUP_ROSTER_UPDATE","UNIT_PET","UNIT_SPELLCAST_SUCCEEDED","ADDON_RESTRICTION_STATE_CHANGED","PLAYER_ENTERING_WORLD"}) do events:RegisterEvent(ev) end
-- Coalesce event bursts and refresh at 10 Hz; no scanning without rules.
local elapsed,dirty=0,true
function A:Schedule()
 if self.enabled and #yAurasDB.auras>0 then
  events:SetScript("OnUpdate",function(_,dt)
   elapsed=elapsed+dt
   if elapsed>=0.1 or dirty then elapsed=0; dirty=false; A:Refresh() end
  end)
 else events:SetScript("OnUpdate",nil) end
end
events:SetScript("OnEvent",function(_,ev,unit,castGUID,spellID)
 if ev=="UNIT_HEALTH" or ev=="UNIT_FLAGS" then
  if unit~="target" and unit~="focus" and unit~="targettarget" then return end
  local dead,ok=safe(UnitIsDeadOrGhost,unit)
  if not ok or not public(dead) or dead~=true then return end
  if A.loaded then A:Refresh();dirty=false end;return
 end
 if ev=="UNIT_TARGET" and unit~="target" then return end
 if ev=="PLAYER_TARGET_CHANGED" or ev=="PLAYER_FOCUS_CHANGED" or ev=="UNIT_TARGET" then
  if A.loaded then A:SyncNative();A:Refresh();dirty=false end;return
 end
 if ev=="UNIT_AURA" and unit~="player" and unit~="target" and unit~="focus" and unit~="targettarget" and unit~="pet" then return end
 -- The editor suppresses gameplay reads, but newly appearing public buffs
 -- still need to teach their IDs to the native filters before combat starts.
 if ev=="UNIT_AURA" and A.loaded and A.PrimeAuraRules then A:PrimeAuraRules(unit) end
 if ev=="SPELL_UPDATE_COOLDOWN" and A.loaded then A:CaptureCooldownFlags() end
 if ev=="UNIT_SPELLCAST_SUCCEEDED" then if unit=="player" then A:NoteOwnCast(spellID) end; return end
 if ev=="SPELLS_CHANGED" or ev=="PLAYER_REGEN_ENABLED" or ev=="ADDON_RESTRICTION_STATE_CHANGED" or ev=="PLAYER_ENTERING_WORLD" then A:InvalidateAll(); if ev=="SPELLS_CHANGED" then A:LearnSpellBook() end end
 if ev=="PLAYER_REGEN_DISABLED" or ev=="PLAYER_REGEN_ENABLED" or ev=="ADDON_RESTRICTION_STATE_CHANGED" then
  if ev=="PLAYER_REGEN_DISABLED" then A.combatState=true elseif ev=="PLAYER_REGEN_ENABLED" then A.combatState=false end
  if A.loaded then A:SyncNative();A:Refresh();dirty=false end
  return
 end
 dirty=true
end)

function A:UpdateAuras() self:Refresh() end
