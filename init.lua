-- TODO(purrie): Get binding for quickly turning one line struct declaration to multiline.

-- Behavior
vim.g.zig_fmt_autosave = 0
vim.opt.exrc = true
vim.opt.scrolloff = 9
vim.opt.signcolumn = "yes"
vim.opt.incsearch = true
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.cache/vim/undo"
vim.opt.undofile = true
vim.opt.updatetime = 50
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.foldmethod = "indent"

-- Allow external programs to communicate with vim through pipe
local pipepath = vim.fn.stdpath("cache") .. "/server.pipe"
if not vim.loop.fs_stat(pipepath) then
  vim.fn.serverstart(pipepath)
end

-- Appearance
vim.opt.termguicolors = true
vim.opt.colorcolumn = "0"
vim.opt.winborder = "rounded"
vim.opt.cursorline = true
vim.opt.cursorcolumn = true
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.wrap = true
vim.opt.hlsearch = true

vim.api.nvim_set_hl(0, "Normal", { fg = "#ffffff", bg = 'none'  })
vim.api.nvim_set_hl(0, "Identifier", { fg = "#ffffff", bg = 'none'  })
vim.api.nvim_set_hl(0, "Function", { fg = "#ffaa88", bg = 'none'  })
vim.api.nvim_set_hl(0, "Special", { fg = "#aa88ff", bg = 'none'  })
vim.api.nvim_set_hl(0, "CursorLine", { fg = "none", bg = 'none', bold = true })
vim.api.nvim_set_hl(0, "CursorColumn", { fg = "none", bg = 'none', bold = true })
vim.api.nvim_set_hl(0, "Folded", { fg = "#a0a0a0", bg = 'none' })

-- utility functions
local function fzfOpenBuffers()
    local choices = vim.fn.getbufinfo({ buflisted = 1 })
    table.sort(choices, function(a, b)
        return (a.lastused or 0) > (b.lastused or 0)
    end)

    local buffers = {}
    for _, buffer in ipairs(choices) do
        local buftype = vim.api.nvim_get_option_value("buftype", { scope = 'local', buf = buffer.bufnr })
        local is_valid = vim.api.nvim_buf_is_valid(buffer.bufnr)
        if is_valid and (buftype == nil or buftype == "") and #buffer.name > 0 then
            table.insert(buffers, buffer.name)
        end
    end
    if #buffers > 0 then
        local opts = {
            source = buffers,
            sink = "b",
            options = "--preview 'cat {}' --ansi --layout=reverse"
        }
        vim.fn['fzf#run'](opts)
    end
end
local function fzfProjectFiles(dir)
    local opts = {
        dir = dir,
        source = "rg --hidden --files --glob '!.git' --glob '!.hg' --glob '!.zig-cache' .",
        sink = "e",
        options = "--preview 'cat {}' --ansi --layout=reverse"
    }
    vim.fn['fzf#run'](opts)
end
local function fzfInCurrentBuffer(query)
    local function goToLine(arg)
        local line_number, line_text = arg:match("^%s-(%S+)%s+(.+)")
        vim.fn.cursor(tonumber(line_number), 0)
    end
    local bufname = vim.api.nvim_buf_get_name(0)
    local options = "--layout=reverse -e"
    if query then
        options = options .. " --query=" .. vim.fn.shellescape(query)
    end
    local opts = {
        source = "cat -n " .. bufname,
        sink = goToLine,
        options = options
    }
    vim.fn['fzf#run'](opts)
end
local function fzfInProject(query, dir)
    local function goToResult(arg)
        local file, line, column = arg:match("^%s-(%S+):(%d+):(%d+):.-")
        vim.cmd("e " .. file)
        line = tonumber(line)
        column = tonumber(column)
        vim.fn.cursor(line, column)
    end
    local options = "--layout=reverse --ansi --bind 'change:reload:rg -n --column --smart-case {q}'"
    local source = {}
    if query then
        local escaped_query = vim.fn.shellescape(query)
        options = options .. " --query=" .. escaped_query
        source = "rg -n --smart-case --column " .. escaped_query 
    end
    local opts = {
        source = source,
        dir = dir,
        sink = goToResult,
        options = options,
    }
    vim.fn['fzf#run'](opts)
end

local function exitToNormalMode()
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.cmd("normal! " .. esc)
end
local function pipeSelectionTo(fun)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "v", true)
    vim.defer_fn(function()
        local start = vim.fn.getpos("'<")
        local ending = vim.fn.getpos("'>")
        local region = vim.fn.getregion(start, ending)
        local to_print = ""
        for _, r in ipairs(region) do 
            to_print = to_print .. r
        end
        fun(to_print)
    end, 100)
end
local function killBuffer()
    local choices = vim.fn.getbufinfo({ buflisted = 1 })
    table.sort(choices, function(a, b)
        return (a.lastused or 0) > (b.lastused or 0)
    end)
    local current_buffer_name = vim.api.nvim_buf_get_name(0)
    for _, buf in ipairs(choices) do
        if buf.name ~= current_buffer_name then
            vim.cmd("b " .. buf.name)
            vim.cmd("bd " .. current_buffer_name)
            goto completed
        end
    end
    ::completed::
