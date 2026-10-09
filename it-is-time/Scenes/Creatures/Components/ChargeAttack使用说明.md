# 地面冲锋能力

挂载 `ChargeAttackController3D.tscn` 到角色根节点。可直接实例化 `Generate_HornedBeast_NPC.tscn`，它继承原单节尾巴角色，拥有远距离冲锋和近距离踏地。没有修改关卡摆放或启用分节尾巴。

## 参数

`Resources/Actions/GroundCharge.tres` 控制冲锋：没有最大距离限制，最小X距离自动按 `(maximum_speed²-starting_speed²)/(2*acceleration)` 计算。默认起始速度2、最大速度12、加速度5，对应最小距离14、加速时间2秒。Z对齐容差0.3、减速度8、冷却5秒。速度单位为Godot世界单位/秒。最小距离是理想匀加速指令的加速距离，实际物理速度会受承重、阻力和速度追踪影响。

NPC行为在 `Resources/AI/HornedBeastChargeAI.tres` 配置。冲锋接收器提供有效最小距离和无限最大距离，覆盖攻击选项中的静态范围，同时参与偏好距离计算。权重和冷却仍按行为预设。冲锋超时按启动时目标的预计行进时间加 Maximum Charge Time（默认8秒容错）计算，NPC最长攻击时长也随之扩展，避免远目标被固定时长提前取消。卡住、离地和失去目标保护仍有效。导航路径允许弯折，因此可达不保证固定X冲锋能绕开障碍，角色碰撞与卡住保护负责处理。

## 行为

启动前不检查头部与目标的高度差，改为检查两者在导航网格上的投影之间是否存在完整路径。Navigation Projection Tolerance 限制水平投影距离；Navigation Endpoint Tolerance 检查路径终点是否到达目标投影，避免把部分路径视为可达。冲锋单独绕过状态机的垂直差和直线视线限制，其他攻击不变。

ALIGNING：先正常沿 Z 行走，追踪目标位置并完成朝向；CHARGING：锁定冲锋方向和 Z 车道，以物理力追踪逐步增长的速度。此时只读取目标当前 X，越过该 X 加上启动时记录的目标半宽及 pass_margin 后进入 BRAKING；目标 Y/Z 和导航变化不影响冲锋推进。立即去除攻击区域，减速结束后恢复原 command_source。卡住、离地、目标失效和按启动距离计算的超时仍作为保护。

临时伤害区域为世界轴对齐长方体，位于 Head 前方（无 Head 时使用战斗锚点），底面由向下射线贴到 StaticBody3D 地形。Obstacle Mask 用于地面查询；无地面时暂停区域伤害。长度为头部 X 长度乘 Weapon Length Ratio，高度为头部 Y 高度，宽度为头部 Y/Z 较大值乘 Weapon Radius Ratio 的两倍。

长方体是禁用物理响应的形状查询，不加入头部刚体，也不与地形发生阻挡、摩擦或反弹。查询只对敌方 PhysicalBodyPart3D 结算，保持全局伤害换算、护甲与单次冲锋每部位一次命中。由于不产生求解器接触冲量，采用冲锋方向相对接近速度乘双方约化质量估算冲量；高速移动使用前后帧区域包围体检测，减少穿过薄部位的漏判。伤害强度应在实战中重新验证。角色自身原有碰撞仍正常与地形交互。

普通移动驱动力和额外地面制动在冲锋/减速时让位，腿部仍参与迈步，重力、支撑和姿态稳定机制保留。Z 轴使用车道纠偏力，因此碰撞仍可能造成少量侧移；不瞬移或刚性冻结世界 Z 坐标。

CHARGING 使用每个控制器独立的临时步态资源，Target Speed 跟随当前冲锋速度，步幅、腾空和预测统一参与计算，不修改原始 tres。冲锋先触发一次起步，随后复用伸展驱动换步：参考步频参与步幅、腾空时间等计算，不设置全局启动间隔或单脚完整周期等待。按剩余伸展距离优先安排换步，仍受接地支撑与迈步名额检查约束，关闭 Allow All Feet Airborne 时至少留一条接地的非迈步腿。日志中的 startup、distance_limit、predicted_limit、extension_emergency、charge_needs_stance 和 charge_retry_wait 分别表示起步、距离触发、预计到达极限、紧急换步、缺少支撑和失败重试等待。迈步超时后间隔0.2秒重新尝试，步幅缩短至前一次的65%，最低35%；成功落地后逐步恢复，冲锋结束后清除临时调整。这是可达性保守重试，并非完整关节逆运动学求解。

