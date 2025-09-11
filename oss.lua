#!/usr/bin/env lua

--- Executes a shell command and returns success status across Lua versions.
-- @param cmd Command to execute
-- @return true if command exits with status 0; otherwise false
local function exec_ok(cmd)
  local r1, r2, r3 = os.execute(cmd)
  if type(r1) == "number" then return r1 == 0 end
  if type(r1) == "boolean" then return r1 and r2 == "exit" and r3 == 0 end
  return false
end

--- Safely quotes a string for POSIX shell usage.
-- @param s String to quote
-- @return Quoted string safe for shell
local function shell_quote(s)
  if s == nil then return "''" end
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- Reads all content from a file handle.
-- @param f File handle (e.g., io.stdin)
-- @return Entire content as string or empty string
local function read_all(f)
  local c = f:read("*a")
  return c or ""
end

--- Reads all lines from a file path into a table.
-- @param path File path to read
-- @return Table of lines (empty if file not found)
local function read_lines(path)
  local t = {}
  local f = io.open(path, "r")
  if not f then return t end
  for line in f:lines() do table.insert(t, line) end
  f:close()
  return t
end

--- Writes an array of lines to a file path.
-- @param path File path to write
-- @param lines Table of strings to write as lines
-- @return nil
local function write_lines(path, lines)
  local f = assert(io.open(path, "w"))
  for _, line in ipairs(lines) do f:write(line, "\n") end
  f:close()
end

--- JSON-escapes a string and wraps it with quotes.
-- @param s String to escape
-- @return Properly escaped JSON string value
local function json_escape_string(s)
  local m = {
    ['\\'] = '\\\\',
    ['"'] = '\\"',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t'
  }
  return '"' .. tostring(s):gsub('[\\\"\b\f\n\r\t]', m):gsub('[\0-\31]', function(c)
    return string.format('\\u%04x', string.byte(c))
  end) .. '"'
end

--- Checks if STDIN is a TTY.
-- @return true when STDIN is a terminal; otherwise false
local function is_stdin_tty()
  return exec_ok("[ -t 0 ]")
end

--- Checks if a command exists on PATH.
-- @param cmd Command name
-- @return true if the command is available; otherwise false
local function has_command(cmd)
  return exec_ok("command -v " .. cmd .. " >/dev/null 2>&1")
end

--- Uses jq to extract data from JSON text with a filter.
-- @param json_text JSON document as text
-- @param filter jq filter string
-- @return Extraction result as string (may contain newlines)
local function jq_extract(json_text, filter)
  local tmp = os.tmpname()
  local f = assert(io.open(tmp, "w"))
  f:write(json_text)
  f:close()
  local cmd = "jq -r " .. shell_quote(filter) .. " " .. shell_quote(tmp) .. " 2>/dev/null"
  local h = io.popen(cmd, "r")
  local out = h:read("*a") or ""
  h:close()
  os.remove(tmp)
  return out
end

--- Checks if jq can parse a JSON text.
-- @param json_text JSON document as text
-- @return true when jq -e . succeeds; otherwise false
local function jq_can_parse(json_text)
  local tmp = os.tmpname()
  local f = assert(io.open(tmp, "w"))
  f:write(json_text)
  f:close()
  local ok = exec_ok("jq -e . " .. shell_quote(tmp) .. " >/dev/null 2>&1")
  os.remove(tmp)
  return ok
end

--- Builds a JSON array from a table of pre-serialized JSON objects.
-- @param lines Array of JSON object strings
-- @return JSON array string
local function build_messages_json(lines)
  if #lines == 0 then return "[]" end
  return "[" .. table.concat(lines, ",") .. "]"
end

--- Entry point: reads history, builds request, streams response and persists history.
-- Environment variables required: CLOUDFLARE_AI_ACCOUNT_ID, CLOUDFLARE_AI_API_KEY.
-- Supports --model flag, stdin piping and SSE streaming.
-- @return nil
local function main()
  local history_path = "/tmp/osschat_messages"
  local history = read_lines(history_path)
  local model = "@cf/openai/gpt-oss-120b"
  local temperature = 0.7
  local message = nil

  if not is_stdin_tty() then
    local stdin_content = read_all(io.stdin)
    if stdin_content and stdin_content ~= "" then
      message = stdin_content
    end
  end

  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "--model" and i + 1 <= #arg then
      model = arg[i + 1]
      i = i + 2
    else
      message = message and (message .. " " .. a) or a
      i = i + 1
    end
  end

  if not message or message == "" then
    print("Usage: oss [--model model-name] your message")
    os.exit(1)
  end

  local user_line = '{"role":"user","content":' .. json_escape_string(message) .. "}"
  table.insert(history, user_line)

  local messages_json = build_messages_json(history)
  local account_id = os.getenv("CLOUDFLARE_AI_ACCOUNT_ID")
  local api_key = os.getenv("CLOUDFLARE_AI_API_KEY")
  if not account_id or account_id == "" or not api_key or api_key == "" then
    io.stderr:write("Missing CLOUDFLARE_AI_ACCOUNT_ID or CLOUDFLARE_AI_API_KEY.\n")
    os.exit(1)
  end

  local url = "https://api.cloudflare.com/client/v4/accounts/" .. account_id .. "/ai/v1/responses"
  local data_body = '{"model":' .. json_escape_string(model) .. ',"input":' .. messages_json .. ',"temperature":' .. tostring(temperature) .. "}"
  local curl_cmd = table.concat({
    "curl", "-s", "-N",
    shell_quote(url),
    "-X", "POST",
    "-H", shell_quote("Authorization: Bearer " .. api_key),
    "-H", shell_quote("Content-Type: application/json"),
    "-H", shell_quote("Accept: text/event-stream"),
    "-d", shell_quote(data_body)
  }, " ")

  local handle = io.popen(curl_cmd, "r")
  local response_text = ""
  local streamed = false
  local raw_buffer = {}
  if handle then
    for line in handle:lines() do
      if line:sub(1, 5) == "data:" then
        streamed = true
        local payload = line:sub(7)
        if payload == "[DONE]" or payload == "" then
          goto continue
        end
        local chunk = ""
        if has_command("jq") and jq_can_parse(payload) then
          chunk = jq_extract(payload, '.output[]? | select(.type == "message") | .content[]?.text // empty')
        else
          chunk = payload
        end
        if chunk and chunk ~= "" then
          io.write(chunk)
          io.flush()
          response_text = response_text .. chunk
        end
      else
        table.insert(raw_buffer, line)
      end
      ::continue::
    end
    handle:close()
  end

  if not streamed then
    local all = table.concat(raw_buffer, "\n")
    if has_command("jq") and jq_can_parse(all) then
      local err = jq_extract(all, ".error")
      if err and err ~= "" and err ~= "null\n" then
        local msg = jq_extract(all, '.error.message // "Unknown endpoint error"')
        io.stderr:write("Endpoint error: " .. (msg:gsub("\n$", "")) .. "\n")
        os.exit(1)
      end
      local content = jq_extract(all, '.output[] | select(.type == "message") | .content[]?.text // empty')
      if content and content ~= "" then
        io.write(content)
        response_text = content
      end
    end
  end

  io.write("\n")

  if response_text == nil or response_text == "" then
    io.stderr:write("No response received from LLM.\n")
    os.exit(1)
  end

  local assistant_line = '{"role":"assistant","content":' .. json_escape_string(response_text) .. "}"
  table.insert(history, assistant_line)
  write_lines(history_path, history)
end

main()