end
local function alignToCharacter(extra_spaces)
    vim.ui.input({ prompt = "Align to > " }, function(input)
        if input == nil or #input == 0 then return end
        exitToNormalMode()
        local first_line = vim.fn.getpos("'<")
        local last_line = vim.fn.getpos("'>")
        first_line = first_line[2]-1
        last_line = last_line[2]
        local lines = vim.api.nvim_buf_get_lines(0, first_line, last_line, false)

        local alignment = {}
        local longest_lead = 0

        for nr, l in ipairs(lines) do
            local s, e = string.find(l, input)
            if s and e then 
                local following  = string.sub(l, s)
                local leading    = string.sub(l, 1, s - 1)
                local spaces     = string.match(leading, "(%s*)$") or ""
                leading          = string.sub(l, 1, s - #spaces - 1)

                if #leading > longest_lead then
                    longest_lead = #leading 
                end

                table.insert(alignment, { lead = leading, following = following, line = nr })
            end
        end
        for _, work in ipairs(alignment) do 
            local line_number      = first_line + work.line
            local spaces_to_insert = longest_lead - #work.lead 
            if extra_spaces then
                spaces_to_insert = spaces_to_insert + 1
            end
            local result           = work.lead .. string.rep(" ", spaces_to_insert) .. work.following
            vim.fn.setline(line_number, result)
        end
    end)
end

-- Keybindings
-- NOTE: <leader>p namespace is reserved for project shortcuts defined in .nvim.lua
vim.g.mapleader = " "
vim.g.maplocalleader = " m"

vim.keymap.set("n", "<leader>.", fzfProjectFiles, { desc = "Edit file" })
vim.keymap.set("n", "<leader>,", fzfOpenBuffers, { desc = "Edit open file" })

vim.keymap.set("n", "<leader>c", vim.cmd.make, { desc = "Run make command" })

vim.keymap.set("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Exit Vim" })
vim.keymap.set("n", "<leader>qQ", "<cmd>qa!<cr>", { desc = "Force exit vim" })

vim.keymap.set("n", "<leader>ss", fzfInCurrentBuffer, { desc = "Search current buffer" })
vim.keymap.set("n", "<leader>sS", "viw<leader>ss", { remap = true })
vim.keymap.set("n", "<leader>sp", fzfInProject, { desc = "Search current directory" })
vim.keymap.set("n", "<leader>sP", "viw<leader>sp", { remap = true })
vim.keymap.set("n", "<leader>sd", vim.cmd.nohlsearch, { desc = "Disable search highlight"})
vim.keymap.set("v", "<leader>ss", function() pipeSelectionTo(fzfInCurrentBuffer) end, { desc = "Search current buffer" })
vim.keymap.set("v", "<leader>sp", function() pipeSelectionTo(fzfInProject) end, { desc = "Search current buffer" })

vim.keymap.set("n", "<leader>by", "m'gg\"+yG''", { desc = "Yank Buffer" })
vim.keymap.set("n", "<leader>bn", vim.cmd.bn, { desc = "Next buffer" })
vim.keymap.set("n", "<leader>bp", vim.cmd.bp, { desc = "Previous buffer" })
vim.keymap.set("n", "<leader>bk", killBuffer, { desc = "Kill current buffer" })

vim.keymap.set({"v", "n"}, "<leader>ep", "\"+p", { desc = "Paste from xClip" })
vim.keymap.set({"v", "n"}, "<leader>ey", "\"+y", { desc = "Yank to xClip" })
vim.keymap.set("x", "<leader>ep", "\"_dP", { desc = "Paste w/o overriding register" })
vim.keymap.set("v", "<leader>eL", alignToCharacter, { desc = "Align lines" })
vim.keymap.set("v", "<leader>el", function() alignToCharacter(true) end, { desc = "Align lines" })

vim.keymap.set("n", "<leader>fs", "<cmd>w<cr>", { desc = "Save" })
vim.keymap.set("n", "<leader>fS", "<cmd>wa<cr>", { desc = "Save all changes" })
vim.keymap.set("n", "<leader>fc", "<cmd>e ~/.config/nvim/init.lua<cr>", { desc = "Open configuration" })

vim.keymap.set("n", "<leader>of", vim.cmd.Ex, { desc = "Open file browser" })

vim.keymap.set("n", "<A-k>", ":m .-2<cr>==", { desc = "Move line up", silent = true })
vim.keymap.set("n", "<A-j>", ":m .+1<cr>==", { desc = "Move line down", silent = true })

vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move lines up", silent = true })
vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move lines down", silent = true })

