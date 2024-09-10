
local micro = import("micro")
local config = import("micro/config")
local util = import("micro/util")
local buffer = import("micro/buffer")

local utf8 = import("utf8")
local fmt = import('fmt')


package.path = fmt.Sprintf('%s;%s/plug/MicroOmni/?.lua', package.path, config.ConfigDir)
local Common = require("Common")

local Self = {}

local OmniOriginalSearchIgnoreCase = false
local OmniOriginalLastSearch = ""
local OmniOriginalLastSearchRegex = true
local OmniOriginalHighlightSearch = true

local OmniJumpWordsRecords = {}
local OmniOriginalWordsRecords = {}

local function AssignJumpWords(majorChars, minorChars, rowIndexStart, rowIndexEnd, currentJumpChar)
    micro.Log("rowIndexStart:", rowIndexStart)
    micro.Log("rowIndexEnd:", rowIndexEnd)
    micro.Log("string.len(majorChars):", string.len(majorChars))
    micro.Log("string.len(minorChars):", string.len(minorChars))
    local bp = micro.CurPane()
    local majorCharIndex = 1
    local minorCharIndex = 1
    
    local jumpWordToRc = {}
    local rcToOriWord = {}
    local jumpWordsSeparators = " \t¬~_++<>:{}|&*($%^!\"£)#-=,.;[]'\\/"

    for i = rowIndexStart, rowIndexEnd do
        rcToOriWord[i] = {}
        
        local currentLineBytes = bp.Buf:LineBytes(i)
        local j = 1
        local wordCharCounter = 0
        local usedAllChars = false
        local charIndex = 0
        
        while j <= #currentLineBytes do
            local endRuneCaptureIndex
            if j + 4 > #currentLineBytes then
                endRuneCaptureIndex = #currentLineBytes
            else
                endRuneCaptureIndex = j + 4
            end
            
            local runeBuffer = {}
            for k = j, endRuneCaptureIndex do
                table.insert(runeBuffer, currentLineBytes[k])
            end
            
            local _, size = utf8.DecodeRune(runeBuffer)
            runeBuffer = {}
            for k = j, j + size - 1 do
                table.insert(runeBuffer, currentLineBytes[k])
            end
            
            local runeStr = util.String(runeBuffer)
            if jumpWordsSeparators:find(runeStr, 1, true) == nil then
                wordCharCounter = wordCharCounter + 1
                
                if wordCharCounter <= 2 and size == 1 then
                    if wordCharCounter == 2 then
                        local currentMajorChar = majorChars:sub(majorCharIndex, majorCharIndex)
                        local currentMinorChar = minorChars:sub(minorCharIndex, minorCharIndex)
                    
                        rcToOriWord[i][j - 1] = {currentLineBytes[j - 1], currentLineBytes[j]}
                        -- jumpWordToRc[currentMajorChar..currentMinorChar] = {i, j - 1}
                        jumpWordToRc[currentMajorChar..currentMinorChar] = {i, charIndex - 1}

                        if currentJumpChar ~= nil and currentJumpChar ~= "" then
                            if currentJumpChar == currentMajorChar then
                                currentLineBytes[j - 1] = string.byte(string.lower(currentMajorChar))
                                currentLineBytes[j] = string.byte(currentMinorChar)
                            end
                        else
                            currentLineBytes[j - 1] = string.byte(currentMajorChar)
                            currentLineBytes[j] = string.byte(currentMinorChar)
                        end
                        
                        if minorCharIndex >= string.len(minorChars) then
                            if majorCharIndex >= string.len(majorChars) then
                                usedAllChars = true
                                break
                            else
                                majorCharIndex = majorCharIndex + 1
                                minorCharIndex = 1
                            end
                        else
                            minorCharIndex = minorCharIndex + 1
                        end
                    end
                end
            else
                wordCharCounter = 0
            end
            
            if size <= 0 then
                break
            end
            
            j = j + size
            charIndex = charIndex + 1
        end
        
        if usedAllChars then
            break
        end
    end
    
    return rcToOriWord, jumpWordToRc
end

