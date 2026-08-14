import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';

const DOMAIN = 0x3201;
const TAG = 'DotNetSmoke';
const RAWFILE_ROOTS: string[] = ['dotnet-runtime', 'i3DSharp', 'i3d-inproc-compiler'];
// v8 起 marker 迁到 dotnet-runtime/ 下（原宿主 dotnet-smoke/ 已随诊断载荷一并移除）
const MARKER = 'dotnet-runtime/.installed-v8';

/**
 * .NET 运行时资源解包器：把 rawfile 中的 dotnet-runtime/（托管框架布局）
 * 与 i3DSharp/（引擎 API 程序集：i3DPlugins.dll + runtimeconfig + i3DSharp.dll +
 * i3DSharpEditor.dll，取自 6.2.0-rc 参考安装；同目录附带 i3D.SourceGenerators.dll，
 * 供进程内编译驱动按 ApiDir 约定定位）解到应用 files 目录。
 * v6 新增 i3d-inproc-compiler/（进程内 Roslyn 编译驱动 + CodeAnalysis 依赖），
 * 解包后落位 files/i3d-inproc-compiler/。
 * v8 移除 G2/T2.4 诊断载荷 dotnet-smoke/、g3/、g3-project/（T3 正式化后随
 * smoke/replay harness 一并退役），marker 升级强制设备端重解包。
 * 完成标记最后写入，中断的安装不会被误认为可用状态。
 */
export class DotNetSmokeInstaller {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  public isInstalled(): boolean {
    return fs.accessSync(`${this.context.filesDir}/${MARKER}`);
  }

  public ensureInstalled(): void {
    if (this.isInstalled()) {
      hilog.info(DOMAIN, TAG, 'dotnet smoke assets already installed, skip');
      return;
    }
    for (const root of RAWFILE_ROOTS) {
      this.extractDir(root, root);
    }
    const markerPath = `${this.context.filesDir}/${MARKER}`;
    const fd = fs.openSync(markerPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(fd.fd, new Date().toISOString());
    fs.closeSync(fd);
    hilog.info(DOMAIN, TAG, 'dotnet smoke assets installed to %{public}s', this.context.filesDir);
  }

  private extractDir(rawPath: string, relOut: string): void {
    const entries = this.context.resourceManager.getRawFileListSync(rawPath);
    for (const name of entries) {
      const childRaw = `${rawPath}/${name}`;
      const childOut = `${relOut}/${name}`;
      let children: string[] = [];
      try {
        children = this.context.resourceManager.getRawFileListSync(childRaw);
      } catch (e) {
        children = [];
      }
      if (children.length > 0) {
        this.extractDir(childRaw, childOut);
      } else {
        this.extractFile(childRaw, childOut);
      }
    }
  }

  private extractFile(rawPath: string, relOut: string): void {
    const outPath = `${this.context.filesDir}/${relOut}`;
    const parent = outPath.substring(0, outPath.lastIndexOf('/'));
    // mkdirSync(recursion=true) 在目录已存在时仍抛 13900015(EEXIST)，先判存在再创建
    if (!fs.accessSync(parent)) {
      fs.mkdirSync(parent, true);
    }
    const content = this.context.resourceManager.getRawFileContentSync(rawPath);
    const fd = fs.openSync(outPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(fd.fd, content.buffer);
    } finally {
      fs.closeSync(fd);
    }
  }
}
