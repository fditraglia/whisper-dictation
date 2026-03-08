-- whisper-dictation: local speech-to-text via whisper.cpp
--
-- Two modes:
--   Ctrl+D       — streaming mode: text appears in chunks as you speak
--   Ctrl+Shift+D — batch mode: records audio, transcribes when you stop (higher quality)

local STREAM_BIN  = os.getenv("HOME") .. "/whisper.cpp/build/bin/whisper-stream"
local WHISPER_CLI = os.getenv("HOME") .. "/whisper.cpp/build/bin/whisper-cli"
local MODEL_PATH  = os.getenv("HOME") .. "/whisper.cpp/models/ggml-large-v3.bin"
local AUDIO_FILE  = "/tmp/whisper-dictation-batch.wav"

local streamTask = nil
local batchRecordTask = nil
local menubar = nil
local isListening = false
local currentMode = nil -- "stream" or "batch"

--------------------------------------------------------------------------------
-- Menubar
--------------------------------------------------------------------------------

local function initMenubar()
    menubar = hs.menubar.new()
    menubar:setTitle("🎤✕")
    menubar:setMenu(function()
        local items = {}
        if streamTask or batchRecordTask then
            local status = "Listening"
            if currentMode == "stream" then
                status = "Streaming..."
            elseif currentMode == "batch" then
                status = "Recording..."
            end
            table.insert(items, { title = status, disabled = true })
            table.insert(items, { title = "-" })
            table.insert(items, {
                title = "Stop",
                fn = function()
                    if currentMode == "stream" then
                        stopStream(false)
                    elseif currentMode == "batch" then
                        stopBatch()
                    end
                end,
            })
        else
            table.insert(items, {
                title = "Idle",
                disabled = true,
            })
            table.insert(items, { title = "-" })
            table.insert(items, {
                title = "Ctrl+D — stream mode",
                disabled = true,
            })
            table.insert(items, {
                title = "Ctrl+Shift+D — batch mode",
                disabled = true,
            })
        end
        return items
    end)
end

--------------------------------------------------------------------------------
-- Streaming mode (Ctrl+D)
-- Text appears in ~6-second chunks as you speak. Lower quality due to limited
-- context per chunk, but provides immediate feedback.
--------------------------------------------------------------------------------

local outputBuffer = ""
local needsSpace = false
local lastChunkWords = {} -- last few words of previous chunk, for dedup

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
        local stripped = {}
        for i = bestOverlap + 1, #words do
            table.insert(stripped, words[i])
        end
        return table.concat(stripped, " ")
    end

    return text
end

local function processStreamOutput(_, stdout)
    if not stdout then return end
    outputBuffer = outputBuffer .. stdout

    while outputBuffer:find("\n") do
        local line, rest = outputBuffer:match("^(.-)\n(.*)$")
        outputBuffer = rest

        -- Take the last \r-separated segment (final version of overwritten line)
        local final = line
        for segment in line:gmatch("[^\r]+") do
            final = segment
        end

        -- Strip ANSI escape codes and trim
        final = final:gsub("\27%[[%d;]*[A-Za-z]", "")
        final = final:match("^%s*(.-)%s*$")

        if #final > 0 then
            final = dedup(final)

            if #final > 0 then
                if needsSpace and not final:match("^[%s%p]") then
                    hs.eventtap.keyStrokes(" " .. final)
                else
                    hs.eventtap.keyStrokes(final)
                end
                needsSpace = true
            end

            local words = splitWords(final)
            lastChunkWords = words
        end
    end
end

