local _, localization = ...
local L = localization.L
local _,A=...
local function safe(fn,...)
 if not fn then return nil,false end
 local ok,result=pcall(fn,...); return ok and result or nil,ok
end
local function public(value) return A:Public(value) end
local function locked() return A.combatState==true or (InCombatLockdown and InCombatLockdown()) end
A.nativeEntries={}; A.nativeDirty=true; A.spellIDs={}
function A:InvalidateRule() self.nativeDirty=true; self.resolved={} end
function A:InvalidateAll() self:InvalidateRule() end
-- The client only resolves some names directly. Index public spell metadata
-- independently of aura presence so unknown procs can be configured by name.
local nameWorker=CreateFrame("Frame")
local nameIndex,pendingNames,searchNames,priority,queued={},{},{},{},{}
local cursor,priorityCursor,upper=1,1,2000000
local function ReadSpellName(id)
 local name
 if C_Spell and C_Spell.GetSpellName then name=safe(C_Spell.GetSpellName,id)
 elseif C_Spell and C_Spell.GetSpellInfo then
  local info=safe(C_Spell.GetSpellInfo,id)
  if info and public(info) then name=info.name end
 end
 if public(name) and type(name)=="string" and name~="" then return name end
end
local function QueueNearby(id)
 if type(id)~="number" or id<=0 or id~=math.floor(id) then return end
 upper=math.max(upper,id+100000)
 -- Rank and triggered-buff definitions often live near their parent spell.
 -- This is only a search priority; every match uses the actual localized name.
 for distance=0,32 do
  for _,candidate in ipairs(distance==0 and {id} or {id-distance,id+distance}) do
   if candidate>0 and not queued[candidate] then
    queued[candidate]=true;priority[#priority+1]=candidate
   end
  end
 end
end
local function SeedClassSpells()
 for _,ids in pairs(A.spellIDs) do for id in pairs(ids) do QueueNearby(id) end end
 local traits=C_Traits
 local configID=C_ClassTalents and safe(C_ClassTalents.GetActiveConfigID)
 if not configID or not traits or not traits.GetConfigInfo or not traits.GetTreeNodes
  or not traits.GetNodeInfo or not traits.GetEntryInfo or not traits.GetDefinitionInfo then return end
 local config=safe(traits.GetConfigInfo,configID)
 for _,treeID in ipairs(config and config.treeIDs or {}) do
  for _,nodeID in ipairs(safe(traits.GetTreeNodes,treeID) or {}) do
   local node=safe(traits.GetNodeInfo,configID,nodeID)
   for _,entryID in ipairs(node and node.entryIDs or {}) do
    local entry=safe(traits.GetEntryInfo,configID,entryID)
    local definition=entry and safe(traits.GetDefinitionInfo,entry.definitionID)
    if definition then QueueNearby(definition.spellID) end
   end
  end
 end
end
local function SearchVersion()
 local build="unknown"
 if GetBuildInfo then local _,value=GetBuildInfo();build=tostring(value) end
 return build..":"..GetLocale()..":"..upper
end
-- Shared metadata only; aura configurations and debuff timing profiles stay per character.
function A:SpellCache()
 local build="unknown"
 if GetBuildInfo then local _,value=GetBuildInfo();build=tostring(value) end
 local version=build..":"..GetLocale()
 yAurasAccountDB=type(yAurasAccountDB)=="table" and yAurasAccountDB or {}
 local cache=yAurasAccountDB.spellCache
 if type(cache)~="table" or cache.version~=version then
  cache={version=version,spellNameIDs={},knownAuraIDs={},spellNameIndexComplete={}}
  yAurasAccountDB.spellCache=cache
 end
 return cache
end
local function SaveNameMatches(name,ids)
 A:SpellCache().spellNameIDs=A:SpellCache().spellNameIDs or {}
 local saved=A:SpellCache().spellNameIDs[name] or {}
 A:SpellCache().spellNameIDs[name]=saved
 local changed=false
 for id in pairs(ids) do
  if not saved[id] then saved[id]=true;changed=true end
 end
 if changed then A.nativeDirty=true end
 return changed
end
local function UpdateNameLookup()
 if locked() or not A.loaded then return end
 for name in pairs(searchNames) do
  local watched=false
  for _,rule in ipairs(yAurasDB.auras) do
   if rule.enabled==1 and rule.type~="Cooldown" and rule.name==name then watched=true;break end
  end
  if not watched then searchNames[name]=nil;pendingNames[name]=nil end
 end
 if not next(searchNames) then nameWorker:SetScript("OnUpdate",nil);return end
 local start=debugprofilestop and debugprofilestop()
 local changed=false
 for _=1,250 do
  local id=priority[priorityCursor]
  if id then priorityCursor=priorityCursor+1
  elseif cursor<=upper then id=cursor;cursor=cursor+1
  else
   A:SpellCache().spellNameIndexComplete=A:SpellCache().spellNameIndexComplete or {}
   for name in pairs(searchNames) do A:SpellCache().spellNameIndexComplete[name]=SearchVersion() end
   wipe(searchNames)
   nameWorker:SetScript("OnUpdate",nil);break
  end
  local name=ReadSpellName(id)
  if name and searchNames[name] then
   local ids=nameIndex[name] or {};nameIndex[name]=ids;ids[id]=true
   if SaveNameMatches(name,ids) then changed=true end
   pendingNames[name]=nil
  end
  if start and debugprofilestop()-start>=2 then break end
 end
 if changed then A:Refresh() end
end
function A:LookupSpellName(name,knownIDs)
 local ids=nameIndex[name]
 if ids then SaveNameMatches(name,ids) end
 local complete=A:SpellCache().spellNameIndexComplete and A:SpellCache().spellNameIndexComplete[name]
 if not searchNames[name] and complete~=SearchVersion()
  and C_Spell and (C_Spell.GetSpellName or C_Spell.GetSpellInfo) then
  searchNames[name]=true
  if not next(knownIDs) and not ids then pendingNames[name]=true end
  for id in pairs(knownIDs) do QueueNearby(id) end
  SeedClassSpells()
  -- A newly watched name must also be checked in the earlier part of the
  -- catalog. Only requested names are held in memory or saved.
  cursor=1
  nameWorker:SetScript("OnUpdate",UpdateNameLookup)
 end
 return ids
end
local profileFlags={"canApplyAura","isStealable","isBossAura","isFromPlayerOrPlayerPet","nameplateShowAll","nameplateShowPersonal"}
function A:RememberAura(d,unit)
 if not d or not public(d) or not public(d.name) or not public(d.spellId)
  or type(d.name)~="string" or type(d.spellId)~="number"
  or d.spellId<=0 or d.spellId~=math.floor(d.spellId) then return end
 local ids=self.spellIDs[d.name] or {}; self.spellIDs[d.name]=ids
 if not ids[d.spellId] then ids[d.spellId]=true; self.nativeDirty=true end
 -- Retain only identities actually observed on a watched aura. Spellbook
 -- entries alone can refer to the talent/cast rather than its proc buff.
 -- No presence, remaining time, or aura instance data is saved here.
 if unit and yAurasDB then
  for _,rule in ipairs(yAurasDB.auras) do
   if rule.type~="Cooldown" and (rule.name==d.name or tonumber(rule.name)==d.spellId) then
    A:SpellCache().knownAuraIDs=A:SpellCache().knownAuraIDs or {}
    local known=A:SpellCache().knownAuraIDs[d.name] or {}
    A:SpellCache().knownAuraIDs[d.name]=known
    known[d.spellId]=true
    break
   end
  end
 end
 -- Learn only public player debuffs outside combat. Save properties, never
 -- presence/expiration/instance IDs; no old aura can be resurrected at combat start.
 if unit~="player" or locked() or not public(d.isHarmful) or d.isHarmful~=true then return end
 if not public(d.duration) or type(d.duration)~="number" or d.duration<=0 then return end
 local watched=false
 for _,rule in ipairs(yAurasDB.auras) do
  if rule.type=="Debuff" and rule.unit=="Player" and (rule.name==d.name or tonumber(rule.name)==d.spellId) then watched=true;break end
 end
 if not watched then return end
 yAurasDB.debuffProfiles=yAurasDB.debuffProfiles or {}
 local old=yAurasDB.debuffProfiles[d.spellId]
 local profile={name=d.name,duration=math.max(old and old.duration or 0,math.floor(d.duration*10+.5)/10)}
 if public(d.dispelName) and type(d.dispelName)=="string" then profile.dispel=d.dispelName end
 for _,key in ipairs(profileFlags) do if public(d[key]) and type(d[key])=="boolean" then profile[key]=d[key] end end
 local changed=not old
 if old then for key,value in pairs(profile) do if old[key]~=value then changed=true end end
  for key,value in pairs(old) do if profile[key]~=value then changed=true end end end
 if changed then yAurasDB.debuffProfiles[d.spellId]=profile;self.nativeDirty=true end
end
function A:ResolveIDs(rule)
 local numeric=tonumber(rule.name)
 if numeric then return {[numeric]=true} end
 local ids=self:Copy(self.spellIDs[rule.name] or {})
 local indexed=A:SpellCache().spellNameIDs and A:SpellCache().spellNameIDs[rule.name]
 if type(indexed)=="table" then for id,valid in pairs(indexed) do
  if valid==true and type(id)=="number" and id>0 and id==math.floor(id) then ids[id]=true end
 end end
 local known=A:SpellCache().knownAuraIDs and A:SpellCache().knownAuraIDs[rule.name]
 if type(known)=="table" then
  for id,valid in pairs(known) do
   if valid==true and type(id)=="number" and id>0 and id==math.floor(id) then ids[id]=true end
  end
 end
 for id,p in pairs(yAurasDB.debuffProfiles or {}) do if p.name==rule.name then ids[id]=true end end
 local id=self:Spell(rule.name); if id then ids[id]=true end
 if rule.enabled==1 and rule.type~="Cooldown" then
  local matches=self:LookupSpellName(rule.name,ids)
  if matches then for spellID in pairs(matches) do ids[spellID]=true end end
 end
 return ids
end
-- Learn the actual aura spell IDs before building native filters. A proc can
-- share its name with a talent or cast spell that has a different ID.
function A:PrimeAuraRules(changedUnit)
 if locked() or not self.loaded then return end
 local scanned={}
 for _,rule in ipairs(yAurasDB.auras) do
  if rule.enabled==1 and rule.type~="Cooldown" and rule.name~="" then
   local unit=self:AuraUnit(rule)
   if (not changedUnit or changedUnit==unit) and UnitExists(unit) then
    local filter=rule.type=="Debuff" and "HARMFUL" or "HELPFUL"
    local key=unit..":"..filter
    if not scanned[key] then self:Scan(unit,filter,false);scanned[key]=true end
   end
  end
 end
end
function A:ApproximateCandidates(rule,ids)
 if rule.type~="Debuff" or rule.unit~="Player" then return end
 local merged
 for id in pairs(ids) do
  local p=(yAurasDB.debuffProfiles or {})[id]
  if p then
   if not merged then merged=self:Copy(p)
   else
    merged.duration=math.max(merged.duration,p.duration)
    if merged.dispel~=p.dispel then merged.dispel=nil end
    for _,key in ipairs(profileFlags) do if merged[key]~=p[key] then merged[key]=nil end end
   end
  end
 end
 if not merged then return end
 local filters={maxDuration=merged.duration+.5}
 if merged.dispel then filters.includeDispelTypes={[merged.dispel]=true} end
 for _,key in ipairs(profileFlags) do filters[key]=merged[key] end
 return filters
end
function A:NativeCandidates(rule,ids)
 local approximate=self:ApproximateCandidates(rule,ids)
 return approximate or {includeSpellIDs=ids},approximate~=nil
end
function A:NativeSort(approximate)
 if approximate and AuraContainerSortMethod then return AuraContainerSortMethod.AuraInstanceIDOnly end
end
function A:LearnSpellBook()
 if not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines then return end
 local bank=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
 if not bank then return end
 local n=safe(C_SpellBook.GetNumSpellBookSkillLines)
 for tab=1,n or 0 do
  local line=safe(C_SpellBook.GetSpellBookSkillLineInfo,tab)
  if line then
   for slot=line.itemIndexOffset+1,line.itemIndexOffset+line.numSpellBookItems do
    local d=safe(C_SpellBook.GetSpellBookItemInfo,slot,bank)
    if d and d.spellID then
     local info=safe(C_Spell.GetSpellInfo,d.spellID)
     if info and info.name then self:RememberAura({name=info.name,spellId=d.spellID}) end
    end
   end
  end
 end
end
function A:IsAuraRestricted(ids)
 if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
  for id in pairs(ids) do
   local value,ok=safe(C_Secrets.ShouldSpellAuraBeSecret,id)
   if not ok or not public(value) or value then return true end
  end
  return false
 end
 local value,ok=safe(C_Secrets and C_Secrets.ShouldAurasBeSecret)
 return not ok or not public(value) or value==true
end
-- Identity filtering is supported for friendly buffs and hostile debuffs.
-- Never let a slot silently match an unrelated player debuff/enemy buff.
function A:CanNativeFilter(rule,ids)
 if not next(ids) then return false end
 if not self:IsAuraRestricted(ids) then return true end
 local unit=A:AuraUnit(rule)
 local assist,ok=safe(UnitCanAssist,"player",unit)
 if unit=="player" or unit=="pet" then assist,ok=true,true end
 if not ok or not public(assist) then return false end
 return (rule.type=="Buff" and assist) or (rule.type=="Debuff" and not assist)
end
local function makeSide(rule,mirror,id)
 local host=CreateFrame("Frame",nil,UIParent)
 local size=A:AuraDisplaySize(rule)
 host:SetSize(size,size)
 host:SetPoint("CENTER",UIParent,"CENTER",(mirror and -1 or 1)*rule.xpos,rule.ypos)
 host:SetFrameStrata("BACKGROUND"); host:SetFrameLevel(A:AuraFrameLevel(id)); host:Hide()
 local container=CreateFrame("AuraContainer",nil,host,"CustomAuraContainerTemplate")
 if type(container.AddAuraSlot)~="function" or type(container.SetUnit)~="function" then host:Hide(); return nil,L.AURACONTAINER_METHODS_ARE_UNAVAILABLE end
 container:SetEnabled(false)
 if not container.SetAuraProcessingPolicy or not CustomAuraContainerAuraProcessingPolicy then return nil,L.NATIVE_AURA_PROCESSING_POLICY_IS_UNAVAILABLE end
 container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
 if rule.invert~=1 then container:SetSize(1,1); container:SetPoint("CENTER",host,"CENTER") end
 local side={host=host,container=container}
 container:SetFrameLevel(host:GetFrameLevel()+3)
 local filter=rule.type=="Debuff" and "HARMFUL" or "HELPFUL"
 if rule.myCast==1 then filter=filter.."|PLAYER" end
 local ids=A:ResolveIDs(rule)
 local candidates,approximate=A:NativeCandidates(rule,ids)
 local sortMethod=A:NativeSort(approximate)
 if rule.invert==1 then
  -- The engine expands this group when a match exists. Its right edge then closes
  -- the sibling clipping rectangle, hiding the missing icon without a Lua query.
  local width=size
  local _,spellIcon=A:Spell(rule.name)
  local source=A:TextureSource(rule,spellIcon)
  local zoom=A:IsSpellIcon(rule,source) and A:ZoomIcons()
  local border=A:IsSpellIcon(rule,source) and (zoom and A:IconPixelSize(host) or (rule.scale or 1)) or 0
  local padding=zoom and 2 or 1
  local presenceWidth=width+padding+2*border
  container:ClearAllPoints(); container:SetPoint("TOPLEFT",host,"TOPLEFT")
  container:AddAuraGroup("presence",filter,{
   candidateFilters=candidates,sortMethod=sortMethod,maxFrameCount=1,
   layout={elementWidth=presenceWidth,elementHeight=width},
   initializeFrame=function(button) button:SetSize(presenceWidth,width); button:SetAlpha(0); A:DisableAuraInteraction(button) end,
  })
  local clip=CreateFrame("Frame",nil,host,"DisableUntrustedLayoutScriptsTemplate")
  clip:SetClipsChildren(true); clip:SetPoint("TOPLEFT",container,"TOPRIGHT",-padding-border,border); clip:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",border,-border)
  side.clip=clip
  local icon=clip:CreateTexture(nil,"ARTWORK"); icon:SetSize(width,width)
  -- The clip decides visibility; its moving edge must not position the icon.
  if zoom then icon:SetPoint("CENTER",host,"CENTER")
  else icon:SetPoint("TOPLEFT",clip,"TOPLEFT",1+border,-border) end
  icon:SetTexture(A:TextureSource(rule,spellIcon));icon:SetVertexColor(unpack(rule.auracolor))
  A:StyleTexture(clip,icon,rule,mirror,A:TextureSource(rule,spellIcon));side.texture=icon
  container:SetUnit(A:AuraUnit(rule));container:SetEnabled(true);container:UpdateAllAuras()
  return side
 end
 side.colorDriver=A:AttachNativeTextureColor(rule,host,filter,ids,mirror,candidates,sortMethod)
 if rule.duration==1 then
  local long=CreateFrame("AuraContainer",nil,host,"CustomAuraContainerTemplate")
  side.longTimer={container=long}
  long:SetEnabled(false);long:SetSize(1,1);long:SetPoint("CENTER",host,"CENTER")
  long:SetFrameLevel(host:GetFrameLevel()+6)
  long:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
  long:AddAuraSlot("longTimer",filter,{
   candidateFilters=candidates,sortMethod=sortMethod,
   initializeFrame=function(button)
    A:DisableAuraInteraction(button);button:SetFrameLevel(host:GetFrameLevel()+7)
    button:SetSize(size,size);button:SetPoint("CENTER",host,"CENTER")
    local text=button:CreateFontString(nil,"OVERLAY");side.longTimer.text=text
    text:SetFont("Fonts\\FRIZQT__.TTF",A:AuraTextSize(rule,false,true),"OUTLINE");A:CenterAuraTimer(text,button)
    text:SetTextColor(1,1,1,0)
    button:SetDurationText(text,{binding=A:NewTimerBinding(nil,rule,true)})
   end,
  })
  long:SetUnit(A:AuraUnit(rule));long:SetEnabled(true);long:UpdateAllAuras()
 end
 container:AddAuraSlot("aura",filter,{
  candidateFilters=candidates,sortMethod=sortMethod,
  initializeFrame=function(button)
   -- All AuraButton registration is done in its initialiser, never in combat polling.
   side.button=button
   button:SetFrameLevel(host:GetFrameLevel()+4)
   button:SetSize(size,size)
   button:ClearAllPoints(); button:SetPoint("CENTER",host,"CENTER")
   A:DisableAuraInteraction(button)
   local tex=button:CreateTexture(nil,"ARTWORK"); side.texture=tex; tex:SetAllPoints(button)
   A:StyleTexture(button,tex,rule,mirror,tonumber(rule.texture) or rule.texture); tex:SetVertexColor(unpack(rule.auracolor))
   if side.colorDriver then tex:SetAlpha(0) end
   if rule.autodetect==1 then button:SetIcon(tex) else tex:SetTexture(tonumber(rule.texture) or rule.texture) end
   local textParent=CreateFrame("Frame",nil,button)
   textParent:SetAllPoints(button);textParent:SetFrameLevel(host:GetFrameLevel()+6)
   local _,spellIcon=A:Spell(rule.name)
   if A:IsSpellIcon(rule,A:TextureSource(rule,spellIcon)) then
    side.swipe=A:CreateIconSwipe(button,rule,host:GetFrameLevel()+5)
    button:SetDurationCooldown(side.swipe)
   end
   if rule.duration==1 then
    local text=textParent:CreateFontString(nil,"OVERLAY"); side.timer=text
    text:SetFont("Fonts\\FRIZQT__.TTF",A:AuraTextSize(rule,false),"OUTLINE"); A:CenterAuraTimer(text,button); text:SetTextColor(1,1,1,rule.auracolor[4])
    local binding=A:NewTimerBinding(nil,rule)
    local opts={textFormatter=A:TimerFormatter(rule),binding=binding}
    if binding then side.durationBinding=binding end
    button:SetDurationText(text,opts)
   end
   if rule.stacks==1 then
    local text=textParent:CreateFontString(nil,"OVERLAY"); side.stacks=text
    text:SetFont("Fonts\\FRIZQT__.TTF",A:AuraTextSize(rule,true),"OUTLINE"); A:AnchorAuraStacks(text,button,rule); text:SetTextColor(1,1,1,rule.auracolor[4])
    button:SetApplicationCount(text,{})
   end
  end,
 })
 container:SetUnit(A:AuraUnit(rule)); container:SetEnabled(true); container:UpdateAllAuras()
 return side
end
function A:PrepareNative()
 if locked() then return end
 if self.nativeDirty then self:PrimeAuraRules() end
 if not self.nativeDirty then return end
 if not self.nativeLoaded then
  if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn,"Blizzard_AuraContainer") end
  self.nativeLoaded=true; self:LearnSpellBook()
 end
 self.nativeDirty=false
 for i,e in pairs(self.nativeEntries) do
  -- Keep old entry running until its replacement is ready; avoid destroying frames.
  if not yAurasDB.auras[i] or yAurasDB.auras[i]~=e.rule then
   for _,side in ipairs(e.sides) do pcall(side.container.SetEnabled,side.container,false); for _,key in ipairs({"colorDriver","longTimer"}) do local helper=side[key];if helper then pcall(helper.container.SetEnabled,helper.container,false) end end; side.host:Hide() end
   self.nativeEntries[i]=nil
  end
 end
 for i,rule in ipairs(yAurasDB.auras) do
  if rule.enabled==1 and rule.name~="" and rule.type~="Cooldown" and next(self:ResolveIDs(rule)) then
   local signature=table.concat({rule.name,rule.type,rule.unit,rule.myCast,rule.invert,rule.autodetect,rule.texture,rule.scale,rule.xpos,rule.ypos,rule.dual,rule.duration,rule.stacks,rule.lowduration,rule.lowdurationvalue,unpack(rule.auracolor)},"|")
   local ids=self:ResolveIDs(rule); local sorted={}; for id in pairs(ids) do sorted[#sorted+1]=id end; table.sort(sorted); signature=signature..":"..table.concat(sorted,",")..":"..table.concat(rule.lowdurationcolor,",")
   signature=signature..":zoom:"..tostring(A:ZoomIcons())..":level:"..self:AuraFrameLevel(i)
   local profile=self:ApproximateCandidates(rule,ids)
   if profile then
    signature=signature..":approx:"..profile.maxDuration
    for _,key in ipairs(profileFlags) do signature=signature..":"..tostring(profile[key]) end
    for dispel in pairs(profile.includeDispelTypes or {}) do signature=signature..":"..dispel end
   end
   local e=self.nativeEntries[i]
   if not e or e.signature~=signature then
    if e then for _,side in ipairs(e.sides) do pcall(side.container.SetEnabled,side.container,false); for _,key in ipairs({"colorDriver","longTimer"}) do local helper=side[key];if helper then pcall(helper.container.SetEnabled,helper.container,false) end end; side.host:Hide() end end
    e={rule=rule,signature=signature,ids=ids,sides={},approximate=profile~=nil}; self.nativeEntries[i]=e
    for sideIndex=1,rule.dual==1 and 2 or 1 do
     local ok,side,err=pcall(makeSide,rule,sideIndex==2,i)
     if ok and side then e.sides[#e.sides+1]=side
     else e.error=tostring(ok and err or side); self.nativeError=e.error end
    end
   end
  end
 end
end
function A:UseNative(i,rule,force)
 local entry=self.nativeEntries[i]
 if not entry or entry.rule~=rule or #entry.sides==0 or entry.error then return false end
 -- Public out-of-combat reads remain exact and keep learning the profile.
 if entry.approximate and (not locked() or not self:IsAuraRestricted(entry.ids)) then return false end
 -- Keep exact missing-aura indicators on their native presence group even
 -- before combat. Switching from Lua to a cold native group at combat entry
 -- can briefly leave neither the present nor the missing icon visible.
 if not force and not entry.engaged and rule.invert~=1 and not self:IsAuraRestricted(entry.ids) then return false end
 local allow=UnitExists(A:AuraUnit(rule)) and not self:IsDeadAuraUnit(rule) and not (self.gui and self.gui:IsShown()) and self.enabled and rule.enabled==1 and rule.name~="" and self:Conditions(rule) and not self.preview and not self.moveAuras and (entry.approximate or self:CanNativeFilter(rule,entry.ids))
 if not allow then return false end
 for _,side in ipairs(entry.sides) do
  if not side.active then
   local ok,err=pcall(side.container.UpdateAllAuras,side.container)
   for _,key in ipairs({"colorDriver","longTimer"}) do local helper=side[key];if helper then pcall(helper.container.UpdateAllAuras,helper.container) end end
   if not ok then side.host:Hide();self.nativeError=tostring(err);return true,false end
  end
 end
 entry.engaged=true
 for _,side in ipairs(entry.sides) do side.host:Show();side.active=true;side.used=true end
 return true,false
end
function A:HideUnusedNative()
 for _,entry in pairs(self.nativeEntries) do
  for _,side in ipairs(entry.sides) do if not side.used then side.host:Hide();side.active=false end; side.used=false end
 end
end
function A:NativeStatus()
 self:Msg(L.BUILD_2_2_31_APPROXIMATE_PLAYER_DEBUFFS..L.VALUE_ON)
 for _,rule in ipairs(yAurasDB.auras) do
  if rule.enabled==1 and rule.type~="Cooldown" and pendingNames[rule.name] then
   self:Msg(L.SPELL_NAME_LOOKUP..rule.name)
  end
 end
 local count=0
 for i,e in pairs(self.nativeEntries) do
  local ids={}; for id in pairs(e.ids) do ids[#ids+1]=id end; table.sort(ids)
  self:Msg("["..i.."] "..e.rule.name..L.IDS..table.concat(ids,",").."; "..(#e.sides>0 and L.VALUE_NATIVE or L.VALUE_FALLBACK)..(e.error and ": "..e.error or ""))
  if e.approximate then
   self:Msg(L.LEARNED_PROPERTY_MATCHING_NATIVE_LIVE_TIMER..(self:NativeSort(true) and L.STABLE_INSTANCE_ID_ORDER_NOT_AN_INSTANCE_LOCK or L.INSTANCE_ID_SORTING_UNAVAILABLE_ON_THIS_CLIENT))
  elseif e.rule.type=="Debuff" and e.rule.unit=="Player" then
   self:Msg(L.WAITING_TO_LEARN_THIS_DEBUFF_OUTSIDE_COMBAT_APPLY_IT_ONCE_THEN_ENTER_COMBAT)
  elseif not self:CanNativeFilter(e.rule,e.ids) then
   self:Msg(L.COMBAT_IDENTITY_FILTER_UNAVAILABLE_FOR..self:LocalizeValue(e.rule.unit).." "..self:LocalizeValue(e.rule.type)..L.ONLY_READABLE_EXACT_MATCHES_CAN_BE_SHOWN)
  end
  self:Msg(L.TEXTURE_COLOUR..(e.rule.lowduration==1 and L.VALUE_ENABLED or L.VALUE_DISABLED)..L.THRESHOLD..e.rule.lowdurationvalue..L.NORMAL..table.concat(e.rule.auracolor,",")..L.LOW..table.concat(e.rule.lowdurationcolor,","))
  for _,side in ipairs(e.sides) do
   local driver=side.colorDriver
   if driver then self:Msg(L.COLOUR..(driver.colorError or (driver.nativeTexture and L.ENGINE_RENDERED_TEXTURE_NO_PROTECTED_READS or L.NOT_CONFIGURED))) end
  end
  count=count+#e.sides
 end
 self:Msg(L.NATIVE_SLOTS..count..(self.nativeError and L.LAST_ERROR..self.nativeError or ""))
end

function A:SyncNative()
 for _,entry in pairs(self.nativeEntries) do
  for _,side in ipairs(entry.sides) do
   side.host:Hide();side.active=false
   local ok,err=pcall(side.container.UpdateAllAuras,side.container)
   for _,key in ipairs({"colorDriver","longTimer"}) do local helper=side[key];if helper then pcall(helper.container.UpdateAllAuras,helper.container) end end
   if not ok then self.nativeError=tostring(err) end
  end
 end
end
