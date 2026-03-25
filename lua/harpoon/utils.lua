local Path = require("plenary.path")
local data_path = vim.fn.stdpath("data")
local Job = require("plenary.job")

local M = {}
local branch_key_cache = {}

M.data_path = data_path

local function is_non_empty(value)
    return value ~= nil and #value > 0 and not M.is_white_space(value)
end

local function dirname(path)
    return path:match("^(.*)/[^/]+/?$")
end

local function get_jj_root()
    local path = vim.loop.cwd()

    while path do
        if vim.loop.fs_stat(path .. "/.jj") then
            return path
        end

        local parent = dirname(path)
        if parent == path then
            break
        end
        path = parent
    end
end

local function get_git_branch()
    local branch

    -- use tpope's fugitive for faster branch name resolution if available
    if vim.fn.exists("*FugitiveHead") == 1 then
        branch = vim.fn["FugitiveHead"]()
        -- return "HEAD" for parity with `git rev-parse` in detached head state
        if #branch == 0 then
            branch = "HEAD"
        end
    else
        -- `git branch --show-current` requires Git v2.22.0+ so going with more
        -- widely available command
        branch = M.get_os_command_output({
            "git",
            "rev-parse",
            "--abbrev-ref",
            "HEAD",
        })[1]
    end

    if is_non_empty(branch) then
        return branch
    end
end

local function get_jj_branch()
    if vim.fn.executable("jj") ~= 1 then
        return nil
    end

    local jj_root = get_jj_root()

    if jj_root == nil then
        return nil
    end

    local branch = M.get_os_command_output({
        "jj",
        "--ignore-working-copy",
        "log",
        "-r",
        "heads(::@ & bookmarks())",
        "--no-graph",
        "-T",
        "bookmarks",
    }, jj_root)[1]

    if is_non_empty(branch) then
        return branch
    end
end

function M.project_key()
    return vim.loop.cwd()
end

function M.clear_branch_key_cache()
    branch_key_cache = {}
end

function M.branch_key()
    local cwd = vim.loop.cwd()
    local cached_branch_key = branch_key_cache[cwd]

    if cached_branch_key ~= nil then
        return cached_branch_key
    end

    local branch = get_jj_branch()

    if branch == nil then
        branch = get_git_branch()
    end

    local branch_key

    if is_non_empty(branch) then
        branch_key = cwd .. "-" .. branch
    else
        branch_key = cwd
    end

    branch_key_cache[cwd] = branch_key

    return branch_key
end

function M.normalize_path(item)
    return Path:new(item):make_relative(M.project_key())
end

function M.get_os_command_output(cmd, cwd)
    if type(cmd) ~= "table" then
        print("Harpoon: [get_os_command_output]: cmd has to be a table")
        return {}
    end
    local command = table.remove(cmd, 1)
    local stderr = {}
    local stdout, ret = Job
        :new({
            command = command,
            args = cmd,
            cwd = cwd,
            on_stderr = function(_, data)
                table.insert(stderr, data)
            end,
        })
        :sync()
    return stdout, ret, stderr
end

function M.split_string(str, delimiter)
    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

function M.is_white_space(str)
    return str:gsub("%s", "") == ""
end

return M
