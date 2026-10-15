# 变更记录

## 2026-10-08 · GitHub 源码包

- 统一保留 world_map、scenario_2_5d、editor 及 integration 目录，包含源码、资源、Demo、配置、测试与模块文档。
- 新增首次运行、架构、上传 GitHub、贡献和许可说明。
- 所有 Godot 启动/测试/转换脚本支持显式路径、GODOT_BIN、本地工具和 PATH；源码包不包含引擎。
- 新增纯 Node GitHub Actions 检查、资源引用检查、白名单打包脚本、逐文件清单与 ZIP 校验值。
- 排除机器缓存、日志、存档、下载包及工具二进制。

此前功能与实施验证记录见各模块 docs。测试结果会在本机重新生成。
