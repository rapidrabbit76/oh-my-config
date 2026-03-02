local M = {}

function M:peek(job)
	local child = Command("mediainfo")
		:args({ tostring(job.file.url) })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()

	local output = child:wait_with_output()
	if output and output.status and output.status.success then
		ya.preview_widgets(job, { ui.Text.parse(output.stdout) })
	end
end

function M:seek(job)
	local h = cx.active.preview.skip // job.area.h
	ya.manager_emit("peek", {
		math.max(0, cx.active.preview.skip + job.units),
		only_if = job.file.url,
	})
end

return M
