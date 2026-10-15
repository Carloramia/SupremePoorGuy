# WorldMap Test Checklist

验证日期：2026-10-06。引擎：Godot 4.7.2 stable official。执行 `Run-Tests.ps1`。前 19 项对应提示词的必需验收，其余为接口及边界验证。

测试实际实例化完整 Demo，在 SceneTree / physics frame 中运行移动、交互、存读档及输入分发。视觉由真实 OpenGL 渲染截图补充检查。

| Test | 验收项 | 结果 |
|---|---|---|
| 1 | 普通移动、真实路径与绕山体抵达 | PASS |
| 2 | 移动途中立即改目标 | PASS |
| 3 | 障碍内部、地图外及禁用 Hex 拒绝 | PASS |
| 4 | 连续迷雾及 VISIBLE / EXPLORED 转换 | PASS |
| 5 | 地点按距离发现、持久显示 | PASS |
| 6 | 视野外地点低透明度、Hover 与点击 | PASS |
| 7 | 导航到 interaction_point、自动弹 UI | PASS |
| 8 | 路过未选中地点不打开 UI | PASS |
| 9 | 地面命令保留地点目标，后来接近触发 | PASS |
| 10 | 新地点替换旧地点目标 | PASS |
| 11 | 不可达地点清空交互意图 | PASS |
| 12 | Settlement 完成后保留并可重复访问 | PASS |
| 13 | Resource Collect、永久移除及自动保存 | PASS |
| 14 | Event 两个选项及会话隐藏状态 | PASS |
| 15 | Battle 请求、Victory / Defeat / Error | PASS |
| 16 | Save / Load、玩家与字节一致 Fog、地点生命周期 | PASS |
| 17 | 实际 Area2D 重叠的优先级速度覆盖 | PASS |
| 18 | Camera follow、RMB drag、zoom、focus | PASS |
| 19 | 正式交互模块暂停及恢复，外部 SceneTree 活动 | PASS |
| 20 | 存档缺失与损坏 JSON 容错 | PASS |
| 21 | RESPAWNABLE 与 restore / respawn 接口 | PASS |
| 22 | PAUSE 保留意图、resume、CANCEL 清路径 | PASS |
| 23 | 多地图私有 Navigation 与平移子树 | PASS |
| 24 | 异步战斗场景重建和怪物永久移除 | PASS |
| 25 | 运行时地点增删替换、描述及墓碑重建 | PASS |
| 26 | 损坏字段类型与未知版本验证 | PASS |
| 27 | 真实 viewport GUI 和地图点击分发 | PASS |
| 28 | TileMap 中心精确对齐、绕第二个不规则障碍 | PASS |

数据验证：400 组 axial/world/cell 可逆转换、range/distance、disabled Hex、JSON roundtrip：PASS。

渲染验证：initial / navigation / settlement / herbs / monument / bandits / fake_battle / overview 八张截图：PASS（布局完整，文字与按钮可见，柔和视野及路径正确显示）。

完整机器结果：world_map/debug/test_results.json；可复现实验脚本：data_validation.gd、acceptance_tests.gd、render_preview.gd。

## Hex debug 修复回归

`Run-Tests.ps1 -Render` 额外运行 `hex_debug_render_test.gd`，通过真实 viewport 鼠标事件点击开关并比较实际 OpenGL 截图：PASS。

- 开启时地图测试区域有 17,251 个像素变化，网格与坐标清晰可见。
- 再次关闭后地图截图差异为 0；UI 点击未触发玩家移动。
- 原有 28 项验收及 400 组数据验证仍全部 PASS。


## 道路功能验收

执行 Run-Tests.ps1；真实 UI 和路面渲染验证使用 -Render。原 28 项验收及道路 28 项均 PASS，400 组数据验证 PASS。

| 测试 | 内容 | 结果 |
|---|---|---|
| api_exact | Programmatic API preserves exact destination unless snapping explicitly enabled | PASS |
| arrival | Player actually arrives at snapped center line | PASS |
| bend_path | Planned path includes road bends rather than an off-road diagonal | PASS |
| bend_trajectory | Actual physics trajectory stays on centerline and reaches the corner before turning; deviation=0.0000 | PASS |
| blocked_centerline | A road through a mountain is rejected even when ordinary Navigation can detour to its end | PASS |
| branch_route | Changing roads follows the main/south junction and all branch bends | PASS |
| branch_trajectory | Actual movement across the shared junction stays on road centers | PASS |
| closest_road | Nearest south-road segment selected across road registry | PASS |
| degenerate | Zero-length segments safely ignored | PASS |
| endpoint | Projection clamps beyond the last endpoint | PASS |
| entry_arrival | Off-road connector joins road and arrives on exact center | PASS |
| entry_connector | Off-road approach uses Navigation to enter nearest center without teleporting | PASS |
| far_ground | Distant ground remains exact | PASS |
| intent | Road ground command retains selected location intent | PASS |
| interior_junction | Crossings split segment interiors into proper road junctions | PASS |
| invalid_raw | Road snapping rejects obstacle and exterior raw clicks | PASS |
| invalid_snapped | Unreachable snapped center line is rejected instead of falling back or bypassing obstacles | PASS |
| location_exact | Location commands preserve exact interaction points without road snapping | PASS |
| mouse_snap | Real viewport ground click snaps target, marker and actual navigation path | PASS |
| near_road | Ground near the road snaps within configurable margin | PASS |
| pause | Road commands respect subsystem pause | PASS |
| projection | Click within road width projects to nearest segment center | PASS |
| registry | Demo registers main and south center lines | PASS |
| route_cancel | Cancel clears centerline waypoints and path display | PASS |
| route_pause | Pause/resume retains centerline route and progresses after resume | PASS |
| route_retarget | New road command replaces old route, including reverse travel | PASS |
| speed_areas | Real Area2D contacts accelerate road movement, Mud overrides and exit restores base speed | PASS |
| translated_map | Road projection remains correct in translated independent map instances | PASS |

图形验证：棕色路面可见、近路点击目标吸附、道路速度为 247.5、显示路径经过中心线拐点：PASS。

实际弯道和主路/支路连续轨迹验证：全程距道路中心线小于 0.1 世界单位；弯道测试报告偏差为 0.0000。路外接入无传送，暂停/恢复、反向改目标、取消、内部交叉点以及阻断中心线均通过。
