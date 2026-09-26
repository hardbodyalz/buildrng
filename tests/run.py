#!/usr/bin/env python3
"""
Headless test runner for the pure (instance-free) Luau modules.

Roblox modules use `require(script.Parent.X)` and
`game:GetService("ReplicatedStorage"):WaitForChild("Shared")`. This script
bundles every .luau file under src/ into one chunk with a tiny fake
`script`/`game` object model that maps those instance paths back to files,
then appends each tests/*.spec.luau and runs it with the `luau` CLI.

Usage:  python3 tests/run.py [path/to/luau] [spec-name-filter]
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Rojo mapping (mirror of default.project.json)
MOUNTS = {
    "src/shared": "ReplicatedStorage/Shared",
    "src/server": "ServerScriptService/Server",
    "src/client": "StarterPlayer/StarterPlayerScripts/Client",
}

PRELUDE = r'''
local __sources = {}
local __cache = {}
local __proxies = {}

local function __proxy(path)
    local p = __proxies[path]
    if p then return p end
    p = setmetatable({ __path = path }, {
        __index = function(self, key)
            if key == "Parent" then
                local parent = string.match(path, "^(.*)/[^/]+$")
                return __proxy(parent or "")
            elseif key == "Name" then
                return string.match(path, "([^/]+)$")
            elseif key == "WaitForChild" or key == "FindFirstChild" then
                return function(_, name) return __proxy(path .. "/" .. name) end
            elseif key == "GetService" then
                return function(_, name) return __proxy(name) end
            end
            return __proxy(path .. "/" .. key)
        end,
    })
    __proxies[path] = p
    return p
end

game = __proxy("")

function require(target)
    local path = target.__path
    if __cache[path] ~= nil then return __cache[path] end
    local fn = __sources[path]
    assert(fn, "module not found: " .. tostring(path))
    local result = fn(__proxy(path))
    __cache[path] = result
    return result
end

-- minimal test framework
local __passed, __failed = 0, 0
function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        __passed += 1
        print("  pass  " .. name)
    else
        __failed += 1
        print("  FAIL  " .. name .. "\n        " .. tostring(err))
    end
end
function check(cond, msg)
    if not cond then error(msg or "check failed", 2) end
end
function checkEq(a, b, msg)
    if a ~= b then error((msg or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
function summary()
    print(string.format("  %d passed, %d failed", __passed, __failed))
end
Shared = game:GetService("ReplicatedStorage").Shared
Server = game:GetService("ServerScriptService").Server
'''


def module_path(rel_file):
    for src, mount in MOUNTS.items():
        if rel_file.startswith(src + "/"):
            inner = rel_file[len(src) + 1:]
            inner = inner.rsplit(".", 1)[0]
            if inner.endswith(".server") or inner.endswith(".client"):
                inner = inner.rsplit(".", 1)[0]
            if inner == "init":
                return mount
            if inner.endswith("/init"):
                inner = inner[: -len("/init")]
            return mount + "/" + inner
    return None


def bundle():
    parts = [PRELUDE]
    for src in MOUNTS:
        for dirpath, _, files in os.walk(os.path.join(ROOT, src)):
            for f in sorted(files):
                if not f.endswith(".luau"):
                    continue
                full = os.path.join(dirpath, f)
                rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
                mpath = module_path(rel)
                with open(full, encoding="utf-8") as fh:
                    code = fh.read()
                # strip --!strict etc. (only valid at file top)
                lines = [l for l in code.split("\n") if not l.startswith("--!")]
                code = "\n".join(lines)
                parts.append(
                    "__sources[%r] = function(script)\n%s\nend\n" % (mpath, code)
                )
    return "\n".join(parts)


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    flt = sys.argv[2] if len(sys.argv) > 2 else ""
    base = bundle()
    specs = sorted(
        f for f in os.listdir(os.path.join(ROOT, "tests")) if f.endswith(".spec.luau") and flt in f
    )
    failed = 0
    out_dir = os.path.join(ROOT, "tests", ".build")
    os.makedirs(out_dir, exist_ok=True)
    for spec in specs:
        with open(os.path.join(ROOT, "tests", spec), encoding="utf-8") as fh:
            body = fh.read()
        mock = ""
        if spec.startswith("server"):
            with open(os.path.join(ROOT, "tests", "mock", "Roblox.luau"), encoding="utf-8") as fh:
                mock = "\n-- ==== Roblox mock ====\n" + fh.read() + "\n"
        chunk = base + mock + "\n-- ==== " + spec + " ====\n" + "do\n" + body + "\nend\n"
        out = os.path.join(out_dir, spec.replace(".spec.luau", ".bundle.luau"))
        with open(out, "w", encoding="utf-8") as fh:
            fh.write(chunk)
        res = subprocess.run([luau, out], capture_output=True, text=True)
        sys.stdout.write(res.stdout)
        if res.returncode != 0 or "FAIL" in res.stdout:
            failed += 1
            sys.stdout.write(res.stderr)
            print("[x] %s FAILED" % spec)
        else:
            print("[ok] %s" % spec)
    if failed:
        print("%d spec file(s) failed" % failed)
        sys.exit(1)


if __name__ == "__main__":
    main()
