VERSION = "0.5.0"

-- luacheck . --globals import VERSION preQuit onAnyEvent init --ignore 212 542 611 612 613 614

local micro = import("micro")
local buffer = import("micro/buffer")
local shell = import("micro/shell")
local util = import("micro/util")
local strings = import("strings")
-- local os = import("os")

local config = import("micro/config")
local fmt = import('fmt')
package.path = fmt.Sprintf('%s;%s/plug/MicroOmni/?.lua', package.path, config.ConfigDir)

local Common = require("Common")
local Search = require("Search")
local History = require("History")
local WordJump = require("WordJump")
local Highlight = require("Highlight")
local Diff = require("Diff")
local Minimap = require("Minimap")
local Session = require("Session")

local OmniCursorSelectMarks = {}

-- See issue https://github.com/zyedidia/micro/issues/3320
-- Modified from https://github.com/kaarrot/microgrep/blob/e1a32e8b95397a40e5dda0fb43e7f8d17469b88c/microgrep.lua#L118
local function WriteToClipboardWorkaround(content)
    if micro.CurPane() == nil then return end

    local curTab = micro.CurPane():Tab()
    local curPaneId = micro.CurPane():ID()
    local curPaneIndex = curTab:GetPane(curPaneId)

    -- Split pane in half and add some text
    micro.CurPane():HSplitAction()
    
    local buf, _ = buffer.NewBuffer(content, "")
    -- Workaround to copy path to clioboard
    micro.CurPane():OpenBuffer(buf)
    micro.CurPane():SelectAll()
    micro.CurPane():Copy()
    micro.CurPane():ForceQuit() -- Close current buffer pane

    curTab:SetActive(curPaneIndex)
end

local function CheckCommand(command)
    local _, error = shell.RunCommand(command)
    if error ~= nil then return false end
    return true
end

