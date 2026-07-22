return {
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        local kanagawa = require("kanagawa")
        kanagawa.setup({
          theme = "wave",
          transparent = false,
        })
        kanagawa.load("wave")
      end,
    },
  },
}
