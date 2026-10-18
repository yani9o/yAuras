local _, localization = ...
local L = localization.L
local addonName, A = ...
local gui
local UI = A.UI
local getn = function(t) return #t end
local rawCreateFrame = CreateFrame
local function CreateFrame(kind, name, parent, templates)
 if not templates then
  if kind == "Button" then templates = "UIPanelButtonTemplate,BackdropTemplate"
  elseif kind == "EditBox" then templates = "InputBoxTemplate,BackdropTemplate"
  elseif kind == "Frame" or kind == "Slider" then templates = "BackdropTemplate" end
 end
 local f = rawCreateFrame(kind, name, parent, templates)
 return f
end
-- Settings closes special windows when returning to the game menu. Keep our
-- standalone windows out of that one close pass, then restore Escape support.
function A:AddEscapeWindow(name)
 if self.settingsIndependent and SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then
  self.settingsEscapeNames[name]=true
  return
 end
 for _,entry in ipairs(UISpecialFrames) do if entry==name then return end end
 table.insert(UISpecialFrames,name)
end
function A:KeepEditorIndependent()
 if not SettingsPanel or not SettingsPanel.IsShown or not SettingsPanel:IsShown() then return end
 self.settingsIndependent=true
 self.settingsEscapeNames=self.settingsEscapeNames or {}
 local own={yAurasGUI=true,yAurasEdit=true,yAurasTextureBrowser=true}
 for i=#UISpecialFrames,1,-1 do
  local name=UISpecialFrames[i]
  if own[name] then self.settingsEscapeNames[name]=true;table.remove(UISpecialFrames,i) end
 end
 if self.settingsCloseHooked then return end
 self.settingsCloseHooked=true
 SettingsPanel:HookScript("OnHide",function()
  C_Timer.After(0,function()
   if SettingsPanel:IsShown() then return end
   A.settingsIndependent=false
   for name in pairs(A.settingsEscapeNames) do A:AddEscapeWindow(name) end
   A.settingsEscapeNames={}
  end)
 end)
end

-- Native Forever window chrome around the existing content layout.
-- Only configuration windows call this; live/test aura frames are untouched.
function A:StyleWindow(frame, title)
  if frame.windowStyle then return end
  local chrome = rawCreateFrame("Frame", nil, frame, "PortraitFrameTemplate")
  frame.windowStyle = chrome
  chrome:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 40)
  chrome:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)
  frame:SetFrameLevel(10)
  local level = frame:GetFrameLevel()
  chrome:SetFrameLevel(level)
  chrome.NineSlice:SetFrameLevel(level + 1)
  chrome.PortraitContainer:SetFrameLevel(level)
  chrome.TitleContainer:SetFrameLevel(level + 3)
  chrome.CloseButton:SetFrameLevel(level + 4)
  for _, surface in ipairs({chrome.TitleContainer, chrome.PortraitContainer}) do
    surface:EnableMouse(true); surface:RegisterForDrag("LeftButton")
    surface:SetScript("OnDragStart",function()
      -- Convert the relative anchor before moving to preserve the cursor offset.
      local scale=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
      local left,top=frame:GetLeft()*scale,frame:GetTop()*scale
      frame:ClearAllPoints();frame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left,top)
      frame:StartMoving()
    end)
    surface:SetScript("OnDragStop",function() frame:StopMovingOrSizing() end)
  end
  chrome.PortraitContainer:SetHitRectInsets(-5,-57,-7,-55)
  chrome:EnableMouse(false)
  chrome:SetTitle(title or self.title)
  chrome:SetPortraitToAsset("Interface\\icons\\Spell_holy_improvedresistanceauras")
  -- Shift only the sampled artwork; portrait anchors, mask and border stay fixed.
  local portrait=chrome.PortraitContainer.portrait
  if portrait then portrait:SetTexCoord(.015,1.015,.03,1.03) end
  if chrome.TopTileStreaks then chrome.TopTileStreaks:Hide() end
  chrome.Bg:SetAtlas("QuestLog-main-background",false)
  chrome.Bg:SetVertexColor(1,1,1,1)
  chrome.CloseButton:SetScript("OnClick", function() frame:Hide() end)
  frame:SetClampedToScreen(true)
end

-- Configuration portraits are independent of the aura's rendered artwork.
function A:GetAuraPortrait(aura)
  local _, portrait = self:Spell(aura.name)
  if not portrait and self.ResolveIDs then
    for spellID in pairs(self:ResolveIDs(aura)) do
      local _, icon = self:Spell(spellID); if icon then portrait=icon;break end
    end
  end
  if not portrait and C_Spell and C_Spell.GetSpellTexture then
    local ok,icon=pcall(C_Spell.GetSpellTexture,tonumber(aura.name) or aura.name)
    if ok and (not issecretvalue or not issecretvalue(icon))
      and (type(icon)=="string" or type(icon)=="number") then portrait=icon end
  end
  -- Icon paths also work before learning a spell. Custom aura artwork stays
  -- separate from the editor's spell portrait.
  if not portrait and type(aura.texture)=="string"
    and aura.texture:lower():match("^interface[\\/]icons[\\/]") then
    portrait=aura.texture
  end
  if not portrait and aura.autodetect==1 then portrait=tonumber(aura.texture) end
  return portrait or "Interface\\icons\\INV_Misc_QuestionMark"
end

function A:SetAuraWindowPortrait(frame,id)
  local aura=id and yAurasDB and yAurasDB.auras and yAurasDB.auras[id]
  local chrome=frame.windowStyle
  if not chrome then return end
  chrome:SetPortraitToAsset(aura and self:GetAuraPortrait(aura) or "Interface\\icons\\Spell_holy_improvedresistanceauras")
  local texture=chrome.PortraitContainer.portrait
  if texture then
    if aura then texture:SetTexCoord(0,1,0,1)
    else texture:SetTexCoord(.015,1.015,.03,1.03) end
  end
end

-- Utility: skin frame with backdrop
function A:SkinFrame(frame, bg, border)
  if frame.windowStyle or frame.nativeStyle then return end
  if frame:IsObjectType("Button") or frame:IsObjectType("EditBox") then frame:SetBackdrop(nil); return end
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  local bgr = bg or {0.1, 0.1, 0.1, 0.95}
  local bdr = border or {0, 0, 0, 1}
  frame:SetBackdropColor(bgr[1], bgr[2], bgr[3], bgr[4] or 1)
  frame:SetBackdropBorderColor(bdr[1], bdr[2], bdr[3], bdr[4] or 1)
end

-- Deep copy helper
local function deepCopy(tbl)
  local t = {}
  for k, v in pairs(tbl) do
    t[k] = (type(v) == "table") and deepCopy(v) or v
  end
  return t
end

-- Create Test frames (used by editor preview)
function A:AnchorPreview(frame,x,y)
 -- Dragging can replace the relative anchor with a screen anchor family.
 -- Clear that family before reattaching the reused preview to UIParent.
 frame:StopMovingOrSizing();frame:ClearAllPoints()
 frame:SetPoint("CENTER",UIParent,"CENTER",x,y)
end
function A:CreateTestAuras()

	if not A.SettingsLoaded then return end

	if A.TestAura then return end
	local TestAura = CreateFrame("Frame", "yAurasTest", UIParent)
	TestAura:SetFrameStrata("BACKGROUND")
	TestAura:SetFrameLevel(128)
	TestAura.texture = TestAura:CreateTexture(nil, "ARTWORK")
	TestAura.texture:SetAllPoints(TestAura)
	TestAura.durationtext = TestAura:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	TestAura.durationtext:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	TestAura.durationtext:SetPoint("CENTER", TestAura, "CENTER", 0, 0)
	TestAura.stackstext = TestAura:CreateFontString(nil, "OVERLAY", "GameFontWhite")
	TestAura.stackstext:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	TestAura.stackstext:SetPoint("TOPLEFT", TestAura.durationtext, "CENTER", 1, -6)
	TestAura:Hide()

	local dragger = CreateFrame("Frame", "yAurasDragger" .. 0, TestAura)
	dragger:SetAllPoints(TestAura)
	dragger:SetFrameStrata("HIGH")
	dragger:EnableMouse(true)
	dragger:RegisterForDrag("LeftButton")
	dragger:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8x8",edgeSize = 1,})
	dragger:SetBackdropBorderColor(0, 1, 0, 0.5) -- Green, semi-transparent

	dragger:SetScript("OnDragStart", function()
      A:StartAuraDrag(TestAura,gui.auraEdit,true)
    end)
    dragger:SetScript("OnDragStop", function()
      A:StopAuraDrag();A:Refresh()
    end)
    dragger:SetScript("OnHide", function()
      if A.activeAuraDrag and A.activeAuraDrag.frame==TestAura then A:StopAuraDrag() end
    end)
    TestAura:SetScript("OnHide", function()
      if A.activeAuraDrag and A.activeAuraDrag.frame==TestAura then A:StopAuraDrag() end
    end)

	A.TestAura = TestAura
	dragger:Hide()
	A.draggers[0] = dragger
	
	local TestAuraDual = CreateFrame("Frame", "yAurasTestDual", UIParent)
	TestAuraDual:SetFrameStrata("BACKGROUND")
	TestAuraDual:SetFrameLevel(128)
	TestAuraDual.texture = TestAuraDual:CreateTexture(nil, "ARTWORK")
	TestAuraDual.texture:SetAllPoints(TestAuraDual)
	TestAuraDual.durationtext = TestAuraDual:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	TestAuraDual.durationtext:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	TestAuraDual.durationtext:SetPoint("CENTER", TestAuraDual, "CENTER", 0, 0)
	TestAuraDual.stackstext = TestAuraDual:CreateFontString(nil, "OVERLAY", "GameFontWhite")
	TestAuraDual.stackstext:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	TestAuraDual.stackstext:SetPoint("TOPLEFT", TestAuraDual.durationtext, "CENTER", 1, -6)
	TestAuraDual:Hide()
	A.TestAuraDual = TestAuraDual
	
end

-- Main GUI frame
if not gui then
  gui = CreateFrame("Frame", "yAurasGUI", UIParent)
  A.gui = gui
  gui:SetFrameStrata("HIGH")
  gui:SetPoint("CENTER", UIParent, "CENTER", -155, 0)
  gui:SetWidth(300)
  gui:SetHeight(450)
  gui:SetMovable(true)
  gui:EnableMouse(true)
  A:StyleWindow(gui, A.title)

  local title = gui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -5)
  title:SetText(A.title)
  title:Hide()

  gui:Hide()
  A:AddEscapeWindow("yAurasGUI")
end