角色在恢复姿态、PlanarConstraints 模式或其他攻击期间不能启动。目标失效、能力禁用、角色失效、离地过久、卡住、超时、再生成都会结束或中断，并清理长方体伤害区域、恢复输入来源与 CCD。

控制台 `trackcharge` 切换每 0.1 秒的冲锋诊断（阶段、原因、目标 X、车道 Z、期望/实际速度、冷却、武器存在）；`trackdamage` 追踪伤害，`tracknpcstate` 追踪 NPC 攻击选择。

专项测试 ValidateGroundCharge 使用真实角色、NPC 攻击选择和伤害服务，模拟脚部支撑及位移来确定性验证状态推进。它不等同于完整复杂地形的行走测试。

冲锋临时步态现在明确启用 Automatic Motion、Speed Based Gait 和 Gallop Enabled，使 `_begin_leg_motion` 使用飞奔的抬脚、轨迹追踪及落地制动流程；是否保留接地支撑腿由冲锋数据的 Allow All Feet Airborne 决定。退出 CHARGING 后恢复原始预设，普通行走是否飞奔仍由原 tres 决定。`trackcharge` 的脚部日志中 `gallop.active` 用于确认飞奔执行是否启用，`automatic_flight` 和 `requires_flight` 仅代表规划计算结果。

验证记录：冲锋专项测试和原 HornedBeast 结构测试通过。旧 ValidateGeneratedNPCAttack3D 测试未通过：其当前 fixture 未生成 Head，触发既有 Head/Torso 联通规则，部位 Broken 后踏地预测失败。本次未修改该 fixture 或联通规则。

冲锋换步现在取“腿链几何剩余距离”和“相对生成站姿的保守后移行程”中较小者。Charge Step Admission / Charge Stance Travel Ratio 默认0.15，用腿链长度的15%作为后移行程预算；这是保守近似，不是完整关节限位求解。预判采用实际相对速度与冲锋目标速度的较大值，预测距离最多为行程预算的80%，防止高目标速度让落在站姿前方的脚立即重复迈步。接地后的重新迈步仍有几何行程检查，紧急接近预算边界时可换步；不恢复固定步频间隔。普通移动沿用原计算。trackcharge 的 extension_demand 新增 geometric_remaining、stance_offset、stance_travel_budget、prediction_speed、prediction_distance；charge_stance_limit / charge_predicted_limit 表示站姿行程到限或预测提前换步。

GroundCharge.tres 的 Allow All Feet Airborne 默认开启。CHARGING 临时步态允许所有脚迈步、Minimum Support Feet 为0；仍检查可达落点、部位有效性和由真实接地记录的有限飞行资格，不强制同步起跳。完全离地时，冲锋按飞奔资格权重衰减施加水平推进，辅助支撑复用原飞奔流程。空中迈步命令不能刷新资格，资格过期后停止冲锋空中推进。冲锋落地阶段允许尚未完全制动的脚通过真实接触续期：脚已抬起、位于可行走表面0.04距离以内、法向速度不超过1.0并持续接触至少0.05秒；接触消失或弹跳会清除确认。安全取消计时从真实支撑和腾空资格都失效后开始，超过 Airborne Timeout 才取消。BRAKING 不使用这一空中许可。关闭开关恢复至少一脚支撑和仅接地推进。trackcharge 的 airborne_elapsed 保留物理离地计时，unsupported_elapsed 表示完全失去有效支撑的持续时间，airborne_support 报告 weight、remaining、feet。

冲锋速度预算：Use Total Load Mass 默认开启，推进负载包含本角色所有未Broken、非冻结的物理部位，以它们的总质量计算推进力，再按可施力躯干质量分配；角色重新生成时冲锋取消，下次重新收集负载。Compensate Linear Damping 默认开启，按部位线性阻尼和项目默认阻尼估算补偿（不包含Area3D覆盖阻尼），并添加冲锋加速前馈。所有分量共同受 Maximum Acceleration 限制，不保证任何地形或结构下都能达到目标速度。trackcharge 的 load_budget 与 torso_force_rows 的 budget_mass/feedforward_acceleration 可检查预算与限幅。

冲锋临时步态使用 Touchdown Stop Time（默认0.12秒）、Touchdown Maximum Acceleration（默认80），高速触地后先制动，脚速足够低才建立锁地约束，避免原0.04秒制动与立即硬锁叠加。允许全脚腾空时，按步幅覆盖需求延长腾空，保留落地确认时间；单次腾空最多1.5秒。资格预算包含腾空、最多0.3秒抬脚余量、按速度和制动加速度计算的最多0.75秒制动余量以及确认时间和0.12秒余量，总计最多3秒，仍报告 distance_deficit。抬脚初期跟随腿根水平速度，不以零世界速度制动整条腿。所有步态改动仅用于CHARGING，原始行走tres不被修改；推进质量预算同时用于冲锋结束制动。

