# 本地化

[config.json](config.json) 指定默认/回退语言和每种语言文件；[catalog.json](catalog.json) 保存稳定文本键、原文及来源；`zh_CN/` 为完整默认文案，`en/` 为部分英文包，缺失项回退中文。

运行时 Autoload 为 [GameLocalization / GameText.gd](../Scripts/Localization/GameText.gd)。普通文本用 `GameText.text()`；需即时切换的控件用 `bind()`，离树自动解除。绑定表达式只负责显示，不在里面触发生成、交易或保存。

| 语言文件名 | 范围 |
|---|---|
| ui.json | 主菜单、设置与通用界面 |
| creatures.json / items.json | 生物与物品显示名 |
| maps_events.json | 地图、地点与事件 |
| console.json | 控制台可见文案 |
| editor.json | 工具提示与编辑器文案 |

增加或修改文本：先找已有键，再编辑语言 JSON。不要翻译 NodePath、输入映射、PartKey、物种/符文 ID、控制命令、存档键或诊断字段。保留 `%s/%d`、`{name}` 占位符与 BBCode 链接 ID。

在项目根目录执行：

```powershell
python Tools/Localization/build_catalog.py
python Tools/Localization/validate_catalog.py
```

提取是写操作，会更新清单；验证检查重复键、未知键、占位符与回退覆盖。新增语言还需在 config.locales 注册。语言设置独立保存在 `user://settings/language.cfg`。

[localization_export](../addons/localization_export) 插件和导出预设的 JSON 过滤保证文本入包。仅在编辑器里显示正常不能替代包体测试；图片内已绘制的字需要另换图片。详细示例见 [原使用说明](使用说明.txt)。
