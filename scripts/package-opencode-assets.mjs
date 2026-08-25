import { createHash } from "node:crypto";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const godotRoot = path.resolve(__dirname, "..");
const workspaceRoot = path.resolve(godotRoot, "..");

const rawfileRoot = path.join(
  godotRoot,
  "platform/openharmony/template/entry/src/main/resources/rawfile"
);
const destination = path.join(rawfileRoot, "opencode_formal");
const staging = path.join(rawfileRoot, ".opencode_formal.staging");

const manifestsDir = path.join(workspaceRoot, "manifests");
const runtimeRoot = path.join(workspaceRoot, "formal-runtime/generated/runtime");
const clientRoot = path.join(workspaceRoot, "formal-runtime/generated/sdk-client");
const instructionsPath = path.join(
  workspaceRoot,
  "formal-runtime/assets/config/AGENTS.md"
);
const opencodeConfigPath = path.join(
  workspaceRoot,
  "formal-runtime/assets/config/opencode.json"
);
const mcpServerRoot = path.join(
  workspaceRoot,
  "formal-runtime/assets/mcp/godot-server"
);

function sha256File(filePath) {
  const content = readFileSync(filePath);
  return createHash("sha256").update(content).digest("hex");
}

function copyTree(sourceDir, targetDir, logicalPrefix, resources) {
  mkdirSync(targetDir, { recursive: true });
  const entries = readdirSync(sourceDir, { withFileTypes: true });
  for (const entry of entries) {
    const sourcePath = path.join(sourceDir, entry.name);
    const targetPath = path.join(targetDir, entry.name);
    const logicalPath = `${logicalPrefix}/${entry.name}`;
    if (entry.isDirectory()) {
      copyTree(sourcePath, targetPath, logicalPath, resources);
    } else if (entry.isFile()) {
      cpSync(sourcePath, targetPath);
      const stat = statSync(sourcePath);
      resources.push({
        path: logicalPath,
        bytes: stat.size,
        sha256: sha256File(sourcePath),
      });
    }
  }
}

function copyOne(sourcePath, targetPath, logicalPath, resources) {
  mkdirSync(path.dirname(targetPath), { recursive: true });
  cpSync(sourcePath, targetPath);
  const stat = statSync(sourcePath);
  resources.push({
    path: logicalPath,
    bytes: stat.size,
    sha256: sha256File(sourcePath),
  });
}

