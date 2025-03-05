VERSION = "0.3.1"

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

local function OmniSelect(bp, args)
    if #args < 1 then return end

    local buf = bp.Buf
    local cursor = buf:GetActiveCursor()
    local targetLine = cursor.Loc.Y

    if Common.OmniSelectType == nil or Common.OmniSelectType == "" then
        Common.OmniSelectType = "relative"
    end

    local selectLineCount = tonumber(args[1])
    if selectLineCount == nil then
        micro.InfoBar():Error(args[1].." is not a valid target selection line")
        return
    end

    if Common.OmniSelectType == "relative" then
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
    bp:Relocate()
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
    -- Convert history line diff to integer in the beginning
    if Common.OmniHistoryLineDiff == nil or Common.OmniHistoryLineDiff == "" then
        Common.OmniHistoryLineDiff = 5
    else
        Common.OmniHistoryLineDiff = tonumber(Common.OmniHistoryLineDiff)
        if Common.OmniHistoryLineDiff == nil then
            Common.OmniHistoryLineDiff = 5
        end
    end
    
    if Common.OmniHistoryTimeTravelMulti == nil or Common.OmniHistoryTimeTravelMulti == "" then
        Common.OmniHistoryTimeTravelMulti = 5
    else
        Common.OmniHistoryTimeTravelMulti = tonumber(Common.OmniHistoryTimeTravelMulti)
        if Common.OmniHistoryTimeTravelMulti == nil then
            Common.OmniHistoryTimeTravelMulti = 5
        end
    end
    
    if Common.OmniCanUseAddCursor == nil then
        Common.OmniCanUseAddCursor = false
    end
    
    if Common.OmniMinimapScrollContent == nil then
        Common.OmniMinimapScrollContent = true
    -- elseif Common.OmniMinimapScrollContent == "true" then
    --     Common.OmniMinimapScrollContent = true
    -- elseif Common.OmniMinimapScrollContent == "false" then
    --     Common.OmniMinimapScrollContent = false
    elseif Common.OmniMinimapScrollContent ~= true and Common.OmniMinimapScrollContent ~= false then
        micro.Log("Invalid value for OmniMinimapScrollContent:", Common.OmniMinimapScrollContent)
        micro.InfoBar():Error("Invalid value for OmniMinimapScrollContent:", Common.OmniMinimapScrollContent)
    end

    if Common.OmniMinimapMaxIndent == nil then
        Common.OmniMinimapMaxIndent = 5
    else
        Common.OmniMinimapMaxIndent = tonumber(Common.OmniMinimapMaxIndent)
        if Common.OmniMinimapMaxIndent == nil then
            Common.OmniMinimapMaxIndent = 5
        end
    end

    if Common.OmniMinimapContextNumLines == nil then
        Common.OmniMinimapContextNumLines = 20
    else
        Common.OmniMinimapContextNumLines = tonumber(Common.OmniMinimapContextNumLines)
        if Common.OmniMinimapContextNumLines == nil then
            Common.OmniMinimapContextNumLines = 20
        end
    end
    
    if Common.OmniMinimapMinDistance == nil then
        Common.OmniMinimapMinDistance = 20
    else
        Common.OmniMinimapMinDistance = tonumber(Common.OmniMinimapMinDistance)
        if Common.OmniMinimapMinDistance == nil then
            Common.OmniMinimapMinDistance = 20
        end
    end
    
    if Common.OmniMinimapMaxColumns == nil then
        Common.OmniMinimapMaxColumns = 75
    else
        Common.OmniMinimapMaxColumns = tonumber(Common.OmniMinimapMaxColumns)
        if Common.OmniMinimapMaxColumns == nil then
            Common.OmniMinimapMaxColumns = 75
        end
    end
    
    if Common.OmniMinimapTargetNumLines == nil then
        Common.OmniMinimapTargetNumLines = 100
    else
        Common.OmniMinimapTargetNumLines = tonumber(Common.OmniMinimapTargetNumLines)
        if Common.OmniMinimapTargetNumLines == nil then
            Common.OmniMinimapTargetNumLines = 100
        end
    end

    if Common.OmniContentArgs == nil or Common.OmniContentArgs == "" then
        Common.OmniContentArgs =
            "--header='enter: select | alt-enter: output filtered results | alt-q/esc: exit | "..
            "page-[up/down]: preview-[up/down] | alt-[up/down]: half-page-[up/down]' "..
            "--bind 'alt-f:reload:rg --glob=!.git/ -i -F -uu -n {q}' "..
            "--delimiter : -i --reverse "..
            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
            "alt-up:half-page-up,alt-down:half-page-down,alt-q:abort "..
            "--bind 'alt-enter:change-multi+select-all+accept' "..
            "--preview-window 'down,+{2}-/2' "..
            "--preview 'bat -f -n --highlight-line {2} {1}'"
    end

    if Common.OmniGotoFileArgs == nil or Common.OmniGotoFileArgs == "" then
        Common.OmniGotoFileArgs = 
            "--header='enter: select | alt-enter: output filtered results | alt-q/esc: exit | "..
            "page-[up/down]: preview-[up/down] | alt-[up/down]: half-page-[up/down]' "..
            "-i --reverse "..
            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
            "alt-up:half-page-up,alt-down:half-page-down,alt-q:abort "..
            "--bind 'alt-enter:change-multi+select-all+accept' "..
            "--preview-window 'down' "..
            "--preview 'bat -f -n {}'"
    end

    if Common.OmniLocalSearchArgs == nil or Common.OmniLocalSearchArgs == "" then
        Common.OmniLocalSearchArgs =
            "--header='enter: select | alt-enter: output filtered results | alt-q/esc: exit | "..
            "page-[up/down]: preview-[up/down] | alt-[up/down]: half-page-[up/down]' "..
            "--bind 'start:reload:bat -n --decorations always {filePath}' "..
            "-i --reverse "..
            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
            "alt-up:half-page-up,alt-down:half-page-down,alt-q:abort "..
            "--bind 'alt-enter:change-multi+select-all+accept' "..
            "--preview-window 'down,+{1}-/2' "..
            "--preview 'bat -f -n --highlight-line {1} {filePath}'"
    end
    
    if Common.OmniTabSearchArgs == nil or Common.OmniTabSearchArgs == "" then 
        Common.OmniTabSearchArgs = 
            "--header='enter: select | alt-enter: output filtered results | alt-q/esc: exit | "..
            "page-[up/down]: preview-[up/down] | alt-[up/down]: half-page-[up/down]' "..
            "--bind 'start:reload:bat {filePath}' "..
            "--delimiter : -i --reverse "..
            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
            "alt-up:half-page-up,alt-down:half-page-down,alt-q:abort "..
            "--bind 'alt-enter:change-multi+select-all+accept' "..
            "--preview-window 'down,+{2}-/2' "..
            "--preview 'bat -f -n --highlight-line {2} {1}'"
    end

    if Common.OmniFzfCmd == nil then
        Common.OmniFzfCmd = "fzf"
    end

    if Common.OmniNewFileMethod == nil then
        Common.OmniNewFileMethod = "smart_newtab"
    end
