# 二十事件和地图整合增量交付包

日期：2026-10-19。源码提交：4aa8d24283917aaebad482715610e686252082bc。工作分支：codex/story-event-tracking。

## 适用版本

本包适用于 SupremePoorGuy 的原基线 816606c8ef033cc69e30998e5c4b48f9a15dbbc2，需要已有完整 Godot 工程。它包含本次新增/修改的全部源码与资源，不是独立完整工程。

最新 main dfc192aa729a91a8f7b8cf49fa1352bca28f4d82 已新增另一套地图、召唤演出和时间功能，与本次修改有7个重叠文件。本包不是对最新 main 的无冲突覆盖补丁；PR作为草稿供审阅，须先整合接口再合并。详见 source/it-is-time/Docs/Integration/二十事件与主分支差异_2026-10-19.md。

## 使用

在基线版本的独立备份中，将本包 source 下的内容复制到仓库根目录。用 Godot 4.7.2 打开 it-is-time/project.godot，等待首次导入后按F5，选择开始新游戏体验事件地图。开场2.5D演出不包含在本包中。

## 内容

二十事件的正式条件、追踪、奖励、AI战斗与持久化；地编高清蜂窝地图与原始依赖；旅途待办和跳转；三段献祭及血雨；四轮赌局与退款；双头、魔眼和新增奇物；弹窗绘制层级修复；对齐旧整合版的移动、镜头、缩放与地点点击；数值来源逐字段标注。

manifest.json 记录源码提交、基线、文件SHA-256与验证结果；validation 保存本次10组回归日志及此前专项验证日志；screenshots 保存图形窗口验证截图。

交付包不含个人存档、个人getlogs压缩包、.godot缓存、Git凭据或原始2.4GB交接ZIP。原始地图JSON和来源配置按字节保存，并通过Git属性避免换行转换破坏SHA-256校验。

## GitHub分片下载

将本目录全部 `.zip.001`、`.zip.002` 等分片与 `package-manifest.json`、`Join-Package.ps1` 下载至同一文件夹，再运行 `powershell -ExecutionPolicy Bypass -File .\Join-Package.ps1`。脚本按清单验证每片和完整ZIP的SHA-256。也可以在完整仓库下载本目录后直接运行。
