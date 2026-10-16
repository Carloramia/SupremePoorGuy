# 构建运行与交付验收

本目录是仓库根，Godot 工程在 `frontier_toolkit/` 内。不要导入仓库根，也不要将工具集配置覆盖到 it-is-time。

## 无引擎的源码检查

安装 Node.js 22，在仓库根运行：

```sh
node frontier_toolkit/tools/Verify-GitHub-Repository.cjs .
cd frontier_toolkit
node tools/Verify-Package.cjs
node tools/Verify-Battle-Integration-Docs.cjs --contracts-only
node editor/tests/model.test.cjs
node editor/tools/Validate-Level.cjs editor/examples/Frontier.mapproject.json
```

首次解压、尚未导入 Godot 或修改文件时，可在仓库根加 `--manifest` 校验交付原始字节。Git 的换行策略或 Godot 重新生成导入元信息后，清单不再代表当前文件；正常 CI 使用不带该参数的源码检查。

## 宿主工程

安装 Godot 4.7.2 标准版，以项目管理器导入 [frontier_toolkit/project.godot](frontier_toolkit/project.godot)，等待资源导入，再 F5。PowerShell：

```powershell
Set-Location frontier_toolkit
$env:GODOT_BIN = 'C:/Apps/Godot/Godot_v4.7.2-stable_win64_console.exe'
./ui_module/tools/Run-Demo.ps1
./world_map/tools/Run-Tests.ps1
./scenario_2_5d/tools/Run-Tests.ps1
./ui_module/tools/Run-Tests.ps1
```

Godot 路径替换为本机安装位置。浏览器编辑器无需 npm：打开 [editor/index.html](frontier_toolkit/editor/index.html)，或在工具集内执行 `node editor/tools/serve.cjs 8765`。

## 两套 Shader 场景

宿主内打开 `ui_module/shader_lab/demo/ShaderLab.tscn`，F6。独立新版工程另行导入 [UI跳转原型_20261015/project.godot](frontier_toolkit/UI跳转原型_20261015/project.godot)，打开 TA/Scenes/ShaderComparison.tscn 或 NativeSkinPreview.tscn 后 F6。

在工具集根执行新版无窗口验证：

```powershell
./UI跳转原型_20261015/Tools/Run-TAShaders.ps1 -GodotPath $env:GODOT_BIN -Tests
```

加 `-Capture` 使用真实 GPU 并重新生成截图；渲染检查不能用 headless 替代。其他入口和关卡转换见 [工具集 BUILD](frontier_toolkit/BUILD.md)。

## 重新生成交接包

从工具集根运行 `./tools/Build-GitHub-Package.ps1 -Name my-handoff-v2`。输出在该工具集的 dist 中，包含仓库文件树、ZIP、ZIP SHA-256。已有目标不覆盖。

这一步仅整理本地文件。上传前按 [整合步骤](docs/INTEGRATING_IN_SUPREMEPOORGUY.md) review；不会自动提交、推送或修改 GitHub PR。