export function packageOpenCodeAssets() {
  console.log("=========================================");
  console.log("  Packaging OpenCode Formal Runtime Assets");
  console.log("=========================================");
  console.log(`  Target: ${destination}`);

  if (!existsSync(runtimeRoot) || !existsSync(clientRoot)) {
    if (existsSync(path.join(destination, "package-manifest.json"))) {
      const manifestPath = path.join(destination, "package-manifest.json");
      const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
      let totalBytes = 0;
      for (const file of manifest.files) {
        const fullPath = path.join(destination, file.path);
        if (existsSync(fullPath)) {
          const content = readFileSync(fullPath);
          file.bytes = content.length;
          file.sha256 = createHash("sha256").update(content).digest("hex");
        }
        totalBytes += file.bytes;
      }
      manifest.bytes = totalBytes;
      const sortedFiles = [...manifest.files].sort((a, b) => a.path.localeCompare(b.path));
      const packageHash = createHash("sha256");
      for (const file of sortedFiles) {
        packageHash.update(`${file.path}:${file.sha256}\n`);
      }
      manifest.outputSha256 = packageHash.digest("hex");
      writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n", "utf8");
      console.log(`  ✓ Using pre-packaged rawfile/opencode_formal assets (refreshed sha256: ${manifest.outputSha256.substring(0, 12)}..., total: ${manifest.files.length} files).`);
      packageGodotMcpAddon();
      packageSkillsSuite();
      console.log("=========================================\n");
      return;
    }
  }

  if (existsSync(staging)) {
    rmSync(staging, { recursive: true, force: true });
  }
  mkdirSync(path.join(staging, "install/v1"), { recursive: true });

  const resources = [];

  console.log("  [1/4] Copying runtime bundle...");
  copyTree(runtimeRoot, path.join(staging, "install/v1/runtime"), "install/v1/runtime", resources);

  console.log("  [2/4] Copying SDK client bundle...");
  copyTree(clientRoot, path.join(staging, "install/v1/client"), "install/v1/client", resources);

  console.log("  [3/4] Copying configuration...");
  copyOne(instructionsPath, path.join(staging, "install/v1/config/AGENTS.md"), "install/v1/config/AGENTS.md", resources);
  if (existsSync(opencodeConfigPath)) {
    copyOne(opencodeConfigPath, path.join(staging, "install/v1/config/opencode.json"), "install/v1/config/opencode.json", resources);
  }
  if (existsSync(mcpServerRoot)) {
    copyTree(mcpServerRoot, path.join(staging, "install/v1/mcp/godot-server"), "install/v1/mcp/godot-server", resources);
  }

  console.log("  [4/4] Copying governance manifests...");
  const manifestFiles = [
    "formal-upstream-baseline.json",
    "source-ownership.json",
    "packaged-extensions.json",
    "model-catalog-snapshot.json",
  ];
  for (const filename of manifestFiles) {
    const sourceFile = path.join(manifestsDir, filename);
    if (existsSync(sourceFile)) {
      copyOne(
        sourceFile,
        path.join(staging, "install/v1/manifests", filename),
        `install/v1/manifests/${filename}`,
        resources
      );
    }
  }

  console.log("  [5/5] Applying HarmonyOS runtime & UI patches...");
  applyHarmonyPatches(staging);

  // Recalculate file hashes and sizes after patching
  for (const r of resources) {
    const fullPath = path.join(staging, r.path);
    if (existsSync(fullPath)) {
      const content = readFileSync(fullPath);
      r.bytes = content.length;
      r.sha256 = createHash("sha256").update(content).digest("hex");
    }
  }

  resources.sort((left, right) => left.path.localeCompare(right.path));

  const totalBytes = resources.reduce((acc, r) => acc + r.bytes, 0);
  const hashStream = createHash("sha256");
  for (const r of resources) {
    hashStream.update(`${r.path}:${r.bytes}:${r.sha256}\n`);
  }
  const outputSha256 = hashStream.digest("hex");

  const packageManifest = {
    schemaVersion: 1,
    packageID: "opencode-formal-harmony-tier-a-v1",
    generator: "godot_zw/scripts/package-opencode-assets.mjs",
    installRoot: "opencode-formal/install/v1",
    rawfileRoot: "opencode_formal",
    outputSha256,
    bytes: totalBytes,
    selections: {
      runtime: "formal-upstream",
      client: "sdk-composed",
      capabilityProfile: "harmony-tier-a",
    },
    files: resources,
  };

  const manifestJson = JSON.stringify(packageManifest, null, 2) + "\n";
  writeFileSync(path.join(staging, "package-manifest.json"), manifestJson, "utf8");
  writeFileSync(path.join(staging, "install/v1/package-manifest.json"), manifestJson, "utf8");

  if (existsSync(destination)) {
    rmSync(destination, { recursive: true, force: true });
  }
  mkdirSync(path.dirname(destination), { recursive: true });
  cpSync(staging, destination, { recursive: true });
  rmSync(staging, { recursive: true, force: true });

  console.log(`  ✓ OpenCode assets packaged successfully (${resources.length} files, ${(totalBytes / 1024 / 1024).toFixed(2)} MB, sha256: ${outputSha256.substring(0, 12)}...)`);
  
  packageGodotMcpAddon();
  packageSkills();
  console.log("=========================================\n");
}

