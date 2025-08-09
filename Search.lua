local micro = import("micro")
local util = import("micro/util")
local filepath = import("path/filepath")
local shell = import("micro/shell")
local config = import("micro/config")
local buffer = import("micro/buffer")


local os = import("os")
local runtime = import("runtime")
local fmt = import('fmt')

package.path = fmt.Sprintf('%s;%s/plug/MicroOmni/?.lua', package.path, config.ConfigDir)
local Common = require("Common")


local OmniContentFindPath = ""
local OmniSearchText = ""

local Self = {}

-- NOTE: lineNum is string
local function fzfParseOutput(output, bp, lineNum, gotoLineIfExists)
    micro.Log("fzfParseOutput called")
    if output ~= "" then
        local file = string.gsub(output, "[\n\r]", "")
        if file == nil then
            return
        end
        Common.HandleOpenFile(file, bp, lineNum, gotoLineIfExists)
    end
end

local function getOS()
    if runtime.GOOS == "windows" then
        return "Windows"
    else
        return "Unix"
    end
end

local function FindContent(str, searchLoc)
    micro.Log("Find Content called")
    local bp = micro.CurPane()
    local selectedText = str
    local fzfArgs
    -- micro.Log("selectedText before: ", selectedText)

    local firstWord, _ = selectedText:match("^(.[^%s]*)%s-(.*)$")

    if firstWord == nil or firstWord == "" then
        micro.InfoBar():Error("Failed to extract first word... str: ", str)
        return
    end
    
    local locations = {}
    for s in string.gmatch(searchLoc, "[^,]+") do
        s = string.gsub(s, '^%s*(.-)%s*$', '%1') -- Trim spaces
        table.insert(locations, s)
    end
    
    local currentOS = getOS()
    local finalCmd;
    if currentOS == "Unix" then
        selectedText = selectedText:gsub("'", "'\\''")
        firstWord = firstWord:gsub("'", "'\\''")
        fzfArgs = config.GetGlobalOption("MicroOmni.GlobalSearchArgs"):gsub("'", "'\\''")
        finalCmd =  "rg --glob=!.git/ "
        
        for _, loc in ipairs(locations) do
            if string.len(loc) ~= 0 then
                if loc:sub(-1, -1) ~= "/" then
                    loc = loc .. "/"
                end
                finalCmd = finalCmd .. "'\\''--glob=" .. loc .. "**'\\'' "
            end
        end
        
        finalCmd =  finalCmd .. " -F -i -uu -n '\\''" .. firstWord .. "'\\'' | " .. 
                    config.GetGlobalOption("MicroOmni.FzfCmd") .. " " .. fzfArgs ..
                    " -q '\\''" .. selectedText .. "'\\''"
    elseif currentOS == "Windows" then
        selectedText = selectedText:gsub("'", '"')
        firstWord = firstWord:gsub("'", '""')
        fzfArgs = config.GetGlobalOption("MicroOmni.GlobalSearchArgs"):gsub("'", '"')
        finalCmd =  "rg --glob=!.git/ -F -i "
        
        for _, loc in ipairs(locations) do
            loc = loc:gsub("\\", "/")
            if string.len(loc) ~= 0 then
                if loc:sub(-1, -1) ~= "/" then
                    loc = loc .. "/"
                end
                finalCmd = finalCmd .. "\"--glob=" .. loc .. "**\" "
            end
        end
        
        finalCmd =  finalCmd .. " -uu -n ^\"" .. firstWord .. "^\" | " .. 
                    config.GetGlobalOption("MicroOmni.FzfCmd").." "..fzfArgs..
                    " -q \""..selectedText.."\""
    end

    if currentOS == "Unix" then
        finalCmd = "sh -c \'"..finalCmd.."\'"
    else
        finalCmd = "cmd /s /v:on /c "..finalCmd..""
    end

    micro.Log("Running search cmd: ", finalCmd)

    local output, err = shell.RunInteractiveShell(finalCmd, false, true)

    if err ~= nil then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local _, outputLinesCount = output:gsub('\n', '\n')
            
        if outputLinesCount > 1 then
            local buf, _ = buffer.NewBuffer(output, "")
            local splitBp = bp:VSplitIndex(buf, true)
            splitBp:SetLocalCmd({"filetype", bp.Buf.Settings["filetype"]})
         elseif output ~= "--" and output ~= "" and outputLinesCount == 1 then
            local path, lineNumber = output:match("^(.-):%s*(%d+):")
            fzfParseOutput(path, bp, lineNumber, true)
        end
    end
end

local function OnFindPromptDone(resp, cancelled)
    if cancelled then return end
    FindContent(resp, OmniContentFindPath)
    return
end

local function OnSearchDirSetDone(resp, cancelled)
    if cancelled then return end

    local bp = micro.CurPane()
    if bp == nil then return end
    
    OmniContentFindPath = resp:gsub("{fileDir}", filepath.Dir(bp.Buf.AbsPath))
    micro.InfoBar():Prompt("Content to find > ", OmniSearchText, "", nil, OnFindPromptDone)
end


function Self.OmniContent(bp)
    OmniSearchText = ""
    if bp.Cursor:HasSelection() then
        OmniSearchText = bp.Cursor:GetSelection()
        OmniSearchText = util.String(OmniSearchText)
    end
    
    micro.InfoBar():Prompt( "Search Directories (use ',' to separate, {fileDir} for current file dir, prefix '!' to exclude) > ", 
                            "", 
                            "", 
                            nil, 
                            OnSearchDirSetDone)
