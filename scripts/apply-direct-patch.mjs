import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const runtimePath = path.resolve('godot_zw/platform/openharmony/template/entry/src/main/resources/rawfile/opencode_formal/install/v1/runtime/opencode-harmony-runtime.mjs');
let c = fs.readFileSync(runtimePath, 'utf8');

// Replace SkillTool definition precisely
const oldSkillToolStart = c.indexOf('SkillTool = define5("skill", exports_Effect.gen(function* () {');
console.log('SkillTool definition at:', oldSkillToolStart);
if (oldSkillToolStart !== -1) {
  const oldSkillToolEnd = c.indexOf('}));\n});', oldSkillToolStart) + 4;
  console.log('SkillTool end at:', oldSkillToolEnd);
  
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
          ].join("\\n")
        };
      })
    };
  }));`;

  c = c.substring(0, oldSkillToolStart) + newSkillTool + c.substring(oldSkillToolEnd);
  console.log('✓ Successfully replaced SkillTool definition cleanly!');
}

// 2. Clean slash command skill template
const oldTemplateIdx = c.indexOf('Base directory for this skill: ${dir3}');
console.log('Slash command template at:', oldTemplateIdx);
if (oldTemplateIdx !== -1) {
  const tStart = c.lastIndexOf('get template()', oldTemplateIdx);
  const tEnd = c.indexOf('},', oldTemplateIdx) + 2;
  const newTemplate = `get template() {\n            return item.content;\n          },`;
  c = c.substring(0, tStart) + newTemplate + c.substring(tEnd);
  console.log('✓ Successfully cleaned slash command skill template!');
}

fs.writeFileSync(runtimePath, c, 'utf8');

// Verify
const verified = fs.readFileSync(runtimePath, 'utf8');
console.log('Verified Base directory gone:', !verified.includes('Base directory for this skill:'));
console.log('Verified ripgrep in skill tool gone:', !verified.includes('files4 = yield* ripgrep.find('));

// Update package-manifest.json
const manifestPath = path.resolve('godot_zw/platform/openharmony/template/entry/src/main/resources/rawfile/opencode_formal/package-manifest.json');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

let totalBytes = 0;
for (const file of manifest.files) {
  const fullPath = path.resolve('godot_zw/platform/openharmony/template/entry/src/main/resources/rawfile/opencode_formal', file.path);
  if (fs.existsSync(fullPath)) {
    const content = fs.readFileSync(fullPath);
    file.bytes = content.length;
    file.sha256 = crypto.createHash('sha256').update(content).digest('hex');
  }
  totalBytes += file.bytes;
}
manifest.bytes = totalBytes;

// Recompute outputSha256
const sortedFiles = [...manifest.files].sort((a, b) => a.path.localeCompare(b.path));
const packageHash = crypto.createHash('sha256');
for (const file of sortedFiles) {
  packageHash.update(`${file.path}:${file.sha256}\n`);
}
manifest.outputSha256 = packageHash.digest('hex');
console.log('New manifest outputSha256:', manifest.outputSha256, 'total bytes:', manifest.bytes);

fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
console.log('✓ Manifest successfully updated with new hash!');

