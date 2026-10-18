# 可配置新手任务栏增量交付包

日期：2026 年 10 月 18 日。

本包包含 it-is-time 的四条可配置新手任务、存档与奖励能力、原生待办 UI 接入、测试和使用说明。四项任务暂不发奖；保留魔力、符文与奇物解锁配置。开场事件与独立 2.5D 场景由其他流程负责。

## 安装

准备 SupremePoorGuy 的完整仓库，在仓库根目录执行 `git apply --check NewPlayerTasks.patch`，通过后执行 `git apply NewPlayerTasks.patch`。补丁位于本包根目录；命令中可使用其绝对路径。

也可将 source 目录中的 it-is-time 文件夹合入仓库对应目录。两种安装方式选择一种，不要重复应用。该包仅包含修改文件，不能单独作为完整 Godot 工程运行。

## 运行与配置

用 Godot 4.7.2 导入 it-is-time/project.godot，等待资源导入后按 F5；开始新游戏进入地图，点击左侧“待办事项”。任务配置位于 Scripts/Application/NewPlayerTasks.gd 的 DEFINITIONS 数组。完整说明在 Docs/Integration/新手任务栏使用说明_2026-10-18.md。

## 验证与内容

三组新增无窗口测试共 116 项通过；图形界面 53 项检查通过；原有会话、旧地图入口、交付地图与真实战斗往返回归通过。validation 保存本次重新验证的日志和结果，screenshots 保存三档窗口截图，manifest.json 保存基线提交、源码提交和文件哈希。