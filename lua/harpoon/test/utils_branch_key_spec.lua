local function load_utils(state)
    package.loaded["harpoon.utils"] = nil
    package.loaded["plenary.path"] = {
        new = function()
            return {
                make_relative = function()
                    return ""
                end,
            }
        end,
    }
    package.loaded["plenary.job"] = {
        new = function(_, opts)
            return {
                sync = function()
                    return state.sync(opts)
                end,
            }
        end,
    }

    vim.fn.stdpath = function()
        return "/tmp"
    end
    vim.fn.exists = function()
        return 0
    end
    vim.fn.executable = function(bin)
        if bin == "jj" and state.jj_executable then
            return 1
        end
        return 0
    end
    vim.fn.isdirectory = function(path)
        if path == ".jj" and state.has_jj_dir then
            return 1
        end
        return 0
    end
    vim.loop.cwd = function()
        return "/repo"
    end
    vim.loop.fs_stat = function(path)
        if path == "/repo/.jj" and state.has_jj_dir then
            return { type = "directory" }
        end
    end

    return require("harpoon.utils")
end

local function assert_equals(actual, expected, message)
    if actual ~= expected then
        error((message or "assertion failed") .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
    end
end

local function run()
    do
        local calls = {}
        local utils = load_utils({
            jj_executable = true,
            has_jj_dir = false,
            sync = function(opts)
                table.insert(calls, { command = opts.command, args = opts.args })
                if opts.command == "git" then
                    return { "main" }, 0
                end
                return {}, 0
            end,
        })

        assert_equals(utils.branch_key(), "/repo-main", "git repo should still resolve git branch")
        assert_equals(calls[1].command, "git", "plain git repo should not invoke jj")
    end

    do
        local calls = {}
        local utils = load_utils({
            jj_executable = true,
            has_jj_dir = true,
            sync = function(opts)
                table.insert(calls, { command = opts.command, args = opts.args })
                if opts.command == "jj" then
                    return { "feature" }, 0
                end
                return { "main" }, 0
            end,
        })

        assert_equals(utils.branch_key(), "/repo-feature", "jj repo should prefer jj bookmark")
        assert_equals(calls[1].command, "jj", "jj repo should resolve jj first")
        assert_equals(calls[1].args[1], "--ignore-working-copy", "jj lookup should skip working copy snapshot")
    end

    do
        local calls = {}
        local utils = load_utils({
            jj_executable = true,
            has_jj_dir = true,
            sync = function(opts)
                table.insert(calls, { command = opts.command, args = opts.args })
                if opts.command == "jj" then
                    return {}, 0
                end
                return { "main" }, 0
            end,
        })

        assert_equals(utils.branch_key(), "/repo-main", "jj repo should fall back to git when no jj bookmark matches")
        assert_equals(calls[1].command, "jj", "jj repo should try jj before git")
        assert_equals(calls[2].command, "git", "jj repo should fall back to git after jj miss")
    end

    do
        local calls = {}
        local utils = load_utils({
            jj_executable = true,
            has_jj_dir = true,
            sync = function(opts)
                table.insert(calls, { command = opts.command, args = opts.args })
                if opts.command == "jj" then
                    return { "feature" }, 0
                end
                return { "main" }, 0
            end,
        })

        assert_equals(utils.branch_key(), "/repo-feature", "first lookup should resolve branch key")
        assert_equals(utils.branch_key(), "/repo-feature", "second lookup should return same branch key")
        assert_equals(#calls, 1, "branch lookup should be cached within the same cwd")

        utils.clear_branch_key_cache()
        assert_equals(utils.branch_key(), "/repo-feature", "cache clear should allow branch key lookup again")
        assert_equals(#calls, 2, "cache clear should force a fresh branch lookup")
    end
end

run()
