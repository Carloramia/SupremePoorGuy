# 构建、运行与验收指南

本目录是独立 Godot 工具集，完整仓库中的路径为 `frontier_toolkit/`。它不替换 `it-is-time/`，也不直接注入主游戏场景。

## 1. 环境与目录

- 已验证引擎：Godot 4.7.2，GL Compatibility。引擎二进制不随 Git 提交。
- Windows 脚本使用 PowerShell 7。
- Node.js 用于本地服务器、JSON 校验、模型测试和打包验证；CI 使用 Node.js 22，无 npm 依赖。
- 浏览器编辑器直接打开 HTML 时，不需要 Godot 或 Node.js。

从仓库根目录开始：

```powershell
Set-Location frontier_toolkit
$env:GODOT_BIN = 'D:\Apps\Godot_v4.7.2-stable_win64_console.exe'
```

请修改为本机引擎实际路径。也可向每个 Godot 脚本传 `-GodotPath`。脚本还支持 `.tools/godot` 和 PATH 中的 `godot` / `godot4`。

## 2. 首次资源导入与 Demo

用 Godot 项目管理器导入 **`frontier_toolkit/project.godot`**。首次导入会生成 `.godot/` 和素材导入记录，无需编译 C++ 或安装插件。

```powershell
& $env:GODOT_BIN --headless --editor --path . --import --quit
./world_map/tools/Run-Demo.ps1
./scenario_2_5d/tools/Run-Demo.ps1
```

F5 默认为大地图。打开 `scenario_2_5d/demo/Scenario25DDemo.tscn` 后 F6 可独立运行。大地图进入 Test Town，弹窗选择“进入场景”，检查悬浮窗口、地图冻结和返回恢复。

跨平台也可使用：

```sh
godot --headless --editor --path . --import --quit
godot --path . res://world_map/demo/WorldMapDemo.tscn
godot --path . res://scenario_2_5d/demo/Scenario25DDemo.tscn
```

## 3. 地编编辑、转换与实际预览

浏览器打开 `editor/index.html`，或执行 `node editor/tools/serve.cjs 8765` 后访问 `http://127.0.0.1:8765/editor/index.html`。本地服务器仅绑定本机。

编辑完成后保存工作集，检查配置，再导出 `*.level.json`。在本目录转换：

```powershell
./editor/tools/Import-Level.ps1 -Source 'D:\Levels\my-map.level.json'
```

转换器先校验配置并导入资源，再输出到 `editor/exports/<地图ID>/`。在 Godot 中打开该目录的 `.tscn`，按 **F6**。F5 运行的是原始 Demo，不是当前导出地图。

示例转换命令：

```powershell
./editor/tools/Import-Level.ps1 -Source ./editor/examples/Frontier.mapproject.json
```

浏览器预览负责检查空间、条件、迷雾和地图关联；正式伤害、控制、自动部署、战斗及奖励由外部游戏系统接入。新规则完整保存在初始配置和 editor_data 中，不代表已有核心自动实现这些玩法。详见 [数据接口](editor/docs/DATA_CONTRACT.md)。

## 4. 自动验证

```powershell
node tools/Verify-Package.cjs
node editor/tests/model.test.cjs
node editor/tools/Validate-Level.cjs editor/examples/Frontier.mapproject.json
./world_map/tools/Run-Tests.ps1
./scenario_2_5d/tools/Run-Tests.ps1
./editor/tools/Run-Tests.ps1
```

需要实际图形检查时，给上述 Run-Tests 加 `-Render`，需要可用图形环境。大地图脚本同时覆盖道路及悬浮场景回归；编辑器脚本包含模型测试、转换和原生场景检查。

仓库根 `.github/workflows/frontier-toolkit.yml` 会在 `frontier_toolkit` 工作目录执行纯 Node 检查。Godot 与 GPU 测试本地执行。测试结果、缓存及存档自动生成并由 Git 忽略。

## 5. 给地编成员打包

```powershell
./tools/Build-Standalone-Editor.ps1
```

生成 `dist/frontier-editor-时间戳.zip`：包含编辑器、内置素材、工作集、可直接阅读的 HTML 说明和 Windows 启动文件。地编成员完整解压后即可离线使用，不需要引擎。完成后交回 `.mapproject.json` 和 `.level.json`，由开发成员转换并测试。

完整工具集包使用 `./tools/Build-GitHub-Package.ps1`，包含三个模块及文档。两个打包脚本均保留已有包，不覆盖同名目标。

## 6. 主要文档

- [首次运行](docs/GETTING_STARTED.md)
- [模块架构](docs/ARCHITECTURE.md)
- [地编总手册](docs/LEVEL_DESIGNER_GUIDE.md)
- [大地图说明](world_map/README.md)
- [2.5D 说明](scenario_2_5d/README.md)
- [编辑器操作说明](editor/README.md)
- [悬浮窗口接入](integration/README.md)

源码包不会携带真实玩家存档、机器引擎、下载的历史工程或压缩包。通过启动脚本运行时，用户数据隔离在本目录 `.tools/userdata`；直接从 Godot 编辑器运行则使用标准 user:// 目录。
