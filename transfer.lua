local _, localization = ...
local L = localization.L
local _,A=...
-- Data-only parser for yAuras table exports. Never executes imports.
local function serialize(v)
 if type(v)=="string" then return string.format("%q",v)
 elseif type(v)=="number" or type(v)=="boolean" then return tostring(v)
 elseif type(v)=="table" then
  local parts={}; for k,value in pairs(v) do parts[#parts+1]="["..serialize(k).."]="..serialize(value) end
  return "{"..table.concat(parts,",").."}"
 end
 error(L.UNSUPPORTED_DATA)
end
function A:Parse(text)
 if type(text)~="string" or #text>1024*1024 then error(L.IMPORT_IS_TOO_LARGE) end
 text=text:gsub("^%s*yAurasDB%s*=%s*", "")
 local pos,nodes=1,0
 local function space() local _,e=text:find("^%s*",pos); pos=(e or pos-1)+1 end
 local function take(s) space(); if text:sub(pos,pos+#s-1)==s then pos=pos+#s; return true end return false end
 local value
 value=function(depth)
  space(); nodes=nodes+1; if nodes>30000 or depth>12 then error(L.IMPORT_IS_TOO_COMPLEX) end
  if take("{") then
   local t={}; local index=1
   while not take("}") do
    local k,v
    if take("[") then k=value(depth+1); if not take("]") or not take("=") then error(L.EXPECTED) end; v=value(depth+1)
    else
     space(); local name=text:match("^([%a_][%w_]*)%s*=",pos)
     if name then pos=pos+#name; if not take("=") then error(L.EXPECTED_2) end; k=name; v=value(depth+1)
     else k=index; index=index+1; v=value(depth+1) end
    end
    if type(k)~="string" and type(k)~="number" then error(L.INVALID_TABLE_KEY) end
    t[k]=v
    if not take(",") and not take(";") then if not take("}") then error(L.EXPECTED_COMMA_OR) end; return t end
   end
   return t
  end
  local quote=text:sub(pos,pos)
  if quote=='"' or quote=="'" then
   pos=pos+1; local out={}
   while pos<=#text do
    local c=text:sub(pos,pos); pos=pos+1
    if c==quote then return table.concat(out) end
    if c=="\\" then
     c=text:sub(pos,pos); pos=pos+1
     local escapes={n="\n",r="\r",t="\t",a="\a",b="\b",f="\f",v="\v"}
     if c:match("%d") then
      local digits=c..(text:match("^(%d?%d?)",pos) or ""); pos=pos+#digits-1
      local code=tonumber(digits); if code>255 then error(L.INVALID_ESCAPE) end; c=string.char(code)
     else c=escapes[c] or c end
    end
    out[#out+1]=c
   end
   error(L.UNCLOSED_STRING)
  end
  if take("true") then return true elseif take("false") then return false end
  space(); local number=text:match("^([+-]?%d+%.?%d*[eE]?[+-]?%d*)",pos)
  if number and tonumber(number) then pos=pos+#number; local n=tonumber(number); if n~=n or n==math.huge or n==-math.huge then error(L.INVALID_NUMBER) end; return n end
  error(L.EXPECTED_TABLE_STRING_NUMBER_OR_BOOLEAN_AT..pos)
 end
 space(); if text:sub(pos,pos+5)=="return" then pos=pos+6 end
 local result=value(0); space(); if pos<=#text then error(L.UNEXPECTED_TRAILING_TEXT) end
 return result
end
function A:Import(text)
 local ok,data=pcall(self.Parse,self,text)
 if not ok or type(data)~="table" then self:Msg(L.INVALID_IMPORT..tostring(data)); return false end
 if data.auras then data=data.auras end
 local rules=data.name and {data} or data
 local validated={}
 for _,t in ipairs(rules) do
  if type(t)~="table" or type(t.name)~="string" then self:Msg(L.IMPORT_CONTAINS_AN_INVALID_AURA); return false end
  validated[#validated+1]=self:Normalize(t)
 end
 if #validated==0 then self:Msg(L.NO_AURA_RULES_FOUND); return false end
 for _,t in ipairs(validated) do yAurasDB.auras[#yAurasDB.auras+1]=t end
 self:Msg(L.IMPORTED..#validated..L.AURA_S); self:InvalidateAll(); self:RefreshAuraList(); self:EditAura(#yAurasDB.auras); self:Refresh(); return true
end

function A:Transfer(export,id)
 local key=export and "exportFrame" or "importFrame"
 local other=export and self.importFrame or self.exportFrame; if other then other:Hide() end
 if not self[key] then
  local name=export and "yAurasExportFrame" or "yAurasImportFrame"
  local f=CreateFrame("Frame",name,UIParent,"BackdropTemplate"); self[key]=f
  f:SetSize(400,200); f:SetPoint("CENTER",UIParent,"CENTER",0,0); f:SetFrameStrata("FULLSCREEN_DIALOG"); self:StyleWindow(f, export and L.EXPORTED_AURA_STRING or L.PASTE_AURA_STRING_TO_IMPORT)
  f:SetMovable(true); f:EnableMouse(true)
  local title=f:CreateFontString(nil,"OVERLAY","GameFontNormal"); title:SetPoint("TOP",0,-10)
  title:SetText(export and L.EXPORTED_AURA_STRING or L.PASTE_AURA_STRING_TO_IMPORT); title:Hide()
  local scroll=CreateFrame("ScrollFrame",nil,f)
  scroll:SetPoint("TOPLEFT",15,-24); scroll:SetPoint("BOTTOMRIGHT",-32,40)
  A.UI.ScrollFrame(scroll,f)
  scroll.ScrollBar:ClearAllPoints()
  scroll.ScrollBar:SetPoint("TOPLEFT",scroll,"TOPRIGHT",10,0)
  scroll.ScrollBar:SetPoint("BOTTOMLEFT",scroll,"BOTTOMRIGHT",10,0)
  local borderHost=CreateFrame("Frame",nil,f)
  borderHost:SetPoint("TOPLEFT",scroll,"TOPLEFT",-4,4)
  borderHost:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-4,36)
  borderHost:SetFrameLevel(scroll:GetFrameLevel())
  A.UI.InputBorder(borderHost)
  f.edit=CreateFrame("EditBox",nil,scroll)
  f.edit:SetMultiLine(true); f.edit:SetAutoFocus(false)
  f.edit:SetFontObject(GameFontHighlightSmall); f.edit:SetTextInsets(6,6,6,6)
  f.edit:SetPropagateKeyboardInput(false)
  local measure=scroll:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
  measure:SetWordWrap(true);measure:Hide()
  local function layout()
   local width=math.max(1,scroll:GetWidth())
   f.edit:SetWidth(width);measure:SetWidth(math.max(1,width-12))
   measure:SetText((f.edit:GetText() or "") .. "\n ")
   f.edit:SetHeight(math.max(scroll:GetHeight(),measure:GetStringHeight()+12))
   scroll:UpdateScrollChildRect()
  end
  f.edit:SetScript("OnTextChanged",layout)
  scroll:HookScript("OnSizeChanged",layout)
  f:HookScript("OnShow",layout)
  f.edit:SetScript("OnEscapePressed",function() f.edit:ClearFocus() end)
  f:HookScript("OnHide",function()f.edit:ClearFocus()end)
  scroll:SetScrollChild(f.edit)
  local function btn(text,x,callback)
   local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
   b:SetSize(80,22);b:SetPoint("BOTTOM",x,10);b:SetText(text)
   b:SetScript("OnClick",callback)
  end
  if export then btn(L.CLOSE,0,function() f:Hide() end)
  else btn(L.IMPORT,-85,function() if A:Import(f.edit:GetText()) then f:Hide() end end);btn(L.CANCEL,85,function() f:Hide() end) end
  table.insert(UISpecialFrames,name)
 end
 local f=self[key]; self:SetAuraWindowPortrait(f,export and id or nil); f.edit:SetText(export and serialize(id and yAurasDB.auras[id] or yAurasDB.auras) or "")
 f:Show(); f.edit:SetFocus(); f.edit:HighlightText()
end
function A:ExportAllAuras() self:Transfer(true) end
function A:ExportSingleAura(id) self:Transfer(true,id) end
function A:ShowImportFrame() self:Transfer(false) end