冲锋中的脚失去落地接触后，解除冻结并立即根据当前腿根和可达范围重新验证落点，重规划不受旧落点的逐帧追踪限速影响。后续失去接触期间仍跟随当前腿根更新目标。若地形或可达性检测拒绝新落点，暂时取消旧落点的水平位置追踪，保持腿根水平速度参考；原有落地超时仍负责结束失败动作。普通步行保留原流程。trackcharge 脚部 gallop 新增 charge_support_contact_confirmed、contact_source、charge_landing_replans、charge_landing_replan_pending；speed_gait 新增 charge_liftoff_reserve 和 charge_braking_reserve。

冲锋高速锁地检查覆盖所有脚，包括尚未迈步、迈步失败和退出迈步状态的脚。新建或保留硬锁要求真实接触距离不超过0.04、切向速度不超过 Gallop Touchdown Speed Limit、法向速度不超过0.7。未迈步脚的高速真实接触通过吸附处理流程附加切向制动力，以脚自身质量计算，使用同一 Touchdown Stop Time 和 Touchdown Maximum Acceleration，活动迈步脚仍只使用原来的落地制动通道，避免重复施力。未接触地面但仍在 LANDING 的脚使用当前腿根水平速度作为追踪参考，并保留对新落点的位置追踪；真实触地后恢复地面制动。落地接触沿用最多0.07的原有容差，硬锁使用更严格的0.04。普通行走及冲锋结束后的减速流程不采用这些新增规则。trackcharge 的脚部 gallop 新增 charge_idle_brake（实际切向制动力、质量、速度及限值）和 charge_airborne_velocity_reference。

## 冲锋触地完成与短时制动

CHARGING 时，脚完成真实抬起后，在下降或接触已将法向速度降低至0附近时（法向速度不超过0.2），检测到距离不超过0.04的有效地面接触，当帧就完成本次迈步，不等待水平速度归零或连续减速确认。这条快速路径优先于上面的旧落地等待流程；未真正抬脚或仍明显上升的脚不能触发。同次迈步只完成一次，其他脚继续各自迈步。完成时以实际接触位置更新有限支撑资格，contact_source 为 instant_touchdown。

完成迈步后，脚进入独立的短时接地制动阶段，使用 GroundCharge.tres 的 Touchdown Brake Duration（默认0.12秒）限制施加额外切向制动力的时间。Touchdown Stop Time 是制动力计算时间常数，Touchdown Maximum Acceleration 是加速度上限；Brake Duration 是施力窗口，三者含义不同，不保证窗口结束前速度归零。每次施力仍须真实接地，离地不制动，窗口不因连续接触而刷新；失败或未迈步脚在首次有效接触时也得到一次有限窗口。再次开始迈步时清除该脚的旧窗口，并要求重新完成抬脚。到期后保留常规法向吸附、摩擦及低速锁地检查，停止额外切向制动。

再次迈步沿用冲锋伸展触发及几何重新触发检查，不要求脚完全停止，也不等待制动窗口到期。关闭或结束冲锋清理这些临时阶段，普通步行不使用即时触地完成机制。trackcharge/tracknpcmotion 的脚部 gallop 新增 charge_ground_phase（time、point、normal、completed_on_contact），charge_idle_brake 新增 remaining，可区分已完成迈步、仍在短时制动以及窗口已经结束。

## 冲锋空中轨迹随腿根移动

CHARGING 的自动飞奔迈步在完成抬脚时立即重新验证落点，丢弃旧世界坐标的逐帧追赶限制。空中 MOVING 阶段的轨迹起点随腿根水平位移同步移动，终点从当前腿根的可达前伸范围重新采样；速度参考包含腿根水平速度，不再重复叠加剩余腾空时间对应的位移预测。抬脚结束时即使身体已经移动很远，也不会继续追赶原来留在后方的落点。

落点的台阶高度检测比较当前脚下地形和目标地形的高度，避免脚自身腾空使平地被判为落差过大。每帧重新检查坡度、地形、空间和腿链可达性；检查失败时临时取消旧目标的水平位置追踪，跟随腿根水平速度，保留竖直轨迹和原有超时处理。真实触地即时完成及短时制动保持原规则。普通行走和非冲锋飞奔不采用此移动参考系。

