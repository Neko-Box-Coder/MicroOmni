VERSION = "0.1.0"

local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local shell = import("micro/shell")
local filepath = import("path/filepath")
local action = import("micro/action")
local util = import("micro/util")
local screen = import("micro/screen")

local OmniContentArgs =  config.GetGlobalOption("OmniContentArgs")
local OmniSelectType = config.GetGlobalOption("OmniSelectType")

local fzfCmd =  config.GetGlobalOption("fzfcmd")
local fzfOpen = config.GetGlobalOption("fzfopen")
local fzfPath = config.GetGlobalOption("fzfpath")



function getOS()
    -- ask LuaJIT first
    -- if jit then
    --   return jit.os
    -- end

    -- Unix, Linux variants
    local fh, err = assert(io.popen("uname -o 2>/dev/null","r"))

    if fh then
        return "Unix"
        -- osname = fh:read()
    end

    -- return osname or "Windows"
    return "Windows"
end

function setupFzf(bp)

    if fzfCmd == nil then
        fzfCmd = "fzf"
    end

    if fzfPath == "relative" then
        currentdir = filepath.Dir(bp.buf.Path)
        bp:CdCmd({currentdir})
    elseif fzfPath ~= nil and fzfPath ~= "" then
        bp:CdCmd(filepath(fzfPath))
    end

    if fzfOpen == nil then
        fzfOpen = "thispane"
    end
end

function OmniContent(bp)
    if OmniContentArgs == nil then
        OmniContentArgs = ""
    end

    local selectedText = ""
    if bp.Cursor:HasSelection() then
        selectedText = bp.Cursor:GetSelection()
    else
        -- micro.InfoBar():Error("You must select something first before searching anything")
        micro.InfoBar():Prompt("Content to find > ", "", "", nil, OnFindPromptDone)
        return
    end

    FindContent(selectedText)
end

function OnFindPromptDone(content, cancelled)
    if cancelled then return end
    FindContent(content)
end

function FindContent(str)

    local bp = micro.CurPane()

    setupFzf(bp)
    local selectedText = util.String(str)
    local fzfArgs = ""

    -- micro.Log("selectedText before: ", selectedText)
    -- micro.Log("OmniContentArgs before: ", OmniContentArgs)
    
    local os = getOS()
    if os == "Unix" then
        selectedText = selectedText:gsub("'", "'\\''")
        fzfArgs = OmniContentArgs:gsub("'", "'\\''")
    else
        selectedText = selectedText:gsub('["%%]', '^%1')
        fzfArgs = OmniContentArgs:gsub('["%%]', '^%1')
    end

    -- micro.Log("selectedText after: ", selectedText)
    -- micro.Log("OmniContentArgs after: ", fzfArgs)

    local grepCmd = "grep -I -i -r -n \""..selectedText.."\" | "
    local finalCmd = grepCmd..fzfCmd.." "..fzfArgs.." -q \""..selectedText.."\""

    if os == "Unix" then
        finalCmd = "sh -c \'"..finalCmd.."\'"
    else
        finalCmd = "cmd /s /v /c \""..finalCmd.."\""
    end

    -- micro.Log("Running search cmd: ", finalCmd)

    local output, err = shell.RunInteractiveShell(finalCmd, false, true)

    if err ~= nil or output == "--" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local filePath, lineNumber = output:match("^(.-):%s*(%d+):")
        -- lineNumber = tonumber(lineNumber)
        fzfParseOutput(filePath, bp, lineNumber)
    end

end


function fzfParseOutput(output, bp, lineNum)
  if output ~= "" then
    local file = string.gsub(output, "[\n\r]", "")
    
    if file == nil then
        return
    end

    -- micro.InfoBar():Message("file is ", file)

    if fzfOpen == "newtab" then
       bp:NewTabCmd({file})
    else
        local buf, err = buffer.NewBufferFromFile(file)
        if fzfOpen == "vsplit" then
            bp:VSplitIndex(buf, true)
        elseif fzfOpen == "hsplit" then
            bp:HSplitIndex(buf, true)
        else
            bp:OpenBuffer(buf)
        end
    end

    micro.CurPane():GotoCmd({lineNum})
  end
end

function OmniCenter(bp)
    local view = bp:GetView()
    bp.Cursor:ResetSelection()
    bp.Cursor:GotoLoc(buffer.Loc(view.StartCol, view.StartLine.Line + view.Height / 2))
end

function OmniSelect(bp, args)
    if #args < 1 then return end

    local buf = bp.Buf
    -- local bufLineNum = buf:LinesNum()
    local cursor = buf:GetActiveCursor()
    local currentLoc = cursor.Loc
    -- local currentLine = cursor.Loc.Y
    local targetLine = cursor.Loc.Y

    cursor.OrigSelection[1] = buffer.Loc(cursor.Loc.X, cursor.Loc.Y)

    if OmniSelectType == nil or OmniSelectType == "" then
        OmniSelectType = "relative"
    end

    if OmniSelectType == "relative" then
        targetLine = targetLine + tonumber(args[1])
     else
        targetLine = tonumber(args[1]) - 1
    end

    -- micro.InfoBar():Message("targetLine: ", targetLine)
    -- micro.Log("targetLine: ", targetLine)

    -- cursor:SetSelectionStart(currentLoc)
    cursor:SelectTo(buffer.Loc(currentLoc.X, targetLine))
    bp:Relocate()
end




function TestECB(msg)
    micro.Log("TestECV called with message: ", msg)
end

function TestDoneCB(msg, cancelled)
    micro.Log("TestDoneCB called with message ", msg, " and cancelled ", cancelled)
end

function OmniTest(bp)
    micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)


end


function init()
    -- config.MakeCommand("fzfinder", fzfinder, config.NoComplete)
    config.MakeCommand("OmniContent", OmniContent, config.NoComplete)
    config.MakeCommand("OmniCenter", OmniCenter, config.NoComplete)
    config.MakeCommand("OmniSelect", OmniSelect, config.NoComplete)

    config.MakeCommand("OmniTest", OmniTest, config.NoComplete)

  
end
