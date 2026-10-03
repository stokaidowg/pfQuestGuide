-- pfQuest Guide
-- Guide one quest at a time: pfQuest's arrow points at the quest's next objective,
-- and a panel lists buttons that target the quest's mobs/NPCs and raid-mark them.

pfQuestGuide = {}
local QG = pfQuestGuide
local compat = pfQuestCompat

local pairs, ipairs, tonumber, type = pairs, ipairs, tonumber, type
local strfind, strlen, strsub, gsub, format = string.find, string.len, string.sub, string.gsub, string.format
local floor, min = math.floor, math.min
local getn, insert, remove, sort = table.getn, table.insert, table.remove, table.sort

local PATH = pfQuestConfig and pfQuestConfig.path or "Interface\\AddOns\\pfQuest"
local TEX_MOB = PATH .. "\\img\\cluster_mob"
local TEX_ITEM = PATH .. "\\img\\cluster_item"
local TEX_MISC = PATH .. "\\img\\cluster_misc"
local TEX_VENDOR = PATH .. "\\img\\icon_vendor"
local TEX_TURNIN = PATH .. "\\img\\complete_c"

-- raid icons handed out by the target buttons, in this order:
-- 1 star, 2 circle, 3 diamond, 4 triangle, 5 moon, 6 square, 7 cross, 8 skull
local MARK_ORDER = { 1, 2, 3, 4, 5, 6, 7, 8 }
local MIN_DROPCHANCE = 2 -- ignore freak drops (e.g. 0.02%) unless nothing better exists
local MAX_TARGETS = 4 -- target buttons per objective
local WIDTH = 240

local VERB_COLOR = {
  ["Kill"] = "|cffff6060",
  ["Buy"] = "|cffffcc00",
  ["Turn in"] = "|cff33ffcc",
  ["Find"] = "|cff33ffcc",
  ["Loot"] = "|cffaaaaff",
  ["Use"] = "|cffaaaaff",
  ["Go to"] = "|cffaaaaff",
}

BINDING_HEADER_PFQUESTGUIDE = "pfQuest Guide"
BINDING_NAME_PFQUESTGUIDE_TARGET = "Target next quest mob / NPC"

local C -- pfQuestGuide_config, bound on ADDON_LOADED
local FONT

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest |cffffcc00Guide|r: " .. msg)
end

local function Error(msg, r, g, b)
  UIErrorsFrame:AddMessage(msg, r or 1, g or 0.3, b or 0.3, 1, 3)
end

-- [[ database helpers ]] --
local function data(db)
  return pfDB[db] and pfDB[db]["data"] or {}
end

local function loc(db, id)
  return pfDB[db] and pfDB[db]["loc"] and pfDB[db]["loc"][id]
end

local function IDs(name, db)
  local ret = {}
  local found = name and pfDatabase:GetIDByName(name, db)
  if found then
    for id in pairs(found) do
      insert(ret, id)
    end
  end
  return ret
end

local function HasZone(coords, zone)
  if not coords or not zone then
    return nil
  end
  for _, c in pairs(coords) do
    if c[3] == zone then
      return true
    end
  end
end

-- zone with the most spawns
local function MainZone(coords)
  local count, best, bestn = {}, nil, 0
  for _, c in pairs(coords or {}) do
    local z = c[3]
    if z and z > 0 then
      count[z] = (count[z] or 0) + 1
      if count[z] > bestn then
        best, bestn = z, count[z]
      end
    end
  end
  return best
end