end

-- local function TermTest(outStr, userArgs)
--     userArgs[1]:Quit()
-- end

function Self.OmniLocalSearch(bp, args)
    local localSearchArgs = 
        config.GetGlobalOption("MicroOmni.LocalSearchArgs"):gsub(   "{filePath}", 
                                                                    "\""..bp.buf.AbsPath.."\"")

    if bp.Cursor:HasSelection() then
        localSearchArgs = localSearchArgs.." -q '"..util.String(bp.Cursor:GetSelection()).."'"
    end

    local output, err = 
        shell.RunInteractiveShell(  config.GetGlobalOption("MicroOmni.FzfCmd") .. " " .. 
                                    localSearchArgs, false, true)

    -- -- Test code for running fzf in term pane, but it has no color :/
    -- local buf, bufErr = buffer.NewBuffer("", "")
    -- if bufErr ~= nil then 
    --     micro.InfoBar():Error("Error when creating new buffer: ", err:Error())
    --     return
    -- end
    -- local splitBp = bp:VSplitIndex(buf, true)
    -- shell.RunTermEmulator(splitBp, 
    --                     -- config.GetGlobalOption("MicroOmni.FzfCmd").." "..localSearchArgs, 
    --                     "fzf", false, true,
    --                    TermTest, {splitBp})
    --                    -- callback func(out string, userargs []interface{}),
    --                    -- userargs []interface{}) error

    if err ~= nil or output == "" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local _, outputLinesCount = output:gsub('\n', '\n')
        
        if outputLinesCount > 1 then
            local buf, _ = buffer.NewBuffer(output, "")
            local splitBp = bp:VSplitIndex(buf, true)
            splitBp:SetLocalCmd({"filetype", bp.Buf.Settings["filetype"]})
        elseif outputLinesCount == 1 then
            local lineNumber = output:match("^%s*(.-)%s.*")
            -- micro.InfoBar():Message("Output is ", output, " and extracted lineNumber is ", lineNumber)
            micro.CurPane().Cursor:ResetSelection()
            micro.CurPane():GotoCmd({lineNumber})
            micro.CurPane():Center()
        end
    end
end


function Self.OmniGotoFile(bp)
    local localGotoFileArgs = config.GetGlobalOption("MicroOmni.GotoFileArgs")
    if bp.Cursor:HasSelection() then
        localGotoFileArgs = localGotoFileArgs.." -q '"..util.String(bp.Cursor:GetSelection()).."'"
    end

    local output, err = 
        shell.RunInteractiveShell(  config.GetGlobalOption("MicroOmni.FzfCmd") .. " " .. 
                                    localGotoFileArgs, false, true)


    if err ~= nil or output == "" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local _, outputLinesCount = output:gsub('\n', '\n')
        
        if outputLinesCount > 1 then
            local buf, _ = buffer.NewBuffer(output, "")
            local splitBp = bp:VSplitIndex(buf, true)
            splitBp:SetLocalCmd({"filetype", bp.Buf.Settings["filetype"]})
        elseif outputLinesCount == 1 then
            -- local lineNumber = output:match("^%s*(.-)%s.*")
            -- local path, lineNumber = output:match("^(.-):%s*(%d+):")
            
            -- micro.InfoBar():Message("Output is ", output, " and extracted lineNumber is ", lineNumber)
            fzfParseOutput(output, bp, "1", false)
        end
    end
end

function Self.OmniTabSearch(bp)
    local buffersStr = ""
    for i = 1, #micro.Tabs().List do
        for j = 1, #micro.Tabs().List[i].Panes do
            local currentPane = micro.Tabs().List[i].Panes[j]
            local currentBuf = currentPane.Buf
            
            if currentBuf ~= nil then
                local currentText = ""
                if currentBuf.Path ~= nil and currentBuf.Path ~= "" then
                    currentText = currentBuf.Path
                elseif currentBuf.AbsPath ~= nil and currentBuf.AbsPath ~= "" then
                    currentText = currentBuf.AbsPath
                end
                
                if currentPane.Cursor ~= nil then
                    currentText = currentText..":"..tostring(currentPane.Cursor.Loc.Y + 1)
                end
                
                buffersStr = buffersStr..currentText.."\n"
            end
        end
    end
    local createdPath, success = 
        Common.CreateRuntimeFile("./temp/tabSearch.txt", buffersStr)
    
    if not success then
        micro.InfoBar():Error("Failed to create temporary text for tab search")
        return
    end
    
    local fzfArgs = config.GetGlobalOption("MicroOmni.TabSearchArgs"):gsub("{filePath}", "\""..createdPath.."\"")
    
    local finalCmd =  config.GetGlobalOption("MicroOmni.FzfCmd").." "..fzfArgs
    local output, err = shell.RunInteractiveShell(finalCmd, false, true)
    
    if err ~= nil then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local _, outputLinesCount = output:gsub('\n', '\n')
            
        if outputLinesCount > 1 then
            local buf, _ = buffer.NewBuffer(output, "")
            local splitBp = bp:VSplitIndex(buf, true)
            splitBp:SetLocalCmd({"filetype", bp.Buf.Settings["filetype"]})
         elseif output ~= "--" and output ~= "" and outputLinesCount == 1 then
            local path, lineNumber = output:match("^(.-):%s*(%d+)")
            fzfParseOutput(path, bp, lineNumber, true)
        end
    end
end

return Self
