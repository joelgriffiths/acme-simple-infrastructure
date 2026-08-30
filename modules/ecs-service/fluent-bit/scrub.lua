-- Redact patient-identifying data from log records before they leave the VPC.
--
-- Acme stores patient names, contact details, and appointment types. Datadog is a fine
-- place for operational telemetry and a bad place for PHI, so scrubbing happens here, in
-- the task, on the way out. This is a backstop: the application should not be logging
-- these fields at all. Treat a redaction firing in production as a bug to fix upstream.
--
-- Fluent Bit embeds Lua 5.1, so these are Lua patterns, not PCRE.

-- Keys whose value is dropped outright, whatever it looks like.
local DROP_KEYS = {
  patient_name    = true,
  patient_email   = true,
  patient_phone   = true,
  patient_id      = true,
  dob             = true,
  date_of_birth   = true,
  address         = true,
  authorization   = true,
  cookie          = true,
  set_cookie      = true,
}

-- Value patterns redacted wherever they appear in a string.
local PATTERNS = {
  { "[%w%.%_%%%+%-]+@[%w%.%-]+%.%a%a+",                                  "[redacted-email]" },
  { "%+?%d?[%s%.%-]?%(?%d%d%d%)?[%s%.%-]?%d%d%d[%s%.%-]?%d%d%d%d",       "[redacted-phone]" },
  { "%d%d%d%-%d%d%-%d%d%d%d",                                            "[redacted-ssn]"   },
  { "%d%d%d%d[%s%-]?%d%d%d%d[%s%-]?%d%d%d%d[%s%-]?%d%d%d%d",             "[redacted-pan]"   },
}

local MAX_DEPTH = 6

local function scrub_string(s)
  for _, rule in ipairs(PATTERNS) do
    s = string.gsub(s, rule[1], rule[2])
  end
  return s
end

local function scrub_value(key, value, depth)
  if depth > MAX_DEPTH then
    return value
  end

  if type(key) == "string" and DROP_KEYS[string.lower(key)] then
    return "[redacted]"
  end

  local t = type(value)
  if t == "string" then
    return scrub_string(value)
  elseif t == "table" then
    local out = {}
    for k, v in pairs(value) do
      out[k] = scrub_value(k, v, depth + 1)
    end
    return out
  end

  return value
end

-- Fluent Bit filter entrypoint. Return code 2 means "record modified, keep it".
function scrub(tag, timestamp, record)
  local out = {}
  for k, v in pairs(record) do
    out[k] = scrub_value(k, v, 1)
  end
  return 2, timestamp, out
end
