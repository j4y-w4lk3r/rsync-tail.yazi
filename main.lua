--- rsync-tail.yazi — rsync with a tailnet destination picker
--- Based on GianniBYoung/rsync.yazi (MIT)

local DEFAULT_TARGETS = {
	{ on = "<A-c>", desc = "Custom destination…", dest = false },
}

local CONFIG = {
	targets = DEFAULT_TARGETS,
	remember = true,
	setup_done = false,
}

local STATE_DIR = os.getenv("HOME") .. "/.local/state/yazi"
local CACHE_FILE = STATE_DIR .. "/rsync-tail.last_target"
local TARGETS_FILE = STATE_DIR .. "/rsync-tail.targets.json"
local LOG_FILE = STATE_DIR .. "/rsync-tail.log"

local function log(msg)
	local line = os.date("%Y-%m-%dT%H:%M:%S") .. " " .. msg .. "\n"
	ya.dbg("[rsync-tail] ", msg)
	os.execute("mkdir -p " .. ya.quote(STATE_DIR))
	local f = io.open(LOG_FILE, "a")
	if f then
		f:write(line)
		f:close()
	end
end

--- rsync expects local filesystem paths, not Yazi Url strings like file:///Users/...
local function local_path(url)
	if url.path then
		return tostring(url.path)
	end

	local s = tostring(url)
	if s:match("^file://") then
		return s:gsub("^file://", "")
	end

	return s
end

