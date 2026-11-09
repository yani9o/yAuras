local _, localization = ...
local L = localization.L
local _,A=...
local formatters,curves={},{}
local function call(fn,...)
 if not fn then return nil end
 local ok,result=pcall(fn,...); if ok then return result end
end
function A:TimerFormatter(rule)
 local threshold=rule.lowdurationvalue
 if not C_StringUtil or not C_StringUtil.CreateNumericRuleFormatter or not Enum or not Enum.NumericRuleFormatRounding then return nil end
 local key=tostring(threshold)
 if not formatters[key] then
  local rounding=Enum.NumericRuleFormatRounding
  local points={{threshold=0,format=""}}
  if threshold>0 then points[2]={threshold=.000001,format="%.1f"} else points[2]={threshold=.000001,format="%d",step=1,rounding=rounding.Up} end
  if threshold>0 and threshold<100 then points[#points+1]={threshold=threshold+.000001,format="%d",step=1,rounding=rounding.Up} end
  points[#points+1]={threshold=100.000001,format="%dm",step=60,rounding=rounding.Up,components={{div=60}}}
  local f=C_StringUtil.CreateNumericRuleFormatter(); f:SetBreakpoints(points); formatters[key]=f
 end
 return formatters[key]
end
function A:TimerColor(rule,long)
 if not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not CreateColor or not Enum or not Enum.LuaCurveType then return nil end
 local key=rule.lowdurationvalue..":"..rule.auracolor[4]..":"..tostring(long==true)
 if not curves[key] then
  local c=C_CurveUtil.CreateColorCurve(); c:SetType(Enum.LuaCurveType.Step)
  local points={0,rule.lowdurationvalue+.000001,600};table.sort(points)
  for _,seconds in ipairs(points) do
   local visible=long and seconds>=600 or not long and seconds<600
   c:AddPoint(seconds,CreateColor(1,seconds<=rule.lowdurationvalue and 0 or 1,seconds<=rule.lowdurationvalue and 0 or 1,visible and rule.auracolor[4] or 0))
  end
  curves[key]=c
 end
 return curves[key]
end
function A:NewTimerBinding(text,rule,long)
 if not C_DurationUtil or not C_DurationUtil.CreateDurationTextBinding then return nil end
 local binding=C_DurationUtil.CreateDurationTextBinding()
 if text then text:SetTextColor(1,1,1,rule.auracolor[4]); binding:SetFontString(text) end
 binding:SetEnabled(text==nil)
 -- Zero means every game tick, independent of aura scanning frequency.
 binding:SetUpdateInterval(0)
 if Enum and Enum.DurationTimeModifier then binding:SetTimeModifier(Enum.DurationTimeModifier.RealTime) end
 binding:SetExpiredText(""); binding:SetZeroDurationText("")
 self:StyleTimerBinding(binding,rule,long)
 return binding
end
function A:StyleTimerBinding(binding,rule,long)
 local formatter=self:TimerFormatter(rule); if formatter then binding:SetFormatter(formatter) end
 local curve=self:TimerColor(rule,long)
 if curve and Enum.DurationTextBindingProperty then binding:SetTextColorCurve(curve,Enum.DurationTextBindingProperty.RemainingDuration) end
end
function A:ClearTimer(f)
 if f.durationBinding and f.timerActive then f.durationBinding:SetEnabled(false) end
 if f.longDurationBinding then f.longDurationBinding:SetEnabled(false) end
 if f.longTimer then f.longTimer:SetText("") end
 f.timerActive=false; f.timerLastText=nil; f.timerEnd=nil; f.timerSource=nil; f:SetScript("OnUpdate",nil)
 f.timer:SetText("")
end
function A:IsAuraTexture(rule)
 return rule.autodetect~=1 and type(rule.texture)=="string" and
  rule.texture:lower():gsub("\\","/"):find("/auras/",1,true)
end
function A:AuraDisplaySize(rule)
 return (self:IsAuraTexture(rule) and 90 or 45)*(rule.scale or 1)
end
function A:CenterAuraTimer(text,parent)
 -- A fixed icon-width text box truncates 60m / decimal timers with ellipses.
 -- A single center anchor lets the font string size itself to its content.
 text:ClearAllPoints();text:SetSize(0,0);text:SetPoint("CENTER",parent,"CENTER",0,0)
 text:SetJustifyH("CENTER");text:SetJustifyV("MIDDLE");text:SetWordWrap(false)
end
function A:AuraTextSize(rule,stacks,long)
 local size=stacks and (self:IsAuraTexture(rule) and 8 or 12) or (long and 16 or 20)
 return math.max(6,size*rule.scale)
end
function A:AnchorAuraStacks(text,parent,rule)
 local inset=4*(rule.scale or 1)
 text:ClearAllPoints();text:SetSize(0,0)
 text:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",-inset,inset)
 text:SetJustifyH("RIGHT");text:SetJustifyV("BOTTOM");text:SetWordWrap(false)
end
function A:SetTimer(f,rule,object,endTime,remaining,preview)
 f.timer:SetFont("Fonts\\FRIZQT__.TTF",self:AuraTextSize(rule,false),"OUTLINE")
 local style=rule.scale..":"..rule.lowdurationvalue..":"..rule.auracolor[4]
 if preview then endTime=nil; object=nil end
 if rule.duration~=1 or (not object and not endTime) then
  self:ClearTimer(f)
  if preview and rule.duration==1 then f.timer:SetText("60"); f.timer:SetTextColor(1,1,1,rule.auracolor[4]) end
  return
 end
 if not f.durationBinding and C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then f.durationBinding=self:NewTimerBinding(f.timer,rule) end
 if not object and endTime and C_DurationUtil and C_DurationUtil.CreateDuration then
  f.localDuration=f.localDuration or C_DurationUtil.CreateDuration()
  if f.timerEnd~=endTime then f.localDuration:SetTimeFromEnd(endTime,math.max(.001,remaining or endTime-GetTime())) end
  object=f.localDuration
 end
 if object and f.durationBinding then
  if not f.longTimer then f.longTimer=f:CreateFontString(nil,"OVERLAY");self:CenterAuraTimer(f.longTimer,f) end
  f.longTimer:SetFont("Fonts\\FRIZQT__.TTF",self:AuraTextSize(rule,false,true),"OUTLINE")
  if not f.longDurationBinding then f.longDurationBinding=self:NewTimerBinding(f.longTimer,rule,true) end
  f:SetScript("OnUpdate",nil)
  if f.timerStyle~=style then self:StyleTimerBinding(f.durationBinding,rule); self:StyleTimerBinding(f.longDurationBinding,rule,true); f.timerStyle=style end
  if f.timerSource~=object or f.timerEnd~=endTime then f.durationBinding:SetDuration(object);f.longDurationBinding:SetDuration(object); f.timerSource=object end
  f.timerEnd=endTime
  if not f.timerActive then f.durationBinding:SetEnabled(true); f.timerActive=true end
  f.longDurationBinding:SetEnabled(true)
 else
  if not endTime then self:ClearTimer(f); return end
  -- Readable-data fallback only: update on every rendered frame, never on the scan throttle.
  f.timerEnd=endTime; f.timerRule=rule
  f:SetScript("OnUpdate",function(self)
   local seconds=math.max(0,self.timerEnd-GetTime());local r=self.timerRule
   self.timer:SetFont("Fonts\\FRIZQT__.TTF",A:AuraTextSize(r,false,seconds>=600),"OUTLINE")
   local text=seconds<=0 and "" or (seconds>100 and math.ceil(seconds/60).."m" or (seconds<=r.lowdurationvalue and string.format("%.1f",seconds) or tostring(math.ceil(seconds))))
   if self.timerLastText~=text then self.timer:SetText(text); self.timerLastText=text end
   self.timer:SetTextColor(1,seconds<=r.lowdurationvalue and 0 or 1,seconds<=r.lowdurationvalue and 0 or 1,r.auracolor[4])
  end)
  -- The first frame is drawn immediately; subsequent frames use OnUpdate.
  local update=f:GetScript("OnUpdate"); if update then update(f) end
 end
end
function A:LayoutIconSwipe(swipe,parent,rule)
 swipe:ClearAllPoints()
 -- Keep the zoomed swipe inside the one-pixel outline.
 local inset=self:ZoomIcons() and self:IconPixelSize(parent) or 3*(rule.scale or 1)
 swipe:SetPoint("TOPLEFT",parent,"TOPLEFT",inset,-inset)
 swipe:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",-inset,inset)
end
function A:CreateIconSwipe(parent,rule,level)
 local swipe=CreateFrame("Cooldown",nil,parent,"CooldownFrameTemplate")
 self:LayoutIconSwipe(swipe,parent,rule);swipe:SetFrameLevel(level or parent:GetFrameLevel()+1)
 swipe:SetHideCountdownNumbers(true);swipe:SetDrawEdge(false);swipe:SetDrawBling(false)
 swipe:SetUseCircularEdge(false);swipe:SetEdgeScale(.35)
 swipe:SetDrawSwipe(true);swipe:SetSwipeColor(0,0,0,.65)
 swipe:SetReverse(rule.type~="Cooldown");swipe:EnableMouse(false)
 return swipe
end
local cooldownFlashSeconds=1
function A:ClearCooldownFlash(f)
 f.flashRule=nil;f.flashSpell=nil;f.flashEnd=nil;f.flashObject=nil;f.flashUntil=nil
 if f.flash then f.flash:Hide();f.flash:Clear() end
end
function A:IsCooldownFlashing(f,now)
 return (f.flashUntil and now<f.flashUntil) or
  (f.flashEnd and now>=f.flashEnd and now<f.flashEnd+cooldownFlashSeconds)
end
function A:UpdateCooldownFlash(f,rule,object,endTime,now)
 if f.flashRule~=rule or f.flashSpell~=rule.name then self:ClearCooldownFlash(f) end
 -- Leave the flash frame alone on a ready update so the animation can finish.
 if endTime and endTime<=now then return end
 if not object and not endTime then return end
 if not f.flash then
  -- A sibling of the aura: "only on cooldown" and secret visibility gates
  -- may hide the icon on the very frame the completion animation starts.
  local flash=CreateFrame("Cooldown",nil,UIParent,"CooldownFrameTemplate")
  flash:SetFrameStrata("BACKGROUND");flash:SetDrawSwipe(false)
  flash:SetDrawEdge(false);flash:SetDrawBling(true)
  flash:SetHideCountdownNumbers(true);flash:EnableMouse(false)
  flash:HookScript("OnCooldownDone",function()
   if not f.flashRule or f.flashRule.showCD~="CD" then return end
   f.flashUntil=GetTime()+cooldownFlashSeconds
   if f.used then self:ClearCooldownGate(f) end
  end)
  f.flash=flash
 end
 local flash=f.flash
 local zoom=self:ZoomIcons()
 if f.flashZoom~=zoom or f.flashRule~=rule or f.flashX~=rule.xpos or f.flashY~=rule.ypos or f.flashScale~=rule.scale or f.flashLevel~=f.id then
  local size=self:AuraDisplaySize(rule)
  local inset=zoom and self:IconPixelSize(f) or 3*(rule.scale or 1)
  flash:ClearAllPoints();flash:SetPoint("CENTER",UIParent,"CENTER",rule.xpos,rule.ypos)
  flash:SetSize(size-2*inset,size-2*inset);flash:SetFrameLevel(self:AuraFrameLevel(f.id)+5)
  f.flashX,f.flashY,f.flashScale,f.flashLevel,f.flashZoom=rule.xpos,rule.ypos,rule.scale,f.id,zoom
 end
 f.flashRule,f.flashSpell=rule,rule.name
 flash:Show()
 if endTime then
  if f.flashEnd~=endTime then flash:SetCooldown(now,endTime-now) end
 elseif f.flashObject~=object or f.flashEnd then
  -- Keep the prior animation when an opaque duration resolves to zero.
  local ok,err=pcall(flash.SetCooldownFromDurationObject,flash,object,false)
  if not ok then self.nativeError=L.ICON_SWIPE..tostring(err) end
 end
 f.flashEnd,f.flashObject=endTime,object
end
function A:SetIconSwipe(f,rule,source,object,preview)
 f.artworkParent:SetFrameLevel(f:GetFrameLevel()-2)
 if preview or rule.invert==1 or not self:IsSpellIcon(rule,source) or not object then
  if f.swipe then f.swipe:Clear();f.swipe:Hide();f.swipeObject=nil end;return
 end
 if not f.swipe then f.swipe=self:CreateIconSwipe(f,rule,f:GetFrameLevel()-1) end
 self:LayoutIconSwipe(f.swipe,f,rule)
 f.swipe:SetFrameLevel(f:GetFrameLevel()-1);f.swipe:SetReverse(rule.type~="Cooldown")
 -- Artwork below the swipe; the frame's text/border remain above it.
 if f.swipeObject~=object then
  local ok,err=pcall(f.swipe.SetCooldownFromDurationObject,f.swipe,object)
  if not ok then self.nativeError=L.ICON_SWIPE..tostring(err);f.swipe:Hide();return end
  f.swipeObject=object
 end
 f.swipe:Show()
end
-- Resolve a known aura's opaque duration without reading its protected time values.
function A:AuraDuration(unit,data)
 if not data or not self:Public(data) then return nil end
 if self:Public(data.auraInstanceID) and data.auraInstanceID then return call(C_UnitAuras and C_UnitAuras.GetAuraDuration,unit,data.auraInstanceID) end
end

-- Let the client choose an RGBA colour from remaining duration. The result can
-- remain secret: it goes directly from duration curve evaluation to SetVertexColor, never to
-- a Lua comparison, formatter or arithmetic operation.
local textureCurves={}
function A:TextureColorCurve(rule,dim)
 if not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not CreateColor or not Enum or not Enum.LuaCurveType then return nil end
 local normal,low=rule.auracolor,rule.lowdurationcolor
 dim=dim or 1
 local key=table.concat({rule.lowdurationvalue,dim,unpack(normal)},":")..":"..table.concat(low,":")
 if not textureCurves[key] then
  local curve=C_CurveUtil.CreateColorCurve();curve:SetType(Enum.LuaCurveType.Step)
  local n=CreateColor(normal[1]*dim,normal[2]*dim,normal[3]*dim,normal[4])
  local l=CreateColor(low[1]*dim,low[2]*dim,low[3]*dim,low[4])
  curve:AddPoint(0,n) -- Zero-duration/permanent auras keep the normal colour.
  if rule.lowdurationvalue>0 then curve:AddPoint(.000001,l);curve:AddPoint(rule.lowdurationvalue+.000001,n) end
  textureCurves[key]=curve
 end
 return textureCurves[key],key
end
local function applyDurationColor(texture,duration,curve)
 texture:SetVertexColor(duration:EvaluateRemainingDuration(curve):GetRGBA())
end
local function recordColorError(err)
 A.nativeError=L.TEXTURE_COLOUR_2..tostring(err)
end
-- Inline texture markup can carry its own static RGB tint. The engine selects
-- the markup/alpha for the current remaining time; Lua never reads that state.
local function InlineIconSize(size)
 return math.max(1,math.floor(size+.5))
end
function A:TextureMarkup(rule,mirror,color)
 local _,spellIcon=self:Spell(rule.name)
 local source=self:TextureSource(rule,spellIcon)
 source=source or "Interface\\Icons\\INV_Misc_QuestionMark"
 local isIcon=self:IsSpellIcon(rule,source)
 local zoom=isIcon and A:ZoomIcons()
 local lo,hi=zoom and 800 or 0,zoom and 9200 or 10000
 local size=InlineIconSize(self:AuraDisplaySize(rule))
 return ("|T%s:%d:%d:0:0:10000:10000:%d:%d:%d:%d:%d:%d:%d|t"):format(
  tostring(source),size,size,mirror and hi or lo,mirror and lo or hi,lo,hi,
  math.floor(color[1]*255+.5),math.floor(color[2]*255+.5),math.floor(color[3]*255+.5))
end
function A:AttachNativeTextureColor(rule,host,filter,ids,mirror,candidates,sortMethod)
 if rule.lowduration~=1 then return end
 if not C_StringUtil or not C_StringUtil.CreateNumericRuleFormatter then
  recordColorError(L.NATIVE_TEXTURE_FORMATTER_IS_UNAVAILABLE);return
 end
 local normal=self:TextureMarkup(rule,mirror,rule.auracolor)
 local low=self:TextureMarkup(rule,mirror,rule.lowdurationcolor)
 local points={{threshold=0,format=normal}}
 if rule.lowdurationvalue>0 then
  points[#points+1]={threshold=.000001,format=low}
  points[#points+1]={threshold=rule.lowdurationvalue+.000001,format=normal}
 end
 local formatter=C_StringUtil.CreateNumericRuleFormatter();formatter:SetBreakpoints(points)
 local alphaRule=A:Copy(rule)
 alphaRule.auracolor={1,1,1,rule.auracolor[4]}
 alphaRule.lowdurationcolor={1,1,1,rule.lowdurationcolor[4]}
 local curve=A:TextureColorCurve(alphaRule)
 local driver=CreateFrame("Frame",nil,host)
 local container=CreateFrame("AuraContainer",nil,host,"CustomAuraContainerTemplate")
 driver.container=container
 container:SetEnabled(false);container:SetSize(1,1);container:SetPoint("CENTER")
 -- Keep inline artwork below the original button's timer, stacks and border.
 container:SetFrameLevel(host:GetFrameLevel()+1)
 container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
 container:AddAuraSlot("colour",filter,{
  candidateFilters=candidates or {includeSpellIDs=ids},sortMethod=sortMethod,
  initializeFrame=function(button)
   A:DisableAuraInteraction(button)
   button:SetFrameLevel(host:GetFrameLevel()+2)
   local size=A:AuraDisplaySize(rule)
   driver.button=button;button:SetSize(size,size)
   local zoom=A:ZoomIcons()
   if zoom then button:ClearAllPoints() end
   button:SetPoint("CENTER",host,"CENTER")
   local parent=button
   local _,spellIcon=A:Spell(rule.name)
   if A:IsSpellIcon(rule,A:TextureSource(rule,spellIcon)) then
    -- Inline text layout can extend a fraction beyond its nominal image size.
    -- Clip the artwork to the same bounds as the icon.
    parent=CreateFrame("Frame",nil,button,"DisableUntrustedLayoutScriptsTemplate")
    if zoom then
     parent:SetAllPoints(button)
    else
     -- Inline FontString artwork cannot take a Texture mask. Keep it inside
     -- the normal frame's inner opening (the default cooldown inset is 3).
     local inset=3*(rule.scale or 1)
     parent:SetPoint("TOPLEFT",button,"TOPLEFT",inset,-inset)
     parent:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-inset,inset)
    end
    parent:SetClipsChildren(true)
    parent:SetFrameLevel(button:GetFrameLevel());driver.iconClip=parent
    if zoom then
     -- Markup dimensions are integers. Scale just the centered artwork back
     -- to the exact size used by the icon, leaving the clip at full size.
     local inlineSize=InlineIconSize(size)
     local artwork=CreateFrame("Frame",nil,parent)
     artwork:SetSize(inlineSize,inlineSize)
     artwork:SetScale(size/inlineSize)
     artwork:SetPoint("CENTER",parent,"CENTER")
     parent=artwork
    end
   end
   local text=parent:CreateFontString(nil,"ARTWORK");driver.source=text
   text:SetFont("Fonts\\FRIZQT__.TTF",12,"");text:SetPoint("CENTER",parent,"CENTER");text:SetWordWrap(false)
   text:SetText(normal);text:SetTextColor(1,1,1,rule.auracolor[4])
   local binding=A:NewTimerBinding(nil,rule)
   if not binding then error(L.DURATION_TEXT_BINDINGS_ARE_UNAVAILABLE) end
   binding:SetFormatter(formatter);binding:SetExpiredText(normal);binding:SetZeroDurationText(normal)
   if curve then binding:SetTextColorCurve(curve,Enum.DurationTextBindingProperty.RemainingDuration) end
   button:SetDurationText(text,{binding=binding})
  end,
 })
 container:SetUnit(A:AuraUnit(rule));container:SetEnabled(true);container:UpdateAllAuras()
 driver.nativeTexture=true
 return driver
end
function A:SetTextureDuration(f,rule,object,endTime,remaining,dim)
 if rule.lowduration~=1 or (not object and not endTime) then self:ClearTextureDuration(f);return end
 local curve=self:TextureColorCurve(rule,dim)
 if not f.colorDriver then
  local driver=CreateFrame("Frame",nil,f);driver:SetSize(1,1);driver:SetPoint("CENTER");f.colorDriver=driver
  driver:SetScript("OnUpdate",function()
   if f.colorObject and f.colorCurve and f.colorObject.EvaluateRemainingDuration then
    local ok,err=pcall(applyDurationColor,f.texture,f.colorObject,f.colorCurve)
    if not ok then recordColorError(err) end
   elseif f.colorEnd then
    -- Readable fallback is independent of native bindings and Show Duration.
    local rem=math.max(0,f.colorEnd-GetTime());local r=f.colorRule
    local c=rem>0 and rem<=r.lowdurationvalue and r.lowdurationcolor or r.auracolor
    f.texture:SetVertexColor(c[1]*f.colorDim,c[2]*f.colorDim,c[3]*f.colorDim,c[4])
   end
  end)
 end
 if not object and endTime and C_DurationUtil and C_DurationUtil.CreateDuration then
  f.colorDuration=f.colorDuration or C_DurationUtil.CreateDuration()
  if f.colorEnd~=endTime then f.colorDuration:SetTimeFromEnd(endTime,math.max(.001,remaining or endTime-GetTime())) end
  object=f.colorDuration
 end
 f.colorObject=object;f.colorCurve=curve;f.colorEnd=endTime;f.colorRule=rule;f.colorDim=dim or 1
 f.colorDriver:Show();f.colorDriver:GetScript("OnUpdate")()
end
function A:ClearTextureDuration(f)
 if f.colorDriver then f.colorDriver:Hide() end
 f.colorObject=nil;f.colorEnd=nil
end

-- Keep cooldown visibility in the native curve evaluator when timing/state
-- are secret. The result goes directly to SetAlpha; Lua never branches on it.
function A:CanGateCooldown(object,charges)
 return C_CurveUtil and C_CurveUtil.CreateCurve and
  ((object and object.EvaluateRemainingDuration) or (charges and
   (type(charges.count)=="number" or not self:Public(charges.count))))
end
function A:ClearCooldownGate(f)
 if f.cooldownGate then f.cooldownGate:SetScript("OnUpdate",nil);f.cooldownGate:Hide() end
 f.gateDuration=nil;f.gateCharges=nil;f:SetAlpha(1)
end
function A:SetCooldownGate(f,rule,object,unknown,charges)
 if rule.type~="Cooldown" or not unknown or not self:CanGateCooldown(object,charges) or self.preview or (self.gui and self.gui:IsShown()) then
  self:ClearCooldownGate(f);return
 end
 self:ClearTextureDuration(f)
 local signature=rule.showCD..":"..tostring(charges~=nil)..":"..rule.lowduration..":"..rule.lowdurationvalue..":"..table.concat(rule.auracolor,",")..":"..table.concat(rule.lowdurationcolor,",")
 if f.gateStyle~=signature then
  local visibility=C_CurveUtil.CreateCurve();visibility:SetType(Enum.LuaCurveType.Step)
  local zero=rule.showCD=="CD" and 0 or 1
  local positive=rule.showCD=="No CD" and 0 or 1
  -- A charge count means ready at >=1, whereas remaining duration means
  -- cooling down at >0. Both are evaluated by the client.
  if charges then visibility:AddPoint(0,positive);visibility:AddPoint(1,zero)
  else visibility:AddPoint(0,zero);visibility:AddPoint(.000001,positive) end
  f.gateVisibility=visibility;f.gateColor=nil
  if C_CurveUtil.CreateColorCurve and CreateColor then
   local color=C_CurveUtil.CreateColorCurve();color:SetType(Enum.LuaCurveType.Step)
   local normal=rule.auracolor;local low=rule.lowdurationcolor
   local function tint(c,dim) return CreateColor(c[1]*dim,c[2]*dim,c[3]*dim,c[4]) end
   color:AddPoint(0,tint(normal,1))
   color:AddPoint(.000001,tint(rule.lowduration==1 and rule.lowdurationvalue>0 and low or normal,1))
   if rule.lowduration==1 and rule.lowdurationvalue>0 then color:AddPoint(rule.lowdurationvalue+.000001,tint(normal,1)) end
   f.gateColor=color
  end
  f.gateStyle=signature
 end
 if not f.cooldownGate then f.cooldownGate=CreateFrame("Frame",nil,f) end
 f.gateDuration=object;f.gateCharges=charges
 f.cooldownGate:SetScript("OnUpdate",function()
  local ok,err=pcall(function()
   if f.gateCharges then f:SetAlpha(f.gateVisibility:Evaluate(f.gateCharges.count))
   else f:SetAlpha(f.gateDuration:EvaluateRemainingDuration(f.gateVisibility)) end
   if f.gateDuration and f.gateColor then
    local c=f.gateDuration:EvaluateRemainingDuration(f.gateColor)
    f.texture:SetVertexColor(c:GetRGBA())
   end
  end)
  if not ok then A.nativeError=L.COOLDOWN_PRESENTATION..tostring(err) end
 end)
 f.cooldownGate:Show();f.cooldownGate:GetScript("OnUpdate")()
end
