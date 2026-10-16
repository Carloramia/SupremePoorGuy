# 贡献与验收约定

运行源码位于 frontier_toolkit。先读 [结构说明](docs/REPOSITORY_LAYOUT.md) 和 [扩展指南](frontier_toolkit/docs/INTEGRATION_AND_EXTENSION.md)。现有 it-is-time 与工具集之间的新增调用放在适配层，保留模块公共边界。

源码检查执行 [BUILD.md](BUILD.md) 中的命令。修改运行逻辑时追加对应 Godot 回归；Shader 或布局改动追加真实 GPU/输入/多分辨率检查。PR 说明列出最终行为、数据迁移、已执行验证和未完成范围。

固定来源 UI 原型保留来源清单与字节一致性。若要升级，先另建新版本、记录新提交和迁移规则，再替换运行基础；不要直接覆盖旧参考或新版已确认布局。

提交代码、必要素材、UID、固定来源的 import 元信息和维护文档；不提交引擎、.godot、.tools、.runtime、用户存档和 dist。交付 ZIP 供下载和校验，GitHub 源码提交使用解压后的文件树。

历史差异索引与测试快照有自己的采样阶段。实现继续演进后，不将其旧统计当成最新结果；重新执行相关验收，并记录新的快照日期与来源版本。
