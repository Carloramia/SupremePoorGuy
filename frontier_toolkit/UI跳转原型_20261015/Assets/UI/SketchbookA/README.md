# A方案 · 可替换的分件素材包

历史测试版本：当前运行已切换纸雕 UI，见 [当前分件入口](../PaperRelief/README.md)。本文件保留上一版青绿水粉 A 测试记录，不再作为当前配色与切片规范。

状态：AI试做母版＋原生组件接入，非最终美术定稿。只在本独立原型使用。

## 分件与入口

- Textures/paper_v1.png：单独空白纸底；用于PaperPanel样式和BoardSurface/Paper。
- Textures/board_frame_v1.png：透明中心的木框；用于BoardSurface/WoodFrame。
- Textures/button_brush_v1.png：不含文字的笔刷色块；通过四份Brush样式复用。
- Icons/copper_clip.svg、copper_rivet.svg：独立可编辑矢量装饰；用于BoardSurface的夹子和铜钉。
- Styles/：纸底、按钮四状态及紧凑属性签，独立资源，不藏在业务脚本。
- SketchbookTheme.tres：当前共享主题；旧PrototypeTheme.tres保留为0.3历史回退参考。
- Scenes/UI/Components/BoardSurface.tscn：纸／木框／夹子／铜钉的装配场景。
- Scenes/UI/Components/BoardMotion.tscn：AnimationPlayer进出轨道；不携带业务数据。
- Scenes/UI/Components/StatButton.tscn：浅色属性纸签；与主操作青绿按钮区分。

上面Scenes路径相对工程根目录；所有贴图与规则文字、数值、法阵格子、怪物图像、点击区域分离。没有整页烘焙图或PSD分层源文件；分层源是Godot场景与独立PNG/SVG。

## 更换步骤

1. 新资产保存为新的版本文件，保留可回退母版。
2. 在Godot导入面板核对Size Limit：纸和木框256，按钮512。原始PNG未缩改，导入尺寸仅服务九宫格。本轮原始纸／框1254方图，按钮2172×724。
3. 在BoardSurface里分别换Paper和WoodFrame；木框Patch Margin四侧32、纸16，不能将大分辨率原图不经重新切片直接套用此参数。
4. 主按钮在Styles/BrushNormal、Hover、Pressed、Disabled分别换Texture或颜色；当前Region Rect=(16,32,480,108)，四侧切片28/16/28/16，内容边距16/12/16/12。新图尺寸变化须重新框选有效区域。
5. 夹子／钉子换各自Texture。装饰Mouse Filter保持Ignore，纸和框也不截获输入。
6. 字体、颜色与常规间距改SketchbookTheme；布局改组件场景；不要改GameDemo坐标或Scale。
7. 跑布局、流程与ArtUI测试，并检查实际截图。贴图变更不代表业务变更。

完整需求、提示词、验收与限制见docs/美术方案/02_A方案_素材分件与效果测试.md。manifest.json提供资源尺寸与生成记录，prompts.json保留实际提示词。生成采用内置图片工具；夹子／铜钉沿用工程原生矢量图标做法，非AI生成。
