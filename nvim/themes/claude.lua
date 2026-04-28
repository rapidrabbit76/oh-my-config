return {
  {
    "rapidrabbit76/claude.inspired.theme.nvim",
    lazy = false,
    priority = 1000,
    config = function(_, opts)
      require("claude").setup(opts)
      require("claude").load()
      require("claude").register_commands()
    end,
    opts = {
      set_background = "dark",
      style = "medium",
      transparent = false,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "claude",
    },
  },
}
