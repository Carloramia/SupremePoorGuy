# 仓库结构与目录职责

```text
repository/
  README.md / BUILD.md                 总入口与运行验收
  CONTRIBUTING.md / LICENSE_NOTICE.md   协作与许可说明
  .github/workflows/                   仓库根有效 CI
  docs/                               仓库布局、合回原仓库步骤
  PACKAGE_MANIFEST.json                交付字节校验清单
  RELEASE_CONTENTS.json                交付布局及来源记录
  frontier_toolkit/
    project.godot / BUILD.md           宿主入口和模块运行说明
    world_map/                        连续地图、道路、地点、迷雾、存档
    scenario_2_5d/                     正交相机、深度、遮挡、交互
    integration/                      现有城镇桥；后续 battle 适配层位置
    editor/                           浏览器地编、数据契约、转换器
    ui_module/                        UI 0.5 运行副本、地图桥、Shader 实验台
    UI跳转原型/                       UI 0.5 原始参考工程
    UI跳转原型_20261015/               UI 0.7.12 来源及新增 TA/测试/工具/配置差异记录
    shader需求/                       Shader 需求文本
    docs/                             技术文档、历史差异、验证快照
    tools/                            检查、构建、包配置及仓库模板
```

工具集沿用历史 PR 的 frontier_toolkit 路径。两个 UI 原型保持相对位置，使现有文件链接、来源工具和资源命名不需要重写。三个 project.godot 分别是独立 Godot 根，各自 res 路径只在各自工程解析；新版 UI 不是宿主当前运行 UI。

it-is-time 是关联仓库已有工程，本包没有再次复制。合回现有仓库后它与 frontier_toolkit 并列。主游戏资源、Autoload、Jolt、Forward Plus 等配置由后续实际战斗集成处理，不能靠目录合并替代接口适配。

根 CI 有效；frontier_toolkit 内原有 .github 保留为模块历史内容，不是上级仓库 Actions 入口。tools/github_repository 是可重复生成根 README、文档和 CI 的模板，.gdignore 防止宿主扫描这些模板。

日常扩展位置与职责见 [模块整合与扩展指南](../frontier_toolkit/docs/INTEGRATION_AND_EXTENSION.md)。
