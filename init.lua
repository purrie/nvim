-- TODO(purrie): Get binding for quickly turning one line struct declaration to multiline.
-- TODO(purrie): Get binding to redo last fzf search

local home_dir = vim.uv.os_homedir()
-- Behavior
vim.g.zig_fmt_autosave = 0
vim.opt.exrc = true
vim.opt.scrolloff = 9
vim.opt.signcolumn = "yes"
vim.opt.incsearch = true
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = home_dir .. "/.cache/vim/undo"
vim.opt.undofile = true
vim.opt.updatetime = 50
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.foldmethod = "indent"
vim.opt.cpoptions = "aABceFs_I"
vim.opt.cinoptions = "L0,:0,l1,b1,t0,(0,Ws,m1"
vim.opt.cinkeys = "0{,0},0),0],:,;,!^F,o,O,e"

-- Allow external programs to communicate with vim through pipe
local pipepath = vim.fn.stdpath("cache") .. "/server.pipe"
if not vim.loop.fs_stat(pipepath) then
  pcall(vim.fn.serverstart, pipepath)
end

-- Appearance
vim.opt.termguicolors = true
vim.opt.colorcolumn = "0"
vim.opt.winborder = "rounded"
vim.opt.cursorline = true
vim.opt.cursorcolumn = true
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.hlsearch = true
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.breakat = " ,"
vim.opt.breakindentopt = "shift:4,list:4"

vim.api.nvim_set_hl(0, "Normal",       { fg = "#ffffff", bg = 'none'  })
vim.api.nvim_set_hl(0, "Identifier",   { fg = "#ffffff", bg = 'none'  })
vim.api.nvim_set_hl(0, "Constant",     { fg = "#abcdef", bg = 'none'  })
vim.api.nvim_set_hl(0, "String",       { fg = "#dadead", bg = 'none'  })
vim.api.nvim_set_hl(0, "Function",     { fg = "#dcedff", bg = 'none'  })
vim.api.nvim_set_hl(0, "Special",      { fg = "#badbee", bg = 'none'  })
vim.api.nvim_set_hl(0, "PreProc",      { fg = "#dabeef", bg = 'none'  })
vim.api.nvim_set_hl(0, "Statement",    { fg = "#ffbada", bg = 'none'  })
vim.api.nvim_set_hl(0, "Todo",         { fg = "#8888ff", bg = 'none'  })
vim.api.nvim_set_hl(0, "CursorLine",   { fg = "none",    bg = 'none', bold = true })
vim.api.nvim_set_hl(0, "CursorColumn", { fg = "none",    bg = 'none', bold = true })
vim.api.nvim_set_hl(0, "Folded",       { fg = "#a0a0a0", bg = 'none'  })

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
        options = "--preview 'cat {}' --ansi --layout=reverse --cycle"
    }
    vim.fn['fzf#run'](opts)
end
local function fzfInCurrentBuffer(query)
    local function goToLine(arg)
        local line_number, line_text = arg:match("^%s-(%S+)%s+(.+)")
        vim.fn.cursor(tonumber(line_number), 0)
    end

    local bufname = vim.api.nvim_buf_get_name(0)
    local options = "--layout=reverse -e --cycle"
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
    local search_command = "rg -n --smart-case --column --engine=pcre2 "
    local options = "--layout=reverse --ansi --cycle --bind 'change:reload:" .. search_command .. "-e {q}'"
    local source = {}
    if query then
        local escaped_query = vim.fn.shellescape(query)
        options = options .. " --query=" .. escaped_query
        source = search_command .. "-e " .. escaped_query 
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
    local escaped = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(escaped, "v", true)
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
local function commandMake()
    vim.ui.input({ prompt = "Command > " },
    function(input)
        if input == nil or #input == 0 then return end
        vim.opt.makeprg = input
        vim.cmd.make()
    end)