-- "Inspired" from: https://github.com/zyedidia/micro/issues/1807#issuecomment-1907899274
local function ResizeInternal(bp, expand, amount)
    if amount == nil then
        micro.InfoBar():Error("Failed to get MicroOmni.ResizeAmount")
        return
    end
    
    if not expand then
        amount = amount * -1
    end
    
    local n = amount
    local tab = bp:Tab()
    local id = bp:ID()
    local node = tab:GetNode(id)
    local nextChildren = {}
    -- local nextChildrenParents = {}
    
    -- We need to figure out what is the parent of bp, need to traverse the whole tree
    -- So first add all the children of tab
    table.insert(nextChildren, tab:Children())
    -- table.insert(nextChildrenParents, tab)
    
    local found = false
    local isEnd = false
    local prevNode = nil
    -- local scaledParent = nil
    while #nextChildren ~= 0 do
        local children = nextChildren[1]
        -- local parent = nextChildrenParents[1]
        table.remove(nextChildren, 1)
        -- table.remove(nextChildrenParents, 1)
        
        for i = 1, #children do
            -- Keep searching recursively if we haven't found the bp
            if children[i]:ID() ~= id then
                table.insert(nextChildren, children[i]:Children())
                -- table.insert(nextChildrenParents, children[i])
            -- Stop and record the parent if we found the bp
            else
                found = true
                isEnd = (i == #children)
                -- scaledParent = parent
                break
            end
            prevNode = children[i]
        end
    end
    
    if not found then
        return
    end
    
    -- NOTE: Dumb hack where ResizePane() actually resizes the previous node if the current node 
    --       is at the end
    if isEnd then
        n = n * -1
        node = prevNode
    end
    
    -- Perform resizing
    if node.Kind == 0 then      -- Vertical
        bp:ResizePane(node.W + n)
    elseif node.Kind == 1 then  -- Horizontal
        bp:ResizePane(node.H + n)
    end
    
    -- Finally, set all the children from bp's parent to not auto scale
    -- if config.GetGlobalOption("MicroOmni.AutoDisablePropResize") then
    --     for i = 1, #scaledParent:Children() do
    --         scaledParent:Children()[i]:SetPropScale(false)
    --     end
    -- end
end


local function OmniResizeIncrease(bp)
    ResizeInternal(bp, true, config.GetGlobalOption("MicroOmni.ResizeAmount"))
end

local function OmniResizeDecrease(bp)
    ResizeInternal(bp, false, config.GetGlobalOption("MicroOmni.ResizeAmount"))
end


local function OmniSelect(bp, args)
    if #args < 1 then return end

    local buf = bp.Buf
    
    for i = 1, bp.Buf:NumCursors() do
        local cursor = bp.Buf:GetCursor(i - 1)
        if config.GetGlobalOption("MicroOmni.SelectType") ~= "relative" then
            cursor = buf:GetActiveCursor()
        end
    
        local targetLine = cursor.Loc.Y
        local selectLineCount = tonumber(args[1])
        if selectLineCount == nil then
            micro.InfoBar():Error(args[1].." is not a valid target selection line")
            return
        end

        if config.GetGlobalOption("MicroOmni.SelectType") == "relative" then
            targetLine = targetLine + selectLineCount
        else
            targetLine = selectLineCount - 1
        end
        
        local selectX = 0
        cursor.OrigSelection[1] = buffer.Loc(cursor.Loc.X, cursor.Loc.Y)

        if targetLine > cursor.Loc.Y then
            local lineLength = util.CharacterCountInString(buf:Line(targetLine))
            selectX = lineLength
        end

        -- micro.InfoBar():Message("targetLine: ", targetLine)
        -- micro.Log("targetLine: ", targetLine)
        cursor:GotoLoc(buffer.Loc(selectX, targetLine))
        cursor:SelectTo(buffer.Loc(selectX, targetLine))
        
        if config.GetGlobalOption("MicroOmni.SelectType") ~= "relative" then
            break
        end
    end
    
    bp:Relocate()
end

local function OmniSelectMark(bp)
    local hasMarks = false
    if #OmniCursorSelectMarks ~= 0 then
        hasMarks = true
    end
    
    if hasMarks and #OmniCursorSelectMarks ~= bp.Buf:NumCursors() then
        micro.InfoBar():Error("Cursor count mismatch, failed to perform marked selection")
        OmniCursorSelectMarks = {}
        return
    end
    
    for i = 1, bp.Buf:NumCursors() do
        local cursor = bp.Buf:GetCursor(i - 1)
        local cursorLoc = buffer.Loc(cursor.Loc.X, cursor.Loc.Y)
        
        if hasMarks == false then
            table.insert(OmniCursorSelectMarks, buffer.Loc(cursorLoc.X, cursorLoc.Y))
        else
            cursor.OrigSelection[1] = OmniCursorSelectMarks[i]
            cursor:GotoLoc(cursorLoc)
            cursor:SelectTo(cursorLoc)
        end
    end
    
    if hasMarks == true then
        micro.InfoBar():Message("Selected from selection markers")
        OmniCursorSelectMarks = {}
        bp:Relocate()
    else
        micro.InfoBar():Message("Created ", #OmniCursorSelectMarks, " selection markers")
    end
end


local function Internal_OmniCopyPathRelative(yes, cancelled)
    if cancelled or not yes then
        return
    end
    local bp = micro.CurPane()
    if bp.Buf == nil then return end
    WriteToClipboardWorkaround(bp.Buf.Path)
    -- clipboard.Write(bp.Buf.Path, clipboard.ClipboardReg)
    micro.InfoBar():Message(bp.Buf.Path, " copied into clipboard")
end

local function Internal_OmniCopyPathAbsolute(yes, cancelled)
    if cancelled or not yes then
        return
    end
    local bp = micro.CurPane()
    if bp.Buf == nil then return end
    WriteToClipboardWorkaround(bp.Buf.AbsPath)
    -- clipboard.Write(bp.Buf.AbsPath, clipboard.ClipboardReg)
    micro.InfoBar():Message(bp.Buf.AbsPath, " copied into clipboard")
end

local function OmniCopyRelativePath(bp)
    if bp.Buf == nil then return end
    micro.InfoBar():YNPrompt("Copy? (y/n/esc) > ", Internal_OmniCopyPathRelative)
end

local function OmniCopyAbsolutePath(bp)
    if bp.Buf == nil then return end
    micro.InfoBar():YNPrompt("Copy? (y/n/esc) > ", Internal_OmniCopyPathAbsolute)
end

local function OmniCenter(bp)
    local view = bp:GetView()
    bp.Cursor:ResetSelection()
    bp.Buf:ClearCursors()
    local targetLineY = view.StartLine.Line + view.Height / 2
    bp.Cursor:GotoLoc(Common.LocBoundCheck(bp.Buf, buffer.Loc(bp.Cursor.Loc.X, targetLineY)))
    
    micro.Log("Node Tree:\n", bp:Tab():String())
end

-- Testing auto complete for commands
local function TestCompleter(buf)
    local activeCursor = buf:GetActiveCursor()
    local input, argstart = buf:GetArg()
    -- micro.Log("input:", input)
    -- micro.Log("argstart:", argstart)
    local suggestions = {}
    local commands =
    {
        "set", 
        "reset",
        "setlocal",
        "show",
        "showkey"
    }
    
    for _, cmd in ipairs(commands) do
        -- micro.Log("cmd:", cmd)
        if strings.HasPrefix(cmd, input) then
            table.insert(suggestions, cmd)
        end
    end

    -- sort.Strings(suggestions)
    table.sort(suggestions, function(a, b) return a:upper() < b:upper() end)
    -- completions := make([]string, len(suggestions))
    local completions = {}
    for _, suggestion in ipairs(suggestions) do
        local offset = activeCursor.X - argstart
        table.insert(completions, string.sub(suggestion, offset + 1, string.len(suggestion)))
    end
    return completions, suggestions
    -- return {"test", "test2"}, {"test", "test A"}
end

local function OmniTest(bp, args)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)
    bp:CdCmd(args)
end

local function TestDoneCB(msg, cancelled)
    -- git diff --output=test.diff -U5 --no-color ".\DefaultUserConfig.yaml" ".\DefaultUserConfig - Copy.yaml"
    local output, err = shell.RunInteractiveShell(msg, false, true)
    if err == nil or err:Error() == "exit status 1" then
        -- OmniNewTabRight(micro.CurPane())
        micro.CurPane().Buf:Insert(buffer.Loc(0, 0), output)
    else
        micro.InfoBar():Error(err)
    end
end

local function OmniTest2(bp, args)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)
    -- local wd = os.Getwd()
    -- micro.InfoBar():Message("Getwd: ", wd)
    -- local bp = micro.CurPane()
    -- bp:HandleCommand("OmniLocalSearch")
    -- bp:HandleCommand("OmniHighlightOnly")
    micro.InfoBar():Prompt("Test prompt> ", "", "Test", nil, TestDoneCB)
    -- local output, err = shell.RunInteractiveShell(finalCmd, false, true)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", nil, OnWordJump)