-- "Crag Boar slain" -> " slain" (from the client's own objective format)
local SLAIN = QUEST_MONSTERS_KILLED and gsub(gsub(QUEST_MONSTERS_KILLED, "%%s", "", 1), ":.*$", "") or " slain"

local function StripSuffix(name, suffix)
  local len = strlen(suffix)
  if len > 0 and strlen(name) > len and strsub(name, -len) == suffix then
    return strsub(name, 1, -len - 1)
  end
  return name
end

local function ParseLeaderBoard(text)
  text = gsub(text or "", "\239\188\154", ":")
  local _, _, name = strfind(text, "^(.*):%s*%d+%s*/%s*%d+%s*$")
  return name or text
end

-- [[ quest steps ]] --
-- step = { key, label, done, sources = { {kind, id, name, verb, tex, desc, coords, chance} }, targets = {...} }
local function NewStep(key, label, done)
  return { key = key, label = label, done = done, sources = {}, seen = {}, targets = {}, more = 0 }
end

local function AddSource(step, kind, id, verb, tex, desc, chance)
  local key = kind .. id
  local src = step.seen[key]
  if src then
    if chance and chance > (src.chance or 0) then
      src.chance = chance
    end
    return
  end

  local db = kind == "U" and "units" or kind == "O" and "objects" or "areatrigger"
  local entry = data(db)[id]
  src = { kind = kind, id = id, verb = verb, tex = tex, chance = chance }
  src.coords = entry and entry.coords
  src.name = kind ~= "A" and loc(db, id) or nil
  src.desc = format(desc, src.name or "?")

  step.seen[key] = src
  insert(step.sources, src)
end

local function AddUnits(step, list, verb, tex, desc)
  for _, id in pairs(list or {}) do
    AddSource(step, "U", id, verb, tex, desc)
  end
end

local function AddObjects(step, list, verb, tex, desc)
  for _, id in pairs(list or {}) do
    AddSource(step, "O", id, verb, tex, desc)
  end
end

local function AddItemSources(step, itemid)
  local item = data("items")[itemid]
  if not item then
    return
  end

  local iname = loc("items", itemid) or "?"
  local loot = "Loot |cff33ffcc" .. iname .. "|r from |cffffcc00%s"

  -- drops: skip freak drops, unless they are all there is
  local best = 0
  for _, chance in pairs(item.U or {}) do
    if chance > best then
      best = chance
    end
  end
  local threshold = min(MIN_DROPCHANCE, best)

  for unit, chance in pairs(item.U or {}) do
    if chance >= threshold then
      AddSource(step, "U", unit, "Kill", TEX_MOB, loot, chance)
    end
  end

  for object, chance in pairs(item.O or {}) do
    if chance > 0 then
      AddSource(step, "O", object, "Loot", TEX_ITEM, loot, chance)
    end
  end

  -- shared loot tables
  local refloot = data("refloot")
  for ref, chance in pairs(item.R or {}) do
    local r = refloot[ref]
    if r and chance > 0 then
      for unit in pairs(r.U or {}) do
        AddSource(step, "U", unit, "Kill", TEX_MOB, loot, chance)
      end
      for object in pairs(r.O or {}) do
        AddSource(step, "O", object, "Loot", TEX_ITEM, loot, chance)
      end
    end
  end

  for unit in pairs(item.V or {}) do
    AddSource(step, "U", unit, "Buy", TEX_VENDOR, "Buy |cff33ffcc" .. iname .. "|r from |cffffcc00%s", 100)
  end
end

local function BuildObjective(text, otype, done, qdata)
  local name = ParseLeaderBoard(text)
  local step = NewStep(name, text, done)
  if done then
    return step
  end

  local qobj = qdata and qdata.obj or {}

  if otype == "monster" then
    local mob = name
    local ids = IDs(mob, "units")
    if getn(ids) == 0 then
      mob = StripSuffix(name, SLAIN)
      ids = IDs(mob, "units")
    end
    AddUnits(step, ids, "Kill", TEX_MOB, "Kill |cffffcc00%s")
    AddObjects(step, IDs(mob, "objects"), "Use", TEX_MISC, "Use |cffffcc00%s")
    if getn(step.sources) == 0 then
      AddUnits(step, qobj.U, "Kill", TEX_MOB, "Kill |cffffcc00%s")
    end
  elseif otype == "item" then
    -- several items can share a name; prefer the ones the quest actually asks for
    local ids, wanted = {}, {}
    for _, id in pairs(qobj.I or {}) do
      wanted[id] = true
    end
    for _, id in ipairs(IDs(name, "items")) do
      if wanted[id] then
        insert(ids, id)
      end
    end
    if getn(ids) == 0 then
      ids = IDs(name, "items")
    end
    if getn(ids) == 0 then
      ids = qobj.I or {}
    end
    step.itemid = ids[1]
    for _, id in pairs(ids) do
      AddItemSources(step, id)
    end
  elseif otype == "object" then
    AddObjects(step, IDs(name, "objects"), "Use", TEX_MISC, "Use |cffffcc00%s")
  end

  -- events, exploration and scripted objectives: fall back to the quest's raw objective data
  if getn(step.sources) == 0 then
    for _, id in pairs(qobj.A or {}) do
      AddSource(step, "A", id, "Go to", TEX_MISC, "Explore the marked area")
    end
    AddUnits(step, qobj.U, "Find", TEX_MISC, "Find |cffffcc00%s")
    AddObjects(step, qobj.O, "Use", TEX_MISC, "Use |cffffcc00%s")
  end

  return step
end

local function BuildTurnIn(qdata)
  local step = NewStep("turnin", "|cff33ffccTurn in the quest|r", nil)
  local qend = qdata and qdata["end"] or {}
  AddUnits(step, qend.U, "Turn in", TEX_TURNIN, "Turn in to |cffffcc00%s")
  AddObjects(step, qend.O, "Turn in", TEX_TURNIN, "Turn in at |cffffcc00%s")
  return step
end

-- targetable NPCs of a step, one per name, preferring the current zone and best drop chance
local function BuildTargets(step, zone)
  local byname, list = {}, {}
  for _, src in ipairs(step.sources) do
    if src.kind == "U" and src.name then
      local inzone = HasZone(src.coords, zone)
      local t = byname[src.name]
      if not t then
        t = { name = src.name, verb = src.verb, chance = src.chance or 0, inzone = inzone, zone = MainZone(src.coords) }
        byname[src.name] = t
        insert(list, t)
      else
        if (src.chance or 0) > t.chance then
          t.chance, t.verb = src.chance, src.verb
        end
        t.inzone = t.inzone or inzone
      end
    end
  end

  sort(list, function(a, b)
    local ai, bi = a.inzone and 1 or 0, b.inzone and 1 or 0
    if ai ~= bi then
      return ai > bi
    end
    if a.chance ~= b.chance then
      return a.chance > b.chance
    end
    return a.name < b.name
  end)

  step.targets = {}
  for i = 1, min(getn(list), MAX_TARGETS) do
    step.targets[i] = list[i]
  end
  step.more = getn(list) - getn(step.targets)
end

-- [[ quest selection ]] --
function QG:QuestList()
  local list = {}
  for id, entry in pairs(pfQuest.questlog or {}) do
    local title, level = compat.GetQuestLogTitle(entry.qlogid)
    insert(list, { id = id, title = entry.title, level = (title == entry.title and level) or 0 })
  end
  sort(list, function(a, b)
    if a.level ~= b.level then
      return a.level < b.level
    end
    return a.title < b.title
  end)
  return list
end

function QG:SelectQuest(id)
  local entry = id and pfQuest.questlog and pfQuest.questlog[id]
  C.quest = entry and id or nil
  C.questtitle = entry and entry.title or nil
  self.focusKey = nil
  self.suspended = nil
  self:Rebuild()
  self:RefreshTracker()

  if entry then
    self:AttachArrow()
    C.shown = true
    self:Render()
  end
end

function QG:ResolveQuest()
  local id = C and C.quest
  if not id then
    return nil
  end

  local entry = pfQuest.questlog and pfQuest.questlog[id]
  if entry then
    return entry
  end

  -- pfQuest rebuilds its quest log a few seconds after login; only give up once it is running
  if pfQuest.lock and GetTime() > pfQuest.lock + 3 then
    Print("Stopped guiding |cffffcc00" .. (C.questtitle or "?") .. "|r - it is no longer in your quest log.")
    C.quest, C.questtitle = nil, nil
    self:RefreshTracker()
  else
    self.status = "Waiting for pfQuest..."
  end
end

function QG:Rebuild()
  self.steps = {}
  self.status = nil
  self.quest = nil

  local entry = self:ResolveQuest()
  if entry then
    local qlogid = entry.qlogid
    local title, level, _, _, _, complete = compat.GetQuestLogTitle(qlogid)
    self.quest = { id = C.quest, title = entry.title, level = tonumber(level), qlogid = qlogid }

    if title ~= entry.title then
      -- quest log moved or its zone header is collapsed
      self.status = "Expand this quest's zone in your quest log."
    else
      local qdata = type(C.quest) == "number" and data("quests")[C.quest]
      local count = GetNumQuestLeaderBoards(qlogid) or 0

      if complete == 1 or count == 0 then
        insert(self.steps, BuildTurnIn(qdata))
      else
        for i = 1, count do
          local text, otype, done = GetQuestLogLeaderBoard(i, qlogid)
          insert(self.steps, BuildObjective(text, otype, done, qdata))
        end
      end

      if not qdata then
        self.status = "pfQuest has no data for this quest."
      end

      local zone = pfMap:GetMapIDByName(GetRealZoneText())
      for _, step in ipairs(self.steps) do
        BuildTargets(step, zone)
      end
    end
  end

  if self.quest and not self.arrowActive and not self.suspended then
    self:AttachArrow()
  elseif not self.quest and self.arrowActive then
    self:DetachArrow()
  end

  self:Render()
  self:UpdateArrow()
end

function QG:ToggleFocus(key)
  self.focusKey = self.focusKey ~= key and key or nil
  self:Render()
  self:UpdateArrow()
end

-- [[ arrow ]] --
-- pfQuest's arrow follows the first entry of pfQuest.route.coords. We add one
-- entry of our own (the nearest spawn of the current step) and make pfQuest's
-- "custom target" logic prefer it. Clicking a node on the map hands the arrow
-- back to pfQuest until the user re-attaches it.
QG.node = { pfqg = true, title = "", priority = 1 }
QG.entry = { 0, 0, QG.node, nil, true, nil }

local route = pfQuest.route
local origIsTarget = route.IsTarget
local origSetTarget = route.SetTarget

route.IsTarget = function(node)
  if QG.arrowActive then
    return node and node.pfqg and true or nil
  end
  return origIsTarget(node)
end

route.SetTarget = function(node, default)
  if node and node.pfqg then
    QG.arrowActive = true
  elseif QG.arrowActive then
    -- the user picked another map node as arrow target
    QG.arrowActive = nil
    QG.suspended = true
    QG:RemoveEntry()
    QG:Render()
  end
  origSetTarget(node, default)

  -- pfQuest bug: SetTarget queues a map refresh with `true`, but the map's
  -- OnUpdate expects a timestamp and errors every frame on "true + 0.25"
  if pfMap.queue_update == true then
    pfMap.queue_update = GetTime()
  end
end

function QG:AttachArrow()
  if not self.quest then
    return
  end
  self.suspended = nil
  self.node.title = self.quest.title
  route.SetTarget(self.node)
  self:UpdateArrow()
end

function QG:DetachArrow()
  self.arrowActive = nil
  origSetTarget(nil)
  self:RemoveEntry()
end

function QG:RemoveEntry()
  local coords = route.coords
  for i = getn(coords), 1, -1 do
    if coords[i] == self.entry then
      remove(coords, i)
      route.firstnode = nil
      route.recalculate = nil
    end
  end
end

function QG:NearestSpot()
  local map = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
  local px, py = GetPlayerMapPosition("player")
  if not map or (px == 0 and py == 0) then
    return
  end
  px, py = px * 100, py * 100

  local focus
  for _, step in ipairs(self.steps or {}) do
    if not step.done and step.key == self.focusKey then
      focus = step
    end
  end

  local best, bx, by, bsrc
  for _, step in ipairs(self.steps or {}) do
    if not step.done and (not focus or step == focus) then
      for _, src in ipairs(step.sources) do
        for _, c in pairs(src.coords or {}) do
          if c[3] == map then
            local dx, dy = (c[1] - px) * 1.5, c[2] - py
            local d = dx * dx + dy * dy
            if not best or d < best then
              best, bx, by, bsrc = d, c[1], c[2], src
            end
          end
        end
      end
    end
  end

  return bx, by, bsrc
end

function QG:UpdateArrow()
  if not self.quest or not self.arrowActive then
    self:RemoveEntry()
    return
  end

  local x, y, src = self:NearestSpot()
  if not x then
    -- nothing for this quest on the current map: let pfQuest's normal routing take over
    self:RemoveEntry()
    return
  end

  local node, entry = self.node, self.entry
  node.title = self.quest.title
  node.qlvl = self.quest.level
  node.questid = self.quest.id
  node.texture = src.tex
  node.description = src.desc
  entry[6] = self.quest.id

  local changed = entry[1] ~= x or entry[2] ~= y
  entry[1], entry[2] = x, y

  local present
  for _, e in ipairs(route.coords) do
    if e == entry then
      present = true
      break
    end
  end
  if not present then
    entry[4] = nil
    insert(route.coords, entry)
    changed = true
  end

  if changed then
    route.firstnode = nil
    route.recalculate = nil
    route.tick = nil
  end
end

-- pfQuest rebuilds its route table on every map refresh; re-add our entry right away
local origUpdateNodes = pfMap.UpdateNodes
pfMap.UpdateNodes = function(self)
  origUpdateNodes(self)
  QG:UpdateArrow()
end

-- [[ targeting and raid marks ]] --
local function Usable()
  return not UnitIsDead("target") and not (UnitIsTapped("target") and not UnitIsTappedByPlayer("target"))
end

-- returns "ok", "dead" (only a dead/tapped one is near) or nil (none near)
function QG:Target(name)
  TargetByName(name, true)
  if UnitName("target") ~= name then
    return nil
  end
  if Usable() then
    return "ok"
  end

  -- the nearest match is dead or tagged by someone else: look through nearby enemies
  if UnitCanAttack("player", "target") then
    for i = 1, 10 do
      TargetNearestEnemy()
      if UnitName("target") == name and Usable() then
        return "ok"
      end
    end
    -- back to the nearest match (a dead one may still need looting)
    TargetByName(name, true)
  end
  return "dead"
end

QG.markUsed = {}

function QG:Mark()
  -- mobs and NPCs only: no players, pets or corpses
  if not UnitExists("target") or UnitIsDead("target") or UnitPlayerControlled("target") then
    return
  end

  local current = GetRaidTargetIndex("target")
  if current then
    -- already marked: keep it, and count it as recently used if it is one of ours
    if self.markUsed[current] then
      self.markUsed[current] = GetTime()
    end
    return
  end

  -- first unused icon, else the one used longest ago
  local pick, oldest
  for _, icon in ipairs(MARK_ORDER) do
    if not self.markUsed[icon] then
      pick = icon
      break
    end
    if not oldest or self.markUsed[icon] < self.markUsed[oldest] then
      oldest = icon
    end
  end
  pick = pick or oldest

  SetRaidTarget("target", pick)
  self.markUsed[pick] = GetTime()
  self.markCheck = { GetTime() + 1.5, pick, UnitName("target") }
end

function QG:TargetAndMark(name)
  local result = self:Target(name)
  if result == "ok" then
    -- also covers re-clicking the unit that is already targeted (no target change event)
    self.pendingMark = true
  elseif result == "dead" then
    Error("Only a dead or tapped " .. name .. " is nearby", 1, 0.8, 0.2)
  else
    Error(name .. " is not nearby")
  end
end

-- keybinding / "/pqg target": the focused objective first, then everything else in panel order
function QG:TargetNext()
  local order, seen = {}, {}
  local function add(step)
    for _, t in ipairs(step.targets) do
      if not seen[t.name] then
        seen[t.name] = true
        insert(order, t.name)
      end
    end
  end

  for _, step in ipairs(self.steps or {}) do
    if not step.done and step.key == self.focusKey then
      add(step)
    end
  end
  for _, step in ipairs(self.steps or {}) do
    if not step.done then
      add(step)
    end
  end

  for _, name in ipairs(order) do
    if self:Target(name) == "ok" then
      self.pendingMark = true
      return
    end
  end
  Error(getn(order) > 0 and "No living quest target nearby" or "No quest target to look for")
end

-- [[ tracker and quest log integration ]] --
function QG:RefreshTracker()
  local tracker = pfQuest.tracker
  for _, button in pairs(tracker.buttons) do
    if not button.empty and button.title then
      tracker.ButtonEvent(button)
    end
  end
end

local MARKER = "|cffffcc00>|r "

local function HookTracker()
  local tracker = pfQuest.tracker

  local origClick = tracker.ButtonClick
  tracker.ButtonClick = function()
    if IsAltKeyDown() and this.questid and pfQuest.questlog[this.questid] then
      QG:SelectQuest(this.questid)
      return
    end
    origClick()
  end

  local origEvent = tracker.ButtonEvent
  tracker.ButtonEvent = function(self)
    origEvent(self)
    local button = self or this
    if button.empty or not button.title or tracker.mode ~= "QUEST_TRACKING" then
      return
    end

    local text = button.text:GetText() or ""
    if C and C.quest and button.questid == C.quest and not strfind(text, MARKER, 1, true) then
      button.text:SetText(MARKER .. text)
    end
    if button.tooltip and not strfind(button.tooltip, "Guide this quest", 1, true) then
      button.tooltip = button.tooltip .. "\n|cff33ffcc<Alt-Click>|r Guide this quest"
    end
  end

  -- buttons created before this hook still point at the old handlers
  for _, button in pairs(tracker.buttons) do
    button:SetScript("OnClick", tracker.ButtonClick)
    button:SetScript("OnEvent", tracker.ButtonEvent)
  end

  -- Alt-click a quest in the quest log to guide it
  local origLogClick = QuestLogTitleButton_OnClick
  QuestLogTitleButton_OnClick = function(a1, a2)
    if IsAltKeyDown() and this and not this.isHeader and QuestLogListScrollFrame then
      local index = this:GetID() + FauxScrollFrame_GetOffset(QuestLogListScrollFrame)
      local title = compat.GetQuestLogTitle(index)
      for id, entry in pairs(pfQuest.questlog) do
        if entry.qlogid == index and entry.title == title then
          QG:SelectQuest(id)
          break
        end
      end
    end
    return origLogClick(a1, a2)
  end
end

-- [[ panel ]] --
local function Backdrop(frame)
  if pfUI and pfUI.api and pfUI.api.CreateBackdrop and not pfUI.api.emulated then
    pfUI.api.CreateBackdrop(frame, nil, true, 0.85)
  else
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  end
end

local function ShowTooltip()
  if not this.tip then
    return
  end
  GameTooltip:SetOwner(this, "ANCHOR_LEFT")
  GameTooltip:SetText("|cff33ffccpf|cffffffffQuest |cffffcc00Guide")
  GameTooltip:AddLine(this.tip, 1, 1, 1)
  GameTooltip:Show()
end

local function HideTooltip()
  GameTooltip:Hide()
end

local rows, buttons = {}, {}

local function GetRow(i)
  if not rows[i] then
    local row = CreateFrame("Button", nil, QG.frame)
    row:SetHeight(14)
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetFont(FONT, 12, "OUTLINE")
    row.text:SetJustifyH("LEFT")
    row.text:SetAllPoints()
    row:SetScript("OnClick", function()
      if this.key == "resume" then
        QG:AttachArrow()
        QG:Render()
      elseif this.key then
        QG:ToggleFocus(this.key)
      end
    end)
    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", HideTooltip)
    rows[i] = row
  end
  return rows[i]
end

local function GetButton(i)
  if not buttons[i] then
    local button = CreateFrame("Button", nil, QG.frame)
    button:SetHeight(18)
    Backdrop(button)

    button.hl = button:CreateTexture(nil, "HIGHLIGHT")
    button.hl:SetTexture(1, 1, 1, 0.15)
    button.hl:SetAllPoints()

    button.text = button:CreateFontString(nil, "OVERLAY")
    button.text:SetFont(FONT, 11, "OUTLINE")
    button.text:SetJustifyH("LEFT")
    button.text:SetPoint("LEFT", 6, 0)
    button.text:SetPoint("RIGHT", -6, 0)

    button:SetScript("OnClick", function()
      QG:TargetAndMark(this.unitname)
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", HideTooltip)
    buttons[i] = button
  end
  return buttons[i]
end

function QG:Render()
  if not self.frame then
    return
  end

  local shown = C.shown ~= false
  if C.full then
    self.bar:Hide()
    if shown then
      self.frame:Show()
      self:RenderFull()
    else
      self.frame:Hide()
    end
  else
    self.frame:Hide()
    if shown then
      self:RenderCompact()
    else
      self.bar:Hide()
    end
  end
end

function QG:RenderFull()
  local f = self.frame

  if self.quest then
    local level = self.quest.level
    local color = compat.GetDifficultyColor(level or UnitLevel("player"))
    f.title:SetText(format("|cff%02x%02x%02x[%s] %s", floor(color.r * 255), floor(color.g * 255),
      floor(color.b * 255), level or "?", self.quest.title))
  else
    f.title:SetText("|cffaaaaaaClick to choose a quest")
  end

  local y, r, b = -24, 0, 0
  local function Row(text, key, indent, tip)
    r = r + 1
    local row = GetRow(r)
    row.key, row.tip = key, tip
    row.text:SetText(text)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + (indent or 0), y)
    row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y)
    row:Show()
    y = y - 15
  end

  if not self.quest and not self.status then
    Row("|cff888888Alt-click a quest in the tracker", nil, 0)
    Row("|cff888888or quest log to guide it.", nil, 0)
  end

  for _, step in ipairs(self.steps or {}) do
    if step.done then
      Row("|cff777777" .. step.label .. " (done)")
    else
      local marker = self.focusKey == step.key and "|cff33ffcc> |r" or ""
      Row(marker .. "|cffffffff" .. step.label, step.key, 0,
        "Click to point the arrow only at this objective.\nClick again to follow all objectives.")

      for _, t in ipairs(step.targets) do
        b = b + 1
        local button = GetButton(b)
        local where = ""
        if not t.inzone and t.zone and loc("zones", t.zone) then
          where = " |cff888888(" .. loc("zones", t.zone) .. ")"
        end
        button.text:SetText((VERB_COLOR[t.verb] or "|cffffffff") .. t.verb .. "|r " .. t.name .. where)
        button.unitname = t.name
        button.tip = "Target the nearest |cffffcc00" .. t.name .. "|r and give it a raid icon."
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", f, "TOPLEFT", 16, y - 1)
        button:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y - 1)
        button:Show()
        y = y - 20
      end

      if step.more > 0 then
        Row("|cff888888+" .. step.more .. " more", nil, 10)
      elseif getn(step.targets) == 0 then
        Row(step.sources[1] and "|cff888888Nothing to target - follow the arrow" or "|cff888888No location data", nil, 10)
      end
    end
    y = y - 4
  end

  if self.status then
    Row("|cffff8888" .. self.status)
  end
  if self.suspended and self.quest then
    Row("|cffffcc00Arrow released - click to re-attach", "resume", 0,
      "You picked another arrow target on the map.\nClick to point the arrow at this quest again.")
  end

  for i = r + 1, getn(rows) do
    rows[i]:Hide()
  end
  for i = b + 1, getn(buttons) do
    buttons[i]:Hide()
  end

  f:SetHeight(-y + 6)