local function startStream()
    if streamTask or batchRecordTask then return end

    currentMode = "stream"
    menubar:setTitle("🎤⏳")
    outputBuffer = ""
    needsSpace = false
    lastChunkWords = {}

    local args = {
        "-m", MODEL_PATH,
        "--step", "3000",
        "--length", "10000",
        "--keep", "200",
        "-l", "auto",
    }

    streamTask = hs.task.new(STREAM_BIN, function(exitCode, _, _)
        streamTask = nil
        isListening = false
        currentMode = nil
        menubar:setTitle("🎤✕")
    end, function(task, stdout, stderr)
        if stdout and #stdout > 0 then
            if not isListening and stdout:find("%[Start speaking%]") then
                isListening = true
                menubar:setTitle("🎤🔴")
                hs.alert.show("Streaming ON", 1)
            end
            if isListening then
                processStreamOutput(task, stdout)
            end
        end
        return true
    end, args)

    streamTask:start()
end

function stopStream(full)
    if streamTask then
        streamTask:terminate()
        streamTask = nil
    end
    isListening = false
    currentMode = nil
    menubar:setTitle("🎤✕")
    if full then
        hs.alert.show("Whisper quit", 1)
    else
        hs.alert.show("Streaming OFF", 1)
    end
end

local function toggleStream()
    if currentMode == "stream" then
        stopStream(false)
    elseif currentMode == nil then
        startStream()
    end
    -- If batch mode is active, ignore stream hotkey
end

--------------------------------------------------------------------------------
-- Batch mode (Ctrl+Shift+D)
-- Records audio to a file. When stopped, transcribes the entire recording in
-- one pass with full context — higher quality, no chunk boundary artifacts.
-- Processing takes ~4 seconds per minute of audio on Apple Silicon.
--------------------------------------------------------------------------------

local function startBatch()
    if streamTask or batchRecordTask then return end

    currentMode = "batch"
    isListening = true
    menubar:setTitle("🎤🟠")
    hs.alert.show("Recording... (Ctrl+Shift+D to stop)", 2)

    -- Record mic audio to wav file (16kHz mono, what whisper expects)
    local args = {
        "-f", "avfoundation",
        "-i", ":0",
        "-ar", "16000",
        "-ac", "1",
        "-y",  -- overwrite existing file
        AUDIO_FILE,
    }

    batchRecordTask = hs.task.new("/opt/homebrew/bin/ffmpeg", function(exitCode, _, _)
        -- This callback fires when ffmpeg exits (after we terminate it)
        batchRecordTask = nil
    end, args)

    batchRecordTask:start()
end

local function stopBatch()
    if not batchRecordTask then return end

    -- Stop recording
    batchRecordTask:interrupt() -- SIGINT = clean ffmpeg shutdown, writes file header
    batchRecordTask = nil
    isListening = false
    menubar:setTitle("🎤⏳")
    hs.alert.show("Transcribing...", 2)

    -- Short delay to let ffmpeg finish writing the file
    hs.timer.doAfter(0.5, function()
        -- Transcribe the recording
        local args = {
            "-m", MODEL_PATH,
            "-f", AUDIO_FILE,
            "--no-timestamps",
            "-l", "auto",
        }

        hs.task.new(WHISPER_CLI, function(exitCode, stdout, stderr)
            currentMode = nil
            menubar:setTitle("🎤✕")

            if exitCode == 0 and stdout and #stdout > 0 then
                -- Trim whitespace and type the result
                local text = stdout:match("^%s*(.-)%s*$")
                if #text > 0 then
                    hs.eventtap.keyStrokes(text)
                    hs.alert.show("Batch done", 1)
                else
                    hs.alert.show("No speech detected", 1)
                end
            else
                hs.alert.show("Transcription failed", 2)
            end

            -- Clean up the audio file
            os.remove(AUDIO_FILE)
        end, args):start()
    end)
end

local function toggleBatch()
    if currentMode == "batch" then
        stopBatch()
    elseif currentMode == nil then
        startBatch()
    end
    -- If stream mode is active, ignore batch hotkey
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------

initMenubar()
hs.hotkey.bind({"ctrl"}, "D", toggleStream)
hs.hotkey.bind({"ctrl", "shift"}, "D", toggleBatch)
hs.alert.show("Whisper dictation loaded", 2)