end

function preQuit(bp)
    Diff.CheckAndQuitDiffView(bp)
    Minimap.CheckAndQuitMinimap(bp)
    return true
end

function onAnyEvent()
    micro.Log("onAnyEvent called")
    local bpToCenter = Diff.UpdateDiffView()
    if bpToCenter ~= nil then
        OmniCenter(bpToCenter)
    end
    History.RecordCursorHistory()
    Minimap.UpdateMinimapView()
end

function init()
    config.MakeCommand("OmniGlobalSearch", Search.OmniContent, config.NoComplete)
    config.MakeCommand("OmniLocalSearch", Search.OmniLocalSearch, config.NoComplete)
    config.MakeCommand("OmniGotoFile", Search.OmniGotoFile, config.NoComplete)
    
    config.MakeCommand("OmniCenter", OmniCenter, config.NoComplete)
    config.MakeCommand("OmniJumpSelect", OmniSelect, config.NoComplete)

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
    
    
    
    config.MakeCommand("OmniTest", OmniTest, TestCompleter)
    config.MakeCommand("OmniTest2", OmniTest2, config.NoComplete)
    config.MakeCommand("OmniTest3", OmniTest3, config.NoComplete)
    
    -- Initialize settings
    InitializeSettings()

    -- Check commands
    local missingCommands = {}
    if not CheckCommand(Common.OmniFzfCmd.." --version") then
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