-- Add button
local addBtn = CreateFrame("Button", nil, gui)
addBtn:SetPoint("TOPLEFT", 58, 7)
addBtn:SetWidth(20)
addBtn:SetHeight(20)
A:SkinFrame(addBtn, {0.2, 0.2, 0.2, 1})
addBtn.text = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
addBtn.text:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
addBtn.text:SetText("+")
addBtn:SetFontString(addBtn.text)
addBtn:SetScript("OnClick", function() A:AddAura() end)
addBtn:SetScript("OnEnter", function() addBtn:SetBackdropColor(0.1, 0.4, 0.1, 1) end)
addBtn:SetScript("OnLeave", function() addBtn:SetBackdropColor(0.2, 0.2, 0.2, 1) end)

-- Export All button
local exportAllBtn = CreateFrame("Button", nil, gui)
exportAllBtn:SetPoint("TOPLEFT", addBtn, "TOPRIGHT", 5, 0)
exportAllBtn:SetWidth(20)
exportAllBtn:SetHeight(20)
A:SkinFrame(exportAllBtn, {0.2, 0.2, 0.2, 1})
exportAllBtn.text = exportAllBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
exportAllBtn.text:SetPoint("CENTER", exportAllBtn, "CENTER", 0, 0)
exportAllBtn.text:SetText("e")
exportAllBtn:SetScript("OnClick", function() A:ExportAllAuras() end)
exportAllBtn:SetScript("OnEnter", function() exportAllBtn:SetBackdropColor(0.5, 0.5, 0.5, 1) end)
exportAllBtn:SetScript("OnLeave", function() exportAllBtn:SetBackdropColor(0.2, 0.2, 0.2, 1) end)

-- Import button
local importBtn = CreateFrame("Button", nil, gui)
importBtn:SetPoint("TOPLEFT", exportAllBtn, "TOPRIGHT", 5, 0)
importBtn:SetWidth(20)
importBtn:SetHeight(20)
A:SkinFrame(importBtn, {0.2, 0.2, 0.2, 1})
importBtn.text = importBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
importBtn.text:SetPoint("CENTER", importBtn, "CENTER", 0, 0)
importBtn.text:SetText("i")
importBtn:SetScript("OnClick", function() A:ShowImportFrame() end)
importBtn:SetScript("OnEnter", function() importBtn:SetBackdropColor(0.5, 0.5, 0.5, 1) end)
importBtn:SetScript("OnLeave", function() importBtn:SetBackdropColor(0.2, 0.2, 0.2, 1) end)

-- Close button
local closeBtn = CreateFrame("Button", nil, gui)
closeBtn:SetPoint("TOPRIGHT", -2, -2)
closeBtn:SetWidth(20)
closeBtn:SetHeight(20)
A:SkinFrame(closeBtn, {0.2, 0.2, 0.2, 1})
closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
closeBtn.text:SetPoint("CENTER", 0.5, 1)
closeBtn.text:SetText("x")
closeBtn:SetFontString(closeBtn.text)
closeBtn:SetScript("OnClick", function()
  gui:Hide()
  if A.TestAura then A.TestAura:Hide() end
  if A.TestAuraDual then A.TestAuraDual:Hide() end
end)
closeBtn:SetScript("OnEnter", function() closeBtn:SetBackdropColor(0.5, 0.5, 0.5, 1) end)
closeBtn:SetScript("OnLeave", function() closeBtn:SetBackdropColor(0.2, 0.2, 0.2, 1) end)
closeBtn:Hide()

UI.IconButton(addBtn, "Interface\\icons\\INV_Misc_Note_05")
UI.IconButton(exportAllBtn, "Interface\\icons\\INV_Misc_Book_09")
UI.IconButton(importBtn, "Interface\\icons\\Spell_Arcane_PortalStormWind")
exportAllBtn:ClearAllPoints();exportAllBtn:SetPoint("LEFT",addBtn,"RIGHT",6,0)
importBtn:ClearAllPoints();importBtn:SetPoint("LEFT",exportAllBtn,"RIGHT",6,0)

UI.Tooltip(addBtn,L.ADD_AURA)
UI.Tooltip(exportAllBtn,L.EXPORT_ALL_AURAS)
UI.Tooltip(importBtn,L.IMPORT)

-- Keep the aura list inside a fixed viewport; the header stays visible.
local AURA_ROW_HEIGHT = 26
local AURA_ROW_STEP = AURA_ROW_HEIGHT + 5
local listScroll = CreateFrame("ScrollFrame", nil, gui)
listScroll:SetPoint("TOPLEFT", 20, -30)
listScroll:SetPoint("BOTTOMRIGHT", -20, 12)
listScroll:SetClipsChildren(true)
listScroll:EnableMouseWheel(true)
gui.listScroll = listScroll
local listContent = CreateFrame("Frame", nil, listScroll)
listContent:SetSize(260, 1)
listScroll:SetScrollChild(listContent)
gui.listContent = listContent
local listScrollbar = UI.Scrollbar(gui)
listScrollbar:SetOrientation("VERTICAL")
listScrollbar:SetWidth(16)
listScrollbar:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 4, 0)
listScrollbar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 4, 0)
listScrollbar:SetValueStep(1)
listScrollbar:SetMinMaxValues(0, 0)
listScrollbar:SetValue(0)

listScrollbar:EnableMouseWheel(true)
gui.listScrollbar = listScrollbar
local listMaxScroll = 0
local syncingListScroll = false
local function SetListScroll(value)
  if syncingListScroll then return end
  syncingListScroll=true
  local offset = math.max(0, math.min(listMaxScroll, value or 0))
  if listScroll:GetVerticalScroll() ~= offset then listScroll:SetVerticalScroll(offset) end
  if listScrollbar:GetValue() ~= offset then listScrollbar:SetValue(offset) end
  syncingListScroll=false
end
local function UpdateListScrollRange()
  listMaxScroll = math.max(0, listContent:GetHeight() - listScroll:GetHeight())
  listScrollbar:SetMinMaxValues(0, listMaxScroll)
  listScrollbar:SetVisibleExtentPercentage(listScroll:GetHeight()/math.max(1,listContent:GetHeight()))
  listScrollbar:SetShown(listMaxScroll > 0)
  SetListScroll(listScroll:GetVerticalScroll())
end
local function ScrollAuraList(_, delta)
  SetListScroll(listScroll:GetVerticalScroll() - delta * 50)
end
listScrollbar:SetScript("OnValueChanged", function(_, value) SetListScroll(value) end)
listScroll:SetScript("OnVerticalScroll", function(_, value) SetListScroll(value) end)
listScroll:SetScript("OnMouseWheel", ScrollAuraList)
listScrollbar:SetScript("OnMouseWheel", ScrollAuraList)
listScroll:SetScript("OnSizeChanged", UpdateListScrollRange)
function A:EnsureAuraListRowVisible(id)
  local top = (id - 1) * AURA_ROW_STEP
  local offset = listScroll:GetVerticalScroll()
  if top < offset then SetListScroll(top)
  elseif top + AURA_ROW_HEIGHT > offset + listScroll:GetHeight() then
    SetListScroll(top + AURA_ROW_HEIGHT - listScroll:GetHeight())
  end
end