local function AssignJumpWordsToView(msg)
    local bp = micro.CurPane()
    local view = bp:GetView()
    local numberOfLines = bp.Buf:LinesNum()
    local viewStart = (view.StartLine.Line < 0 and {0} or {view.StartLine.Line})[1]
    local viewEnd = viewStart + view.Height - 2
    viewEnd = (viewEnd >= numberOfLines and {numberOfLines - 1} or {viewEnd})[1]
    local viewMid = (viewEnd + viewStart) / 2

    local leftMajorChars = "ASDF"
    local leftMinorChars = "GQWERTZXCVB"
    
    local rightMajorChars = "JKL"
    local rightMinorChars = "HYUIOPNM"

    local rightOriginalWords, rightJumpWords = AssignJumpWords( rightMajorChars..rightMinorChars, 
                                                                rightMajorChars..rightMinorChars, 
                                                                viewMid, 
                                                                viewEnd,
                                                                msg)
    
    local leftOriginalWords = {}
    local leftJumpWords = {}
    
    if viewMid ~= 0 then
        leftOriginalWords, leftJumpWords = AssignJumpWords( leftMajorChars..leftMinorChars, 
                                                            leftMajorChars..leftMinorChars, 
                                                            viewStart, 
                                                            viewMid - 1,
                                                            msg)
    end
    
    OmniOriginalWordsRecords = {}
    OmniJumpWordsRecords = {}
    
    for k, v in pairs(leftOriginalWords) do
        OmniOriginalWordsRecords[k] = v
    end
    
    for k, v in pairs(rightOriginalWords) do
        OmniOriginalWordsRecords[k] = v
    end
    
    if viewMid ~= 0 then
        for k, v in pairs(leftJumpWords) do
            OmniJumpWordsRecords[k] = v
        end
        
        for k, v in pairs(rightJumpWords) do
            OmniJumpWordsRecords[k] = v
        end
    end

    -- if numberOfLines >= 1 then
    --     bp.Buf:Insert(buffer.Loc(0, 0), "A")
    --     bp.Buf:Remove(buffer.Loc(0, 0), buffer.Loc(1, 0))
    -- end
    -- bp.Buf:UpdateRules()
end

local function RestoreOriginalWords(rcToOriWord, exclusionRow)
    local bp = micro.CurPane()
    for row, rowValues in pairs(rcToOriWord) do
        if exclusionRow == nil or row ~= exclusionRow then
            local currentLineBytes = bp.Buf:LineBytes(row)
            for column, words in pairs(rowValues) do
                currentLineBytes[column] = words[1]
                currentLineBytes[column + 1] = words[2]
            end
        end
    end
end

local function OnTypingJump(msg)
    local bp = micro.CurPane()

    if string.len(msg) > 2 then
        bp.Buf.HighlightSearch = false
        return
    end
    
    if string.len(msg) == 2 then
        micro.InfoBar():DonePrompt(false)
        return
    end
    
    msg = string.upper(msg)
    RestoreOriginalWords(OmniOriginalWordsRecords, nil)
    AssignJumpWordsToView(msg)
    
    if string.len(msg) == 1 then
        bp.Buf.LastSearch = "\\b[a-z][A-Z]"
    else
        bp.Buf.LastSearch = "\\b[A-Z]{2}"
    end
    
    bp.Buf.HighlightSearch = true
    bp.Buf.LastSearchRegex = true

end

local function OnWordJump(msg, cancelled)
    RestoreOriginalWords(OmniOriginalWordsRecords, nil)
    local bp = micro.CurPane()
    
    -- Restore the original search settings
    bp.Buf.Settings["ignorecase"] = OmniOriginalSearchIgnoreCase
    bp.Buf.LastSearch = OmniOriginalLastSearch
    bp.Buf.LastSearchRegex = OmniOriginalLastSearchRegex
    bp.Buf.HighlightSearch = OmniOriginalHighlightSearch
    
    if string.len(msg) ~= 2 or cancelled then
        return
    end
    
    msg = string.upper(msg)
    if OmniJumpWordsRecords[msg] == nil then
        return
    end
    
    local jumpRowColumn = OmniJumpWordsRecords[msg]
    bp.Cursor:GotoLoc(Common.LocBoundCheck(bp.Buf, buffer.Loc(jumpRowColumn[2], jumpRowColumn[1])))
end

function Self.OmniJump(bp)
    bp.Cursor:ResetSelection()
    bp.Buf:ClearCursors()
    
    AssignJumpWordsToView("")
    
    -- Store the original search related settings
    OmniOriginalSearchIgnoreCase = bp.Buf.Settings["ignorecase"]
    OmniOriginalLastSearch = bp.Buf.LastSearch
    OmniOriginalLastSearchRegex = bp.Buf.LastSearchRegex
    OmniOriginalHighlightSearch = bp.Buf.HighlightSearch
    
    -- NOTE:    Syntax highlighting could be used instead of search highlight using UpdateRules.
    --          But would require me to use cursor to modify the buffer instead of modifying bytes.
    --          Which will be a lot of work (and complications!!) plus polluting the history as well.
    bp.Buf.Settings["ignorecase"] = false
    bp.Buf.LastSearch = "\\b[A-Z]{2}"
    bp.Buf.LastSearchRegex = true
    bp.Buf.HighlightSearch = true
    
    micro.InfoBar():Prompt( "Select Word To Jump To > ", "", "Command", OnTypingJump, OnWordJump)
end

return Self

