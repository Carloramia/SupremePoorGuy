# 验证记录

日期：2026-10-13。环境：Windows，Godot 4.7.2-stable，GL Compatibility，OpenGL 3.3，NVIDIA GeForce RTX 4070 SUPER。

最终复测：无窗口检查 51 项通过；真实 GPU、输入及像素检查 77 项通过，0 项失败。9 张最终截图已重新生成。Godot 输出无 Shader 编译或脚本错误。

仓库检查 `node tools/Verify-Package.cjs` 通过：18 个必要入口存在，277 个 Godot 资源引用全部可解析。

已提供两类验证：无窗口的算法／组件检查，以及真实 GPU 的渲染／输入／截图检查。后者检查 Shader 编译错误、同素材五组效果、稳定种子、真实鼠标点击和 Tab 焦点、禁用状态、准确输入路径、宽窄九宫格、1280×720／1920×1080、浅纸／深色／复杂背景。

白底像素测试使用有透明内孔的同一 RGBA 图，检查内孔变白、外轮廓白底宽度、主体色保留、开关恢复透明、画布贴边图形仍有向外白底，以及白底之外与原背景完全一致。静态帧逐字节比较，确认没有逐帧游动。

## 截图索引

- [默认中强度 · 720p 五组对照](tests/screenshots/01_comparison_medium_1280x720.png)
- [默认中强度 · 1080p 五组对照](tests/screenshots/05_comparison_medium_1920x1080.png)
- [深色背景](tests/screenshots/02_background_dark.png)
- [复杂地图背景](tests/screenshots/03_background_map.png)
- [轻预设](tests/screenshots/04_strength_light.png)
- [强预设](tests/screenshots/04_strength_strong.png)
- [组件状态与九宫格 · 720p](tests/screenshots/06_states_and_nine_slice_1280x720.png)
- [组件状态与九宫格 · 1080p](tests/screenshots/07_states_and_nine_slice_1920x1080.png)
- [白底填洞与外轮廓探针](tests/screenshots/08_silhouette_probe.png)

人工检查已确认文字和数值独立清楚，五列共享同一素材，白底连续，宽窄九宫格角区正常，按钮焦点可辨识。对照素材和参数属于本轮可调版本，尚未由项目美术负责人确认最终参数。

未改写召唤、库存、地图、输入系统或默认入口。本轮完成需求案指定的独立验证和资源交接，正式 UI 各页面接入应使用本文关联的组件并再做页面回归。没有对移动设备作性能结论。