end

local function OmniTest3(bp, args)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)
    -- local wd = os.Getwd()
    -- local path = bp.buf.AbsPath
end

local function OmniNewTabRight(bp)
    local currentActiveIndex = micro.Tabs():Active()
    bp:NewTabCmd({})
    bp:TabMoveCmd({tostring(currentActiveIndex + 2)})
end

local function OmniTabScrollRight(bp)
    -- local totalSize = micro.Tabs().TabWindow:TotalSize()
    -- micro.InfoBar():Message("totalSize:", totalSize)
    micro.Tabs().TabWindow:Scroll(25)
    -- w.hscroll = util.Clamp(w.hscroll, 0, s-w.Width)
end

local function OmniTabScrollLeft(bp)
    -- local totalSize = micro.Tabs().TabWindow:TotalSize()
    -- micro.InfoBar():Message("totalSize:", totalSize)
    micro.Tabs().TabWindow:Scroll(-25)
    -- w.hscroll = util.Clamp(w.hscroll, 0, s-w.Width)
end


local function OmniNewTabLeft(bp)
    local currentActiveIndex = micro.Tabs():Active()
    bp:NewTabCmd({})
    bp:TabMoveCmd({tostring(currentActiveIndex + 1)})
end

local function InitializeSettings()
    config.RegisterCommonOption('MicroOmni', 'GlobalSearchArgs', 
            "--header='enter: select | alt-enter: output filtered results | alt-q/esc: exit | "..
            "alt-f: ripgrep query | page-[up/down]: preview-[up/down] | "..
            "alt-[up/down]: half-page-[up/down]' "..
            "--bind 'alt-f:reload:rg --glob=!.git/ -i -F -uu -n {q}' "..
            "--delimiter : -i --reverse "..
            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
            "alt-up:half-page-up,alt-down:half-page-down,alt-q:abort "..
            "--bind 'alt-enter:change-multi+select-all+accept' "..
            "--preview-window 'down,+{2}-/2' "..
            "--preview 'bat -f -n --highlight-line {2} {1}'")
    
    config.RegisterCommonOption('MicroOmni', 'LocalSearchArgs', 
            "--header='enter: select | alt-enter: output filtered results | alt-q/esc: exit | "..
            "page-[up/down]: preview-[up/down] | alt-[up/down]: half-page-[up/down]' "..
            "--bind 'start:reload:bat -n --decorations always {filePath}' "..
            "-i --reverse "..
            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
            "alt-up:half-page-up,alt-down:half-page-down,alt-q:abort "..
            "--bind 'alt-enter:change-multi+select-all+accept' "..
            "--preview-window 'down,+{1}-/2' "..
            "--preview 'bat -f -n --highlight-line {1} {filePath}'")
    
    config.RegisterCommonOption('MicroOmni', 'GotoFileArgs', 
            "--header='enter: select | alt-enter: output filtered results | alt-q/esc: exit | "..
            "page-[up/down]: preview-[up/down] | alt-[up/down]: half-page-[up/down]' "..
            "-i --reverse "..
            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
            "alt-up:half-page-up,alt-down:half-page-down,alt-q:abort "..
            "--bind 'alt-enter:change-multi+select-all+accept' "..
            "--preview-window 'down' "..
            "--preview 'bat -f -n {}'")
    
    config.RegisterCommonOption('MicroOmni', 'TabSearchArgs', 
            "--header='enter: select | alt-enter: output filtered results | alt-q/esc: exit | "..
            "page-[up/down]: preview-[up/down] | alt-[up/down]: half-page-[up/down]' "..
            "--bind 'start:reload:bat {filePath}' "..
            "--delimiter : -i --reverse "..
            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
            "alt-up:half-page-up,alt-down:half-page-down,alt-q:abort "..
            "--bind 'alt-enter:change-multi+select-all+accept' "..
            "--preview-window 'down,+{2}-/2' "..
            "--preview 'bat -f -n --highlight-line {2} {1}'")
    
    config.RegisterCommonOption('MicroOmni', 'SelectType', "relative")
    config.RegisterCommonOption('MicroOmni', 'HistoryLineDiff', 5)
    config.RegisterCommonOption('MicroOmni', 'HistoryTimeTravelMulti', 5)
    config.RegisterCommonOption('MicroOmni', 'CanUseAddCursor', false)

    config.RegisterCommonOption('MicroOmni', 'FzfCmd', 'fzf')
    config.RegisterCommonOption('MicroOmni', 'NewFileMethod', 'smart_newtab')

    config.RegisterCommonOption('MicroOmni', 'MinimapMaxIndent', 5)
    config.RegisterCommonOption('MicroOmni', 'MinimapContextNumLines', 20)
    config.RegisterCommonOption('MicroOmni', 'MinimapMinDistance', 20)
    config.RegisterCommonOption('MicroOmni', 'MinimapMaxColumns', 75)
    config.RegisterCommonOption('MicroOmni', 'MinimapTargetNumLines', 100)
    config.RegisterCommonOption('MicroOmni', 'MinimapScrollContent', true)
    
    config.RegisterCommonOption('MicroOmni', 'AutoSaveEnabled', true)
    config.RegisterCommonOption('MicroOmni', 'AutoSaveToLocal', false)
    config.RegisterCommonOption('MicroOmni', 'AutoSaveName', "autosave")
    config.RegisterCommonOption('MicroOmni', 'AutoSaveInterval', 60)
    config.RegisterCommonOption('MicroOmni', 'ResizeAmount', 5)
    -- config.RegisterCommonOption('MicroOmni', 'AutoDisablePropResize', true)
    
    if config.GetGlobalOption("OmniGlobalSearchArgs") ~= nil then
        micro.InfoBar():Error(  "OmniGlobalSearchArgs is no longer used, " .. 
                                "use MicroOmni.GlobalSearchArgs instead")
    end

    if config.GetGlobalOption("OmniLocalSearchArgs") ~= nil then
        micro.InfoBar():Error(  "OmniLocalSearchArgs is no longer used, " .. 
                                "use MicroOmni.LocalSearchArgs instead")
    end

    if config.GetGlobalOption("OmniGotoFileArgs") ~= nil then
        micro.InfoBar():Error(  "OmniGotoFileArgs is no longer used, " .. 
                                "use MicroOmni.GotoFileArgs instead")
    end

    if config.GetGlobalOption("OmniTabSearchArgs") ~= nil then
        micro.InfoBar():Error(  "OmniTabSearchArgs is no longer used, " .. 
                                "use MicroOmni.TabSearchArgs instead")
    end

    if config.GetGlobalOption("OmniSelectType") ~= nil then
        micro.InfoBar():Error(  "OmniSelectType is no longer used, " .. 
                                "use MicroOmni.SelectType instead")
    end

    if config.GetGlobalOption("OmniHistoryLineDiff") ~= nil then
        micro.InfoBar():Error(  "OmniHistoryLineDiff is no longer used, " .. 
                                "use MicroOmni.HistoryLineDiff instead")
    end

    if config.GetGlobalOption("OmniHistoryTimeTravelMulti") ~= nil then
        micro.InfoBar():Error(  "OmniHistoryTimeTravelMulti is no longer used, " .. 
                                "use MicroOmni.HistoryTimeTravelMulti instead")
    end

    if config.GetGlobalOption("OmniFzfCmd") ~= nil then
        micro.InfoBar():Error(  "OmniFzfCmd is no longer used, " .. 
                                "use MicroOmni.FzfCmd instead")
    end

    if config.GetGlobalOption("OmniNewFileMethod") ~= nil then
        micro.InfoBar():Error(  "OmniNewFileMethod is no longer used, " .. 
                                "use MicroOmni.NewFileMethod instead")
    end

    if config.GetGlobalOption("OmniMinimapMaxIndent") ~= nil then
        micro.InfoBar():Error(  "OmniMinimapMaxIndent is no longer used, " .. 
                                "use MicroOmni.MinimapMaxIndent instead")
    end

    if config.GetGlobalOption("OmniMinimapContextNumLines") ~= nil then
        micro.InfoBar():Error(  "OmniMinimapContextNumLines is no longer used, " .. 
                                "use MicroOmni.MinimapContextNumLines instead")
    end

    if config.GetGlobalOption("OmniMinimapMinDistance") ~= nil then
        micro.InfoBar():Error(  "OmniMinimapMinDistance is no longer used, " .. 
                                "use MicroOmni.MinimapMinDistance instead")
    end

    if config.GetGlobalOption("OmniMinimapMaxColumns") ~= nil then
        micro.InfoBar():Error(  "OmniMinimapMaxColumns is no longer used, " .. 
                                "use MicroOmni.MinimapMaxColumns instead")
    end

    if config.GetGlobalOption("OmniMinimapTargetNumLines") ~= nil then
        micro.InfoBar():Error(  "OmniMinimapTargetNumLines is no longer used, " .. 
                                "use MicroOmni.MinimapTargetNumLines instead")
    end

    if config.GetGlobalOption("OmniMinimapScrollContent") ~= nil then
        micro.InfoBar():Error(  "OmniMinimapScrollContent is no longer used, " .. 
                                "use MicroOmni.MinimapScrollContent instead")
    end