local selected_or_hovered = ya.sync(function()
	local tab = cx.active
	local paths = {}

	for _, url in pairs(tab.selected) do
		paths[#paths + 1] = local_path(url)
	end

	if #paths == 0 and tab.current.hovered then
		paths[1] = local_path(tab.current.hovered.url)
	end

	return paths
end)

local function save_targets(targets)
	local ok, json = pcall(ya.json_encode, targets)
	if not ok or not json then
		return
	end

	os.execute("mkdir -p " .. ya.quote(STATE_DIR))
	local f = io.open(TARGETS_FILE, "w")
	if f then
		f:write(json)
		f:close()
	end
end

local function load_targets_from_file()
	local f = io.open(TARGETS_FILE, "r")
	if not f then
		return nil
	end

	local content = f:read("*a")
	f:close()

	local ok, targets = pcall(ya.json_decode, content)
	if not ok then
		log("json_decode failed: " .. tostring(targets))
		return nil
	end
	if type(targets) ~= "table" or #targets == 0 then
		log("targets file empty or invalid")
		return nil
	end

	log("loaded " .. #targets .. " target(s) from " .. TARGETS_FILE)
	return targets
end

local function targets_for(self)
	-- File first: CONFIG may still hold the 1-entry default after module reload.
	local file_targets = load_targets_from_file()
	if file_targets then
		return file_targets
	end

	if self and type(self.targets) == "table" and #self.targets > 0 then
		log("using self.targets (" .. #self.targets .. ")")
		return self.targets
	end

	if CONFIG.setup_done and type(CONFIG.targets) == "table" and #CONFIG.targets > 0 then
		log("using CONFIG.targets (" .. #CONFIG.targets .. ")")
		return CONFIG.targets
	end

	log("falling back to DEFAULT_TARGETS")
	return DEFAULT_TARGETS
end

local function remember_for(self)
	if self and type(self.remember) == "boolean" then
		return self.remember
	end
	return CONFIG.remember
end

local function expand_tilde(path)
	if not path then
		return nil
	end

	if path:sub(1, 1) == "~" then
		local home = os.getenv("HOME") or os.getenv("USERPROFILE")
		if home then
			return home .. path:sub(2)
		end

		ya.notify({
			title = "Rsync",
			content = "Could not expand '~': HOME is not set.",
			level = "warn",
			timeout = 5,
		})
		return path
	end

	return path
end

local function read_cached_target()
	local f = io.open(CACHE_FILE, "r")
	if not f then
		return ""
	end

	local cached = f:read("*a"):match("^%s*(.-)%s*$") or ""
	f:close()
	return cached
end

local function write_cached_target(self, dest)
	if not remember_for(self) or not dest or dest == "" then
		return
	end

	os.execute("mkdir -p " .. ya.quote(STATE_DIR))
	local f = io.open(CACHE_FILE, "w")
	if f then
		f:write(dest)
		f:close()
	end
end

local function format_key(on)
	if type(on) == "table" then
		return table.concat(on, "")
	end
	return tostring(on)
end

local function notify_targets(targets)
	local lines = {}
	for _, target in ipairs(targets) do
		lines[#lines + 1] = string.format("%s  %s", format_key(target.on), target.desc or target.dest or "")
	end

	ya.notify({
		title = "Rsync destinations",
		content = table.concat(lines, "\n"),
		level = "info",
		timeout = 8,
	})
end

local function pick_destination(self)
	local targets = targets_for(self)
	if #targets == 0 then
		ya.notify({
			title = "Rsync",
			content = "No destinations configured in init.lua",
			level = "error",
			timeout = 6,
		})
		return nil
	end

	local cands = {}
	for _, target in ipairs(targets) do
		cands[#cands + 1] = { on = target.on, desc = target.desc }
	end

	notify_targets(targets)

	local idx = ya.which({ cands = cands, silent = false })
	if not idx then
		return nil
	end

	local target = targets[idx]
	if target.dest then
		return target.dest
	end

	local cached = read_cached_target()
	local default = cached ~= "" and cached or ""
	local dest, ok = ya.input({
		title = "Rsync destination [user@host]:path",
		value = default,
		pos = { "top-center", y = 3, w = 55 },
	})
	if ok ~= 1 then
		return nil
	end

	dest = dest:match("^%s*(.-)%s*$")
	if dest == "" then
		return nil
	end

	if not dest:match(":") then
		dest = expand_tilde(dest)
	end

	return dest
end

local function run_rsync(self, files, dest)
	local cmd = Command("rsync")
		:arg({ "-ahP", "--no-motd" })
		:arg(files)
		:arg(dest)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if cmd.status.code ~= 0 then
		ya.notify({
			title = "Rsync",
			content = string.format("Failed (exit %s)\n\n%s", cmd.status.code, cmd.stderr),
			level = "error",
			timeout = 12,
		})
		return false
	end

	ya.notify({
		title = "Rsync",
		content = string.format("Sent %d item(s) → %s", #files, dest),
		timeout = 4,
	})
	write_cached_target(self, dest)
	return true
end

local function apply_setup(self, opts)
	CONFIG.targets = DEFAULT_TARGETS
	CONFIG.remember = true

	if type(opts) == "table" then
		if type(opts.targets) == "table" and #opts.targets > 0 then
			CONFIG.targets = opts.targets
		end
		if type(opts.remember) == "boolean" then
			CONFIG.remember = opts.remember
		end
	end

	CONFIG.setup_done = true
	save_targets(CONFIG.targets)
	log("setup saved " .. #CONFIG.targets .. " target(s)")

	if type(self) == "table" then
		self.targets = CONFIG.targets
		self.remember = CONFIG.remember
	end
end

return {
	setup = function(self, opts)
		if opts == nil and type(self) == "table" and type(self.targets) == "table" then
			apply_setup(nil, self)
			return
		end

		apply_setup(self, opts)
	end,

	entry = function(self, _)
		local ok, err = pcall(function()
			log("entry start")
			ya.emit("escape", { visual = true })

			local files = selected_or_hovered()
			if #files == 0 then
				return ya.notify({
					title = "Rsync",
					content = "No files selected",
					level = "warn",
					timeout = 3,
				})
			end

			local dest = pick_destination(self)
			if not dest then
				return
			end

			run_rsync(self, files, dest)
		end)

		if not ok then
			ya.notify({
				title = "Rsync",
				content = tostring(err),
				level = "error",
				timeout = 12,
			})
			ya.err("[rsync-tail] ", err)
		end
	end,
}
