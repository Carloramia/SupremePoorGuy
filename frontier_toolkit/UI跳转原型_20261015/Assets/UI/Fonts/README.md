# 小赖手写字体

当前UI全局使用Xiaolai Regular，接近用户手绘示例的中文手写方向；并非声称找到了截图所用的确切原字体。

- 作者项目：https://github.com/lxgw/kose-font
- 发布版本：v3.126
- 原始文件：https://github.com/lxgw/kose-font/releases/download/v3.126/Xiaolai-Regular.ttf
- 本地文件：Xiaolai-Regular.ttf（原样保留，未修改、未子集化）
- SHA256：E2F68DAF0E72777A8CF58BC83DE1B98634B251E537DDBFCA24B0AE50D1802DA2
- 授权：SIL Open Font License 1.1，全文随工程保存在OFL.txt；分发字体时一并保留授权与版权信息。
- 不安装到操作系统；工程主题直接引用打包字体，换电脑无需安装。

替换入口：Assets/UI/PaperRelief/PaperReliefTheme.tres的Font外部资源。默认正文18px，说明／紧凑按钮16px，任务标题22px，窗口标题24–26px。字体与底纸、Shader、业务逻辑独立。

当前运行页面均使用PaperReliefTheme；PrototypeTheme和SketchbookTheme为历史资源，未为本次换字重写历史示意。
