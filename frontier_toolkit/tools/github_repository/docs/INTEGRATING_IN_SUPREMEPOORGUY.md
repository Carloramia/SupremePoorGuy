# 合回 SupremePoorGuy 的步骤

关联仓库历史 PR #1 已提供 frontier_toolkit。当前交接包沿用这一目录，新增宿主 UI、Shader 库、新版独立 TA 工程、技术文档和交付工具。

## 目录映射与合并

| 交接包内容 | 关联仓库目标 | 合并方法 |
| --- | --- | --- |
| frontier_toolkit/ | frontier_toolkit/ | 在新分支按文件比较更新；保留团队后续本地修改 |
| .github/workflows/frontier-toolkit.yml | 同名根工作流 | review 新的结构/协议检查步骤与工作目录 |
| 根 README.md、BUILD.md、CONTRIBUTING.md、LICENSE_NOTICE.md | 仓库已有总说明 | 合并相关入口和内容；保留原 it-is-time 介绍 |
| docs/ 两个仓库说明 | 仓库 docs 或团队约定位置 | 保持链接映射；若调整路径同步更新根 README |
| .gitignore/.gitattributes | 仓库根同名文件 | 合并规则；保留 it-is-time 原有规则，加入固定 UI 来源的字节保护 |
| PACKAGE_MANIFEST.json / RELEASE_CONTENTS.json | 本次交付记录目录或根 | 作为交付快照；不要当成持续更新的游戏数据库 |

不要将整个交接包再嵌套成 frontier_toolkit/frontier_toolkit，不要把工具集 project.godot 覆盖到 it-is-time，也不要用本包根 README 全量覆盖主游戏介绍。

## 可评审的操作顺序

1. 在关联仓库最新目标分支上创建 `codex/` 前缀的新分支，确认工作区状态并保留已有修改。
2. 按上述路径映射比较交接包与现有文件。先合入模块源码和文档，再合并根 CI/忽略规则/总入口。
3. 在仓库根执行结构检查；若交付清单归档到其他位置，按团队布局同步更新检查配置，不使用清单覆盖现有数据。
4. 在 frontier_toolkit 执行 Node 检查，导入宿主与新版 UI 两个当前开发工程，再执行对应 Godot 验收。
5. review 暂存文件，确认无缓存、引擎、测试存档或用户目录；PR 描述明确运行 UI 仍为 0.5，真实战斗尚未接入。

已有仓库无需重新 git init、修改远程或重写历史。此交付工具只生成本地源码包，不执行以上 Git 操作。

## 后续整合次序

先按 [模块扩展指南](../frontier_toolkit/docs/INTEGRATION_AND_EXTENSION.md) 固定公共接口和数据所有权，再按 [战斗技术文档](../frontier_toolkit/docs/BATTLE_INTEGRATION_GUIDE.md) 的 M0–M5 实施。正式战斗需要上下文、生成/导航就绪、输入与跨世界隔离、死亡判定和可靠结算，不能仅切换入口到 TestLevel。

新版召唤 2.0 的 UI/队位/存档迁移与实际战斗接入分别 review；TA 先在独立场景验收，再逐页面应用。每个阶段保留旧 Demo 与测试入口，便于回退和定位问题。
