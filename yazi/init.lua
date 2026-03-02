function Linemode:size_and_mtime()
	local time = math.floor(self._file.cha.mtime or 0)
	local time_str = time > 0 and os.date("%Y-%m-%d", time) or ""

	local size = self._file:size()
	local size_str = size and ya.readable_size(size) or "-"

	local perm = self._file.cha:perm()
	local perm_str = perm and tostring(perm) or ""

	return string.format("%s  %s  %s", perm_str, size_str, time_str)
end

-- Git plugin
require("git"):setup()

-- Full border
require("full-border"):setup()

-- DuckDB (CSV/TSV/Parquet preview)
require("duckdb"):setup()

-- Bookmarks
require("bookmarks"):setup({
	persist = "all",
	desc_format = "full",
	show_keys = true,
	notify = {
		enable = true,
		timeout = 3,
	},
})

-- Autosession
require("autosession"):setup()

-- Yatline (status bar)
require("yatline"):setup({
	display_header_line = false,
	status_line = {
		left = {
			section_a = { {type = "string", custom = false, name = "tab_mode"} },
			section_b = { {type = "string", custom = false, name = "hovered_size"} },
			section_c = { {type = "string", custom = false, name = "hovered_path"}, {type = "coloreds", custom = false, name = "count"} },
		},
		right = {
			section_a = { {type = "string", custom = false, name = "cursor_position"} },
			section_b = { {type = "string", custom = false, name = "cursor_percentage"} },
			section_c = { {type = "string", custom = false, name = "hovered_file_extension", params = {true}}, {type = "coloreds", custom = false, name = "githead"} },
		},
	},
})

-- Projects
require("projects"):setup({
	save = {
		method = "yazi",
	},
	merge = {
		quit_after_merge = false,
	},
})

-- Relative motions
require("relative-motions"):setup({
	show_numbers = "relative",
	show_motion = true,
})

-- Restore
require("restore"):setup()

-- Eza preview
require("eza-preview"):setup({
	level = 3,
	follow_symlinks = true,
	all = true,
	git_ignore = true,
})