end

-- [[ compact mode: one icon per objective ]] --
local ICON_SIZE = 28
local ICON_GAP = 3
local ICON_KILL = "Interface\\Icons\\INV_Sword_04"
local ICON_BUY = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_OTHER = "Interface\\Icons\\INV_Misc_Bag_08"
local ICON_STATUS = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_RESUME = "Interface\\Icons\\INV_Misc_Map_01"

local icons = {}

-- clicking an objective icon tries its NPCs in panel order (current zone, best drop chance first)
function QG:TargetStep(step)
  local dead
  for _, t in ipairs(step.targets) do
    local result = self:Target(t.name)
    if result == "ok" then
      self.pendingMark = true
      return
    elseif result == "dead" then
      dead = dead or t.name
    end
  end

  if dead then
    TargetByName(dead, true)
    Error("Only a dead or tapped " .. dead .. " is nearby", 1, 0.8, 0.2)
  elseif step.targets[1] then
    Error(step.targets[1].name .. " is not nearby")
  else
    Error("Nothing to target here - follow the arrow", 1, 0.8, 0.2)
  end
end

local function ItemTexture(itemid)
  if itemid then
    local _, _, _, _, _, _, _, _, texture = GetItemInfo(itemid)
    return texture
  end
end

local function StepTexture(step)
  if step.turnin then
    return ICON_TURNIN
  end
  local texture = ItemTexture(step.itemid)
  if texture then
    return texture
  end
  local verb = step.targets[1] and step.targets[1].verb
  if verb == "Kill" then
    return ICON_KILL
  elseif verb == "Buy" then
    return ICON_BUY
  end
  return ICON_OTHER
