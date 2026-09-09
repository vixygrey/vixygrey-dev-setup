import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const extensionPath = Bun.argv[2];
if (!extensionPath) throw new Error("Usage: bun check-omp-protected-paths.ts <extension.ts>");

// The test receives the extracted generated extension at runtime, so a static import cannot name it.
const extension = await import(pathToFileURL(resolve(extensionPath)).href);
const root = mkdtempSync(join(tmpdir(), "omp-protected-paths-"));
const home = join(root, "home");
const cwd = join(root, "repo");
mkdirSync(join(home, ".ssh"), { recursive: true });
mkdirSync(cwd, { recursive: true });
symlinkSync(join(home, ".ssh"), join(cwd, "linked-secrets"));

try {
    const blocked = [
        [".env", "environment secret"],
        [".env.local", "environment secret"],
        [".git/config", "version-control metadata"],
        ["vendor/node_modules/pkg/index.js", "dependency tree"],
        [join(home, ".aws", "credentials"), "credential directory"],
        [join(home, ".config", "gh", "hosts.yml"), "credential file"],
        [join(home, ".omp", "agent", "agent.db:credentials:1"), "omp credential database"],
        ["linked-secrets/config", "credential directory"],
    ] as const;
    for (const [path, reason] of blocked) {
        assert.match(extension.classifyProtectedPath(path, cwd, home) ?? "", new RegExp(reason), path);
    }

    for (const path of [
        ".env.example",
        ".github/workflows/ci.yml",
        "src/app.ts",
        join(home, ".omp", "agent", "config.yml"),
        join(home, ".config", "gh", "config.yml"),
    ]) {
        assert.equal(extension.classifyProtectedPath(path, cwd, home), null, path);
    }

    type Handler = (event: unknown, context: { cwd: string }) => unknown;
    let handler: Handler | undefined;
    extension.default({
        on(event: string, callback: Handler) {
            if (event === "tool_call") handler = callback;
        },
    });
    assert.ok(handler, "tool_call handler was not registered");

    const writeResult = await handler(
        { toolName: "write", input: { path: ".env", content: "SECRET=x" } },
        { cwd },
    );
    assert.deepEqual(writeResult, {
        block: true,
        reason: "Blocked a write to .env. The target is protected: an environment secret file.",
    });

    const editResult = await handler(
        { toolName: "edit", input: { patch: "[.git/config#ABCD]\nPUT 1.=1:\n+blocked" } },
        { cwd },
    );
    assert.deepEqual(editResult, {
        block: true,
        reason: "Blocked a write to .git/config. The target is protected: version-control metadata.",
    });

    const deviceResult = await handler(
        {
            toolName: "write",
            input: {
                path: "xd://ast_edit",
                content: JSON.stringify({ paths: ["node_modules/pkg/index.js"], ops: [] }),
            },
        },
        { cwd },
    );
    assert.deepEqual(deviceResult, {
        block: true,
        reason: "Blocked a write to node_modules/pkg/index.js. The target is protected: the dependency tree.",
    });

    const lspResult = await handler(
        {
            toolName: "lsp",
            input: { action: "rename_file", file: "src/app.ts", new_name: ".env.local" },
        },
        { cwd },
    );
    assert.deepEqual(lspResult, {
        block: true,
        reason: "Blocked a write to .env.local. The target is protected: an environment secret file.",
    });

    const readResult = await handler(
        { toolName: "read", input: { path: ".env" } },
        { cwd },
    );
    assert.equal(readResult, undefined);
} finally {
    rmSync(root, { recursive: true, force: true });
}
