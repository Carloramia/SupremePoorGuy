# GitHub 交接包内容与校验

本次打包整理将工具集、两版 UI 来源、宿主 Shader 库、新版 TA、需求和技术文档组成可上传的源码文件树。宿主仍使用 UI 0.5；UI 0.7.12 是独立工程；it-is-time 实际战斗尚未接入。

## 包含与排除

| 分类 | 包含内容 |
| --- | --- |
| 仓库外层 | README、BUILD、贡献/许可说明、有效根 CI、布局与关联仓库整合步骤 |
| frontier_toolkit | Godot 入口、world_map、scenario_2_5d、editor、integration、ui_module |
| 两版 UI | UI跳转原型 原始 0.5；UI跳转原型_20261015 原始 0.7.12 与 TA/测试/Tools/.handoff |
| 文档 | 战斗对接、历史 PR 差异、扩展指南、需求文本和来源清单 |
| 验证资料 | 历史验证汇总、归档 JSON、截图、交付 SHA-256 清单 |

排除 `.git/.godot/.tools/.runtime/node_modules/dist`、原始大批审阅素材 Raw、引擎二进制、历史 ZIP/RAR、本机录屏、日志、缓存、测试存档和备份。两版固定来源原本自带的四个小型 MP4 预览保留并校验，不作为新增录屏上传。GitHub 已有 it-is-time 不重复打包，保留原项目单独合并。

仅两个固定来源清单内跟踪的 `.import` 元信息保留，确保 171+287 个上游文件完整且可以核验；其他本机生成的 `.import` 排除。UID、运行贴图、字体授权和必要原型截图保留。两个原始工程使用 -text 属性保护来源字节；宿主运行副本按常规代码换行规则维护。

固定来源共 458 个文件中，457 个原样一致；新版 project.godot 有一项已核实的配置差异：省略显式 disabled/keep，Godot 4.7.2 读取到相同默认值。打包保留当前字节，通过 source-adaptations.json 的原始/当前哈希精确识别，不改写原来源清单，也不把它报告为原样文件。

## 三类校验

1. `Verify-GitHub-Repository.cjs <仓库根>` 检查布局、来源文件、三工程资源引用和主要文档链接。无需 Git、网络或审计缓存。
2. 加 `--manifest` 检查 PACKAGE_MANIFEST 中全部文件的原始字节、尺寸与 SHA-256，适合首次解压；清单自身不包含在清单内。
3. ZIP 的 `.sha256` 校验整个下载包。导入 Godot、Git 换行转换或后续编辑后，使用运行测试和源码检查；交付清单仍是原始版本记录。

静态引用扫描不解析动态加载路径，不替代 Godot 导入、物理战斗、GPU 或目标平台构建。固定来源 .import 被 Godot 重新生成后，普通源码校验单列提醒；首次交付的 --manifest 仍要求原始字节一致。

合回关联仓库时，检查范围限定为 frontier_toolkit 与配置定义的仓库外层文件；现有 it-is-time、上级 UI 原型和参考资料不属于本次交付检查，不会被当作包内多余文件或待删除内容。

## 可重复生成

在工具集根运行 `./tools/Build-GitHub-Package.ps1 -Name <新名称>`。Node staging 按配置选择文件、校验固定来源和复制内容，再生成来源记录与清单；PowerShell 验证后压缩。已存在目标停止，不覆盖、不删除、不移动源文件。

构建策略为 [github-package.config.json](../tools/github-package.config.json)，仓库外层模板在 tools/github_repository。修改布局或 CI 时同步改模板和 [上传说明](GITHUB_UPLOAD.md)。

此前 [PR 差异说明](PR_VERSION_DIFFERENCES.md) 保留的是打包整理前的审计阶段，包含当时缺少 BUILD、新版目录未纳入默认包等结论；本次已补 BUILD 并更新默认交付清单。历史统计没有伪装成整理后最新差异。

## 发布记录

RELEASE_CONTENTS.json 记录交付来源和布局；PACKAGE_MANIFEST.json 记录精确文件快照。验证说明见 [本次解压验收](RELEASE_VALIDATION_20261015.md)、[历史结果](verification/20261015/README.md) 与发布目录旁的最终封装复核记录。新改动应产生新的验证记录和新包名，不覆盖旧快照。
