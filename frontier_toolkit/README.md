# Frontier Toolkit · 大地图、2.5D 场景与地编工作台

一个 Godot 项目，包含三个按目录组织的模块及连接层。在 SupremePoorGuy 仓库中，本工具集位于 frontier_toolkit/；下文所有命令都在该目录执行。构建与验收见 [BUILD.md](BUILD.md)。

| 模块 | 入口 | 文档 |
| --- | --- | --- |
| 大地图 | `world_map/demo/WorldMapDemo.tscn` | [大地图说明](world_map/README.md) |
| 2.5D 场景 | `scenario_2_5d/demo/Scenario25DDemo.tscn` | [场景框架说明](scenario_2_5d/README.md) |
| 地编工作台 | `editor/index.html` | [编辑器手册](editor/README.md) |
| 悬浮场景连接层 | `integration/scenario_overlay.gd` | [接入说明](integration/README.md) |

## 首次运行

已验证 Godot 4.7.2，GL Compatibility。引擎不包含在仓库中。浏览器编辑器无需 npm 依赖；本地 HTTP 启动、配置转换和模型测试使用 Node.js（CI 使用 22）。

1. 克隆或解压仓库，安装 Godot。
2. 用 Godot 项目管理器导入根目录 `project.godot`，等待首次资源导入。
3. F5 运行大地图；打开 2.5D Demo 后 F6 独立运行。
4. 使用浏览器打开 `editor/index.html` 进入地编工作台。

Windows PowerShell 也可运行：

```powershell
$env:GODOT_BIN = 'C:\Apps\Godot\Godot_v4.7.2-stable_win64_console.exe'
./world_map/tools/Run-Demo.ps1
./scenario_2_5d/tools/Run-Demo.ps1
./editor/tools/Run-Editor.ps1
```

从大地图进入 Test Town，在弹窗选择“进入场景 / Enter town”，打开应用内 2.5D 悬浮窗口。大地图保持冻结；返回或场景结束后恢复地图。

## 仓库目录

```text
project.godot               共享 Godot 项目入口
world_map/                  大地图代码、Demo、资源、文档、测试与工具
scenario_2_5d/              2.5D 代码、Demo、纸绘素材、文档、测试与工具
editor/                     浏览器编辑器、素材、工作集、Godot 转换与测试
integration/                大地图到 2.5D 悬浮窗口的适配与回归测试
docs/                       首次运行、架构、地编总手册、GitHub 上传指南
tools/                      Godot 查找、仓库检查与可重复打包
.github/workflows/          浏览器编辑器模型与配置检查 CI
```

三个模块共用 `res://` 路径，保持目录名和根目录结构。无需分别新建三个 Godot 项目。运行时生成 `.godot/` 和 `.tools/`，均被 Git 忽略。

## 测试与地编导出

```powershell
node tools/Verify-Package.cjs
./world_map/tools/Run-Tests.ps1
./scenario_2_5d/tools/Run-Tests.ps1
./editor/tools/Run-Tests.ps1
./editor/tools/Import-Level.ps1 -Source ./editor/examples/Frontier.mapproject.json
```

测试加 `-Render` 可运行实际图形验证。地编预览进度和正式玩家存档不会覆盖初始配置。伤害、控制、自动战斗及结算由游戏系统接入，详见 [数据接口与边界](editor/docs/DATA_CONTRACT.md)。

## 文档导航

- [首次运行与环境配置](docs/GETTING_STARTED.md)
- [模块依赖与数据流](docs/ARCHITECTURE.md)
- [地编人员场景编辑总手册](docs/LEVEL_DESIGNER_GUIDE.md)
- [编辑器使用手册](editor/README.md)
- [上传 GitHub 与重新打包](docs/GITHUB_UPLOAD.md)
- [贡献与验证流程](CONTRIBUTING.md)
- [变更记录](CHANGELOG.md)
- [许可说明](LICENSE_NOTICE.md)
