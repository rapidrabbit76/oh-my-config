local M = {}

local get_selected_items = ya.sync(function()
	local tab = cx.active
	local items = {}
	if #tab.selected == 0 then
		if tab.current.hovered then
			table.insert(items, {
				name = tostring(tab.current.hovered.name),
				url = tostring(tab.current.hovered.url),
			})
		end
	else
		for _, url in pairs(tab.selected) do
			local full = tostring(url)
			local name = full:match("([^/]+)/?$")
			table.insert(items, { name = name, url = full })
		end
		ya.emit("escape", {})
	end
	return items
end)

local emit_shell = ya.sync(function(_, cmd)
	ya.emit("shell", { cmd, block = true, orphan = false })
end)

function M:entry(job)
	local default_fmt = job.args[1] or "zip"

	ya.emit("escape", { visual = true })

	local items = get_selected_items()
	if not items or #items == 0 then
		ya.notify({
			title = "Compress Each",
			content = "No files selected",
			timeout = 3,
		})
		return
	end

	local fmt, fmt_event = ya.input({
		title = string.format("Compress %d item(s) each as:", #items),
		value = default_fmt,
		pos = { "top-center", y = 3, w = 40 },
	})
	if fmt_event ~= 1 then
		return
	end

	local parts = {}
	for _, item in ipairs(items) do
		local output = item.name .. "." .. fmt
		table.insert(parts, "ouch c -y " .. ya.quote(item.url) .. " " .. ya.quote(output))
	end
	local cmd = table.concat(parts, " && ")

	emit_shell(cmd)
end

return M