end

local function IconTooltip()
  local step = this.step
  GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT")

  if QG.quest then
    local color = compat.GetDifficultyColor(QG.quest.level or UnitLevel("player"))
    GameTooltip:SetText(format("[%s] %s", QG.quest.level or "?", QG.quest.title), color.r, color.g, color.b)
  else
    GameTooltip:SetText("|cff33ffccpf|cffffffffQuest |cffffcc00Guide")
  end

  if this.tip then
    GameTooltip:AddLine(this.tip, 1, 1, 1)
  elseif step then
    GameTooltip:AddLine(step.label, 1, 1, 1)
    for _, t in ipairs(step.targets) do
      local where = ""
      if not t.inzone and t.zone and loc("zones", t.zone) then
        where = " |cff888888(" .. loc("zones", t.zone) .. ")"
      end
      GameTooltip:AddLine((VERB_COLOR[t.verb] or "|cffffffff") .. t.verb .. "|r " .. t.name .. where, 1, 1, 1)
    end
    if step.more > 0 then
      GameTooltip:AddLine("+" .. step.more .. " more", 0.6, 0.6, 0.6)
    elseif not step.targets[1] then
      GameTooltip:AddLine("Nothing to target - follow the arrow", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff33ffccClick|r target and mark the nearest one", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff33ffccRight-click|r point the arrow only here", 0.8, 0.8, 0.8)
  end

  GameTooltip:AddLine("|cff33ffccCtrl-click|r choose quest  |cff33ffccDrag|r move", 0.8, 0.8, 0.8)
  GameTooltip:Show()
