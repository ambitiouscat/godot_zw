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
      console.log("  ✓ Using pre-packaged rawfile/opencode_formal assets from repository.");
      packageGodotMcpAddon();
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

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  packageOpenCodeAssets();
}