end
local function grepForThing()
    exitToNormalMode()
    local start = vim.fn.getpos("'<")
    local ending = vim.fn.getpos("'>")
    local region = vim.fn.getregion(start, ending)
    local text = ""
    for _, r in ipairs(region) do 
        text = text .. r
    end
    vim.cmd("vim " .. text .. " **")
end

-- Keybindings
-- NOTE: <leader>p namespace is reserved for project shortcuts defined in .nvim.lua
-- NOTE: <localleader> namespace is for file type specific key bindings.
vim.g.mapleader = " "
vim.g.maplocalleader = " m"

vim.keymap.set("n", "<leader>.", fzfProjectFiles, { desc = "Edit file" })
vim.keymap.set("n", "<leader>,", fzfOpenBuffers, { desc = "Edit open file" })

vim.keymap.set("n", "<leader>C", vim.cmd.make, { desc = "Run make command" })
vim.keymap.set("n", "<leader>c", commandMake, { desc = "Input make command" })

vim.keymap.set("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Exit Vim" })
vim.keymap.set("n", "<leader>qQ", "<cmd>qa!<cr>", { desc = "Force exit vim" })

vim.keymap.set("n", "<leader>ss", fzfInCurrentBuffer, { desc = "Search current buffer" })
vim.keymap.set("n", "<leader>sS", "viw<leader>ss", { remap = true })
vim.keymap.set("n", "<leader>sp", fzfInProject, { desc = "Search current directory" })
vim.keymap.set("n", "<leader>sP", "viw<leader>sp", { remap = true })
vim.keymap.set("n", "<leader>sd", vim.cmd.nohlsearch, { desc = "Disable search highlight"})
vim.keymap.set("v", "<leader>ss", function() pipeSelectionTo(fzfInCurrentBuffer) end, { desc = "Search current buffer" })
vim.keymap.set("v", "<leader>sp", function() pipeSelectionTo(fzfInProject) end, { desc = "Search current buffer" })
vim.keymap.set("v", "<leader>sg", grepForThing, { desc = "Grep current root folder" })
vim.keymap.set("n", "<leader>sg", "viw<leader>sg", { desc = "Grep for thing under cursor", remap = true })

vim.keymap.set("n", "<leader>by", "m'gg\"+yG''", { desc = "Yank Buffer" })
vim.keymap.set("n", "<leader>bn", vim.cmd.bn, { desc = "Next buffer" })
vim.keymap.set("n", "<leader>bp", vim.cmd.bp, { desc = "Previous buffer" })
vim.keymap.set("n", "<leader>bk", killBuffer, { desc = "Kill current buffer" })

vim.keymap.set({"v", "n"}, "<leader>ep", "\"+p", { desc = "Paste from xClip" })
vim.keymap.set({"v", "n"}, "<leader>ey", "\"+y", { desc = "Yank to xClip" })
vim.keymap.set("x", "<leader>ep", "\"_dP", { desc = "Paste w/o overriding register" })
vim.keymap.set("v", "<leader>eL", alignToCharacter, { desc = "Align lines" })
vim.keymap.set("v", "<leader>el", function() alignToCharacter(true) end, { desc = "Align lines" })
vim.keymap.set("n", "<leader>ec", "yyp<cmd>.!calc -p<enter>", { desc = "Perform math calculation on current line" })
vim.keymap.set("n", "<leader>ek", "ky$jhp", { desc = "Copy from line above" })

vim.keymap.set("n", "<leader>fs", "<cmd>w<cr>", { desc = "Save" })
vim.keymap.set("n", "<leader>fS", "<cmd>wa<cr>", { desc = "Save all changes" })
vim.keymap.set("n", "<leader>fc", "<cmd>e ~/.config/nvim/init.lua<cr>", { desc = "Open configuration" })

vim.keymap.set("n", "<leader>of", vim.cmd.Ex, { desc = "Open file browser" })

vim.keymap.set("n", "<A-k>", ":m .-2<cr>==", { desc = "Move line up", silent = true })
vim.keymap.set("n", "<A-j>", ":m .+1<cr>==", { desc = "Move line down", silent = true })

vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move lines up", silent = true })
vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move lines down", silent = true })
vim.keymap.set("v", ">", ">gv", { desc = "Indent deeper", silent = true })
vim.keymap.set("v", "<", "<gv", { desc = "Indent shallower", silent = true })

-- Navigation
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

vim.keymap.set("n", "<leader>&", "<C-^>", { desc = "Jump to previous file" })

local left_key = vim.api.nvim_replace_termcodes("<left>", true, false, true)
local right_key = vim.api.nvim_replace_termcodes("<right>", true, false, true)

if vim.g.purr_registered_commands == nil then
    vim.g.purr_registered_commands = true
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "qf",
        callback = function()
            vim.keymap.set("n", "<C-CR>", "<cr><cmd>lclose<cr><cmd>cclose<cr>",
            { buffer = true, silent = true, desc = "Open entry and close location list" })

            vim.keymap.set("n", "q", "<cmd>bd<cr>", { silent = true, buffer = true, desc = "Close quick list"})
        end
    })

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "c",
        callback = function(env)
            vim.keymap.set("n", "<localleader>t", "<cmd>!ctags **.c **.h<cr>", { desc = "Setup ctags", buffer = env.bufnr })
        end
    })

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "zig",
        callback = function(env)
            local dir = home_dir .. "/opt/zig/lib/std"

            vim.keymap.set("n", "<localleader>ss", function() fzfInProject(nil, dir) end, { buffer = env.bufnr, desc = "Search text in standard libraries" })
            vim.keymap.set("v", "<localleader>ss", function() pipeSelectionTo(function(sel) fzfInProject(sel, dir) end) end, { buffer = env.bufnr, desc = "Search text in standard libraries" })
            vim.keymap.set("n", "<localleader>sf", function() fzfProjectFiles(dir) end, { buffer = env.bufnr, desc = "Search for file in standard libraries" })
            vim.keymap.set("n", "<localleader>t", "<cmd>!ztags **.zig " .. home_dir .. "/opt/zig/lib/std/**.zig<cr>", { desc = "Setup ctags", buffer = env.bufnr })
        end
    })

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "odin",
        callback = function(env) 
            local dir = home_dir .. "/opt/odin"

            vim.keymap.set("n", "<localleader>ss", function() fzfInProject(nil, dir) end, { buffer = env.bufnr, desc = "Search text in standard libraries" })
            vim.keymap.set("v", "<localleader>ss", function() pipeSelectionTo(function(sel) fzfInProject(sel, dir) end) end, { buffer = env.bufnr, desc = "Search text in standard libraries" })
            vim.keymap.set("n", "<localleader>sf", function() fzfProjectFiles(dir) end, { buffer = env.bufnr, desc = "Search for file in standard libraries" })
        end
    })

    vim.api.nvim_create_autocmd("InsertCharPre", {
        callback = function ()
            local inserted = vim.v.char
            local closing = inserted
            local modify_insert = true
            if inserted == "{" then
                closing = "}"
            elseif inserted == "[" then
                closing = "]"
            elseif inserted == "(" then
                closing = ")"
            elseif inserted == "'" or inserted == '"' then
            elseif inserted == "]" or inserted == ")" or inserted == "}" then
                modify_insert = false
            else
                return
            end

            local pos = vim.fn.getcursorcharpos()
            local row = pos[2]
            local col = pos[3]
            local line = vim.fn.getline(row)
            local next_char = line:sub(col, col) or ""

            if next_char == closing and closing == inserted then
                vim.v.char = ""
                vim.schedule(function()
                    vim.api.nvim_feedkeys(right_key, "t", true)
                end)
            elseif modify_insert then
                vim.v.char = inserted .. closing
                vim.schedule(function()
                    vim.api.nvim_feedkeys(left_key, "t", true)
                end)
            end
        end
    })
end