end

local function SaveBarPosition()
  local point, _, relpoint, x, y = QG.bar:GetPoint()
  C.barpos = { point, relpoint, x, y }
end

-- [[ portraits ]] --
-- The client only renders a portrait for a live unit (target, mouseover), so we
-- grab one the first time a quest NPC is seen and keep it for the session. Each
-- portrait is a small frame that gets reparented onto whichever icon needs it.
local portraits = {}

function QG:IsTargetName(name)
  for _, step in ipairs(self.steps or {}) do
    for _, t in ipairs(step.targets) do
      if t.name == name then
        return true
      end
    end
  end
end

function QG:CapturePortrait(unit)
  if not UnitExists(unit) or UnitIsPlayer(unit) then
    return
  end
  local name = UnitName(unit)
  if not name or not self:IsTargetName(name) then
    return
  end

  local p = portraits[name]
  local new = not p
  if new then
    p = CreateFrame("Frame", nil, UIParent)
    p:Hide()
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetAllPoints()
    p.tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    portraits[name] = p
  end
  SetPortraitTexture(p.tex, unit)

  if new then
    self:Render()
  end
end

local function DetachPortrait(b)
  local p = b.portrait
  if p then
    p:Hide()
    p:SetParent(UIParent)
    p.owner = nil
    b.portrait = nil
  end
