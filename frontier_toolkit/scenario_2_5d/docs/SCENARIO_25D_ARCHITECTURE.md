# SCENARIO 2.5D Architecture

```text
ScenarioController
 ├─ SceneDefinition (Resource)
 ├─ SceneMode: EXPLORE / COMBAT
 ├─ ScenarioCameraController
 │   ├─ CameraBounds3D
 │   └─ CameraPivot / Orthographic Camera3D
 ├─ ScenarioInteractionController
 ├─ ScenarioOcclusionController
 ├─ NavigationRoot (interface only)
 ├─ SpawnRoot / SpawnPoint3D (interface only)
 └─ DemoUI (replaceable CanvasLayer)

Actor / Object
 ├─ PhysicsRoot / external Body slot
 └─ VisualRoot
     ├─ BillboardVisual3D / QuadMesh / Paper Shader
     └─ BlobShadow

Interactable3D / StaticBody3D
 ├─ Collider
 ├─ InteractableDefinition (immutable content)
 ├─ InteractableRuntimeState (per-instance duplicate)
 └─ Hover / Selected / Interaction Request
```

空间使用 XZ，Y 为真实高度。相机 Rig 移动 XZ，Camera 局部固定 -50° pitch / 0° yaw / 距离 30；size 做指数平滑。平移由当前/前一屏幕坐标的水平面射线交点差得到，松手丢弃未追上的目标，不累积惯性。聚焦是一次性 API，无自动跟随。

输入先交给 Godot GUI；控制器只处理 unhandled 事件，拖动松手另在 _input 监听以避免在 UI 上松手导致拖动粘连。Interactable > Ground：仅最近实体命中参与交互。地面必须标注 scenario_ground，普通建筑/障碍消费点击但不发 ground event。固定模式只选择 ground signal，外部监听模式信号改变自己的 UI/hover 策略。

层 1：真实实体与地面拾取；层 2：可淡化遮挡物。Ray origin 由 target 的屏幕投影还原，避免正交 Camera 使用相机中心透视射线产生错误遮挡。每条 ray 使用排除 RID 列表遍历多个遮挡体，多个 target 合并为 active set；旧集合中消失的对象 restore。材质复制在 Occluder 完成子节点 Ready 后进行，记录初始颜色与 transparency；未支持的材质保留原始显示并在全部材质不支持时警告。Controller 只调用 Fade API。

场景、运行状态和玩法解耦：资源提供内容，节点提供空间，RuntimeState 提供外部状态，Signal 提供意图。Battle、Exploration、Navigation、Spawn 与 SceneManager 都位于框架之外。世界地图独立，二者没有互相 preload/load 或调用。

可替换点：正式高亮连接 hovered_changed/selected_changed；动画连接 visual_animation_requested；Occluder 可扩展 set_fade_amount/restore_fade 的材质实现；正式 UI 替换 DemoUI；物理碰撞挂到外部 Body slot；真实高台直接使用布局 Collider。

本版没有导航、战斗、角色移动、复杂多层拾取优先级和局部透明 Mask。Occluder 最多按物理碰撞包围体判定，树冠透明边缘与实际 Collider 可能不完全一致。BlobShadow 是局部平面贴片，需要外部适配器在坡地调整高度和法线。
