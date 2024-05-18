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
        micro.InfoBar():Error("You must select something first before searching anything")
        return
    end

    setupFzf(bp)
    selectedText = util.String(selectedText)

    if os == "Unix" then
        selectedText:gsub("'", "'\\''")
    else
        selectedText:gsub('["%%]', '^%1')
    end

    local grepCmd = "grep -T -I -i -r -n -o -E \".{0,50}"..selectedText..".{0,50}\" | "
    local finalCmd = grepCmd..fzfCmd.." "..OmniContentArgs.." -q \""..selectedText.."\""

    local os = getOS()
    if os == "Unix" then
        finalCmd = "sh -c \'"..finalCmd.."\'"
    else
        finalCmd = "cmd /s /v /c \""..finalCmd.."\""
    end

    local output, err = shell.RunInteractiveShell(finalCmd, false, true)

    if err ~= nil then
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

    micro.InfoBar():Message("file is ", file)

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
    -- local buf = bp.buf
    -- micro.Log("Hello")
    -- local cur = buf.Cursor
    -- bp.buf.Cursor:Deselect(false)
    -- cur:ResetSelection()
    -- buf:MergeCursors()
    -- bp.Cursor.X = 0
    -- bp.Cursor.Y = bp:BufView().y + bp:BufView().Height / 2
    local view = bp:GetView()
    -- bp:Relocate()
    bp.Cursor:ResetSelection()
    bp.Cursor:GotoLoc(buffer.Loc(view.StartCol, view.StartLine.Line + view.Height / 2))
    -- bp:Relocate()
end

function init()
  -- config.MakeCommand("fzfinder", fzfinder, config.NoComplete)
  config.MakeCommand("OmniContent", OmniContent, config.NoComplete)
  config.MakeCommand("OmniCenter", OmniCenter, config.NoComplete)
end
