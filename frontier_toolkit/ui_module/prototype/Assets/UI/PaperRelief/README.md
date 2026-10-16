# 纸雕 UI 当前素材入口

当前运行版本0.5。依据用户1009／10019两份素材抽取层叠纸雕语言，不替换怪物设计，不修改正式工程。

- PaperReliefTheme.tres：全局字体、色板、普通按钮四态及PrimaryButton。
- Styles：底纸、怪物纸卡、按钮和紧凑属性样式，均可在Godot编辑。
- Textures：独立底纸、空心框、空白按钮三张PNG母版，内置image_gen生成。不是一张整页UI图。
- Icons：书本、夹子、铜钉独立SVG，延续原生图标系统。
- ExampleArt：用户狼／强盗／沙虫概念原图的未修改副本。均带完整场景背景，不是透明生产角色。
- manifest.json：资源尺寸、来源、SHA256、导入和切片；prompts.json记录生成提示词。

规范入口：[美术指导与素材格式](../../../docs/美术方案/03_纸雕UI_美术指导与素材格式.md)、[UI风格规范](../../../docs/02_UI风格与组件规范.md)、[可视化调整指南](../../../docs/04_UI组件可视化调整指南.md)。

BoardSurface的Paper／WoodFrame／Clip／LeftRivet／RightRivet是分开插槽。WoodFrame沿用旧节点名但当前显示叠层纸框。怪物Artwork优先于Reference示例，不被数据刷新重置。原生文字不烘焙，装饰不抢鼠标。

纸和框Size Limit256，按钮512，原图插画768。Region和Patch Margin针对导入后的尺寸，改变Size Limit须重新切片。母版PNG未缩改。素材规格完整表只维护在美术指导文档，避免多份冲突。

旧SketchbookA保留上一轮水粉A测试，不是当前主题；旧PrototypeTheme保留历史回退参考。