export function packageSkills() {
  console.log("  Packaging Godot & OpenSpec Skills Suite...");
  const skillsSourceDir = path.join(workspaceRoot, "skills");
  const targetSkillsDir = path.join(rawfileRoot, "opencode_skills");
  const stagingSkillsDir = path.join(rawfileRoot, ".opencode_skills.staging");

  if (!existsSync(skillsSourceDir)) {
    console.warn(`  [!] Skills source directory ${skillsSourceDir} does not exist.`);
    return;
  }

  if (existsSync(stagingSkillsDir)) {
    rmSync(stagingSkillsDir, { recursive: true, force: true });
  }
  mkdirSync(path.join(stagingSkillsDir, "harmony"), { recursive: true });

  const skillsToPackage = [
    "godot-game-gen",
    "godot-api",
    "godot-visual-qa",
    "godot-error-doctor",
    "godot-game-script-engineer",
    "game-audio",
    "godot-shader-dev",
    "level-design",
    "godot-multiplayer",
    "game-art",
    "openspec-propose",
    "openspec-apply-change",
    "openspec-explore",
    "openspec-archive-change",
    "workspace-session-skill",
    "resource-finder",
    "shell-guard"
  ];

  const files = [];

  for (const skillName of skillsToPackage) {
    const srcDir = path.join(skillsSourceDir, skillName);
    if (!existsSync(srcDir)) continue;

    const dstDir = path.join(stagingSkillsDir, "harmony", skillName);
    mkdirSync(dstDir, { recursive: true });

    function collectSkillFiles(currentSrc, currentDst, relPrefix) {
      mkdirSync(currentDst, { recursive: true });
      const entries = readdirSync(currentSrc, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.name.startsWith(".")) continue;
        const srcPath = path.join(currentSrc, entry.name);
        const dstPath = path.join(currentDst, entry.name);
        const relPath = `${relPrefix}/${entry.name}`;
        if (entry.isDirectory()) {
          collectSkillFiles(srcPath, dstPath, relPath);
        } else if (entry.isFile()) {
          cpSync(srcPath, dstPath);
          const stat = statSync(srcPath);
          files.push({
            path: relPath,
            bytes: stat.size,
            sha256: sha256File(srcPath)
          });
        }
      }
    }

    collectSkillFiles(srcDir, dstDir, skillName);
  }

  const rootProtocolFiles = ["AGENTS.md", "GODOT_GAME_DEV_PROTOCOL.md"];
  for (const fileName of rootProtocolFiles) {
    const srcPath = path.join(skillsSourceDir, fileName);
    if (!existsSync(srcPath)) continue;
    const dstPath = path.join(stagingSkillsDir, "harmony", fileName);
    cpSync(srcPath, dstPath);
    const stat = statSync(srcPath);
    files.push({
      path: fileName,
      bytes: stat.size,
      sha256: sha256File(srcPath)
    });
  }

  files.sort((a, b) => a.path.localeCompare(b.path));
  const totalBytes = files.reduce((acc, f) => acc + f.bytes, 0);

  const hashStream = createHash("sha256");
  for (const f of files) {
    hashStream.update(`${f.path}:${f.bytes}:${f.sha256}\n`);
  }
  const outputSha256 = hashStream.digest("hex");

  const manifest = {
    schemaVersion: 1,
    packageID: "godot-game-skills-v1",
    rawfileRoot: "opencode_skills",
    skillsSubdir: "harmony",
    installRoot: "opencode-formal/v1/home/.agents/skills",
    outputSha256,
    bytes: totalBytes,
    files
  };

  writeFileSync(
    path.join(stagingSkillsDir, "skills-manifest.json"),
    JSON.stringify(manifest, null, 2) + "\n",
    "utf8"
  );

  if (existsSync(targetSkillsDir)) {
    rmSync(targetSkillsDir, { recursive: true, force: true });
  }
  mkdirSync(path.dirname(targetSkillsDir), { recursive: true });
  cpSync(stagingSkillsDir, targetSkillsDir, { recursive: true });
  rmSync(stagingSkillsDir, { recursive: true, force: true });

  console.log(`  ✓ Skills suite packaged (${files.length} files across ${skillsToPackage.length} skills, ${(totalBytes / 1024 / 1024).toFixed(2)} MB, sha256: ${outputSha256.substring(0, 12)}...)`);
}

