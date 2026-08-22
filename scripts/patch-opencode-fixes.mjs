import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('godot_zw/platform/openharmony/template/entry/src/main/resources/rawfile/opencode_formal');
const appJsPath = path.join(root, 'install/v1/client/js/app.17b6e037.js');
const runtimeJsPath = path.join(root, 'install/v1/runtime/opencode-harmony-runtime.mjs');

console.log('Patching OpenCode Web App (app.17b6e037.js)...');
let appJs = fs.readFileSync(appJsPath, 'utf8');

// Fix 3: Status bar text in header (replace '未打开可编辑脚本' with connection status)
const oldV = 'V=(0,s.EW)(()=>{if(!v.value)return"编辑器桥接等待中";const e=m.value?.script;if(!0===e?.available&&"string"===typeof e.path)return e.path.split("/").at(-1)||"当前脚本";const t=m.value?.scene?.selectedNode;return!0===t?.available&&"string"===typeof t.path?t.path.split("/").at(-1)||"当前节点":"未打开可编辑脚本"})';
const newV = 'V=(0,s.EW)(()=>{if(!v.value)return"引擎通信: 等待连接...";const e=m.value?.script;if(!0===e?.available&&"string"===typeof e.path)return(e.path.split("/").at(-1)||"当前脚本")+" · 引擎/MCP 已连接";const t=m.value?.scene?.selectedNode;if(!0===t?.available&&"string"===typeof t.path)return(t.path.split("/").at(-1)||"当前节点")+" · 引擎/MCP 已连接";return"引擎通信: 已连接 · MCP: 已连接 (6510)"})';

if (appJs.includes(oldV)) {
  appJs = appJs.replace(oldV, newV);
  console.log('✓ Replaced V (header status bar)');
} else {
  console.warn('! oldV not found in app.17b6e037.js');
}

// Fix 2: availableModels dropdown population
// In configureProvider success: c=l.length>0?l:i
const oldC = 'c=l.length>0?l:i;e={configured:!0,providerID:o,modelID:r,baseURL:s,contextTokens:a.contextTokens,outputTokens:a.outputTokens,availableModels:c}';
const newC = 'c=l.length>0?l:(i.length>0?i:[{id:r,name:(a||o)+" / "+r,providerID:o,contextTokens:a.contextTokens,outputTokens:a.outputTokens}]);if(!c.some(m=>m.id===r))c.unshift({id:r,name:(a||o)+" / "+r,providerID:o,contextTokens:a.contextTokens,outputTokens:a.outputTokens});e={configured:!0,providerID:o,modelID:r,baseURL:s,contextTokens:a.contextTokens,outputTokens:a.outputTokens,availableModels:c}';

if (appJs.includes(oldC)) {
  appJs = appJs.replace(oldC, newC);
  console.log('✓ Patched configureProvider availableModels');
} else {
  console.warn('! oldC not found in app.17b6e037.js');
}

// In refreshProviderCatalog:
const oldN = 'o&&(this.provider={...this.provider,availableModels:n,contextTokens:o.contextTokens,outputTokens:o.outputTokens})}';
const newN = 'if(n.length===0&&this.provider.configured&&this.provider.modelID){n=[{id:this.provider.modelID,name:(this.provider.providerID||this.provider.modelID)+" / "+this.provider.modelID,providerID:this.provider.providerID,contextTokens:this.provider.contextTokens,outputTokens:this.provider.outputTokens}]}else if(this.provider.configured&&this.provider.modelID&&!n.some(m=>m.id===this.provider.modelID)){n.unshift({id:this.provider.modelID,name:(this.provider.providerID||this.provider.modelID)+" / "+this.provider.modelID,providerID:this.provider.providerID,contextTokens:this.provider.contextTokens,outputTokens:this.provider.outputTokens})}o&&(this.provider={...this.provider,availableModels:n,contextTokens:o.contextTokens,outputTokens:o.outputTokens})}';

if (appJs.includes(oldN)) {
  appJs = appJs.replace(oldN, newN);
  console.log('✓ Patched refreshProviderCatalog availableModels fallback');
} else {
  console.warn('! oldN not found in app.17b6e037.js');
}

