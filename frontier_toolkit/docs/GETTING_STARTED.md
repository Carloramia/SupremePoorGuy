# 首次运行与环境配置

## 环境

已验证 Godot 4.7.2，GL Compatibility 渲染。仓库包含源码及必要素材，不包含 Godot 可执行文件。安装来源：[Godot 官方下载](https://godotengine.org/download/)。其他版本尚未验证。

浏览器编辑器可直接通过 Edge / Chrome 打开 `editor/index.html`。启动静态服务器、Node 模型测试及 PowerShell 配置转换需要 Node.js；[Node.js 官网](https://nodejs.org/)。CI 使用 Node.js 22。没有 npm 安装步骤。

Windows 工具脚本使用 PowerShell 7（`pwsh`）；跨平台可使用下方直接引擎命令。下载项目压缩包后先解压，不能从压缩文件夹内部运行。

## 配置 Godot

工具按以下顺序查找：显式 `-GodotPath`、环境变量 `GODOT_BIN`、项目本地 `.tools/godot`、PATH 中的 `godot` 或 `godot4`。

```powershell
$env:GODOT_BIN = 'C:\Apps\Godot\Godot_v4.7.2-stable_win64_console.exe'
./world_map/tools/Run-Demo.ps1 -Editor
# 也可直接指定，不需要配置环境变量
./scenario_2_5d/tools/Run-Demo.ps1 -GodotPath 'D:\Apps\Godot.exe'
```

Godot 项目管理器选择“导入”，定位仓库根目录 `project.godot`。首次导入会重建缓存和素材导入记录。F5 默认大地图；打开各模块 Demo 后 F6 运行该场景。

## 跨平台命令行

以下命令在仓库根目录运行，假设 `godot` 和 `node` 在 PATH：

```sh
godot --headless --editor --path . --import --quit
godot --path . res://world_map/demo/WorldMapDemo.tscn
godot --path . res://scenario_2_5d/demo/Scenario25DDemo.tscn
node editor/tools/serve.cjs 8765
```

服务器启动后访问 `http://127.0.0.1:8765/editor/index.html`；Ctrl+C 结束命令行服务器。直接打开 HTML 不需要服务器。

## 地编工作流

打开编辑器 → 打开示例工作集 → 摆放与配置 → 检查配置 → 保存工作集 → 导出初始配置 → 生成 Godot 场景。操作细节见 [编辑器手册](../editor/README.md)。

```powershell
./editor/tools/Import-Level.ps1 -Source ./editor/examples/Frontier.mapproject.json
```

跨平台生成同一份示例：

```sh
node editor/tools/Validate-Level.cjs editor/examples/Frontier.mapproject.json
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://editor/godot/import_level.gd -- --source=res://editor/examples/Frontier.mapproject.json --output=res://editor/exports
```

输出目录已附带示例转换结果，打开 `editor/exports/frontier/frontier.tscn` 或 `editor/exports/camp_battle_01/camp_battle_01.tscn` 按 F6。

## 验证

```powershell
node tools/Verify-Package.cjs
node editor/tests/model.test.cjs
./world_map/tools/Run-Tests.ps1
./scenario_2_5d/tools/Run-Tests.ps1
./editor/tools/Run-Tests.ps1 -Render
```

无图形环境可不传 `-Render`。GitHub Actions 自动检查目录依赖、JS 语法、编辑器模型和示例配置；原生 Godot 以及 GPU 渲染由上述脚本本地验证。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| 找不到 Godot | 传正确可执行文件路径或配置 GODOT_BIN；引擎不随包提供 |
| PowerShell 阻止脚本 | 在本次会话执行 `Set-ExecutionPolicy -Scope Process Bypass`，或直接使用 Godot / Node 命令 |
| 缺少全局脚本类 | 用 Godot 编辑器导入项目，或运行 headless --editor --import 命令 |
| Godot 找不到素材 | 保持仓库目录和名称；运行 `node tools/Verify-Package.cjs` 检查引用 |
| 编辑器刷新后恢复示例 | 保存工作集到本地文件，使用“打开”重载；浏览器不自动保存源文件 |
| 本机存档与他人不同 | 源码包不包含玩家存档；启动脚本和直接 Godot 的存档目录不同 |

Windows 脚本将 APPDATA 临时指向 `<仓库>/.tools/userdata` 并在结束后恢复。直接 Godot 启动使用标准 `user://` 用户数据目录。两者都不应提交到仓库。
