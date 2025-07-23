local micro = import("micro")

local shell = import("micro/shell")
local buffer = import("micro/buffer")
local config = import("micro/config")
local fmt = import('fmt')
package.path = fmt.Sprintf('%s;%s/plug/MicroOmni/?.lua', package.path, config.ConfigDir)

local Common = require("Common")

local Self = {}

local OmniDiffPlusFile = true
local OmniDiffTargetPanes = {}
local OmniDiffDiffPanes = {}

local function processDiffOutput(output)
    local outputLines = {}
    local currentLineIndex = 1
    
    -- Split the output string by newline
    for i = 1, #output do
        local c = output:sub(i, i)
        if c == "\r" then
            if outputLines[currentLineIndex] ~= nil then
                outputLines[currentLineIndex] = table.concat(outputLines[currentLineIndex])
            end
            currentLineIndex = currentLineIndex + 1
        elseif c == "\n" then
            if i > 1 and output:sub(i - 1, i - 1) ~= "\r" then
                if outputLines[currentLineIndex] ~= nil then
                    outputLines[currentLineIndex] = table.concat(outputLines[currentLineIndex])
                end
                currentLineIndex = currentLineIndex + 1
            end
        else
            if outputLines[currentLineIndex] == nil then
                outputLines[currentLineIndex] = {}
            end
            
            table.insert(outputLines[currentLineIndex], c)
        end
    end
    
    -- micro.Log("outputLines: ", outputLines)
    
    -- Get the index of the first diff
    local outputLinesCount = currentLineIndex
    local firstDiffIndex = -1
    for i = 1, outputLinesCount do
        local curLine
        if outputLines[i] ~= nil then
            curLine = outputLines[i]
            micro.Log("Trying to find first diff: ", curLine)
            if #curLine > 2 then
                micro.Log("Checking[1]: ", curLine:sub(1, 1):byte())
                micro.Log("Checking[2]: ", curLine:sub(2, 2):byte())
            end
            
            if #curLine > 2 and curLine:sub(1, 2) == "@@" then
                firstDiffIndex = i
                break
            end
        end
    end

    micro.Log("firstDiffIndex: ", firstDiffIndex)
    
    -- Return empty string if no diff
    if firstDiffIndex <= 0 then
        micro.Log("No diff found")
        return ""
    end
    
    -- Populate the return lines
    local returnLines = {}
    for i = firstDiffIndex, outputLinesCount do
        local curLine
        if outputLines[i] ~= nil then
            curLine = outputLines[i]
            -- micro.Log("Processing: ", curLine)
            
            local targetLineIndex = nil
            if #curLine > 2 and curLine:sub(1, 2) == "@@" then
                if OmniDiffPlusFile then
                    targetLineIndex = curLine:match("%+%d+")
                else
                    targetLineIndex = curLine:match("%-%d+")
                end
                targetLineIndex = tonumber(targetLineIndex:sub(2, #targetLineIndex))
            end
        
            -- micro.Log("targetLineIndex: ", targetLineIndex)

            -- If we are at new diff
            if targetLineIndex ~= nil then
                -- Add empty lines until we reach the hunk
                while #returnLines < targetLineIndex - 2 do
                    table.insert(returnLines, "")
                end
                
                -- Add diff header
                if #returnLines == targetLineIndex - 1 then
                    returnLines[#returnLines] = curLine
                elseif #returnLines == targetLineIndex - 2 then
                    table.insert(returnLines, curLine)
                    -- micro.Log("Appending diff header")
                end
            else
                -- Otherwise just append the diffs
                table.insert(returnLines, curLine)
                -- micro.Log("Appending diff content")
            end
        end
    end
    
    return returnLines
end

local function OnDiffFinishCallback(resp, cancelled)
    if cancelled then
        return
    end

    local tabSpecified = false
    local tabIndex = -1
    local splitIndex = 1
    
    if #resp >= 4 and resp:sub(1, 4) == "tab:" then
        tabSpecified = true
        
        local respTokens = {}
        for s in string.gmatch(resp, "[^:]+") do
            table.insert(respTokens, s)
        end
        
        if #respTokens == 1 then
            micro.InfoBar():Error("tab expecting index, like tab:<tab index>")
            return
        elseif #respTokens == 2 then
            tabIndex = tonumber(respTokens[2])
        elseif #respTokens == 3 then
            tabIndex = tonumber(respTokens[2])
            splitIndex = tonumber(respTokens[3])
        end
        
        if tabIndex == nil or splitIndex == nil then
            micro.InfoBar():Error("Failed to parse tab index")
            return
        end
        
        if respTokens[2]:sub(1, 1) == "-" or respTokens[2]:sub(1, 1) == "+" then
            -- NOTE: micro.Tabs():Active() starts counting at 1
            tabIndex = micro.Tabs():Active() + 1 + tabIndex
        end
    end

    local respPath = resp
    
    if tabSpecified then
        if tabIndex <= 0 or tabIndex > #micro.Tabs().List then
            micro.InfoBar():Error("tabIndex ", tabIndex, " out of bound for ", #micro.Tabs().List)
            return
        end
        
        if splitIndex <= 0 or splitIndex > #micro.Tabs().List[tabIndex].Panes then
            micro.InfoBar():Error("splitIndex ", splitIndex, " out of bound for ", #micro.Tabs().List[tabIndex].Panes)
            return
        end
        
        if micro.Tabs().List[tabIndex].Panes[splitIndex] == nil then
            micro.InfoBar():Error("micro.Tabs().List[", tabIndex, "].Panes[", splitIndex, "] is nil")
            return
        end
        
        respPath = micro.Tabs().List[tabIndex].Panes[splitIndex].Buf.AbsPath
    end
    
    local minusFile
    local plusFile

    if OmniDiffPlusFile then
        minusFile = respPath
        plusFile = micro.CurPane().Buf.AbsPath
        
        -- Create temp files if needed
        if tabSpecified and micro.Tabs().List[tabIndex].Panes[splitIndex].Buf:Modified() then
            local createdPath, success = 
                Common.CreateRuntimeFile(   "./temp/minus.temp",
                                            micro.Tabs().List[tabIndex].Panes[splitIndex].Buf:Bytes())
            if not success then
                return
            end
            minusFile = createdPath
        end
        
        if micro.CurPane().Buf:Modified() then
            local createdPath, success = 
                Common.CreateRuntimeFile("./temp/plus.temp", micro.CurPane().Buf:Bytes())
            if not success then
                return
            end
            plusFile = createdPath
        end
    else
        minusFile = micro.CurPane().Buf.AbsPath
        plusFile = respPath
        
        -- Create temp files if needed
        if micro.CurPane().Buf:Modified() then
            micro.Log("A")
            local createdPath, success = 
                Common.CreateRuntimeFile("./temp/minus.temp", micro.CurPane().Buf:Bytes())
            if not success then
                return
            end
            minusFile = createdPath
        end
    
        if tabSpecified and micro.Tabs().List[tabIndex].Panes[splitIndex].Buf:Modified() then
            local createdPath, success = 
                Common.CreateRuntimeFile(   "./temp/plus.temp",
                                            micro.Tabs().List[tabIndex].Panes[splitIndex].Buf:Bytes())
            if not success then
                return
            end
            micro.Log("Minus plus file success: ", createdPath)
            plusFile = createdPath
        end
    end
    
    if not Common.path_exists(plusFile) then
        micro.InfoBar():Error("plusFile: ", minusFile, " does not exist")
        return
    end
    if not Common.path_exists(minusFile) then
        micro.InfoBar():Error("minusFile: ", minusFile, " does not exist")
        return
    end

    micro.Log("Running: ", "diff -U 5 \""..minusFile.."\" \""..plusFile.."\"")
    local output, err = shell.RunCommand("diff -U 5 \""..minusFile.."\" \""..plusFile.."\"")
    
    micro.Log("output: ", output)
    micro.Log("err: ", err)
    local processedDiffLines = processDiffOutput(output)
    
    if err == nil or err:Error() == "exit status 1" or err:Error() == "exit status 2" then
        local curPane = micro.CurPane()
        
        local buf, bufErr = buffer.NewBuffer("", "diff"..#OmniDiffTargetPanes)
        for i = 1, #processedDiffLines do
            buf:Insert(buffer.Loc(0, i - 1), processedDiffLines[i] .. "\n")
        end
        
        if bufErr ~= nil then 
            micro.InfoBar():Error(bufErr)
            return
        end
        
        local bp = micro.CurPane()
        
        local diffPane = micro.CurPane():VSplitIndex(buf, not OmniDiffPlusFile)
        table.insert(OmniDiffTargetPanes, curPane)
        table.insert(OmniDiffDiffPanes, diffPane)
        micro.CurPane():SetLocalCmd({"filetype", "patch"})
        
        -- Set focus back so that it is not scroll to top
        bp:Tab():SetActive(bp:Tab():GetPane(bp:ID()))
    else
        micro.InfoBar():Error(err)
    end
end

function Self.CheckAndQuitDiffView(targetBp)
    if  targetBp == nil then
        return
    end
    
    -- If one of the target pane is trying to quit, we quit the diff view first. 
    -- Then remove the records
    for i, val in ipairs(OmniDiffTargetPanes) do
        if targetBp == val then
            OmniDiffDiffPanes[i]:Quit()
            table.remove(OmniDiffTargetPanes, i)
            table.remove(OmniDiffDiffPanes, i)
            return
        end
    end
    
    -- If one of the diff pane is trying to quit, just remove records
    for i, val in ipairs(OmniDiffDiffPanes) do
        if targetBp == val then
            table.remove(OmniDiffTargetPanes, i)
            table.remove(OmniDiffDiffPanes, i)
            return
        end
    end
end

function Self.UpdateDiffView()
    -- micro.InfoBar():Message("UpdateDiffCalled")
    if  micro.CurPane() == nil then
        return nil
    end
    
    for i, val in ipairs(OmniDiffTargetPanes) do
        if micro.CurPane() == val then
            OmniDiffDiffPanes[i]:GetView().StartLine.Line = micro.CurPane():GetView().StartLine.Line
            -- OmniCenter(OmniDiffDiffPanes[i])
            return OmniDiffDiffPanes[i]
        end
    end
    
    for i, val in ipairs(OmniDiffDiffPanes) do
        if micro.CurPane() == val then
            OmniDiffTargetPanes[i]:GetView().StartLine.Line = micro.CurPane():GetView().StartLine.Line
            -- OmniCenter(OmniDiffTargetPanes[i])
            return OmniDiffTargetPanes[i]
        end
    end
end


local function OnDiffPlusCallback(yes, cancelled)
    if cancelled then
        return
    end
    
    OmniDiffPlusFile = yes
    micro.InfoBar():Prompt( "File to diff against (Use tab:[+/-]<tab index>[:<split index>] to diff other buffers) > ", 
                            "",
                            "",
                            nil,
                            OnDiffFinishCallback)
end

function Self.OmniDiff(bp)
    micro.InfoBar():YNPrompt("Is this plus file? (y/n/esc) > ", OnDiffPlusCallback)
end

return Self