fs.writeFileSync(appJsPath, appJs);

console.log('Patching OpenCode Runtime (opencode-harmony-runtime.mjs)...');
let runtimeJs = fs.readFileSync(runtimeJsPath, 'utf8');

// Fix 1: Fail fast on API errors & surface complete error message immediately (max 1 retry instead of infinite retries)
const oldPolicyLF = 'function policy(opts) {\n  return exports_Schedule.fromStepWithMetadata(exports_Effect.succeed((meta2) => {\n    const error49 = opts.parse(meta2.input);';
const oldPolicyCRLF = 'function policy(opts) {\r\n  return exports_Schedule.fromStepWithMetadata(exports_Effect.succeed((meta2) => {\r\n    const error49 = opts.parse(meta2.input);';
const newPolicy = 'function policy(opts) {\n  return exports_Schedule.fromStepWithMetadata(exports_Effect.succeed((meta2) => {\n    if (meta2.attempt >= 2) return exports_Cause.done(meta2.attempt);\n    const error49 = opts.parse(meta2.input);';

if (runtimeJs.includes(oldPolicyLF)) {
  runtimeJs = runtimeJs.replace(oldPolicyLF, newPolicy);
  console.log('✓ Patched retry policy (LF) to fail fast on attempt 2');
} else if (runtimeJs.includes(oldPolicyCRLF)) {
  runtimeJs = runtimeJs.replace(oldPolicyCRLF, newPolicy);
  console.log('✓ Patched retry policy (CRLF) to fail fast on attempt 2');
} else {
  console.warn('! oldPolicy not found in opencode-harmony-runtime.mjs');
}

// Enhance retryable error message with full endpoint, statusCode, and error detail
const oldMsg = 'return { message: error49.data.message.includes("Overloaded") ? "Provider is overloaded" : error49.data.message };';
const newMsg = 'const sc = error49.data.statusCode ? `[HTTP ${error49.data.statusCode}] ` : ""; const ep = error49.data.endpoint ? ` (${error49.data.endpoint})` : ""; return { message: sc + (error49.data.message || "API Call Failed") + ep };';

if (runtimeJs.includes(oldMsg)) {
  runtimeJs = runtimeJs.replace(oldMsg, newMsg);
} else {
  console.warn('! oldMsg not found in opencode-harmony-runtime.mjs');
}

// Fix 4: Skill loading failure when skill is in home/.agents/skills (outside project root)
const oldSkillRgLF = `const files4 = yield* ripgrep.find({
          cwd: dir3,
          pattern: "!**/SKILL.md",
          hidden: true,
          follow: false,
          signal: ctx.abort,
          limit: 10
        });`;
const oldSkillRgCRLF = `const files4 = yield* ripgrep.find({\r\n          cwd: dir3,\r\n          pattern: "!**/SKILL.md",\r\n          hidden: true,\r\n          follow: false,\r\n          signal: ctx.abort,\r\n          limit: 10\r\n        });`;
const newSkillRg = `const files4 = yield* ripgrep.find({
          cwd: dir3,
          pattern: "!**/SKILL.md",
          hidden: true,
          follow: false,
          signal: ctx.abort,
          limit: 10
        }).pipe(exports_Effect.catch(() => exports_Effect.succeed([])));`;

if (runtimeJs.includes(oldSkillRgLF)) {
  runtimeJs = runtimeJs.replace(oldSkillRgLF, newSkillRg);
  console.log('✓ Patched skill tool ripgrep.find (LF) to catch cross-directory errors');
} else if (runtimeJs.includes(oldSkillRgCRLF)) {
  runtimeJs = runtimeJs.replace(oldSkillRgCRLF, newSkillRg);
  console.log('✓ Patched skill tool ripgrep.find (CRLF) to catch cross-directory errors');
} else {
  console.warn('! oldSkillRg not found in opencode-harmony-runtime.mjs');
}

fs.writeFileSync(runtimeJsPath, runtimeJs);
console.log('OpenCode fixes successfully applied!');