trackcharge / tracknpcmotion 的脚部 gallop 新增 charge_swing_target：valid 为最近一次空中落点验证结果，reason 为 valid 或具体拒绝原因，retargets 为成功更新次数，frame_origin 为本次抬脚结束时腿根的位置。charge_airborne_velocity_reference 同时涵盖落点无效时的速度跟随回退。

## 按触地速度和剩余窗口制动

冲锋接地制动使用 GroundCharge.tres 的 Touchdown Brake Margin（默认1.25）预留25%余量，Touchdown Maximum Acceleration 默认从80提高到600。Touchdown Stop Time 和 Touchdown Brake Duration 仍默认0.12秒。每帧计算：有效停止时间 = max(min(Stop Time, 窗口剩余时间), 物理帧时长)，请求减速度 = 当前切向速度 / 有效停止时间 × Margin；实际减速度取请求值、Maximum Acceleration、当前速度 / 物理帧时长三者的最小值。随后乘脚自身质量生成反向切向力。最后一项限制防止该制动力在单帧内使脚速度反向，不代表能消除其他关节力的影响。

只有真实接地且制动窗口未耗尽时施力，不提前在空中制动，不刷新窗口，也不等待停止才允许换步。活动落地和已完成迈步的脚使用同一算法，常态下前者由迈步追踪流程施加、后者由吸附流程施加，避免重复叠加；活动落地的切向制动也使用脚自身质量，不额外乘腿链承重质量。非冲锋步态保留原制动策略。余量和上限并不能保证复杂关节系统在窗口内完全停止；更强制动也可能通过关节影响躯干速度。

trackcharge / tracknpcmotion 的 charge_idle_brake（及活动落地的 touchdown_brake）增加 active、margin、effective_stop_time、requested_acceleration、applied_acceleration、acceleration_limited、tick_limited、real_contact，便于区分窗口到期、加速度不足和单帧防反向限幅。

## 接地到抬脚的衔接与高速前伸

冲锋的新迈步若仍真实接地，保留上次触地的制动窗口，不因开始抬脚而清除或重置。抬脚阶段的竖直力继续工作，水平追踪改由接地制动接管，不提前跟随躯干速度。窗口到期则停止额外制动，但仍不主动向前追踪，直到离地。确认脱离真实接触后，以脱离时脚的实际水平速度为起点，经过 Charge Liftoff Follow Blend Time（默认0.1秒）平滑切换至腿根跟随及空中轨迹速度。过渡期间重新接地会中断速度混合，回到原接地窗口；不因此延长制动。无需等待脚完全停止才允许抬脚，保留原有伸展触发和超时保护。

移动控制器 Inspector 的 Generated Swing Reach 下新增 Speed Adaptive Forward Extension（默认开启）和 High Speed Forward Extension Ratio（默认0.95）。原 Forward Extension Ratio（默认0.75）作为低速值；冲锋时使用平滑实际水平速度 / 冲锋 Maximum Speed 的0～1比例，经 smoothstep 后在低高速值间插值。该功能仅在 CHARGING 生效，关闭开关或非冲锋时保留原比例。正在迈步的脚会随每帧落点更新应用新比例，仍保留地形、空间及腿链可达检测；这不是完整关节限位求解，也不扩大接地后移预算。

trackcharge / tracknpcmotion 的 gallop 新增 forward_extension_ratio 和 charge_liftoff_transition，后者记录 ground_braking / air_follow、速度混合进度以及制动或速度参考。前伸放宽与阶段衔接的实际表现仍需通过完整物理测试确认。

## 冲锋低头

GroundCharge.tres 的 Charge Head Posture 提供 Lower Head Enabled（默认开启）、Head Lower Angle Degrees（默认15°）及 Head Lower Transition Time（默认0.3秒）。CHARGING 时将 Head 的目标姿态相对原始姿态向下旋转，BRAKING、取消或关闭功能后平滑恢复。通过原有 HeadPositionSupport3D 的惯量缩放力矩和阻尼执行，不直接修改刚体旋转、不新增相互竞争的姿态控制器。所有有效 Head 使用各自连接关系，Horn 随现有物理连接跟随。

低头绕躯干局部Z轴的负向进行，使局部+X朝向下方；角色朝左时仍会向下低头。头部位置伺服同步补偿绕连接点旋转引起的中心位移。默认15°低于当前HornedBeast的20°颈部角度限制；增加角度仍受既有关节和姿态力矩限制，不会自动扩大关节范围。trackcharge 新增 head_posture_request 和 head_posture，后者记录各头部目标/当前控制角度、旋转误差及姿态力矩；控制角度表示伺服目标偏移，并非测量到的实际头部转角。
