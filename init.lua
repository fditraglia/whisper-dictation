-- whisper-dictation: local speech-to-text via whisper.cpp
-- Press Ctrl+D to toggle dictation on/off

local STREAM_BIN = os.getenv("HOME") .. "/whisper.cpp/build/bin/whisper-stream"
local MODEL_PATH = os.getenv("HOME") .. "/whisper.cpp/models/ggml-large-v3.bin"

local streamTask = nil
local menubar = nil
local isListening = false

-- Menubar setup
local function initMenubar()
    menubar = hs.menubar.new()
    menubar:setTitle("🎤✕")
    menubar:setMenu(function()
        local items = {}
        if streamTask then
            table.insert(items, {
                title = isListening and "Listening..." or "Paused",
                disabled = true,
            })
            table.insert(items, { title = "-" })
            table.insert(items, {
                title = "Quit Whisper",
                fn = function() stopStream(true) end,
            })
        else
            table.insert(items, {
                title = "Idle (press Ctrl+D)",
                disabled = true,
            })
        end
        return items
    end)
end

-- Buffer for accumulating stdout between newlines.
-- whisper-stream overwrites the same line with partial transcriptions (via
-- ANSI \33[2K\r). Only the last version before a newline is the finalized
-- text. We accumulate into outputBuffer and only type when we see \n.
local outputBuffer = ""
local needsSpace = false
local lastChunkWords = {} -- last few words of previous chunk, for dedup

-- Split a string into words
local function splitWords(s)
    local words = {}
    for w in s:gmatch("%S+") do
        table.insert(words, w)
    end
    return words
end

-- Remove overlapping words at the start of newText that match the end of the
-- previous chunk. whisper-stream's --keep overlap causes the model to sometimes
-- re-transcribe the last 1-3 words.
local function dedup(text)
    if #lastChunkWords == 0 then return text end

    local words = splitWords(text)
    if #words == 0 then return text end

    -- Check for overlap of 1-3 words
    local maxOverlap = math.min(3, #lastChunkWords, #words)
    local bestOverlap = 0

    for overlap = 1, maxOverlap do
        local match = true
        for i = 1, overlap do
            local prev = lastChunkWords[#lastChunkWords - overlap + i]
            local curr = words[i]
            if prev:lower() ~= curr:lower() then
                match = false
                break
            end
        end
        if match then
            bestOverlap = overlap
        end
    end

    if bestOverlap > 0 then
        -- Remove the overlapping words from the start
        local stripped = {}
        for i = bestOverlap + 1, #words do
            table.insert(stripped, words[i])
        end
        return table.concat(stripped, " ")
    end

    return text
end

local function processOutput(_, stdout)
    if not stdout then return end
    outputBuffer = outputBuffer .. stdout

    -- Only process complete lines (text ending with \n)
    while outputBuffer:find("\n") do
        local line, rest = outputBuffer:match("^(.-)\n(.*)$")
        outputBuffer = rest

        -- The line contains multiple \r-separated overwrites; take the last one
        local final = line
        for segment in line:gmatch("[^\r]+") do
            final = segment
        end

        -- Strip ANSI escape codes and trim
        final = final:gsub("\27%[[%d;]*[A-Za-z]", "")
        final = final:match("^%s*(.-)%s*$")

        if #final > 0 then
            -- Remove words duplicated from the previous chunk's overlap
            final = dedup(final)

            if #final > 0 then
                -- Add a leading space to separate from the previous chunk
                if needsSpace and not final:match("^[%s%p]") then
                    hs.eventtap.keyStrokes(" " .. final)
                else
                    hs.eventtap.keyStrokes(final)
                end
                needsSpace = true
            end

            -- Remember the last few words for next dedup
            local words = splitWords(final)
            lastChunkWords = words
        end
    end
end

-- Start the whisper-stream process
local function startStream()
    if streamTask then return end

    menubar:setTitle("🎤⏳")
    outputBuffer = ""
    needsSpace = false
    lastChunkWords = {}

    local args = {
        "-m", MODEL_PATH,
        "--step", "3000",
        "--length", "10000",
        "--keep", "200",
        "-l", "en",
    }

    streamTask = hs.task.new(STREAM_BIN, function(exitCode, _, _)
        -- Callback when process exits
        streamTask = nil
        isListening = false
        menubar:setTitle("🎤✕")
    end, function(task, stdout, stderr)
        -- Streaming callback for stdout/stderr
        if stdout and #stdout > 0 then
            -- Detect when model is loaded and streaming starts
            if not isListening and stdout:find("%[Start speaking%]") then
                isListening = true
                menubar:setTitle("🎤🔴")
                hs.alert.show("Dictation ON", 1)
            end
            if isListening then
                processOutput(task, stdout)
            end
        end
        return true -- keep streaming
    end, args)

    streamTask:start()
end

-- Stop the whisper-stream process
function stopStream(full)
    if streamTask then
        streamTask:terminate()
        streamTask = nil
    end
    isListening = false
    menubar:setTitle("🎤✕")
    if full then
        hs.alert.show("Whisper quit", 1)
    else
        hs.alert.show("Dictation OFF", 1)
    end
end

-- Toggle dictation
local function toggleDictation()
    if isListening then
        stopStream(false)
    else
        startStream()
    end
end

-- Initialize
initMenubar()
hs.hotkey.bind({"ctrl"}, "D", toggleDictation)
hs.alert.show("Whisper dictation loaded", 2)
