# SupremePoorGuy 工具集与 UI Shader 交接源码

此目录可以作为新 GitHub 仓库根目录，也可按 [关联仓库整合步骤](docs/INTEGRATING_IN_SUPREMEPOORGUY.md) 合回 SupremePoorGuy。运行工程保留历史 PR 的 `frontier_toolkit/` 路径，便于与已有 `it-is-time/` 并存。

| 内容 | 入口 | 状态 |
| --- | --- | --- |
| 大地图、原生 UI、城镇 2.5D | [frontier_toolkit/project.godot](frontier_toolkit/project.godot) | F5 运行带 UI 的地图，宿主 UI 基础为 0.5 |
| 宿主 UI Shader 实验台 | [ShaderLab.tscn](frontier_toolkit/ui_module/shader_lab/demo/ShaderLab.tscn) | 在宿主工程 F6；S1/S2/S3 独立对照 |
| 新版 UI 0.7.12 与 TA | [独立 project.godot](frontier_toolkit/UI跳转原型_20261015/project.godot) | 单独导入；一项等值窗口配置差异已记录；TA 场景接入 |
| 地编工具 | [editor/index.html](frontier_toolkit/editor/index.html) | 浏览器编辑、保存、配置校验和 Godot 转换 |
| 旧 UI 原始参考 | [UI跳转原型](frontier_toolkit/UI跳转原型/README.md) | 0.5 固定来源，与运行副本分开 |
| 实际战斗 | [对接技术文档](frontier_toolkit/docs/BATTLE_INTEGRATION_GUIDE.md) | it-is-time 接入待实施；当前仍使用 FakeBattleAdapter |

快速开始见 [BUILD.md](BUILD.md)。Godot 已验证版本为 4.7.2 / GL Compatibility；Node 检查使用 22；Windows 工具使用 PowerShell 7。引擎、缓存和用户存档不包含在源码包中。

## 整合与扩展文档

- [仓库结构和各目录用途](docs/REPOSITORY_LAYOUT.md)
- [合回 SupremePoorGuy 的步骤](docs/INTEGRATING_IN_SUPREMEPOORGUY.md)
- [模块整合与扩展约定](frontier_toolkit/docs/INTEGRATION_AND_EXTENSION.md)
- [实际战斗技术设计与实施清单](frontier_toolkit/docs/BATTLE_INTEGRATION_GUIDE.md)
- [历史 PR 与打包整理前版本的差异](frontier_toolkit/docs/PR_VERSION_DIFFERENCES.md)
- [本次交付范围和文件校验方法](frontier_toolkit/docs/RELEASE_CONTENTS.md)
- [本次解压运行验收](frontier_toolkit/docs/RELEASE_VALIDATION_20261015.md)
- [贡献流程](CONTRIBUTING.md) 与 [许可说明](LICENSE_NOTICE.md)

根 `.github/workflows/frontier-toolkit.yml` 执行源码结构、资源引用、协议文档与编辑器模型检查；Godot 和 GPU 验收按 BUILD 本地执行。PACKAGE_MANIFEST.json 是交付时的逐文件 SHA-256 快照，RELEASE_CONTENTS.json 记录布局与来源。运行和编辑后按当前源码测试；历史验证记录不替代新改动的验收。