end

local function AttachPortrait(b, p)
  if b.portrait == p then
    return
  end
  DetachPortrait(b)
  if p.owner then
    DetachPortrait(p.owner)
  end
  p:SetParent(b)
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  p:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  p:SetFrameLevel(b:GetFrameLevel() + 1)
  p:Show()
  p.owner, b.portrait = b, p
end

-- portrait of the step's preferred NPC, else of any of its NPCs we have seen
local function StepPortrait(step)
  for _, t in ipairs(step.targets) do
    if portraits[t.name] then
      return portraits[t.name]
    end
  end
end

local function GetIcon(i)
  if not icons[i] then
    local b = CreateFrame("Button", nil, QG.bar)
    b:SetWidth(ICON_SIZE)
    b:SetHeight(ICON_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    Backdrop(b)
    b.border = { b:GetBackdropBorderColor() }

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)

    -- badge, count and highlight live on a child frame so they draw above the portrait
    b.overlay = CreateFrame("Frame", nil, b)
    b.overlay:SetAllPoints()
    b.overlay:SetFrameLevel(b:GetFrameLevel() + 3)

    -- small corner icon: coin (buy), item (loot) or "?" (turn in)
    b.badge = b.overlay:CreateTexture(nil, "OVERLAY")
    b.badge:SetWidth(13)
    b.badge:SetHeight(13)
    b.badge:SetPoint("TOPLEFT", -2, 2)

    b.count = b.overlay:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(FONT, 10, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -1, 2)
    b.count:SetJustifyH("RIGHT")

    b.hl = b.overlay:CreateTexture(nil, "ARTWORK")
    b.hl:SetTexture(1, 1, 1, 0.2)
    b.hl:SetAllPoints(b.icon)
    b.hl:Hide()

    b:SetScript("OnClick", function()
      if IsControlKeyDown() or this.action == "menu" then
        ToggleDropDownMenu(1, nil, QG.dropdown, "cursor", 0, 0)
      elseif this.action == "resume" then
        QG:AttachArrow()
        QG:Render()
      elseif arg1 == "RightButton" then
        QG:ToggleFocus(this.step.key)
      else
        QG:TargetStep(this.step)
      end
    end)
    b:SetScript("OnEnter", function()
      this.hl:Show()
      IconTooltip()
    end)
    b:SetScript("OnLeave", function()
      this.hl:Hide()
      HideTooltip()
    end)
    b:SetScript("OnDragStart", function()
      QG.bar:StartMoving()
    end)
    b:SetScript("OnDragStop", function()
      QG.bar:StopMovingOrSizing()
      SaveBarPosition()
    end)
    icons[i] = b
  end
  return icons[i]
end

