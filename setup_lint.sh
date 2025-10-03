#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Error: Exactly one argument required."
    exit 1
fi

cd "$1" || exit 1

find . -name "*.sv" -o -name "*.svh" -o -name "*.v" | sort >.verilator.f

cat >.rules.verible_lint <<EOF
parameter-name-style=localparam_style:ALL_CAPS
-always-comb
-explicit-parameter-storage-type
-unpacked-dimensions-range-ordering
-line-length=120
EOF

cat >.lazy.lua <<EOF
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
        "--bbox-sys",
        "--bbox-unsup",
        "--lint-only",
        "-ImyCPU",
        "--top-module", "mycpu_top",
      }
    end,
  },

}
EOF

cd ..
