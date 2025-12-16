return {
  {
    -- https://github.com/mfussenegger/nvim-lint
    "mfussenegger/nvim-lint",
    dependencies = { "neovim/nvim-lspconfig" },
    opts = {
      linters_by_ft = {
        verilog = { "verilator" },
      },
    },
    init = function()
      local verilator = require("lint").linters.verilator
      verilator.args = {
        "-Wall",
        "--lint-only",
        "-ImyCPU",
        "--top-module", "mycpu_top",
      }
    end,
  },

}
