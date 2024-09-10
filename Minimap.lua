local micro = import("micro")
local config = import("micro/config")
local util = import("micro/util")
local buffer = import("micro/buffer")

local fmt = import('fmt')
package.path = fmt.Sprintf('%s;%s/plug/MicroOmni/?.lua', package.path, config.ConfigDir)
local Common = require("Common")

local Self = {}

local OmniMinimapTargetPanes = {}
local OmniMinimapPanes = {}
local OmniMinimapRecords = {}


local function GetIndentLevel(str, tabSize)
    local indentLevel = 0
    local continuousSpace = 0
    local nonWhiteSpaceChar = nil
    
    for char in str:gmatch"." do
        if char == " " then
            continuousSpace = continuousSpace + 1
            if continuousSpace == tabSize then
                indentLevel = indentLevel + 1
                continuousSpace = 0
            end
        elseif char == "\t" then
            continuousSpace = 0
            indentLevel = indentLevel + 1
        else
            nonWhiteSpaceChar = char
            break
        end
    end
    
    return indentLevel, nonWhiteSpaceChar
end

local function RemoveMinimapIfExist(targetBp)
    for i, val in ipairs(OmniMinimapTargetPanes) do
        if targetBp == val then
            OmniMinimapPanes[i]:Quit()
            table.remove(OmniMinimapTargetPanes, i)
            table.remove(OmniMinimapPanes, i)
            table.remove(OmniMinimapRecords, i)
            return true
        end
    end
    
    for i, val in ipairs(OmniMinimapPanes) do
        if targetBp == val then
            OmniMinimapPanes[i]:Quit()
            table.remove(OmniMinimapTargetPanes, i)
            table.remove(OmniMinimapPanes, i)
            table.remove(OmniMinimapRecords, i)
            return true
        end
    end
    
    return false
end