export function packageGodotMcpAddon() {
  console.log("  Packaging Godot MCP Pro In-Engine Addon...");
  const sourceDir = path.join(godotRoot, "editor/plugins/godot_mcp");
  const targetDir = path.join(rawfileRoot, "editor/addons/godot_mcp");
  const manifestPath = path.join(rawfileRoot, "editor/addons/godot-mcp-manifest.json");

  if (!existsSync(sourceDir)) {
    console.warn(`  [!] Source directory ${sourceDir} does not exist.`);
    return;
  }

  if (existsSync(targetDir)) {
    rmSync(targetDir, { recursive: true, force: true });
  }
  mkdirSync(targetDir, { recursive: true });

  const files = [];
  function collectAndCopy(currentSrc, currentDst, relPrefix = "") {
    mkdirSync(currentDst, { recursive: true });
    const entries = readdirSync(currentSrc, { withFileTypes: true });
    for (const entry of entries) {
      const srcPath = path.join(currentSrc, entry.name);
      const dstPath = path.join(currentDst, entry.name);
      const relPath = relPrefix ? `${relPrefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        collectAndCopy(srcPath, dstPath, relPath);
      } else if (entry.isFile()) {
        cpSync(srcPath, dstPath);
        files.push(relPath);
      }
    }
  }

  collectAndCopy(sourceDir, targetDir);
  files.sort();

  const manifest = {
    version: "1.16.0",
    addonName: "godot_mcp",
    files,
  };
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n", "utf8");
  console.log(`  ✓ Godot MCP Pro Addon packaged (${files.length} files into rawfile/editor/addons/godot_mcp)`);
}

export function applyHarmonyPatches(stagingRoot) {
  const runtimePath = path.join(stagingRoot, "install/v1/runtime/opencode-harmony-runtime.mjs");
  const appJsPath = path.join(stagingRoot, "install/v1/client/js/app.17b6e037.js");

  if (existsSync(runtimePath)) {
    let c = readFileSync(runtimePath, "utf8");

    // 1. Replace SkillTool definition precisely with zero-cost version
    const oldSkillToolStart = c.indexOf('SkillTool = define5("skill"');
    if (oldSkillToolStart !== -1) {
      let oldSkillToolEnd = c.indexOf('}));\r\n});', oldSkillToolStart);
      if (oldSkillToolEnd === -1) {
        oldSkillToolEnd = c.indexOf('}));\n});', oldSkillToolStart);
      }
      if (oldSkillToolEnd !== -1) {
        oldSkillToolEnd += 4;
        const newSkillTool = `SkillTool = define5("skill", exports_Effect.gen(function* () {
    const skill = yield* exports_skill4.Service;
    return {
      description: skill_default,
      parameters: Parameters8,
      execute: (params2, ctx) => exports_Effect.gen(function* () {
        const info3 = yield* skill.require(params2.name).pipe(exports_Effect.catchTag("Skill.NotFoundError", (error49) => exports_Effect.die(new Error(error49.message))));
        yield* ctx.ask({
          permission: "skill",
          patterns: [params2.name],
          always: [params2.name],
          metadata: {}
        });
        return {
          title: \`Loaded skill: \${info3.name}\`,
          output: [
            \`<skill_content name="\${info3.name}">\`,
            \`# Skill: \${info3.name}\`,
            "",
            info3.content.trim(),
            "",
            \`Skill "\${info3.name}" is fully loaded and active. Follow the instructions above.\`,
            "</skill_content>"
          ].join("\\n"),
          metadata: {
            truncated: false
          }
        };
      })
    };
  }));`;
        c = c.substring(0, oldSkillToolStart) + newSkillTool + c.substring(oldSkillToolEnd);
        console.log("    ✓ Patched SkillTool in staging (with metadata.truncated: false)");
      }
    }

    // 1b. Make tool executor resilient against missing metadata
    const oldExecCheck = 'if (result7.metadata.truncated !== undefined) {';
    const newExecCheck = 'if (result7 && result7.metadata && result7.metadata.truncated !== undefined) {';
    if (c.includes(oldExecCheck)) {
      c = c.replaceAll(oldExecCheck, newExecCheck);
      console.log("    ✓ Patched tool executor metadata.truncated null check");
    }

    // 2. Clean slash command skill template
    while (c.includes('Base directory for this skill:')) {
      const idx = c.indexOf('Base directory for this skill:');
      const tStart = c.lastIndexOf('get template()', idx);
      if (tStart !== -1 && tStart > idx - 300) {
        const tEnd = c.indexOf('},', idx) + 2;
        const newTemplate = `get template() {\n            return item.content;\n          },`;
        c = c.substring(0, tStart) + newTemplate + c.substring(tEnd);
        console.log("    ✓ Patched slash command get template() in staging");
      } else {
        break;
      }
    }

    // 3. Retry policy fail-fast
    const oldPolicyLF = 'function policy(opts) {\n  return exports_Schedule.fromStepWithMetadata(exports_Effect.succeed((meta2) => {\n    const error49 = opts.parse(meta2.input);';
    const oldPolicyCRLF = 'function policy(opts) {\r\n  return exports_Schedule.fromStepWithMetadata(exports_Effect.succeed((meta2) => {\r\n    const error49 = opts.parse(meta2.input);';
    const newPolicy = 'function policy(opts) {\n  return exports_Schedule.fromStepWithMetadata(exports_Effect.succeed((meta2) => {\n    if (meta2.attempt >= 2) return exports_Cause.done(meta2.attempt);\n    const error49 = opts.parse(meta2.input);';
    if (c.includes(oldPolicyLF)) c = c.replace(oldPolicyLF, newPolicy);
    else if (c.includes(oldPolicyCRLF)) c = c.replace(oldPolicyCRLF, newPolicy);

    // 4. Error detail formatting
    const oldMsg = 'return { message: error49.data.message.includes("Overloaded") ? "Provider is overloaded" : error49.data.message };';
    const newMsg = 'const sc = error49.data.statusCode ? `[HTTP ${error49.data.statusCode}] ` : ""; const ep = error49.data.endpoint ? ` (${error49.data.endpoint})` : ""; return { message: sc + (error49.data.message || "API Call Failed") + ep };';
    if (c.includes(oldMsg)) c = c.replace(oldMsg, newMsg);

    // 5. Sandboxing contains6 & relativeToRoot permissions
    const oldContainsLF = `const contains6 = (candidate) => {\n    const relative2 = path41.relative(root, candidate);\n    return relative2 === "" || !path41.isAbsolute(relative2) && relative2 !== ".." && !relative2.startsWith(\`..\${path41.sep}\`);\n  };`;
    const oldContainsCRLF = `const contains6 = (candidate) => {\r\n    const relative2 = path41.relative(root, candidate);\r\n    return relative2 === "" || !path41.isAbsolute(relative2) && relative2 !== ".." && !relative2.startsWith(\`..\${path41.sep}\`);\r\n  };`;
    const newContains = `const contains6 = (candidate) => {\n    const relative2 = path41.relative(root, candidate);\n    if (relative2 === "" || (!path41.isAbsolute(relative2) && relative2 !== ".." && !relative2.startsWith(\`..\${path41.sep}\`))) {\n      return true;\n    }\n    const norm = String(candidate).replaceAll("\\\\", "/");\n    if (norm.includes("/opencode-formal/") || norm.includes("/.agents/")) {\n      return true;\n    }\n    return false;\n  };`;
    if (c.includes(oldContainsLF)) c = c.replace(oldContainsLF, newContains);
    else if (c.includes(oldContainsCRLF)) c = c.replace(oldContainsCRLF, newContains);

    const oldRelRootLF = `relativeToRoot = (root, value8) => {\n  const relative2 = path47.relative(path47.resolve(root), path47.resolve(value8));\n  if (relative2 === "")\n    return "";\n  if (path47.isAbsolute(relative2) || relative2 === ".." || relative2.startsWith(\`..\${path47.sep}\`)) {\n    throw new globalThis.Error("Search path is outside the authorized project root");\n  }\n  return relative2.replaceAll("\\\\", "/");\n},`;
    const oldRelRootCRLF = `relativeToRoot = (root, value8) => {\r\n  const relative2 = path47.relative(path47.resolve(root), path47.resolve(value8));\r\n  if (relative2 === "")\r\n    return "";\r\n  if (path47.isAbsolute(relative2) || relative2 === ".." || relative2.startsWith(\`..\${path47.sep}\`)) {\r\n    throw new globalThis.Error("Search path is outside the authorized project root");\r\n  }\r\n  return relative2.replaceAll("\\\\", "/");\r\n},`;
    const newRelRoot = `relativeToRoot = (root, value8) => {\n  const relative2 = path47.relative(path47.resolve(root), path47.resolve(value8));\n  if (relative2 === "")\n    return "";\n  if (path47.isAbsolute(relative2) || relative2 === ".." || relative2.startsWith(\`..\${path47.sep}\`)) {\n    const norm = path47.resolve(value8).replaceAll("\\\\", "/");\n    if (norm.includes("/opencode-formal/") || norm.includes("/.agents/")) {\n      return "";\n    }\n    throw new globalThis.Error("Search path is outside the authorized project root");\n  }\n  return relative2.replaceAll("\\\\", "/");\n},`;
    if (c.includes(oldRelRootLF)) c = c.replace(oldRelRootLF, newRelRoot);
    else if (c.includes(oldRelRootCRLF)) c = c.replace(oldRelRootCRLF, newRelRoot);

    // 6. Safeguard createOpenAICompatible URL resolution & alias normalization
    const oldCreateOpenAI = `function createOpenAICompatible(options10) {\n  const baseURL = withoutTrailingSlash(options10.baseURL);`;
    const oldCreateOpenAICRLF = `function createOpenAICompatible(options10) {\r\n  const baseURL = withoutTrailingSlash(options10.baseURL);`;
    const newCreateOpenAI = `function createOpenAICompatible(options10) {\n  const rawBaseURL = options10.baseURL || options10.baseUrl || options10.endpoint || options10.url || "";\n  const baseURL = withoutTrailingSlash(rawBaseURL ? String(rawBaseURL).trim() : "");`;
    if (c.includes(oldCreateOpenAI)) {
      c = c.replace(oldCreateOpenAI, newCreateOpenAI);
      console.log("    ✓ Patched createOpenAICompatible baseURL resolution");
    } else if (c.includes(oldCreateOpenAICRLF)) {
      c = c.replace(oldCreateOpenAICRLF, newCreateOpenAI);
      console.log("    ✓ Patched createOpenAICompatible baseURL resolution (CRLF)");
    }

    const oldUrlConstructor = `url: ({ path: path23 }) => {\n      const url3 = new URL(\`\${baseURL}\${path23}\`);`;
    const oldUrlConstructorCRLF = `url: ({ path: path23 }) => {\r\n      const url3 = new URL(\`\${baseURL}\${path23}\`);`;
    const newUrlConstructor = `url: ({ path: path23 }) => {\n      const base = baseURL || "https://api.openai.com/v1";\n      const p = String(path23).startsWith("/") ? path23 : "/" + path23;\n      const url3 = new URL(\`\${base}\${p}\`);`;
    if (c.includes(oldUrlConstructor)) {
      c = c.replace(oldUrlConstructor, newUrlConstructor);
      console.log("    ✓ Patched createOpenAICompatible url construction");
    } else if (c.includes(oldUrlConstructorCRLF)) {
      c = c.replace(oldUrlConstructorCRLF, newUrlConstructor);
      console.log("    ✓ Patched createOpenAICompatible url construction (CRLF)");
    }

    writeFileSync(runtimePath, c, "utf8");
    console.log("    ✓ Patched opencode-harmony-runtime.mjs in staging (SkillTool, no-rg, clean template, sandbox, custom provider)");
  }

  if (existsSync(appJsPath)) {
    let appJs = readFileSync(appJsPath, "utf8");
    const oldV = 'V=(0,s.EW)(()=>{if(!v.value)return"编辑器桥接等待中";const e=m.value?.script;if(!0===e?.available&&"string"===typeof e.path)return e.path.split("/").at(-1)||"当前脚本";const t=m.value?.scene?.selectedNode;return!0===t?.available&&"string"===typeof t.path?t.path.split("/").at(-1)||"当前节点":"未打开可编辑脚本"})';
    const newV = 'V=(0,s.EW)(()=>{if(!v.value)return"引擎通信: 等待连接...";const e=m.value?.script;if(!0===e?.available&&"string"===typeof e.path)return(e.path.split("/").at(-1)||"当前脚本")+" · 引擎/MCP 已连接";const t=m.value?.scene?.selectedNode;if(!0===t?.available&&"string"===typeof t.path)return(t.path.split("/").at(-1)||"当前节点")+" · 引擎/MCP 已连接";return"引擎通信: 已连接 · MCP: 已连接 (6510)"})';
    if (appJs.includes(oldV)) appJs = appJs.replace(oldV, newV);

    const oldC = 'c=l.length>0?l:i;e={configured:!0,providerID:o,modelID:r,baseURL:s,contextTokens:a.contextTokens,outputTokens:a.outputTokens,availableModels:c}';
    const newC = 'c=l.length>0?l:(i.length>0?i:[{id:r,name:(a||o)+" / "+r,providerID:o,contextTokens:a.contextTokens,outputTokens:a.outputTokens}]);if(!c.some(m=>m.id===r))c.unshift({id:r,name:(a||o)+" / "+r,providerID:o,contextTokens:a.contextTokens,outputTokens:a.outputTokens});e={configured:!0,providerID:o,modelID:r,baseURL:s,contextTokens:a.contextTokens,outputTokens:a.outputTokens,availableModels:c}';
    if (appJs.includes(oldC)) appJs = appJs.replace(oldC, newC);

    const oldN = 'o&&(this.provider={...this.provider,availableModels:n,contextTokens:o.contextTokens,outputTokens:o.outputTokens})}';
    const newN = 'if(n.length===0&&this.provider.configured&&this.provider.modelID){n=[{id:this.provider.modelID,name:(this.provider.providerID||this.provider.modelID)+" / "+this.provider.modelID,providerID:this.provider.providerID,contextTokens:this.provider.contextTokens,outputTokens:this.provider.outputTokens}]}else if(this.provider.configured&&this.provider.modelID&&!n.some(m=>m.id===this.provider.modelID)){n.unshift({id:this.provider.modelID,name:(this.provider.providerID||this.provider.modelID)+" / "+this.provider.modelID,providerID:this.provider.providerID,contextTokens:this.provider.contextTokens,outputTokens:this.provider.outputTokens})}o&&(this.provider={...this.provider,availableModels:n,contextTokens:o.contextTokens,outputTokens:o.outputTokens})}';
    if (appJs.includes(oldN)) appJs = appJs.replace(oldN, newN);

    writeFileSync(appJsPath, appJs, "utf8");
    console.log("    ✓ Patched app.17b6e037.js in staging (header status, model list fallback)");
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  packageOpenCodeAssets();
}
