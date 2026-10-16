# 工具集构建运行与验收

当前目录是 Godot 宿主工程根。GitHub 交接包将它放在 `frontier_toolkit/`，仓库根另有总 README、BUILD 和 CI。两个参考 UI 工程保留为当前目录下的独立子工程。

## 环境和入口

- Godot 4.7.2 标准版、GL Compatibility；PowerShell 7；Node.js 22。
- F5：`ui_module/demo/UIWorldMapDemo.tscn`，带 UI 的真实大地图。
- F6：打开 `scenario_2_5d/demo/Scenario25DDemo.tscn` 或 `ui_module/shader_lab/demo/ShaderLab.tscn`。
- 新版 UI：单独导入 `UI跳转原型_20261015/project.godot`；TA/Scenes 下有对照与原生插槽预览。
- 浏览器地编：打开 `editor/index.html`，或 `node editor/tools/serve.cjs 8765`。

## 验证与转换

```powershell
$env:GODOT_BIN = 'C:/Apps/Godot/Godot_v4.7.2-stable_win64_console.exe'
node tools/Verify-Package.cjs
node tools/Verify-Battle-Integration-Docs.cjs --contracts-only
node editor/tests/model.test.cjs
node editor/tools/Validate-Level.cjs editor/examples/Frontier.mapproject.json
./world_map/tools/Run-Tests.ps1
./scenario_2_5d/tools/Run-Tests.ps1
./ui_module/tools/Run-Tests.ps1
./editor/tools/Run-Tests.ps1
./editor/tools/Import-Level.ps1 -Source ./editor/examples/Frontier.mapproject.json
./UI跳转原型_20261015/Tools/Run-TAShaders.ps1 -GodotPath $env:GODOT_BIN -Tests
```

替换 Godot 路径；参数也可用各脚本的 `-GodotPath`。图形变更追加 `-Render` 或新版 TA 的 `-Capture`，在真实渲染环境执行。

## GitHub 源码交付

```powershell
./tools/Build-GitHub-Package.ps1 -Name supremepoor-toolkit-v1
```

输出 `dist/<Name>/` 是可上传的完整仓库文件树，其下 `frontier_toolkit/` 才是本 Godot 工程。相邻 ZIP 与 `.sha256` 用于下载和校验。已有目标不覆盖；不移动原工程、不改 Git 索引、不自动推送。

构建读取 [github-package.config.json](tools/github-package.config.json)，检查固定来源文件和复制哈希，再验证仓库结构、三个 Godot 工程的字面量资源引用、主要文档链接和完整交付清单。只保留来源清单跟踪的 `.import` 元信息，其他机器导入记录排除。

完整步骤见 [GitHub 上传说明](docs/GITHUB_UPLOAD.md)、[交付范围](docs/RELEASE_CONTENTS.md)、[整合与扩展约定](docs/INTEGRATION_AND_EXTENSION.md)。正式战斗见 [技术设计](docs/BATTLE_INTEGRATION_GUIDE.md)，目前尚未接入。