function Self.OmniMinimap(bp)
    if RemoveMinimapIfExist(bp) then
        return
    end

    -- micro.InfoBar():Message("bp.buf.AbsPath: ", bp.buf.AbsPath)

    local numOfLines = bp.Buf:LinesNum()
    local linesRecords = {}
    local indentCount = {}
    
    -- Settings
    local indentCutoff = Common.OmniMinimapMaxIndent
    local showSubsequentLines = Common.OmniMinimapContextNumLines
    local minDist = Common.OmniMinimapMinDistance
    local minimapShowLength = Common.OmniMinimapMaxColumns
    
    -- States
    local lastIndent = 9999
    local forceOutput = false
    local subsequentLinesShowed = 0
    local lastOutputLine = -99
    
    -- Read the bp buffer
    for i = 0, numOfLines - 1 do
        local currentLineBytes = bp.Buf:LineBytes(i)
        local currentLineStr = util.String(currentLineBytes)
        local currentIndentLevel, firstNonWhiteSpaceChar = 
            GetIndentLevel(currentLineStr, bp.Buf.Settings["tabsize"])
        
        -- Get the indentation level of each line
        linesRecords[i] = {}
        linesRecords[i].indentLevel = currentIndentLevel
        linesRecords[i].isEmpty = (firstNonWhiteSpaceChar == nil and {true} or {false})[1]
        
        -- Simulate if this line will be output or not
        if not linesRecords[i].isEmpty then
            local canOutput = false
            if  linesRecords[i].indentLevel == lastIndent and 
                subsequentLinesShowed < showSubsequentLines then
            
                canOutput = true
                subsequentLinesShowed = subsequentLinesShowed + 1
            else
                subsequentLinesShowed = 0
            end
            
            if  not canOutput and 
                (forceOutput or
                (linesRecords[i].indentLevel ~= lastIndent and 
                i - lastOutputLine > minDist)) then
            
                canOutput = true
                subsequentLinesShowed = 1
            end
            
            -- micro.Log("canOutput for line", i, "is", canOutput)
            
            if canOutput then
                lastOutputLine = i
                lastIndent = linesRecords[i].indentLevel
                -- micro.Log("linesRecords[i].indentLevel", linesRecords[i].indentLevel)
                if indentCount[linesRecords[i].indentLevel] == nil then
                    indentCount[linesRecords[i].indentLevel] = 1
                else
                    indentCount[linesRecords[i].indentLevel] = indentCount[linesRecords[i].indentLevel] + 1
                end
                -- micro.Log("indentCount[linesRecords[i].indentLevel]", indentCount[linesRecords[i].indentLevel])
            end
            
            forceOutput = false
        else
            subsequentLinesShowed = 0
            forceOutput = true
        end
        
        -- micro.Log(  "Line", i, "indent level:", linesRecords[i].indentLevel, 
        --             "isEmpty", linesRecords[i].isEmpty)
    end
    
    -- Allocate number of lines each indent level can output to minimap
    local minimapMaxLines = Common.OmniMinimapTargetNumLines
    local indentBudget = {}
    local firstIndent = -1
    
    for i = 0, indentCutoff do
        if indentCount[i] ~= nil and indentCount[i] ~= 0 then
            if indentCount[i] > minimapMaxLines and firstIndent == -1 then
                indentBudget[i] = indentCount[i]
                break
            else
                if indentCount[i] > minimapMaxLines then
                    indentBudget[i] = minimapMaxLines
                    break
                else
                    indentBudget[i] = indentCount[i]
                    minimapMaxLines = minimapMaxLines - indentCount[i]
                end
            end
            
            if firstIndent == -1 then
                firstIndent = i
            end
        end
    end
    
    for i = 0, indentCutoff do
        micro.Log("i:", i)
        if indentCount[i] ~= nil then
            micro.Log("indentCount[", i, "]:", indentCount[i])
        end
        if indentBudget[i] ~= nil then
            micro.Log("indentBudget[", i, "]:", indentBudget[i])
        end
    end
    
    -- States
    -- This holds line numbers
    local minimapRecords = {}
    
    local outputLines = {}
    lastIndent = 9999
    forceOutput = false
    subsequentLinesShowed = 0
    local lastShowedLine = -99
    
    -- Parse and output lines for minimap
    for i = 0, numOfLines - 1 do
        local curLineNum = i + 1
        local curLineRecord = linesRecords[i]
        
        local skipFarEnough = false
        local showFarEnough = false
        
        if  #minimapRecords == 0 or 
            curLineNum - minimapRecords[#minimapRecords] > minDist then
            
            skipFarEnough = true
        end
        
        if  #minimapRecords == 0 or 
            curLineNum - lastShowedLine > minDist then
            
            showFarEnough = true
        end
        
        local indentChange = false
        if #minimapRecords == 0 or curLineRecord.indentLevel ~= lastIndent then
            indentChange = true
        end
        
        -- micro.Log(  "Line", curLineNum - 1, "farEnough:", farEnough, "indentChange", 
        --             indentChange, "lastIndent", lastIndent, "forceOutput", forceOutput, 
        --             "curLineRecord.indentLevel", curLineRecord.indentLevel,
        --             "curLineRecord.isEmpty", curLineRecord.isEmpty)
        
        -- if indentBudget[curLineRecord.indentLevel] ~= nil then
        --     micro.Log("indentBudget[", curLineRecord.indentLevel, "]:", indentBudget[curLineRecord.indentLevel])
        -- end
        
        local writeLine = false
        local writeSkip = false
        
        -- Write line to minimap
        if  not curLineRecord.isEmpty and
            indentBudget[curLineRecord.indentLevel] ~= nil and 
            indentBudget[curLineRecord.indentLevel] > 0 then
            
            -- If last line has same indent level and within subsequent showable distance, show it
            if  #minimapRecords ~= 0 and
                curLineNum - minimapRecords[#minimapRecords] == 1 and 
                not indentChange and 
                subsequentLinesShowed < showSubsequentLines then
                
                subsequentLinesShowed = subsequentLinesShowed + 1
                writeLine = true
            else
                subsequentLinesShowed = 0
            end
            
            -- If we force output or it is far enough with change in indent, show it
            if not writeLine and (forceOutput or (showFarEnough and indentChange)) then
                writeLine = true
                subsequentLinesShowed = 1
            end
        end
        
        -- Write ... to minimap every certain distance
        if not writeLine and skipFarEnough then
            writeSkip = true
        end
        
        if writeLine then
            lastIndent = curLineRecord.indentLevel
            lastShowedLine = curLineNum
            local currentLineBytes = bp.Buf:LineBytes(curLineNum - 1)
            local currentLineStr = util.String(currentLineBytes)
            -- micro.Log("currentLineStr[", curLineNum, "]:", currentLineStr)
            -- currentLineStr = string.gsub(currentLineStr, "[\n\r]", "")
            if #currentLineStr > minimapShowLength then
                table.insert(   outputLines, 
                                string.format(  "%-5d %s", 
                                                curLineNum, 
                                                currentLineStr:sub(1, minimapShowLength).."..."))
            else
                table.insert(outputLines, string.format("%-5d %s", curLineNum, currentLineStr))
            end
            
            local processedLine, _ = string.gsub(outputLines[#outputLines], "\\\"", "")
            processedLine, _ = string.gsub(processedLine, "\\\'", "")
            
            local _, doubleQuoteCount = string.gsub(processedLine, "\"", "")
            local _, singleQuoteCount = string.gsub(processedLine, "\'", "")
            local _, blockCommentCount = string.gsub(processedLine, "/%*", "")
            
            local appends = ""
            if singleQuoteCount % 2 == 1 then
                appends = appends.."\'"
            end
            if doubleQuoteCount % 2 == 1 then
                appends = appends.."\""
            end
            if blockCommentCount > 0 then
                appends = appends.."*/"
            end
            if #appends ~= 0 then
                outputLines[#outputLines] = outputLines[#outputLines]..appends
            end
            
            indentBudget[curLineRecord.indentLevel] = indentBudget[curLineRecord.indentLevel] - 1
            table.insert(minimapRecords, curLineNum)
        elseif writeSkip then
            table.insert(outputLines, string.format("%-5d %s", curLineNum, "..."))
            table.insert(minimapRecords, curLineNum)
        end
        
        forceOutput = false
        -- If it is an empty line, we force minimap output next time
        if curLineRecord.isEmpty then
            forceOutput = true
        end
    end
    
    -- Output minimap
    local minimapBuf, err = buffer.NewBuffer(table.concat(outputLines, "\n"), "minimap"..#OmniMinimapTargetPanes)
    
    if err ~= nil then 
        micro.InfoBar():Error(err)
        return
    end
    
    minimapBuf.Type.Readonly = true
    minimapBuf:SetOptionNative("ruler", false)
    local minimapPane = micro.CurPane():VSplitIndex(minimapBuf, true)
    
    table.insert(OmniMinimapTargetPanes, bp)
    table.insert(OmniMinimapPanes, minimapPane)
    table.insert(OmniMinimapRecords, minimapRecords)
    
    minimapPane:SetLocalCmd({"filetype", bp.Buf.Settings["filetype"]})
    
    -- Set focus back
    bp:Tab():SetActive(bp:Tab():GetPane(bp:ID()))
    Self.UpdateMinimapView()
end

function Self.CheckAndQuitMinimap(targetBp)
    if targetBp == nil then
        return
    end
    
    -- If one of the target pane is trying to quit, we quit the minimap first. 
    -- Then remove the records
    for i, val in ipairs(OmniMinimapTargetPanes) do
        if targetBp == val then
            OmniMinimapPanes[i]:Quit()
            table.remove(OmniMinimapTargetPanes, i)
            table.remove(OmniMinimapPanes, i)
            table.remove(OmniMinimapRecords, i)
            return
        end
    end
    
    -- If one of the minimap is trying to quit, just remove records
    for i, val in ipairs(OmniMinimapPanes) do
        if targetBp == val then
            table.remove(OmniMinimapTargetPanes, i)
            table.remove(OmniMinimapPanes, i)
            table.remove(OmniMinimapRecords, i)
            return
        end
    end
end

function Self.UpdateMinimapView()
    if micro.CurPane() == nil then
        return
    end
    local cursorLoc = micro.CurPane().Cursor.Loc
    
    for i, val in ipairs(OmniMinimapTargetPanes) do
        if micro.CurPane() == val then
            local targetMinimapLine = 1
            for j = 1, #OmniMinimapRecords[i] do
                if OmniMinimapRecords[i][j] > cursorLoc.Y + 1 then
                    break
                end
                targetMinimapLine = j
            end
            
            OmniMinimapPanes[i].Cursor:ResetSelection()
            OmniMinimapPanes[i].Buf:ClearCursors()
            OmniMinimapPanes[i].Cursor:GotoLoc(Common.LocBoundCheck(OmniMinimapPanes[i].Buf, 
                                                                    buffer.Loc(0, targetMinimapLine - 1)))
            OmniMinimapPanes[i].Cursor:SelectWord()
            local minimapHeight = OmniMinimapPanes[i]:GetView().Height - 2
            OmniMinimapPanes[i]:GetView().StartLine.Line = targetMinimapLine - minimapHeight / 2
            if OmniMinimapPanes[i]:GetView().StartLine.Line < 0 then
                OmniMinimapPanes[i]:GetView().StartLine.Line = 0
            end
            return
        end
    end
    
    if Common.OmniMinimapScrollContent == false then
        return
    end
    
    for i, val in ipairs(OmniMinimapPanes) do
        if micro.CurPane() == val then
            if cursorLoc.Y + 1 > #OmniMinimapRecords[i] then
                return
            end
            OmniMinimapTargetPanes[i].Cursor:GotoLoc(
                Common.LocBoundCheck(   OmniMinimapTargetPanes[i].Buf, 
                                        buffer.Loc(0, OmniMinimapRecords[i][cursorLoc.Y + 1] - 1)))
            
            local viewHeight = OmniMinimapTargetPanes[i]:GetView().Height - 2
            OmniMinimapTargetPanes[i]:GetView().StartLine.Line = 
                OmniMinimapTargetPanes[i].Cursor.Loc.Y - viewHeight / 2
            
            if OmniMinimapTargetPanes[i]:GetView().StartLine.Line < 0 then
                OmniMinimapTargetPanes[i]:GetView().StartLine.Line = 0
            end
            return
        end
    end
end


return Self