-- Navigation
vim.keymap.set({ "n", "v" }, "#", "_", { desc = "Back to indentation" })
vim.keymap.set("i", "<C-e>", "<End>", { desc = "Go to line ending" })
vim.keymap.set("i", "<C-a>", "<cmd>norm _<cr>", { desc = "Go to line start" })
vim.keymap.set("i", "<C-f>", "<right>", { desc = "Character forward" })
vim.keymap.set("i", "<C-b>", "<left>", { desc = "Character backward" })
vim.keymap.set("i", "<M-f>", "<C-right>", { desc = "Word forward" })
vim.keymap.set("i", "<M-b>", "<C-left>", { desc = "Word backward" })
vim.keymap.set("i", "<C-o>", "<escape>o", { desc = "Append Line" })
vim.keymap.set("i", "<M-o>", "<escape>O", { desc = "Prepend Line" })
vim.keymap.set("i", "<C-p>", "<up>", { desc = "Move up one line" })
vim.keymap.set("i", "<C-n>", "<down>", { desc = "Move down one line" })

vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-l>", "<C-w>l")
vim.keymap.set("n", "<C-h>", "<C-w>h")

-- Auto brackets
local function create_pair(opening, closing)
    local function create_opener()
        local pos = vim.fn.getcursorcharpos()
        local row = pos[2]
        local col = pos[3]
        local line = vim.fn.getline(row)
        local next_char = line:sub(col, col) or ""
        if vim.stricmp(next_char, opening) ~= 0 then
            line = line:sub(0, col - 1) .. opening .. closing .. line:sub(col)
            vim.fn.setline(row, line)
        end
        vim.fn.setcursorcharpos(row, col + 1)
    end
    local function create_closer()
        local pos = vim.fn.getcursorcharpos()
        local row = pos[2]
        local col = pos[3]
        local line = vim.fn.getline(row)
        local next_char = line:sub(col, col) or ""
        if vim.stricmp(next_char, closing) ~= 0 then
            if vim.stricmp(opening, closing) == 0 then
                line = line:sub(0, col - 1) .. opening .. closing .. line:sub(col)
            else
                line = line:sub(0, col - 1) .. closing .. line:sub(col)
            end
            vim.fn.setline(row, line)
        end
        vim.fn.setcursorcharpos(row, col + 1)
    end
    vim.keymap.set("i", opening, create_opener)
    vim.keymap.set("i", closing, create_closer)
end
create_pair("(", ")")
create_pair("{", "}")
create_pair("[", "]")
create_pair("\"", "\"")
create_pair("'", "'")

local current_window = 0
local last_window = 0
local last_buffer = 0
local window_focus = 0

-- Move to previously visited buffer
vim.keymap.set("n", "<leader>&", function()
    if vim.w.purr_last_buffer then
        vim.cmd.buffer(vim.w.purr_last_buffer)
    end
end)


if vim.g.purr_registered_commands == nil then
    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function(ev)
            current_window = vim.api.nvim_get_current_win()
            last_window = current_window
            window_focus = current_window
        end
    })
    vim.api.nvim_create_autocmd("WinEnter", {
        callback = function()
            current_window = vim.api.nvim_get_current_win()
        end
    })
    vim.api.nvim_create_autocmd("WinLeave", {
        callback = function(ev)
            last_window = vim.api.nvim_get_current_win()
        end
    })
    vim.api.nvim_create_autocmd("BufLeave", {
        callback = function(ev)
            last_buffer = ev.buf
            local cur = vim.api.nvim_win_get_cursor(0)
        end
    })
    vim.api.nvim_create_autocmd("BufEnter", {
        callback = function(ev)
            if window_focus == current_window then
                vim.w.purr_last_buffer = last_buffer
            end
            window_focus = current_window
        end
    })

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "qf",
        callback = function()
            vim.keymap.set("n", "<C-CR>", "<cr><cmd>lclose<cr><cmd>cclose<cr>",
            { buffer = true, silent = true, desc = "Open entry and close location list" })

            vim.keymap.set("n", "q", "<cmd>bd<cr>", { silent = true, buffer = true })
        end
    })
    vim.api.nvim_create_autocmd("BufNew", {
        callback = function(ev)
            if #ev.file > 0 then
                local dir = nil

                if string.sub(ev.file, -3) == "zig" then
                    dir = os.getenv("HOME") .. "/opt/zig/lib/std"
                elseif string.sub(ev.file, -4) == "odin" then
                    dir = os.getenv("HOME") .. "/opt/odin"
                end

                if dir then
                    vim.keymap.set("n", "<localleader>ss", function() fzfInProject(nil, dir) end, { buffer = ev.bufnr, desc = "Search text in standard libraries" })
                    vim.keymap.set("v", "<localleader>ss", function() pipeSelectionTo(function(sel) fzfInProject(sel, dir) end) end, { buffer = ev.bufnr, desc = "Search text in standard libraries" })
                    vim.keymap.set("n", "<localleader>sf", function() fzfProjectFiles(dir) end, { buffer = ev.bufnr, desc = "Search for file in standard libraries" })
                end
            end
        end
    })
    vim.g.purr_registered_commands = true
end