-- Refresh list of configured auras
function A:RefreshAuraList()

  if not A.SettingsLoaded then return end

  -- hide old rows
  for _, entry in ipairs(gui.list or {}) do entry:Hide() end
  gui.list = {}
  gui.rows = gui.rows or {}

  if not yAurasDB or not yAurasDB.auras then return end

  for i, aura in ipairs(yAurasDB.auras) do
    local id = i
    local row = gui.rows[id] or CreateFrame("Button", nil, gui.listContent, "BackdropTemplate")
    gui.rows[id] = row
    row:ClearAllPoints()
    row:Show()
    if row.up then row.up:Hide() end
    if row.down then row.down:Hide() end
    row:SetWidth(260)
    row:SetHeight(AURA_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", gui.listContent, "TOPLEFT", 0, -(id - 1) * AURA_ROW_STEP)
    row:SetFrameStrata("HIGH")
    row.nativeStyle = true
    row:SetNormalAtlas("common-button-list-collapseExpand")
    row:SetHighlightAtlas("questlog-header-glow-yellow")
    local hover=row:GetHighlightTexture()
    hover:ClearAllPoints()
    hover:SetPoint("TOPLEFT",row,"TOPLEFT",0,3)
    hover:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",0,3)
    row.selected = row.selected or row:CreateTexture(nil,"OVERLAY",nil,-1)
    row.selected:SetDrawLayer("OVERLAY",-1)
    row.selected:SetBlendMode("ADD")
    row.selected:ClearAllPoints()
    row.selected:SetPoint("TOPLEFT",row,"TOPLEFT",0,3)
    row.selected:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",0,3)
    row.selected:SetAtlas("questlog-header-glow-yellow")
    row.selected:SetShown(gui.auraEdit == id)
    row:SetBackdrop(nil)

    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", ScrollAuraList)
    row.auraId = id

    -- hover colors (lookup current aura at runtime to avoid nil indexing)
    row:SetScript("OnEnter", function()
      row:SetBackdropColor(0.5, 0.5, 0.5, 1)
    end)

    row:SetScript("OnLeave", function()
      local current = yAurasDB and yAurasDB.auras and yAurasDB.auras[row.auraId]
      if gui.auraEdit == row.auraId then
        row:SetBackdropColor(0.5, 0.5, 0.5, 1)
      elseif current and current.enabled == 0 then
        row:SetBackdropColor(0.4, 0.1, 0.1, 1)
      else
        row:SetBackdropColor(0.2, 0.2, 0.2, 1)
      end
    end)

    -- label
    row.text = row.text or row:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWidth(210)
    row.text:SetText("[" .. id .. "] " .. (aura.name ~= "" and aura.name or L.UNNAMED))
    row.text:SetTextColor(unpack(aura.auracolor or {1, 1, 1}))

    -- initial backdrop state
    if gui.auraEdit == id then
      row:SetBackdropColor(0.5, 0.5, 0.5, 1)
    elseif aura.enabled == 0 then
      row:SetBackdropColor(0.4, 0.1, 0.1, 1)
    end

    -- click to edit
    row:SetScript("OnClick", function()
      if gui.editor then
        if A.TestAura then A.TestAura:Hide() end
        if A.TestAuraDual then A.TestAuraDual:Hide() end
        gui.editor:Hide()
        gui.editor = nil
      end
      A:CreateTestAuras()
      A:EditAura(id)
    end)

    -- up button (swap with previous)
    if id > 1 then
      local up = row.up or CreateFrame("Button", nil, row, "BackdropTemplate")
      row.up = up; up:Show();up:SetFrameLevel(row:GetFrameLevel()+2)
      up:SetWidth(15)
      up:SetHeight(15)
      up:ClearAllPoints();up:SetPoint("RIGHT", row, "RIGHT", -25, 0)
      A:SkinFrame(up, {0.15, 0.15, 0.15, 1})
      UI.Arrow(up, true)
      UI.Tooltip(up,L.MOVE_UP)


      up:SetScript("OnClick", function()
        yAurasDB.auras[id], yAurasDB.auras[id - 1] = yAurasDB.auras[id - 1], yAurasDB.auras[id]
        A:InvalidateAll()
        A:RefreshAuraList()
        if gui.editor then
          if A.TestAura then A.TestAura:Hide() end
          if A.TestAuraDual then A.TestAuraDual:Hide() end
          gui.editor:Hide()
          gui.editor = nil
          A:EditAura(id - 1)
          A:EnsureAuraListRowVisible(id - 1)
        end
      end)
    end

    -- down button (swap with next)
    if id < getn(yAurasDB.auras) then
      local down = row.down or CreateFrame("Button", nil, row, "BackdropTemplate")
      row.down = down; down:Show();down:SetFrameLevel(row:GetFrameLevel()+2)
      down:SetWidth(15)
      down:SetHeight(15)
      down:ClearAllPoints();down:SetPoint("RIGHT", row, "RIGHT", -5, 0)
      A:SkinFrame(down, {0.15, 0.15, 0.15, 1})
      UI.Arrow(down, false)
      UI.Tooltip(down,L.MOVE_DOWN)


      down:SetScript("OnClick", function()
        yAurasDB.auras[id], yAurasDB.auras[id + 1] = yAurasDB.auras[id + 1], yAurasDB.auras[id]
        A:InvalidateAll()
        A:RefreshAuraList()
        if gui.editor then
          if A.TestAura then A.TestAura:Hide() end
          if A.TestAuraDual then A.TestAuraDual:Hide() end
          gui.editor:Hide()
          gui.editor = nil
          A:EditAura(id + 1)
          A:EnsureAuraListRowVisible(id + 1)
        end
      end)
    end

    gui.list[id] = row
  end

  listContent:SetHeight(math.max(1, #yAurasDB.auras * AURA_ROW_STEP - 5))
  UpdateListScrollRange()
end

-- Save aura data from editor
function A:SaveAura(id)
 local ed = gui.editor
 local data = yAurasDB.auras[id]
 if not ed or not data then return end
 local controls = {enabled="enabled",myCast="myCast",autodetect="autoDetect",duration="duration",stacks="stacks",lowduration="lowduration",inCombat="inCombat",outCombat="outCombat",inParty="inParty",inRaid="inRaid",invert="invert",dual="dual",onlyWithTarget="onlyWithTarget"}
 for key,control in pairs(controls) do data[key]=ed[control].value end
 for key,control in pairs({name="name",texture="texturePath",scale="scale",xpos="x",ypos="y",lowdurationvalue="lowdurationvalue"}) do
  local value=ed[control]:GetText(); data[key]=type(A.defaults[key])=="number" and (tonumber(value) or A.defaults[key]) or value
 end
 data.type=ed.typeButton.value or data.type; data.unit=ed.unitButton.value or data.unit; data.showCD=ed.showCD.value or data.showCD
 data.targetType=ed.targetType.value or data.targetType
 data.auracolor=ed.auracolor; data.lowdurationcolor=ed.lowdurationcolor
 yAurasDB.auras[id]=A:Normalize(data)
 A:UpdateDetectedTexture(yAurasDB.auras[id])
 for _,control in ipairs({"name","texturePath","scale","x","y","lowdurationvalue"}) do ed[control]:ClearFocus() end
 A:InvalidateRule(id); A:EditAura(id); A:Refresh()
end

-- Add new aura (optionally copy from existing)
function A:AddAura(copyId)
  table.insert(yAurasDB.auras, {})
  local newId = getn(yAurasDB.auras)
  if copyId and yAurasDB.auras[copyId] then
    yAurasDB.auras[newId] = deepCopy(yAurasDB.auras[copyId])
  else
    yAurasDB.auras[newId] = A:Copy(A.defaults)
  end
  if gui.editor and gui.editor:IsShown() then
    gui.editor:Hide()
    gui.editor = nil
    if A.TestAura then A.TestAura:Hide() end
    if A.TestAuraDual then A.TestAuraDual:Hide() end
  end
  A:UpdateAuras()
  A:EditAura(newId)
  A:EnsureAuraListRowVisible(newId)
end

-- Editor window / show and build controls
function A:EditAura(id)
  local aura = yAurasDB.auras[id]
  if not aura then return end
  A:CreateTestAuras()
  gui.auraEdit = id
  A.TestAura:SetMovable(false)

  local ed = A.editor
  if not ed then
    ed = CreateFrame("Frame", "yAurasEdit", UIParent)
    A.editor = ed
    ed:SetWidth(460)
    ed:SetHeight(485)
    ed:SetPoint("LEFT", gui, "RIGHT", 36, 0)
    A:StyleWindow(ed, A.title)
    ed:SetMovable(true)
    ed:EnableMouse(true)
    ed:SetScript("OnHide", function()
      A:StopAuraDrag()
      gui.editor=nil; gui.auraEdit=nil
      A.TestAura:Hide(); A.TestAuraDual:Hide()
      for _,key in ipairs({"typeButton","unitButton","showCD","targetType"}) do
        if ed[key] and ed[key].menu then ed[key].menu:Hide() end
      end
      if ed.browseFrame then ed.browseFrame:Hide() end
    end)
    A:AddEscapeWindow("yAurasEdit")

    ed.title = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.title:SetPoint("TOP", ed, "TOP", 0, -5)
    ed.title:Hide()
    hooksecurefunc(ed.title, "SetText", function(_, text) ed.windowStyle:SetTitle(text) end)

    -- Enabled Checkbox
    ed.enabled = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.enabled:SetWidth(16)
    ed.enabled:SetHeight(16)
    ed.enabled:SetPoint("TOPLEFT", ed, "TOPLEFT", 12.5, -35)
    A:SkinFrame(ed.enabled, {0.15,0.15,0.15,1})
    ed.enabled:SetScript("OnEnter", function() ed.enabled:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.enabled:SetScript("OnLeave", function() ed.enabled:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.enabled)
    ed.enabled.nativeStyle = true
    ed.enabled.checked = ed.enabled:GetCheckedTexture()





    ed.enabled.value = 1
    ed.enabled:SetScript("OnClick", function(self)
      ed.enabled.value = 1 - (ed.enabled.value or 0)
      if ed.enabled.value == 1 then ed.enabled.checked:Show() else ed.enabled.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)
    ed.enabledLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.enabledLabel:SetPoint("LEFT", ed.enabled, "RIGHT", 5, 0)
    ed.enabledLabel:SetText(L.ENABLED)

	if true then
		-- MyCast Checkbox
		ed.myCast = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
		ed.myCast:SetWidth(16)
		ed.myCast:SetHeight(16)
		ed.myCast:SetPoint("TOPLEFT", ed, "TOPLEFT", 240, -35)
		A:SkinFrame(ed.myCast, {0.15,0.15,0.15,1})
		ed.myCast:SetScript("OnEnter", function() ed.myCast:SetBackdropColor(0.5,0.5,0.5,1) end)
		ed.myCast:SetScript("OnLeave", function() ed.myCast:SetBackdropColor(0.15,0.15,0.15,1) end)
		UI.Check(ed.myCast)
    ed.myCast.nativeStyle = true
    ed.myCast.checked = ed.myCast:GetCheckedTexture()





		ed.myCast.value = 1
		ed.myCast:SetScript("OnClick", function(self)
		  ed.myCast.value = 1 - (ed.myCast.value or 0)
		  if ed.myCast.value == 1 then ed.myCast.checked:Show() else ed.myCast.checked:Hide() end
		  A:SaveAura(gui.auraEdit)
		end)
		ed.myCastLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		ed.myCastLabel:SetPoint("LEFT", ed.myCast, "RIGHT", 5, 0)
		ed.myCastLabel:SetText(L.MY_CASTS_ONLY)
	end
 
    -- Name
    ed.nameLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.nameLabel:SetPoint("TOPLEFT", ed.enabled, "BOTTOMLEFT", 0, -15)
    ed.nameLabel:SetText(L.AURA_NAME)
    ed.name = CreateFrame("EditBox", nil, ed)
    ed.name:SetPoint("LEFT", ed.nameLabel, "RIGHT", 5, 0)
    ed.name:SetWidth(math.max(120, 435 - ed.nameLabel:GetStringWidth() - 5))
    ed.name:SetHeight(20)
    ed.name:SetMultiLine(false)
    ed.name:SetAutoFocus(false)
    ed.name:SetFontObject(GameFontHighlightSmall)
    ed.name:SetTextColor(1, 1, 1)
    ed.name:SetMaxLetters(100)
    ed.name:SetTextInsets(4, 4, 4, 4)
    ed.name:SetJustifyH("LEFT")



    ed.name:SetScript("OnEnterPressed", function() A:SaveAura(gui.auraEdit) end)

    -- Separator
    local lineone = ed:CreateTexture(nil, "OVERLAY")
    lineone:SetTexture("Interface\\Buttons\\WHITE8x8")
    lineone:SetVertexColor(1, 0.8, 0.06, 1)
    lineone:SetPoint("TOPLEFT", ed.nameLabel, "BOTTOMLEFT", 0, -15)
    lineone:SetWidth(435)
    lineone:SetHeight(1)

    -- Texture label + color picker + autodetect
    ed.texLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.texLabel:SetPoint("TOPLEFT", lineone, "BOTTOMLEFT", 0, -15)
    ed.texLabel:SetText(L.ICON_TEXTURE)

    ed.auracolorpicker = CreateFrame("Button", nil, ed, "BackdropTemplate")
    ed.auracolorpicker:SetWidth(24)
    ed.auracolorpicker:SetHeight(12)
    ed.auracolorpicker:SetPoint("LEFT", ed.texLabel, "RIGHT", 5, 0)
    A:SkinFrame(ed.auracolorpicker, {1,1,1,1})
    ed.auracolorpicker.prev = ed.auracolorpicker:CreateTexture(nil, "OVERLAY")
    ed.auracolorpicker.prev:SetAllPoints(ed.auracolorpicker)

    -- Autodetect checkbox
    ed.autoDetect = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.autoDetect:SetWidth(16)
    ed.autoDetect:SetHeight(16)
    ed.autoDetect:SetPoint("LEFT", ed.texLabel, "LEFT", 228, 0)
    A:SkinFrame(ed.autoDetect, {0.15,0.15,0.15,1})
    ed.autoDetect:SetScript("OnEnter", function() ed.autoDetect:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.autoDetect:SetScript("OnLeave", function() ed.autoDetect:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.autoDetect)
    ed.autoDetect.nativeStyle = true
    ed.autoDetect.checked = ed.autoDetect:GetCheckedTexture()





    ed.autoDetect.value = 0
    ed.autoDetect:SetScript("OnClick", function(self)
      ed.autoDetect.value = 1 - (ed.autoDetect.value or 0)
      if ed.autoDetect.value == 1 then ed.autoDetect.checked:Show() else ed.autoDetect.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)

    ed.autoLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.autoLabel:SetPoint("LEFT", ed.autoDetect, "RIGHT", 5, 1)
    ed.autoLabel:SetText(L.AUTODETECT)

    -- Texture input + browse
    ed.texturePath = CreateFrame("EditBox", nil, ed)
    ed.texturePath:SetPoint("TOPLEFT", ed.texLabel, "BOTTOMLEFT", 0, -10)
    ed.texturePath:SetWidth(320)
    ed.texturePath:SetHeight(20)
    ed.texturePath:SetMultiLine(false)
    ed.texturePath:SetAutoFocus(false)
    ed.texturePath:SetTextInsets(4, 4, 4, 4)
    ed.texturePath:SetFontObject(GameFontHighlightSmall)
    ed.texturePath:SetTextColor(1,1,1)



    ed.texturePath:SetScript("OnEnterPressed", function() A:SaveAura(gui.auraEdit) end)
    ed.texturePath:SetScript("OnEnter", function(owner)
      GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
      GameTooltip:SetText(L.ICON_PATH_HELP_TITLE)
      GameTooltip:AddLine(L.ICON_PATH_HELP, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    ed.texturePath:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ed.browseBtn = CreateFrame("Button", nil, ed)
    ed.browseBtn:SetWidth(100)
    ed.browseBtn:SetHeight(20)
    ed.browseBtn:SetPoint("LEFT", ed.texturePath, "RIGHT", 15, 0)
    A:SkinFrame(ed.browseBtn, {0.2,0.2,0.2,1})
    ed.browseBtn.text = ed.browseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.browseBtn.text:SetPoint("CENTER", ed.browseBtn, "CENTER", 0, 0)
    ed.browseBtn.text:SetText(L.BROWSE)
    ed.browseBtn:SetScript("OnEnter", function() ed.browseBtn:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.browseBtn:SetScript("OnLeave", function() ed.browseBtn:SetBackdropColor(0.2,0.2,0.2,1) end)

    -- Scale / position inputs
    ed.scaleLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.scaleLabel:SetPoint("TOPLEFT", ed.texturePath, "TOPLEFT", 0, -30)
    ed.scaleLabel:SetText(L.SCALE)
    ed.scale = CreateFrame("EditBox", nil, ed)
    ed.scale:SetPoint("LEFT", ed.scaleLabel, "RIGHT", 5, 0)
    ed.scale:SetWidth(30)
    ed.scale:SetHeight(20)
	ed.scale:SetJustifyH("CENTER")
    ed.scale:SetMultiLine(false)
    ed.scale:SetAutoFocus(false)
    ed.scale:SetFontObject(GameFontHighlightSmall)
    ed.scale:SetTextColor(1,1,1)



    ed.scale:SetScript("OnEnterPressed", function() A:SaveAura(gui.auraEdit) end)

    ed.xLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.xLabel:SetPoint("LEFT", ed.scaleLabel, "LEFT", 145, 0)
    ed.xLabel:SetText(L.X_POS)
    ed.x = CreateFrame("EditBox", nil, ed)
    ed.x:SetPoint("LEFT", ed.xLabel, "RIGHT", 5, 0)
    ed.x:SetWidth(30)
    ed.x:SetHeight(20)
	ed.x:SetJustifyH("CENTER")
    ed.x:SetMultiLine(false)
    ed.x:SetAutoFocus(false)
    ed.x:SetFontObject(GameFontHighlightSmall)
    ed.x:SetTextColor(1,1,1)



    ed.x:SetScript("OnEnterPressed", function() A:SaveAura(gui.auraEdit) end)

    ed.yLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.yLabel:SetPoint("LEFT", ed.scaleLabel, "LEFT", 290, 0)
    ed.yLabel:SetText(L.Y_POS)
    ed.y = CreateFrame("EditBox", nil, ed)
    ed.y:SetPoint("LEFT", ed.yLabel, "RIGHT", 5, 0)
    ed.y:SetWidth(30)
    ed.y:SetHeight(20)
	ed.y:SetJustifyH("CENTER")
    ed.y:SetMultiLine(false)
    ed.y:SetAutoFocus(false)
    ed.y:SetFontObject(GameFontHighlightSmall)
    ed.y:SetTextColor(1,1,1)



    ed.y:SetScript("OnEnterPressed", function() A:SaveAura(gui.auraEdit) end)

    -- Duration / stacks checkboxes
    ed.duration = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.duration:SetWidth(16)
    ed.duration:SetHeight(16)
    ed.duration:SetPoint("TOPLEFT", ed.scaleLabel, "BOTTOMLEFT", 0, -15)
    A:SkinFrame(ed.duration, {0.15,0.15,0.15,1})
    ed.duration:SetScript("OnEnter", function() ed.duration:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.duration:SetScript("OnLeave", function() ed.duration:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.duration)
    ed.duration.nativeStyle = true
    ed.duration.checked = ed.duration:GetCheckedTexture()





    ed.duration.value = 0
    ed.duration:SetScript("OnClick", function(self)
      ed.duration.value = 1 - (ed.duration.value or 0)
      if ed.duration.value == 1 then ed.duration.checked:Show() else ed.duration.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)
    ed.durationLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.durationLabel:SetPoint("LEFT", ed.duration, "RIGHT", 5, 0)
    ed.durationLabel:SetText(L.SHOW_DURATION)

    ed.stacks = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.stacks:SetWidth(16)
    ed.stacks:SetHeight(16)
    ed.stacks:SetPoint("LEFT", ed.duration, "LEFT", 228, 0)
    A:SkinFrame(ed.stacks, {0.15,0.15,0.15,1})
    ed.stacks:SetScript("OnEnter", function() ed.stacks:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.stacks:SetScript("OnLeave", function() ed.stacks:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.stacks)
    ed.stacks.nativeStyle = true
    ed.stacks.checked = ed.stacks:GetCheckedTexture()





    ed.stacks.value = 0
    ed.stacks:SetScript("OnClick", function(self)
      ed.stacks.value = 1 - (ed.stacks.value or 0)
      if ed.stacks.value == 1 then ed.stacks.checked:Show() else ed.stacks.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)
    ed.stacksLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.stacksLabel:SetPoint("LEFT", ed.stacks, "RIGHT", 5, 0)
    ed.stacksLabel:SetText(L.SHOW_STACKS)

    -- Conditions (unit / type)
    local linetwo = ed:CreateTexture(nil, "OVERLAY")
    linetwo:SetTexture("Interface\\Buttons\\WHITE8x8")
    linetwo:SetVertexColor(1, 0.8, 0.06, 1)
    linetwo:SetPoint("TOPLEFT", ed.duration, "BOTTOMLEFT", 0, -15)
    linetwo:SetWidth(435)
    linetwo:SetHeight(1)

    ed.conditionsLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.conditionsLabel:SetPoint("TOP", linetwo, "BOTTOM", 0, -15)
    ed.conditionsLabel:SetJustifyH("CENTER")
    ed.conditionsLabel:SetText(L.CONDITIONS)

    -- Type dropdown
    ed.typeLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ed.typeLabel:SetPoint("TOPLEFT", linetwo, "BOTTOMLEFT", 0, -45)
    ed.typeLabel:SetText(L.TYPE)
    ed.typeButton = CreateFrame("DropdownButton", nil, ed, "WowStyle1DropdownTemplate,BackdropTemplate")
    ed.typeButton:SetWidth(80)
    ed.typeButton:SetHeight(20)
    ed.typeButton:SetPoint("LEFT", ed.typeLabel, "RIGHT", 5, 0)
    A:SkinFrame(ed.typeButton, {0.2,0.2,0.2,1})



    ed.typeButton.nativeStyle = true
    UI.DropdownLayout(ed.typeButton)
    ed.typeButton:SetSelectionText(function() return A:LocalizeValue(ed.typeButton.value) or "" end)
    ed.typeButton:SetupMenu(function(_,root)
      for _,value in ipairs({"Buff","Debuff","Cooldown"}) do
        local choice=value
        root:CreateRadio(A:LocalizeValue(choice),function() return ed.typeButton.value==choice end,function()
          ed.typeButton.value=choice
          UI.DropdownLabel(ed.typeButton,A:LocalizeValue(choice))
          yAurasDB.auras[gui.auraEdit].type=choice
          A:SaveAura(gui.auraEdit)
        end)
      end
    end)

    -- Unit dropdown
	ed.unitLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ed.unitLabel:SetPoint("LEFT", ed.typeLabel, "LEFT", 228, 0)
	ed.unitLabel:SetText(L.UNIT)
	ed.unitButton = CreateFrame("DropdownButton", nil, ed, "WowStyle1DropdownTemplate,BackdropTemplate")
	ed.unitButton:SetWidth(120)
	ed.unitButton:SetHeight(20)
	ed.unitButton:SetPoint("LEFT", ed.unitLabel, "RIGHT", 5, 0)
	A:SkinFrame(ed.unitButton, {0.2,0.2,0.2,1})



	ed.unitButton.nativeStyle = true
    UI.DropdownLayout(ed.unitButton)
    ed.unitButton:SetSelectionText(function() return A:LocalizeValue(ed.unitButton.value) or "" end)
    ed.unitButton:SetupMenu(function(_,root)
      for _,value in ipairs({"Player","Target","Focus","TargetTarget","Friendly","Enemy"}) do
        local choice=value
        root:CreateRadio(A:LocalizeValue(choice),function() return ed.unitButton.value==choice end,function()
          ed.unitButton.value=choice
          UI.DropdownLabel(ed.unitButton,A:LocalizeValue(choice))
          yAurasDB.auras[gui.auraEdit].unit=choice
          A:SaveAura(gui.auraEdit)
        end)
      end
    end)
	
	-- Cooldown option
	ed.showCD = CreateFrame("DropdownButton", nil, ed, "WowStyle1DropdownTemplate,BackdropTemplate")
	ed.showCD:SetWidth(80)
	ed.showCD:SetHeight(20)
	ed.showCD:SetPoint("LEFT", ed.typeLabel, "LEFT", 228, 0)
	A:SkinFrame(ed.showCD, {0.2,0.2,0.2,1})



	ed.showCD.nativeStyle = true
    UI.DropdownLayout(ed.showCD)
    ed.showCD:SetSelectionText(function() return A:LocalizeValue(ed.showCD.value) or "" end)
    ed.showCD:SetupMenu(function(_,root)
      for _,value in ipairs({"Always","CD","No CD"}) do
        local choice=value
        root:CreateRadio(A:LocalizeValue(choice),function() return ed.showCD.value==choice end,function()
          ed.showCD.value=choice
          UI.DropdownLabel(ed.showCD,A:LocalizeValue(choice))
          yAurasDB.auras[gui.auraEdit].showCD=choice
          A:SaveAura(gui.auraEdit)
        end)
      end
    end)
	ed.showCD:Hide()

    -- Optional target condition, independent of the aura's watched unit.
    ed.onlyWithTarget = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.onlyWithTarget:SetSize(16, 16)
    ed.onlyWithTarget:SetPoint("TOPLEFT", ed.typeLabel, "BOTTOMLEFT", 0, -15)
    A:SkinFrame(ed.onlyWithTarget, {0.15,0.15,0.15,1})
    ed.onlyWithTarget:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.onlyWithTarget:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.onlyWithTarget)
    ed.onlyWithTarget.nativeStyle = true
    ed.onlyWithTarget.checked = ed.onlyWithTarget:GetCheckedTexture()




    ed.onlyWithTarget.value = 0
    ed.onlyWithTarget:SetScript("OnClick", function(self)
      self.value = 1 - (self.value or 0)
      A:SaveAura(gui.auraEdit)
    end)
    ed.onlyWithTargetLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.onlyWithTargetLabel:SetPoint("LEFT", ed.onlyWithTarget, "RIGHT", 5, 0)
    ed.onlyWithTargetLabel:SetText(L.ONLY_SHOW_WITH_TARGET)

    ed.targetType = CreateFrame("DropdownButton", nil, ed, "WowStyle1DropdownTemplate,BackdropTemplate")
    ed.targetType:SetSize(120, 20)
    ed.targetType:SetPoint("LEFT", ed.onlyWithTarget, "LEFT", 228, 0)
    A:SkinFrame(ed.targetType, {0.2,0.2,0.2,1})



    ed.targetType.nativeStyle = true
    UI.DropdownLayout(ed.targetType)
    ed.targetType:SetSelectionText(function() return A:LocalizeValue(ed.targetType.value) or "" end)
    ed.targetType:SetupMenu(function(_,root)
      for _,value in ipairs({"Any","Friendly","Enemy","None"}) do
        local choice=value
        root:CreateRadio(A:LocalizeValue(choice),function() return ed.targetType.value==choice end,function()
          ed.targetType.value=choice
          UI.DropdownLabel(ed.targetType,A:LocalizeValue(choice))
          yAurasDB.auras[gui.auraEdit].targetType=choice
          A:SaveAura(gui.auraEdit)
        end)
      end
    end)

    -- Low duration options
    ed.lowduration = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.lowduration:SetWidth(16)
    ed.lowduration:SetHeight(16)
    ed.lowduration:SetPoint("TOPLEFT", ed.onlyWithTarget, "BOTTOMLEFT", 0, -15)
    A:SkinFrame(ed.lowduration, {0.15,0.15,0.15,1})
    ed.lowduration:SetScript("OnEnter", function() ed.lowduration:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.lowduration:SetScript("OnLeave", function() ed.lowduration:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.lowduration)
    ed.lowduration.nativeStyle = true
    ed.lowduration.checked = ed.lowduration:GetCheckedTexture()





    ed.lowduration.value = 0
    ed.lowduration:SetScript("OnClick", function(self)
      ed.lowduration.value = 1 - (ed.lowduration.value or 0)
      if ed.lowduration.value == 1 then ed.lowduration.checked:Show() else ed.lowduration.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)
    ed.lowdurationLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.lowdurationLabel:SetPoint("LEFT", ed.lowduration, "RIGHT", 5, 0)
    ed.lowdurationLabel:SetText(L.LOW_DURATION_COLOR)

    ed.lowdurationcolorpicker = CreateFrame("Button", nil, ed, "BackdropTemplate")
    ed.lowdurationcolorpicker:SetWidth(24)
    ed.lowdurationcolorpicker:SetHeight(12)
    ed.lowdurationcolorpicker:SetPoint("LEFT", ed.lowdurationLabel, "RIGHT", 10, 0)
    A:SkinFrame(ed.lowdurationcolorpicker, {1,1,1,1})
    ed.lowdurationcolorpicker.prev = ed.lowdurationcolorpicker:CreateTexture(nil, "OVERLAY")
    ed.lowdurationcolorpicker.prev:SetAllPoints(ed.lowdurationcolorpicker)

    ed.lowdurationLabelprefix = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.lowdurationLabelprefix:SetPoint("LEFT", ed.lowdurationcolorpicker, "RIGHT", 12, 0)
    ed.lowdurationLabelprefix:SetText("(<=")

    ed.lowdurationvalue = CreateFrame("EditBox", nil, ed)
    ed.lowdurationvalue:SetPoint("LEFT", ed.lowdurationLabelprefix, "RIGHT", 2, 0)
    ed.lowdurationvalue:SetWidth(30)
    ed.lowdurationvalue:SetHeight(20)
	ed.lowdurationvalue:SetJustifyH("CENTER")
    ed.lowdurationvalue:SetMultiLine(false)
    ed.lowdurationvalue:SetAutoFocus(false)
    ed.lowdurationvalue:SetFontObject(GameFontHighlightSmall)
    ed.lowdurationvalue:SetTextColor(1,1,1)



    ed.lowdurationvalue:SetScript("OnEnterPressed", function() A:SaveAura(gui.auraEdit) end)

    ed.lowdurationLabelsuffix = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.lowdurationLabelsuffix:SetPoint("LEFT", ed.lowdurationvalue, "RIGHT", 2, 0)
    ed.lowdurationLabelsuffix:SetText(L.SEC)

    -- In Combat checkbox
    ed.inCombat = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.inCombat:SetWidth(16)
    ed.inCombat:SetHeight(16)
    ed.inCombat:SetPoint("TOPLEFT", ed.lowduration, "BOTTOMLEFT", 0, -15)
    A:SkinFrame(ed.inCombat, {0.15,0.15,0.15,1})
    ed.inCombat:SetScript("OnEnter", function() ed.inCombat:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.inCombat:SetScript("OnLeave", function() ed.inCombat:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.inCombat)
    ed.inCombat.nativeStyle = true
    ed.inCombat.checked = ed.inCombat:GetCheckedTexture()





    ed.inCombat.value = 0
    ed.inCombat:SetScript("OnClick", function(self)
      ed.inCombat.value = 1 - (ed.inCombat.value or 0)
      if ed.inCombat.value == 1 then ed.inCombat.checked:Show() else ed.inCombat.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)

    ed.incombatLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.incombatLabel:SetPoint("LEFT", ed.inCombat, "RIGHT", 5, 1)
    ed.incombatLabel:SetText(L.IN_COMBAT)

    -- Out of Combat checkbox
    ed.outCombat = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.outCombat:SetWidth(16)
    ed.outCombat:SetHeight(16)
    ed.outCombat:SetPoint("LEFT", ed.inCombat, "LEFT", 228, 0)
    A:SkinFrame(ed.outCombat, {0.15,0.15,0.15,1})
    ed.outCombat:SetScript("OnEnter", function() ed.outCombat:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.outCombat:SetScript("OnLeave", function() ed.outCombat:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.outCombat)
    ed.outCombat.nativeStyle = true
    ed.outCombat.checked = ed.outCombat:GetCheckedTexture()





    ed.outCombat.value = 0
    ed.outCombat:SetScript("OnClick", function(self)
      ed.outCombat.value = 1 - (ed.outCombat.value or 0)
      if ed.outCombat.value == 1 then ed.outCombat.checked:Show() else ed.outCombat.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)

    ed.outcombatLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.outcombatLabel:SetPoint("LEFT", ed.outCombat, "RIGHT", 5, 1)
    ed.outcombatLabel:SetText(L.OUT_OF_COMBAT)

    -- In Party checkbox
    ed.inParty = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.inParty:SetWidth(16)
    ed.inParty:SetHeight(16)
    ed.inParty:SetPoint("TOPLEFT", ed.inCombat, "BOTTOMLEFT", 0, -15)
    A:SkinFrame(ed.inParty, {0.15,0.15,0.15,1})
    ed.inParty:SetScript("OnEnter", function() ed.inParty:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.inParty:SetScript("OnLeave", function() ed.inParty:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.inParty)
    ed.inParty.nativeStyle = true
    ed.inParty.checked = ed.inParty:GetCheckedTexture()





    ed.inParty.value = 0
    ed.inParty:SetScript("OnClick", function(self)
      ed.inParty.value = 1 - (ed.inParty.value or 0)
      if ed.inParty.value == 1 then ed.inParty.checked:Show() else ed.inParty.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)
    ed.inpartyLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.inpartyLabel:SetPoint("LEFT", ed.inParty, "RIGHT", 5, 1)
    ed.inpartyLabel:SetText(L.IN_PARTY)

    -- In Raid checkbox
    ed.inRaid = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.inRaid:SetWidth(16)
    ed.inRaid:SetHeight(16)
    ed.inRaid:SetPoint("TOPLEFT", ed.outCombat, "BOTTOMLEFT", 0, -15)
    A:SkinFrame(ed.inRaid, {0.15,0.15,0.15,1})
    ed.inRaid:SetScript("OnEnter", function() ed.inRaid:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.inRaid:SetScript("OnLeave", function() ed.inRaid:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.inRaid)
    ed.inRaid.nativeStyle = true
    ed.inRaid.checked = ed.inRaid:GetCheckedTexture()





    ed.inRaid.value = 0
    ed.inRaid:SetScript("OnClick", function(self)
      ed.inRaid.value = 1 - (ed.inRaid.value or 0)
      if ed.inRaid.value == 1 then ed.inRaid.checked:Show() else ed.inRaid.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)
    ed.inraidLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.inraidLabel:SetPoint("LEFT", ed.inRaid, "RIGHT", 5, 1)
    ed.inraidLabel:SetText(L.IN_RAID)

    -- Invert / Dual
    ed.invert = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.invert:SetWidth(16)
    ed.invert:SetHeight(16)
    ed.invert:SetPoint("BOTTOMLEFT", ed, "BOTTOMLEFT", 12.5, 40)
    A:SkinFrame(ed.invert, {0.15,0.15,0.15,1})
    ed.invert:SetScript("OnEnter", function() ed.invert:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.invert:SetScript("OnLeave", function() ed.invert:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.invert)
    ed.invert.nativeStyle = true
    ed.invert.checked = ed.invert:GetCheckedTexture()





    ed.invert.value = 0
    ed.invert:SetScript("OnClick", function(self)
      ed.invert.value = 1 - (ed.invert.value or 0)
      if ed.invert.value == 1 then ed.invert.checked:Show() else ed.invert.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)
    ed.invertLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.invertLabel:SetPoint("LEFT", ed.invert, "RIGHT", 5, 0)
	ed.invertLabel:SetText(L.INVERT)

    ed.dual = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate,BackdropTemplate")
    ed.dual:SetWidth(16)
    ed.dual:SetHeight(16)
    ed.dual:SetPoint("LEFT", ed.invert, "LEFT", 228, 0)
    A:SkinFrame(ed.dual, {0.15,0.15,0.15,1})
    ed.dual:SetScript("OnEnter", function() ed.dual:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.dual:SetScript("OnLeave", function() ed.dual:SetBackdropColor(0.15,0.15,0.15,1) end)
    UI.Check(ed.dual)
    ed.dual.nativeStyle = true
    ed.dual.checked = ed.dual:GetCheckedTexture()





    ed.dual.value = 0
    ed.dual:SetScript("OnClick", function(self)
      ed.dual.value = 1 - (ed.dual.value or 0)
      if ed.dual.value == 1 then ed.dual.checked:Show() else ed.dual.checked:Hide() end
	  A:SaveAura(gui.auraEdit)
    end)
    ed.dualLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.dualLabel:SetPoint("LEFT", ed.dual, "RIGHT", 5, 0)
    ed.dualLabel:SetText(L.DUAL)
	
	if aura.type == "Cooldown" then
		ed.unitLabel:Hide()
		ed.unitButton:Hide()
		ed.invert:Hide()
		ed.invertLabel:Hide()
		ed.dual:Hide()
		ed.dualLabel:Hide()
		ed.showCD:Show()
	end

    -- Delete / Close / Copy buttons
    ed.delete = CreateFrame("Button", nil, ed)
    ed.delete:SetPoint("BOTTOM", 0, 8)
    ed.delete:SetWidth(100)
    ed.delete:SetHeight(20)
    A:SkinFrame(ed.delete, {0.2,0.2,0.2,1})
    ed.delete.text = ed.delete:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.delete.text:SetPoint("CENTER", ed.delete, "CENTER", 0, 0)
    ed.delete.text:SetText(L.DELETE)
    ed.delete:SetScript("OnEnter", function() ed.delete:SetBackdropColor(0.4,0.1,0.1,1) end)
    ed.delete:SetScript("OnLeave", function() ed.delete:SetBackdropColor(0.2,0.2,0.2,1) end)

    ed.copy = CreateFrame("Button", nil, ed)
    ed.copy:SetPoint("TOPLEFT", 2, -2)
    ed.copy:SetWidth(20)
    ed.copy:SetHeight(20)
    A:SkinFrame(ed.copy, {0.2,0.2,0.2,1})
    ed.copy.text = ed.copy:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.copy.text:SetPoint("CENTER", 0.5, 1)
    ed.copy.text:SetText("c")
    ed.copy:SetScript("OnEnter", function() ed.copy:SetBackdropColor(0.1,0.4,0.1,1) end)
    ed.copy:SetScript("OnLeave", function() ed.copy:SetBackdropColor(0.2,0.2,0.2,1) end)

    -- Export Single button
    ed.export = CreateFrame("Button", nil, ed)
    ed.export:SetPoint("TOPLEFT", ed.copy, "TOPRIGHT", 5, 0)
    ed.export:SetWidth(20)
    ed.export:SetHeight(20)
    A:SkinFrame(ed.export, {0.2,0.2,0.2,1})
    ed.export.text = ed.export:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ed.export.text:SetPoint("CENTER", 0.5, 1)
    ed.export.text:SetText("e")
    ed.export:SetScript("OnEnter", function() ed.export:SetBackdropColor(0.5,0.5,0.5,1) end)
    ed.export:SetScript("OnLeave", function() ed.export:SetBackdropColor(0.2,0.2,0.2,1) end)

    UI.IconButton(ed.copy, "Interface\\icons\\INV_Misc_Note_05")
    UI.IconButton(ed.export, "Interface\\icons\\INV_Misc_Book_09")
    UI.Tooltip(ed.copy,L.COPY_AURA)
    UI.Tooltip(ed.export,L.EXPORT_AURA)
    UI.Tooltip(ed.browseBtn,L.SELECT_TEXTURE)
    UI.Tooltip(ed.delete,L.DELETE_AURA)
    UI.Tooltip(ed.auracolorpicker,L.ICON_TEXTURE)
    UI.Tooltip(ed.lowdurationcolorpicker,L.LOW_DURATION_COLOR)
    ed.copy:ClearAllPoints(); ed.copy:SetPoint("TOPLEFT",58,7)
    ed.export:ClearAllPoints(); ed.export:SetPoint("LEFT",ed.copy,"RIGHT",6,0)
    gui.editor = ed
  end
  gui.editor = ed
  if ed.confirm then ed.confirm:Hide() end
  if ed.browseFrame then ed.browseFrame:Hide() end
  for _,control in ipairs({ed.typeButton, ed.unitButton, ed.showCD, ed.targetType}) do if control.menu then control.menu:Hide() end end
  for _,control in ipairs({ed.unitLabel, ed.unitButton, ed.invert, ed.invertLabel, ed.dual, ed.dualLabel}) do control:SetShown(aura.type ~= "Cooldown") end
  ed.showCD:SetShown(aura.type == "Cooldown")

  -- Populate fields with aura values
  A:SetAuraWindowPortrait(ed,id)
  ed.title:SetText("[" .. tostring(gui.auraEdit) .. "] " .. (aura.name ~= "" and aura.name or L.UNNAMED))
  ed.enabled.value = aura.enabled or 1
  if ed.enabled.value == 1 then ed.enabled.checked:Show() else ed.enabled.checked:Hide() end
  if ed.myCast then
	  ed.myCast.value = aura.myCast or 0
	  if ed.myCast.value == 1 then ed.myCast.checked:Show() else ed.myCast.checked:Hide() end
  end
  ed.name:SetText(aura.name or "")
  ed.auracolor = aura.auracolor or {1,1,1,1}
  ed.auracolorpicker = ed.auracolorpicker -- ensure exists
  ed.auracolorpicker.prev:SetColorTexture(unpack(ed.auracolor))

  ed.autoDetect.value = aura.autodetect or 0
  if ed.autoDetect.value == 1 then ed.autoDetect.checked:Show() else ed.autoDetect.checked:Hide() end

  A:UpdateDetectedTexture(aura)
  ed.texturePath:SetText(aura.texture or "")
  ed.scale:SetText(aura.scale or 1)
  ed.x:SetText(aura.xpos or 0)
  ed.y:SetText(aura.ypos or 0)

  ed.duration.value = aura.duration or 0
  if ed.duration.value == 1 then ed.duration.checked:Show() else ed.duration.checked:Hide() end

  ed.stacks.value = aura.stacks or 0
  if ed.stacks.value == 1 then ed.stacks.checked:Show() else ed.stacks.checked:Hide() end

  ed.onlyWithTarget.value = aura.onlyWithTarget or 0
  ed.onlyWithTarget.checked:SetShown(ed.onlyWithTarget.value == 1)
  ed.targetType.value = aura.targetType or "Any"
  UI.DropdownLabel(ed.targetType,A:LocalizeValue(ed.targetType.value))
  ed.targetType:SetEnabled(ed.onlyWithTarget.value == 1)
  ed.targetType:SetAlpha(ed.onlyWithTarget.value == 1 and 1 or 0.5)

  ed.lowduration.value = aura.lowduration or 0
  if ed.lowduration.value == 1 then ed.lowduration.checked:Show() else ed.lowduration.checked:Hide() end
  ed.lowdurationvalue:SetText(aura.lowdurationvalue or 0)
  ed.lowdurationcolor = aura.lowdurationcolor or {1,0,0,1}
  ed.lowdurationcolorpicker.prev:SetColorTexture(unpack(ed.lowdurationcolor))

  ed.typeButton.value = aura.type or "Buff"
  UI.DropdownLabel(ed.typeButton,A:LocalizeValue(ed.typeButton.value))
  if ed.unitButton then
	ed.unitButton.value = aura.unit or "Player"
  UI.DropdownLabel(ed.unitButton,A:LocalizeValue(ed.unitButton.value))
  end
  if ed.showCD then
	ed.showCD.value = aura.showCD or "Always"
  UI.DropdownLabel(ed.showCD,A:LocalizeValue(ed.showCD.value))
  end
  ed.inCombat.value = aura.inCombat or 0
  if ed.inCombat.value == 1 then ed.inCombat.checked:Show() else ed.inCombat.checked:Hide() end
  ed.outCombat.value = aura.outCombat or 0
  if ed.outCombat.value == 1 then ed.outCombat.checked:Show() else ed.outCombat.checked:Hide() end
  ed.inRaid.value = aura.inRaid or 0
  if ed.inRaid.value == 1 then ed.inRaid.checked:Show() else ed.inRaid.checked:Hide() end
  ed.inParty.value = aura.inParty or 0
  if ed.inParty.value == 1 then ed.inParty.checked:Show() else ed.inParty.checked:Hide() end
  ed.invert.value = aura.invert or 0
  if ed.invert.value == 1 then ed.invert.checked:Show() else ed.invert.checked:Hide() end
  ed.dual.value = aura.dual or 0
  if ed.dual.value == 1 then ed.dual.checked:Show() else ed.dual.checked:Hide() end

  ed.export:SetScript("OnClick", function() A:ExportSingleAura(gui.auraEdit) end)

  -- Show Test aura(s)
  A:AnchorPreview(A.TestAura,aura.xpos or 0,aura.ypos or 0)
  local displaySize=A:AuraDisplaySize(aura)
  A.TestAura:SetSize(displaySize,displaySize)
  A.TestAura:SetFrameLevel(A:AuraFrameLevel(gui.auraEdit)+4)
  A:CenterAuraTimer(A.TestAura.durationtext,A.TestAura)
  local _,spellIcon=A:Spell(aura.name)
  local source=A:TextureSource(aura,spellIcon)
  A.TestAura.texture:SetTexture(source)
  A:StyleTexture(A.TestAura,A.TestAura.texture,aura,false,source)
  A.TestAura.texture:SetVertexColor(unpack(aura.auracolor or {1,1,1,1}))
  if aura.duration == 1 then A.TestAura.durationtext:SetText("60") A.TestAura.durationtext:SetFont("Fonts\\FRIZQT__.TTF", A:AuraTextSize(aura,false), "OUTLINE") else A.TestAura.durationtext:SetText("") end
  A:AnchorAuraStacks(A.TestAura.stackstext,A.TestAura,aura)
  if aura.stacks == 1 then A.TestAura.stackstext:SetText("20") A.TestAura.stackstext:SetFont("Fonts\\FRIZQT__.TTF", A:AuraTextSize(aura,true), "OUTLINE") else A.TestAura.stackstext:SetText("") end
	  
	  local _, _, _, durationalpha = unpack(aura.auracolor or {1,1,1,1})
	  local durationcolor = {1, 1, 1, durationalpha}
	  local stackcolor = {1, 1, 1, durationalpha}

	  A.TestAura.durationtext:SetTextColor(unpack(durationcolor))
	  A.TestAura.stackstext:SetTextColor(unpack(stackcolor))
	  A.TestAuraDual.durationtext:SetTextColor(unpack(durationcolor))
	  A.TestAuraDual.stackstext:SetTextColor(unpack(stackcolor))
	  
  A.TestAura:Show()
  
  if aura.dual == 1 and aura.type ~= "Cooldown" then
    A:AnchorPreview(A.TestAuraDual,-(aura.xpos or 0),aura.ypos or 0)
    A.TestAuraDual:SetSize(displaySize,displaySize)
    A.TestAuraDual:SetFrameLevel(A:AuraFrameLevel(gui.auraEdit)+4)
    A:CenterAuraTimer(A.TestAuraDual.durationtext,A.TestAuraDual)
    A.TestAuraDual.texture:SetTexture(source)
    A:StyleTexture(A.TestAuraDual,A.TestAuraDual.texture,aura,true,source)
    A.TestAuraDual.texture:SetVertexColor(unpack(aura.auracolor or {1,1,1,1}))
    if aura.duration == 1 then A.TestAuraDual.durationtext:SetText("60") A.TestAuraDual.durationtext:SetFont("Fonts\\FRIZQT__.TTF", A:AuraTextSize(aura,false), "OUTLINE") else A.TestAuraDual.durationtext:SetText("") end
    A:AnchorAuraStacks(A.TestAuraDual.stackstext,A.TestAuraDual,aura)
    if aura.stacks == 1 then A.TestAuraDual.stackstext:SetText("20") A.TestAuraDual.stackstext:SetFont("Fonts\\FRIZQT__.TTF", A:AuraTextSize(aura,true), "OUTLINE") else A.TestAuraDual.stackstext:SetText("") end
    A.TestAuraDual:Show()
  else
    A.TestAuraDual:Hide()
  end

  for _,key in ipairs({"enabled","myCast","autoDetect","duration","stacks","onlyWithTarget","lowduration","inCombat","outCombat","inParty","inRaid","invert","dual"}) do ed[key]:SetChecked(ed[key].value == 1) end

  -- Editor button handlers
  ed.windowStyle.CloseButton:SetScript("OnClick", function() ed:Hide(); gui.editor = nil; A.TestAura:Hide(); A.TestAuraDual:Hide(); gui.auraEdit = nil; A:RefreshAuraList(); end)
  ed.copy:SetScript("OnClick", function() A:AddAura(gui.auraEdit) end)

  ed.delete:SetScript("OnClick", function()
    if ed.confirm then A:SetAuraWindowPortrait(ed.confirm,gui.auraEdit); ed.confirm.msg:SetText(string.format(L.DELETE_AURA_CONFIRM, gui.auraEdit, yAurasDB.auras[gui.auraEdit].name or L.UNNAMED)); ed.confirm:Show(); return end
    ed.confirm = CreateFrame("Frame", nil, UIParent)
    ed.confirm:EnableMouse(true)
    ed.confirm:SetMovable(true)
    ed.confirm:SetFrameStrata("DIALOG")
    ed.confirm:SetFrameLevel(10)
    ed.confirm:SetPoint("CENTER", ed, "CENTER", 0, 0)
    ed.confirm:SetWidth(250)
    ed.confirm:SetHeight(80)
    A:StyleWindow(ed.confirm, A.title)
    -- Keep the entire dialog chrome above the editor, including its portrait.
    local level=ed:GetFrameLevel()+20
    ed.confirm:SetFrameLevel(level)
    local chrome=ed.confirm.windowStyle
    chrome:SetFrameLevel(level)
    chrome.NineSlice:SetFrameLevel(level+1)
    chrome.PortraitContainer:SetFrameLevel(level)
    chrome.TitleContainer:SetFrameLevel(level+3)
    chrome.CloseButton:SetFrameLevel(level+4)
    -- Copy the editor's actual backdrop and crop its center for the smaller dialog.
    local function updateDialogBackground()
      local source=ed.windowStyle.Bg
      local target=chrome.Bg
      local asset=source:GetTexture()
      if not asset then return end
      target:SetTexture(asset)
      target:SetHorizTile(false);target:SetVertTile(false)
      local ulx,uly,llx,lly,urx,ury,lrx,lry=source:GetTexCoord()
      local width=math.min(1,target:GetWidth()/math.max(1,source:GetWidth()))
      local height=math.min(1,target:GetHeight()/math.max(1,source:GetHeight()))
      local u0,u1=(1-width)/2,(1+width)/2
      local v0,v1=(1-height)/2,(1+height)/2
      local function sample(u,v)
        return ulx*(1-u)*(1-v)+urx*u*(1-v)+llx*(1-u)*v+lrx*u*v,
          uly*(1-u)*(1-v)+ury*u*(1-v)+lly*(1-u)*v+lry*u*v
      end
      local x0,y0=sample(u0,v0)
      local x1,y1=sample(u0,v1)
      local x2,y2=sample(u1,v0)
      local x3,y3=sample(u1,v1)
      target:SetTexCoord(x0,y0,x1,y1,x2,y2,x3,y3)
      target:SetVertexColor(source:GetVertexColor())
    end
    chrome:HookScript("OnSizeChanged",updateDialogBackground)
    chrome:HookScript("OnShow",updateDialogBackground)
    updateDialogBackground()
    -- Short portrait frames need native bottom-corner cropping; otherwise their
    -- lower corner art overlaps the portrait corner.
    local function updateDialogCorners(self,_,height)
      if NineSliceUtil and NineSliceUtil.UpdateCornerCropping then
        NineSliceUtil.UpdateCornerCropping(self,height or self:GetHeight())
      end
    end
    chrome:HookScript("OnSizeChanged",updateDialogCorners)
    chrome:HookScript("OnShow",function(self)updateDialogCorners(self)end)
    updateDialogCorners(chrome)
    A:SetAuraWindowPortrait(ed.confirm,gui.auraEdit)
    local msg = ed.confirm:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    ed.confirm.msg = msg
    msg:SetPoint("TOP", 0, -20)
    msg:SetText(string.format(L.DELETE_AURA_CONFIRM, gui.auraEdit, aura.name ~= "" and aura.name or L.UNNAMED))
    msg:SetTextColor(1,0,0)

    local yes = CreateFrame("Button", nil, ed.confirm)
    yes:SetPoint("BOTTOMLEFT", 30, 10)
    yes:SetWidth(60)
    yes:SetHeight(20)
    A:SkinFrame(yes, {0.2,0.2,0.2,1})
    yes.text = yes:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    yes.text:SetPoint("CENTER", yes, "CENTER", 0, 0)
    yes.text:SetText(L.YES)
    yes:SetScript("OnEnter", function() yes:SetBackdropColor(0.4,0.1,0.1,1) end)
    yes:SetScript("OnLeave", function() yes:SetBackdropColor(0.2,0.2,0.2,1) end)
    yes:SetScript("OnClick", function()
      table.remove(yAurasDB.auras, gui.auraEdit)
      A:InvalidateAll()
      A:Refresh()
      ed.confirm:Hide()
      ed:Hide()
      gui.editor = nil
      gui.auraEdit = nil
      A:RefreshAuraList()
      A.TestAura:Hide()
      A.TestAuraDual:Hide()
    end)

    local no = CreateFrame("Button", nil, ed.confirm)
    no:SetPoint("BOTTOMRIGHT", -30, 10)
    no:SetWidth(60)
    no:SetHeight(20)
    A:SkinFrame(no, {0.2,0.2,0.2,1})
    no.text = no:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    no.text:SetPoint("CENTER", no, "CENTER", 0, 0)
    no.text:SetText(L.NO)
    no:SetScript("OnEnter", function() no:SetBackdropColor(0.5,0.5,0.5,1) end)
    no:SetScript("OnLeave", function() no:SetBackdropColor(0.2,0.2,0.2,1) end)
    no:SetScript("OnClick", function() ed.confirm:Hide() end)
  end)

  ed.auracolorpicker:SetScript("OnClick", function() A:PickColor("auracolor") end)
  ed.lowdurationcolorpicker:SetScript("OnClick", function() A:PickColor("lowdurationcolor") end)

  -- Browse textures
  ed.browseBtn:SetScript("OnClick", function(self)
    if ed.browseFrame then
      ed.browseFrame.selectedTexture=ed.texturePath:GetText()
      A:SetAuraWindowPortrait(ed.browseFrame,gui.auraEdit)
      ed.browseFrame:UpdateSelection();ed.browseFrame:Show();return
    end
    local bf = CreateFrame("Frame", "yAurasTextureBrowser", UIParent)
    A:AddEscapeWindow("yAurasTextureBrowser")
    bf:SetMovable(true)
    bf:EnableMouse(true)
    bf:SetSize(300,450)
    bf:SetPoint("CENTER",UIParent,"CENTER",0,0)
    bf:SetFrameStrata("DIALOG")
    A:StyleWindow(bf, L.SELECT_TEXTURE)
    A:SetAuraWindowPortrait(bf,gui.auraEdit)
    ed.browseFrame = bf

    bf.title = bf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bf.title:SetPoint("TOP", bf, "TOP", 0, -5)
    bf.title:SetText(L.SELECT_TEXTURE)
    bf.title:Hide()

    local close = CreateFrame("Button", nil, bf)
    close:SetWidth(20)
    close:SetHeight(20)
    close:SetPoint("TOPRIGHT", -2, -2)
    A:SkinFrame(close, {0.2,0.2,0.2,1})
    close.text = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    close.text:SetPoint("CENTER", close, "CENTER", 0, 0)
    close.text:SetText("x")
    close:SetScript("OnEnter", function() close:SetBackdropColor(0.5,0.5,0.5,1) end)
    close:SetScript("OnLeave", function() close:SetBackdropColor(0.2,0.2,0.2,1) end)
    close:SetScript("OnClick", function() bf:Hide() end)
    close:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, bf)
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -10, 40)
    local content = CreateFrame("Frame", nil, scroll)
    local total = 246
    local numPerRow = 6
    local size = 36
    local padding = 4
    local rows = math.ceil(total / numPerRow)
    content:SetWidth(numPerRow * (size + padding))
    content:SetHeight(rows * (size + padding) - padding)
    scroll:SetScrollChild(content)

    local wheel = scroll
    wheel:EnableMouseWheel(true)
    wheel:SetScript("OnMouseWheel", function(_, dir)
    dir = dir or 0
      local step = 30
      local current = scroll:GetVerticalScroll() or 0
      local max = (content:GetHeight() or 0) - (scroll:GetHeight() or 1)
      local target = math.max(0, math.min(current - dir * step, max))
      scroll:SetVerticalScroll(target)
    end)

    bf.textureButtons={}
    function bf:UpdateSelection()
      for _,button in ipairs(self.textureButtons) do
        button.selected:SetShown(button.texturePath==self.selectedTexture)
      end
    end
    bf.selectedTexture=ed.texturePath:GetText()
    for i = 1, total do
      local btn = CreateFrame("Button", nil, content, "BackdropTemplate")
      local row = math.floor((i - 1) / numPerRow)
      local col = ((i - 1) % numPerRow)
      btn:SetWidth(size)
      btn:SetHeight(size)
      btn:SetPoint("TOPLEFT", col * (size + padding) + 22, -row * (size + padding))
      local tex = btn:CreateTexture(nil, "ARTWORK")
      tex:SetAllPoints(btn)
      tex:SetTexture("Interface\\AddOns\\yAuras\\Auras\\Aura" .. i)
      A:SkinFrame(btn, {0.2,0.2,0.2,1})
      btn.texturePath = "Interface\\AddOns\\yAuras\\Auras\\Aura" .. i
      btn.selected=btn:CreateTexture(nil,"OVERLAY")
      btn.selected:SetPoint("TOPLEFT",btn,"TOPLEFT",-8,8)
      btn.selected:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",8,-8)
      btn.selected:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
      btn.selected:SetBlendMode("ADD");btn.selected:SetVertexColor(1,.85,.2)
      bf.textureButtons[#bf.textureButtons+1]=btn
      btn:SetScript("OnClick", function(self)
        bf.selectedTexture = btn.texturePath
        bf:UpdateSelection()
      end)
    end
    bf:UpdateSelection()

    local select = CreateFrame("Button", nil, bf)
    select:SetWidth(80)
    select:SetHeight(20)
    select:SetPoint("BOTTOM", 0, 10)
    A:SkinFrame(select, {0.2,0.2,0.2,1})
    select:SetScript("OnEnter", function() select:SetBackdropColor(0.5,0.5,0.5,1) end)
    select:SetScript("OnLeave", function() select:SetBackdropColor(0.2,0.2,0.2,1) end)
    select.text = select:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    select.text:SetPoint("CENTER", select, "CENTER", 0, 0)
    select.text:SetText(L.SELECT)
    select:SetScript("OnClick", function()
      if bf.selectedTexture then
        ed.texturePath:SetText(bf.selectedTexture)
        ed.autoDetect.value=0
        ed.browseFrame:Hide()
        A:SaveAura(gui.auraEdit)
      end
    end)
	
    local scrollbar = UI.Scrollbar(bf)
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetWidth(16)
    scrollbar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 4, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 4, 0)

    
    scrollbar:SetMinMaxValues(0, 1)
    scrollbar:SetValueStep(1)
    scrollbar:SetValue(0)
    scrollbar:SetScript("OnValueChanged", function()
      scroll:SetVerticalScroll(scrollbar:GetValue())
    end)
    scroll:SetScript("OnVerticalScroll", function()
      scrollbar:SetValue(scroll:GetVerticalScroll())
    end)
    scrollbar:SetScript("OnValueChanged", function()
      scroll:SetVerticalScroll(scrollbar:GetValue())
    end)
    scroll:SetScript("OnVerticalScroll", function()
      scrollbar:SetValue(scroll:GetVerticalScroll())
    end)
    local contentHeight = content:GetHeight()
    local visibleHeight = scroll:GetHeight()
    local maxScroll = math.max(0, contentHeight - visibleHeight)
    scrollbar:SetVisibleExtentPercentage(visibleHeight/math.max(1,contentHeight))
    scrollbar:SetMinMaxValues(0, maxScroll)
    scrollbar:SetValue(0)
	
  end)
  
  A:RefreshAuraList()

  -- Refresh native selection descriptions after the aura values have been loaded.
  for _,key in ipairs({"typeButton","unitButton","showCD","targetType"}) do
    ed[key]:GenerateMenu()
  end
  -- ensure editor visible
  ed:Show()
end


-- Window lifecycle and the move gesture (Ctrl+Alt+Shift).
function A:OpenEditor()
 if not self.loaded then return end
 self.SettingsLoaded = true
 self:KeepEditorIndependent()
 self:CreateTestAuras(); gui:Show(); self:RefreshAuraList(); self:Refresh()
end
function A:LoadFields()
 if gui.editor and gui.auraEdit then self:EditAura(gui.auraEdit) end
end
function A:CloseEditor()
 self:StopAuraDrag()
 if self.editor then self.editor:Hide() end
 gui.editor=nil; gui.auraEdit=nil
 if self.TestAura then self.TestAura:Hide(); self.TestAuraDual:Hide() end
 for _,handle in pairs(self.draggers) do handle:Hide() end
 self.moveAuras=false; self.preview=false
end
gui:SetScript("OnHide",function() A:CloseEditor(); A:Refresh() end)
A.editorUpdate = CreateFrame("Frame")
A.editorUpdate:SetScript("OnUpdate",function()
 if not A.loaded then return end
 local moving = gui:IsShown() and IsControlKeyDown() and IsAltKeyDown() and IsShiftKeyDown()
 if moving ~= A.moveAuras then
  if not moving then A:StopAuraDrag() end
  A.moveAuras=moving; gui:SetAlpha(moving and 0 or 1)
  if gui.editor then gui.editor:SetAlpha(moving and 0 or 1) end
  if A.draggers[0] then A.draggers[0]:SetShown(moving and gui.editor~=nil) end
  A:Refresh()
 end
end)
function A:PickColor(key)
 local id=gui.auraEdit; local ed=gui.editor
 if not id or not ed then return end
 local owner=yAurasDB.auras[id]; local original=self:Copy(owner[key])
 local function apply(color)
  owner[key]=color; ed[key]=color
  local picker=key=="auracolor" and ed.auracolorpicker or ed.lowdurationcolorpicker
  picker.prev:SetColorTexture(unpack(color))
  self.TestAura.texture:SetVertexColor(unpack(color)); self.TestAuraDual.texture:SetVertexColor(unpack(color))
  if gui.list[id] and key=="auracolor" then gui.list[id].text:SetTextColor(unpack(color)) end
  self:InvalidateRule(id); self:Refresh()
 end
 local function changed()
  local r,g,b=ColorPickerFrame:GetColorRGB()
  local a=ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or original[4]
  apply({r,g,b,a})
 end
 ColorPickerFrame:SetParent(UIParent); ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
 ColorPickerFrame:SetupColorPickerAndShow({r=original[1],g=original[2],b=original[3],opacity=original[4],hasOpacity=true,
 swatchFunc=changed,opacityFunc=changed,cancelFunc=function() apply(original) end})
end

function A:RegisterSettings()
 if not Settings or not Settings.RegisterCanvasLayoutCategory then return end
 local optionsTitle = "|cff4b7dccy|rAuras"
 local p = CreateFrame("Frame")
 p:SetSize(700, 560)
 local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
 title:SetPoint("TOPLEFT", 32, -24)
 title:SetText(optionsTitle)
 title:SetJustifyH("LEFT")

 local enable = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
 enable:SetPoint("TOPLEFT", 400, -18)
 local enableText = enable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
 enableText:SetPoint("LEFT", enable, "RIGHT", 2, 0)
 enableText:SetText(L.ENABLE_YAURAS)
 p.enable = enable

 local controls = CreateFrame("Frame", nil, p)
 controls:SetAllPoints(p)
 p.controls = controls
 local desc = controls:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
 desc:SetPoint("TOPLEFT", 32, -64)
 desc:SetJustifyH("LEFT")
 desc:SetText(L.CONFIGURE_BUFF_DEBUFF_AND_SPELL_COOLDOWN_DISPLAYS_IN_THE_EDITOR)

 local open = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
 open:SetSize(160, 24)
 open:SetPoint("TOPLEFT", 32, -110)
 open:SetText(L.OPEN_EDITOR)
 p.openEditor = open
 open:SetScript("OnClick", function()
  if not A.enabled then return end
  if SettingsPanel and SettingsPanel:IsShown() then
   if HideUIPanel then HideUIPanel(SettingsPanel) else SettingsPanel:Hide() end
  end
  if GameMenuFrame then
   if HideUIPanel then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
  end
  -- Settings can restore the system menu as part of its close transition.
  C_Timer.After(0, function()
   if GameMenuFrame then
    if HideUIPanel then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
   end
   A:OpenEditor()
  end)
 end)

 local zoom = CreateFrame("CheckButton", nil, controls, "InterfaceOptionsCheckButtonTemplate")
 zoom:SetPoint("TOPLEFT", 32, -158)
 local zoomText = zoom:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
 zoomText:SetPoint("LEFT", zoom, "RIGHT", 2, 0)
 zoomText:SetText(L.ZOOM_ICONS_SQUARE_1PX_BLACK_BORDER)
 UI.Check(enable);UI.Check(zoom)
 local function RefreshForm()
  enable:SetChecked(A.enabled)
  controls:SetShown(A.enabled)
  zoom:SetChecked(A:ZoomIcons())
 end
 p.RefreshForm = RefreshForm
 self.settingsPanel = p
 self.zoomCheckbox = zoom
 enable:SetScript("OnClick", function(self)
  A:SetEnabled(self:GetChecked() and true or false)
 end)
 zoom:SetScript("OnClick", function(self)
  A:SetZoomIcons(self:GetChecked())
  RefreshForm()
 end)
 p:SetScript("OnShow", RefreshForm)
 RefreshForm()
 self.category=Settings.RegisterCanvasLayoutCategory(p,optionsTitle)
 Settings.RegisterAddOnCategory(self.category)
end
