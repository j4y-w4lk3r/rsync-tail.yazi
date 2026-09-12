--- rsync-tail.yazi — rsync with a tailnet destination picker
--- Based on GianniBYoung/rsync.yazi (MIT)

local DEFAULT_TARGETS = {
	{ on = "c", desc = "Custom destination…", dest = false },
}

local state = {
	targets = DEFAULT_TARGETS,
	remember = true,
}

local CACHE_FILE = os.getenv("HOME") .. "/.config/yazi/plugins/rsync-tail.yazi/.last_target"

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

local function write_cached_target(dest)
	if not state.remember or not dest or dest == "" then
		return
	end

	local f = io.open(CACHE_FILE, "w")
	if f then
		f:write(dest)
		f:close()
	end
end

local function build_picker_cands()
	local cands = {}
	for _, target in ipairs(state.targets) do
		cands[#cands + 1] = { on = target.on, desc = target.desc }
	end
	return cands
end

local function pick_destination()
	local cands = build_picker_cands()
	local idx = ya.which({ cands = cands, silent = false })
	if not idx then
		return nil
	end

	local target = state.targets[idx]
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

local function run_rsync(files, dest)
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
	write_cached_target(dest)
	return true
end

return {
	setup = function(_, opts)
		if type(opts) ~= "table" then
			return
		end

		if type(opts.targets) == "table" and #opts.targets > 0 then
			state.targets = opts.targets
		end

		if type(opts.remember) == "boolean" then
			state.remember = opts.remember
		end
	end,

	entry = function(_, _)
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

		local dest = pick_destination()
		if not dest then
			return
		end

		run_rsync(files, dest)
	end,
}
