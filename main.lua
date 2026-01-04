--- @since 25.12.29

local M = {}

-- Module-level state (avoids ya.sync polling issues in async peek context)
M._opts = {
	level = 3,
	follow_symlinks = true,
	dereference = false,
	all = true,
	ignore_glob = {},
	git_ignore = true,
	git_status = false,
	icons = true,
}
M._tree = true

local function fail(s, ...)
	ya.notify({ title = "Eza Preview", content = string.format(s, ...), timeout = 5, level = "error" })
end

function M:setup(user_config)
	user_config = user_config or {}
	for key, value in pairs(user_config) do
		if key == "default_tree" then
			M._tree = value
		elseif M._opts[key] ~= nil then
			M._opts[key] = value
		end
	end
end

-- Sync blocks for entry point mutations only (not called from async peek)
local toggle_view_mode = ya.sync(function()
	M._tree = not M._tree
	ya.manager_emit("refresh", {})
end)

local inc_level = ya.sync(function()
	M._opts.level = M._opts.level + 1
	ya.manager_emit("refresh", {})
end)

local dec_level = ya.sync(function()
	if M._opts.level > 1 then
		M._opts.level = M._opts.level - 1
		ya.manager_emit("refresh", {})
	end
end)

local toggle_follow_symlinks = ya.sync(function()
	M._opts.follow_symlinks = not M._opts.follow_symlinks
	ya.manager_emit("refresh", {})
end)

local toggle_hidden = ya.sync(function()
	M._opts.all = not M._opts.all
	ya.manager_emit("refresh", {})
end)

local toggle_git_ignore = ya.sync(function()
	M._opts.git_ignore = not M._opts.git_ignore
	ya.manager_emit("refresh", {})
end)

local toggle_git_status = ya.sync(function()
	M._opts.git_status = not M._opts.git_status
	ya.manager_emit("refresh", {})
end)

function M:entry(job)
	local args = string.gsub(job.args[1] or "", "^%s*(.-)%s*$", "%1")
	if args == "inc-level" then
		inc_level()
	elseif args == "dec-level" then
		dec_level()
	elseif args == "toggle-follow-symlinks" then
		toggle_follow_symlinks()
	elseif args == "toggle-hidden" then
		toggle_hidden()
	elseif args == "toggle-git-ignore" then
		toggle_git_ignore()
	elseif args == "toggle-git-status" then
		toggle_git_status()
	else
		toggle_view_mode()
	end
	ya.manager_emit("seek", { 0 })
end

function M:peek(job)
	-- Access module-level state directly (no ya.sync call from async context)
	local opts = M._opts
	local is_tree = M._tree
	local args = {
		"--color=always",
		"--group-directories-first",
		"--no-quotes",
		tostring(job.file.url),
	}
	if is_tree then
		table.insert(args, "--tree")
		table.insert(args, string.format("--level=%d", opts.level))
	end
	if opts then
		if opts.icons then
			table.insert(args, "--icons=always")
		end
		if opts.follow_symlinks then
			table.insert(args, "--follow-symlinks")
		end
		if opts.all then
			table.insert(args, "--all")
		end
		if opts.dereference then
			table.insert(args, "--dereference")
		end
		if opts.git_status then
			table.insert(args, "--long")
			table.insert(args, "--no-permissions")
			table.insert(args, "--no-user")
			table.insert(args, "--no-time")
			table.insert(args, "--no-filesize")
			table.insert(args, "--git")
			table.insert(args, "--git-repos")
		end
		if opts.git_ignore then
			table.insert(args, "--git-ignore")
		end
		if opts.ignore_glob and type(opts.ignore_glob) == "table" and #opts.ignore_glob > 0 then
			local pattern_str = table.concat(opts.ignore_glob, "|")
			table.insert(args, "-I")
			table.insert(args, pattern_str)
		elseif opts.ignore_glob and type(opts.ignore_glob) == "string" and opts.ignore_glob ~= "" then
			table.insert(args, "-I")
			table.insert(args, opts.ignore_glob)
		end
	end
	local child, err = Command("eza"):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if not child then
		return ya.preview_widget(job, ui.Text("eza: " .. (err or "spawn failed")):area(job.area))
	end
	local limit = job.area.h
	local lines = ""
	local num_lines = 1
	local num_skip = 0
	local empty_output = false
	repeat
		local line, event = child:read_line()
		if event == 1 then
			fail(tostring(event))
		elseif event ~= 0 then
			break
		end
		if num_skip >= job.skip then
			lines = lines .. line
			num_lines = num_lines + 1
		else
			num_skip = num_skip + 1
		end
	until num_lines >= limit
	if num_lines == 1 and not is_tree then
		empty_output = true
	elseif num_lines == 2 and is_tree then
		empty_output = true
	end
	child:start_kill()
	if job.skip > 0 and num_lines < limit then
		ya.manager_emit("peek", {
			tostring(math.max(0, job.skip - (limit - num_lines))),
			only_if = tostring(job.file.url),
			upper_bound = "",
		})
	elseif empty_output then
		ya.preview_widget(job, {
			ui.Text({ ui.Line("No items") }):area(job.area):align(ui.Text.CENTER),
		})
	else
		ya.preview_widget(job, {
			ui.Text.parse(lines):area(job.area),
		})
	end
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = math.floor(job.units * job.area.h / 10)
		ya.manager_emit("peek", {
			math.max(0, cx.active.preview.skip + step),
			only_if = tostring(job.file.url),
			force = true,
		})
	end
end

return M
