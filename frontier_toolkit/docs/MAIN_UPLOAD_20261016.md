# 2026 年 10 月 16 日 main 目录提交说明

本版本直接提交到关联仓库 main，只更新 `frontier_toolkit/`。仓库根 README、.github 工作流、忽略规则和其他文件夹保持原样；it-is-time、上级 UI 原型与参考资料继续独立维护，不经过 PR 流程。

## 工程入口

- 导入本目录 project.godot，F5 运行带原生 UI 的地图。
- 在宿主内打开 scenario_2_5d Demo 或 ui_module/shader_lab 后 F6。
- 新版 UI/TA 单独导入 UI跳转原型_20261015/project.godot；运行 UI 仍为旧 0.5，新版 0.7.12 保持独立。
- 运行、模块整合、真实战斗后续步骤分别见 [BUILD](../BUILD.md)、[扩展指南](INTEGRATION_AND_EXTENSION.md) 和 [战斗技术文档](BATTLE_INTEGRATION_GUIDE.md)。实际战斗目前尚未接入。

## 校验与交接包

在本目录执行：

```sh
node tools/Verify-Package.cjs
node tools/Verify-Battle-Integration-Docs.cjs --contracts-only
node editor/tests/model.test.cjs
node editor/tools/Validate-Level.cjs editor/examples/Frontier.mapproject.json
```

本次上传复核结构/引用、协议和编辑器检查；Godot、UI 与 Shader 解压验收记录见 [交接验收](RELEASE_VALIDATION_20261015.md)。源场景和运行资源与已验收版本对应，历史 GPU 检查不重复计为本次执行。

tools/github_repository 内保留完整交接仓库外层的 README、BUILD、CI 和整合步骤模板。`Build-GitHub-Package.ps1` 可导出带这些外层文件的独立交接包；该导出布局不表示关联仓库根文件已被修改。

`Verify-GitHub-Repository.cjs <交接仓库根>` 验证导出的完整交接包，需要对应根目录文件。当前按要求只更新工具集文件夹，日常源码检查使用上面四条命令和已有根 CI，不要求原仓库补装交接包外层。