function QG:RenderCompact()
  local n = 0
  local function Icon(texture, step, action, tip)
    n = n + 1
    local b = GetIcon(n)
    b.step, b.action, b.tip = step, action, tip
    b.icon:SetTexture(texture)
    if strfind(texture, "Interface\\Icons\\", 1, true) then
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
      b.icon:SetTexCoord(0, 1, 0, 1)
    end
    DetachPortrait(b)
    b.badge:Hide()
    b.count:SetText("")
    b:SetBackdropBorderColor(b.border[1], b.border[2], b.border[3], b.border[4])
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", QG.bar, "TOPLEFT", (n - 1) * (ICON_SIZE + ICON_GAP), 0)
    b:Show()
    return b
  end

  for _, step in ipairs(self.steps or {}) do
    if not step.done then
      local b = Icon(StepTexture(step), step)
      local _, _, cur, req = strfind(step.label, "(%d+)%s*/%s*(%d+)%s*$")
      if cur then
        b.count:SetText(cur .. "/" .. req)
      end

      local portrait = StepPortrait(step)
      if portrait then
        AttachPortrait(b, portrait)
      end

      -- with a portrait on top, the corner badge says what the NPC is for
      local badge
      if step.targets[1] and step.targets[1].verb == "Buy" then
        badge = ICON_BUY
      elseif portrait and step.turnin then
        badge = ICON_TURNIN
      elseif portrait then
        badge = ItemTexture(step.itemid)
      end
      if badge then
        b.badge:SetTexture(badge)
        if badge == ICON_TURNIN then
          b.badge:SetTexCoord(0, 1, 0, 1)
        else
          b.badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        b.badge:Show()
      end

      if self.focusKey == step.key then
        b:SetBackdropBorderColor(1, 0.8, 0, 1)
      end
    end
  end

  if self.status then
    Icon(ICON_STATUS, nil, "menu", self.status)
  end
  if self.suspended and self.quest then
    Icon(ICON_RESUME, nil, "resume", "Arrow released - you picked another target on the map.\nClick to point the arrow at this quest again.")
  end

  for i = n + 1, getn(icons) do
    DetachPortrait(icons[i])
    icons[i]:Hide()
  end

  -- enlarge button always sits at the end, so the bar stays reachable even with no quest
  local enlarge = self.bar.enlarge
  enlarge:ClearAllPoints()
  enlarge:SetPoint("TOPLEFT", self.bar, "TOPLEFT", n * (ICON_SIZE + ICON_GAP), 0)
  self.bar:SetWidth(n * (ICON_SIZE + ICON_GAP) + enlarge:GetWidth())
  self.bar:Show()
end

-- switch between the icon row and the full window, keeping the top-left corner in place
function QG:SetMini(mini)
  local from, to = self.frame, self.bar
  if not mini then
    from, to = self.bar, self.frame
  end

  local left, top = from:GetLeft(), from:GetTop()
  if left and top then
    local scale = from:GetEffectiveScale() / UIParent:GetEffectiveScale()
    to:ClearAllPoints()
    to:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale, top * scale)
    C.pos = { "TOPLEFT", "BOTTOMLEFT", left * scale, top * scale }
    C.barpos = C.pos
  end

  C.full = not mini
  C.shown = true
  self:Render()
end

function QG:CreateBar()
  local bar = CreateFrame("Frame", "pfQuestGuideBar", UIParent)
  self.bar = bar
  bar:SetHeight(ICON_SIZE)
  bar:SetWidth(ICON_SIZE)
  bar:SetFrameStrata("MEDIUM")
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:ClearAllPoints()
  if C.barpos then
    bar:SetPoint(C.barpos[1], UIParent, C.barpos[2], C.barpos[3], C.barpos[4])
  else
    bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -220)
  end
  bar:Hide()

  local enlarge = CreateFrame("Button", nil, bar)
  bar.enlarge = enlarge
  enlarge:SetWidth(14)
  enlarge:SetHeight(ICON_SIZE)
  enlarge:RegisterForDrag("LeftButton")
  Backdrop(enlarge)
  enlarge.text = enlarge:CreateFontString(nil, "OVERLAY")
  enlarge.text:SetFont(FONT, 13, "OUTLINE")
  enlarge.text:SetAllPoints()
  enlarge.text:SetText("|cffaaaaaa+")
  enlarge.tip = "Enlarge to the full window.\nDrag to move."
  enlarge:SetScript("OnEnter", ShowTooltip)
  enlarge:SetScript("OnLeave", HideTooltip)
  enlarge:SetScript("OnClick", function()
    QG:SetMini(false)
  end)
  enlarge:SetScript("OnDragStart", function()
    QG.bar:StartMoving()
  end)
  enlarge:SetScript("OnDragStop", function()
    QG.bar:StopMovingOrSizing()
    SaveBarPosition()
  end)
end

function QG:InitDropDown()
  local info = { text = "Guide which quest?", isTitle = 1, notCheckable = 1 }
  UIDropDownMenu_AddButton(info)

  for _, q in ipairs(self:QuestList()) do
    local color = compat.GetDifficultyColor(q.level > 0 and q.level or UnitLevel("player"))
    info = {}
    info.text = format("|cff%02x%02x%02x[%d] %s", floor(color.r * 255), floor(color.g * 255),
      floor(color.b * 255), q.level, q.title)
    info.value = q.id
    info.checked = C.quest == q.id
    info.func = function()
      QG:SelectQuest(this.value)
    end
    UIDropDownMenu_AddButton(info)
  end

  if C.quest then
    info = { text = "|cffff8888Stop guiding", notCheckable = 1 }
    info.func = function()
      QG:SelectQuest(nil)
    end
    UIDropDownMenu_AddButton(info)
  end
end

local function SavePosition()
  local point, _, relpoint, x, y = QG.frame:GetPoint()
  C.pos = { point, relpoint, x, y }
end