end

function preQuit(bp)
    Diff.CheckAndQuitDiffView(bp)
    Minimap.CheckAndQuitMinimap(bp)
    return true
end

function onAnyEvent()
    -- micro.Log("onAnyEvent called")
    local bpToCenter = Diff.UpdateDiffView()
    if bpToCenter ~= nil then
        OmniCenter(bpToCenter)
    end
    History.RecordCursorHistory()
    Minimap.UpdateMinimapView()
    
    -- Add auto-save check
    Session.CheckAutoSave()
end

function preinit()
    config.MakeCommand("OmniGlobalSearch", Search.OmniContent, config.NoComplete)
    config.MakeCommand("OmniLocalSearch", Search.OmniLocalSearch, config.NoComplete)
    config.MakeCommand("OmniGotoFile", Search.OmniGotoFile, config.NoComplete)
    
    config.MakeCommand("OmniCenter", OmniCenter, config.NoComplete)
    config.MakeCommand("OmniJumpSelect", OmniSelect, config.NoComplete)
    config.MakeCommand("OmniSelectMark", OmniSelectMark, config.NoComplete)

    config.MakeCommand("OmniPreviousHistory", History.GoToPreviousHistory, config.NoComplete)
    config.MakeCommand("OmniNextHistory", History.GoToNextHistory, config.NoComplete)

    config.MakeCommand("OmniCopyRelativePath", OmniCopyRelativePath, config.NoComplete)
    config.MakeCommand("OmniCopyAbsolutePath", OmniCopyAbsolutePath, config.NoComplete)

    config.MakeCommand("OmniHighlightOnly", Highlight.OmniHighlightOnly, config.NoComplete)
    config.MakeCommand("OmniSpawnCursorNextHighlight", Highlight.OmniSpawnCursorNextHighlight, config.NoComplete)
    config.MakeCommand("OmniMoveLastCursorNextHighlight", Highlight.OmniMoveLastCursorNextHighlight, config.NoComplete)
    
    config.MakeCommand("OmniJump", WordJump.OmniJump, config.NoComplete)
    
    config.MakeCommand("OmniNewTabRight", OmniNewTabRight, config.NoComplete)
    config.MakeCommand("OmniNewTabLeft", OmniNewTabLeft, config.NoComplete)

    config.MakeCommand("OmniDiff", Diff.OmniDiff, config.NoComplete)
    
    config.MakeCommand("OmniMinimap", Minimap.OmniMinimap, config.NoComplete)
    
    config.MakeCommand("OmniTabScrollRight", OmniTabScrollRight, config.NoComplete)
    config.MakeCommand("OmniTabScrollLeft", OmniTabScrollLeft, config.NoComplete)
    
    config.MakeCommand("OmniTabSearch", Search.OmniTabSearch, config.NoComplete)
    
    -- Session management commands
    config.MakeCommand("OmniSaveSession", Session.SaveSession, config.NoComplete)
    config.MakeCommand("OmniLoadSession", Session.LoadSession, Session.SessionCompleter)
    config.MakeCommand("OmniListSessions", Session.ListSessions, config.NoComplete)
    config.MakeCommand("OmniDeleteSession", Session.DeleteSession, Session.SessionCompleter)
    
    -- Working directory session management commands
    config.MakeCommand("OmniSaveSessionLocal", Session.SaveSessionLocal, config.NoComplete)
    config.MakeCommand("OmniLoadSessionLocal", Session.LoadSessionLocal, Session.SessionCompleterLocal)
    config.MakeCommand("OmniListSessionsLocal", Session.ListSessionsLocal, config.NoComplete)
    config.MakeCommand("OmniDeleteSessionLocal", Session.DeleteSessionLocal, Session.SessionCompleterLocal)

    config.MakeCommand("OmniResizeIncrease", OmniResizeIncrease, config.NoComplete)
    config.MakeCommand("OmniResizeDecrease", OmniResizeDecrease, config.NoComplete)
    
    config.MakeCommand("OmniTest", OmniTest, TestCompleter)
    config.MakeCommand("OmniTest2", OmniTest2, config.NoComplete)
    config.MakeCommand("OmniTest3", OmniTest3, config.NoComplete)
    
    -- Initialize settings
    InitializeSettings()

    -- Check commands
    local missingCommands = {}
    if not CheckCommand(config.GetGlobalOption("MicroOmni.FzfCmd").." --version") then
        missingCommands[#missingCommands + 1] = "fzf"
    end
    
    if not CheckCommand("rg -V") then
        missingCommands[#missingCommands + 1] = "ripgrep"
    end
    
    if not CheckCommand("bat -V") then
        missingCommands[#missingCommands + 1] = "bat"
    end
    
    if not CheckCommand("diff -v") then
        missingCommands[#missingCommands + 1] = "diff"
    end

    if #missingCommands ~= 0 then
        local missingCommandsString = ""
        
        for i = 1, #missingCommands do
            if i ~= #missingCommands then
                missingCommandsString = missingCommandsString..missingCommands[i]..", "
            else
                missingCommandsString = missingCommandsString..missingCommands[i].." "
            end
        end
        
        micro.InfoBar():Error(  missingCommandsString..
                                "are missing. Some functionalities might not work")
    end

end