function QG:CreatePanel()
  local f = CreateFrame("Frame", "pfQuestGuideFrame", UIParent)
  self.frame = f
  f:SetWidth(WIDTH)
  f:SetHeight(60)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  Backdrop(f)

  f:ClearAllPoints()
  if C.pos then
    f:SetPoint(C.pos[1], UIParent, C.pos[2], C.pos[3], C.pos[4])
  else
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -220)
  end

  -- header: click for the quest menu, drag to move
  local header = CreateFrame("Button", nil, f)
  header:SetPoint("TOPLEFT", 6, -4)
  header:SetPoint("TOPRIGHT", -36, -4)
  header:SetHeight(16)
  header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  header:RegisterForDrag("LeftButton")
  header.tip = "Click: choose the quest to guide\nRight-click: stop guiding\nDrag: move this window"
  header:SetScript("OnEnter", ShowTooltip)
  header:SetScript("OnLeave", HideTooltip)
  header:SetScript("OnDragStart", function()
    QG.frame:StartMoving()
  end)
  header:SetScript("OnDragStop", function()
    QG.frame:StopMovingOrSizing()
    SavePosition()
  end)
  header:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      QG:SelectQuest(nil)
    else
      ToggleDropDownMenu(1, nil, QG.dropdown, "cursor", 0, 0)
    end
  end)

  f.title = header:CreateFontString(nil, "OVERLAY")
  f.title:SetFont(FONT, 13, "OUTLINE")
  f.title:SetJustifyH("LEFT")
  f.title:SetAllPoints()

  local close = CreateFrame("Button", nil, f)
  close:SetPoint("TOPRIGHT", -5, -4)
  close:SetWidth(14)
  close:SetHeight(16)
  close.text = close:CreateFontString(nil, "OVERLAY")
  close.text:SetFont(FONT, 13, "OUTLINE")
  close.text:SetAllPoints()
  close.text:SetText("|cffaaaaaax")
  close.tip = "Hide this window (/pqg to show it again).\nThe arrow keeps guiding the quest."
  close:SetScript("OnEnter", ShowTooltip)
  close:SetScript("OnLeave", HideTooltip)
  close:SetScript("OnClick", function()
    C.shown = false
    QG:Render()
  end)

  local mini = CreateFrame("Button", nil, f)
  mini:SetPoint("RIGHT", close, "LEFT", -2, 0)
  mini:SetWidth(14)
  mini:SetHeight(16)
  mini.text = mini:CreateFontString(nil, "OVERLAY")
  mini.text:SetFont(FONT, 13, "OUTLINE")
  mini.text:SetAllPoints()
  mini.text:SetText("|cffaaaaaa-")
  mini.tip = "Minimize to a row of icons."
  mini:SetScript("OnEnter", ShowTooltip)
  mini:SetScript("OnLeave", HideTooltip)
  mini:SetScript("OnClick", function()
    QG:SetMini(true)
  end)

  self.dropdown = CreateFrame("Frame", "pfQuestGuideDropDown", UIParent, "UIDropDownMenuTemplate")
  UIDropDownMenu_Initialize(self.dropdown, function()
    QG:InitDropDown()
  end, "MENU")

  f:Hide()
  self:CreateBar()
end

-- [[ events ]] --
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:SetScript("OnEvent", function()
  if event == "PLAYER_TARGET_CHANGED" then
    -- marked on the next frame, so the enemies the target buttons cycle through
    -- on the way to a living mob don't all get an icon
    QG.pendingMark = true
    if C then
      QG:CapturePortrait("target")
    end
    return
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    if C then
      QG:CapturePortrait("mouseover")
    end
    return
  elseif event == "ADDON_LOADED" then
    if arg1 ~= "pfQuestGuide" then
      return
    end
    pfQuestGuide_config = pfQuestGuide_config or {}
    C = pfQuestGuide_config
    FONT = pfUI and pfUI.font_default or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    QG:CreatePanel()
    HookTracker()
  end
  QG.dirty = true
end)

events:SetScript("OnUpdate", function()
  if not C then
    return
  end
  local now = GetTime()

  if QG.pendingMark then
    QG.pendingMark = nil
    QG:Mark()
  end

  -- vanilla may refuse raid icons while solo; say so once instead of failing silently
  local check = QG.markCheck
  if check and now > check[1] then
    QG.markCheck = nil
    if UnitName("target") == check[3] and GetRaidTargetIndex("target") ~= check[2] and not QG.markWarned then
      QG.markWarned = true
      if GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then
        Print("The raid icon didn't stick - this client may only allow raid icons while you're in a party.")
      else
        Print("The raid icon didn't stick - in a raid you need to be leader or assistant to set them.")
      end
    end
  end

  if (this.tick or 0) > now then
    return
  end
  this.tick = now + 0.25

  -- rebuild after quest log changes (also retries until pfQuest's database is ready)
  if QG.dirty and pfDatabase.localized then
    QG.dirty = nil
    QG:Rebuild()
  elseif QG.status == "Waiting for pfQuest..." then
    QG.dirty = true
  end

  if (this.arrowtick or 0) < now then
    this.arrowtick = now + 0.5
    QG:UpdateArrow()
  end
end)

-- [[ slash command ]] --
SLASH_PFQUESTGUIDE1 = "/pqg"
SLASH_PFQUESTGUIDE2 = "/pfguide"
SlashCmdList["PFQUESTGUIDE"] = function(msg)
  msg = string.lower(msg or "")
  if msg == "target" then
    QG:TargetNext()
  elseif msg == "clear" then
    QG:SelectQuest(nil)
  elseif msg == "marks" then
    QG.markUsed = {}
    Print("Raid icon rotation reset.")
  elseif msg == "help" then
    Print("/pqg - show or hide the window")
    Print("/pqg target - target the next quest mob/NPC (same as the keybinding)")
    Print("/pqg clear - stop guiding the current quest")
    Print("/pqg marks - start handing out raid icons from the first one again")
  else
    C.shown = C.shown == false
    QG:Render()
  end
end
