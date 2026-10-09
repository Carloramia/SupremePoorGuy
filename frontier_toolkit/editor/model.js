/* Shared document model. Browser and Node tests use exactly the same code. */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.MapEditorModel = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const VERSION = 1;
  const clone = value => JSON.parse(JSON.stringify(value));
  const f = (path, label, kind = 'text', options = {}) => ({ path, label, kind, ...options });
  const number = (path, label, min, max, step = 1) => f(path, label, 'number', { min, max, step });
  const select = (path, label, options) => f(path, label, 'select', { options });
  const reference = (path, label, ref) => f(path, label, 'reference', { ref });
  const ASSETS = [
    ['road', '碎石道路', 'road.svg'], ['rock', '层叠岩石', 'rock.svg'], ['tree', '林地树木', 'tree.svg'],
    ['barricade', '完好路障', 'barricade.svg'], ['rubble', '路障残骸', 'rubble.svg'],
    ['house', '林间小屋', 'house.svg'], ['town', '边境城镇', 'town.svg'], ['camp', '怪兽营地', 'camp.svg'],
    ['grass', '草丛', 'grass.svg'], ['thorns', '荆棘', 'thorns.svg'], ['mud', '泥潭', 'mud.svg'],
    ['web', '蛛网', 'web.svg'], ['pit', '落穴', 'pit.svg'], ['monster', '怪兽示意', 'monster.svg'],
    ['altar', '战后祭坛', 'altar.svg'], ['cloth', '衬布纹理', 'cloth.svg']
  ].map(([id, name, file]) => ({ id, name, path: 'res://editor/assets/' + file, category: '内置素材' }));
  const TYPES = {
    road: { name: '道路', icon: '↝', group: '道路与地表', modes: ['exploration'], asset: 'road', layer: 'roads' },
    destructible: { name: '可破坏障碍', icon: '╳', group: '障碍与交互', modes: ['exploration'], asset: 'barricade', layer: 'collisions' },
    traversable: { name: '可跨越障碍', icon: '⇢', group: '障碍与交互', modes: ['exploration'], asset: 'rock', layer: 'collisions' },
    indestructible: { name: '不可破坏障碍', icon: '◆', group: '障碍与交互', modes: ['exploration'], asset: 'rock', layer: 'collisions' },
    house: { name: '小屋', icon: '⌂', group: '地标', modes: ['exploration'], asset: 'house', layer: 'landmarks' },
    camp: { name: '怪兽营地', icon: '⚑', group: '地标', modes: ['exploration'], asset: 'camp', layer: 'landmarks' },
    town: { name: '城镇', icon: '▥', group: '地标', modes: ['exploration'], asset: 'town', layer: 'landmarks' },
    decoration: { name: '装饰贴片 / 草', icon: '✧', group: '装饰', modes: ['exploration', 'battle'], asset: 'grass', layer: 'decoration' },
    tree: { name: '树木贴片', icon: '♠', group: '装饰', modes: ['exploration', 'battle'], asset: 'tree', layer: 'decoration' },
    cloth: { name: '独立衬布层', icon: '▱', group: '道路与地表', modes: ['exploration'], asset: 'cloth', layer: 'cloth' },
    reveal_area: { name: '初始揭示区域', icon: '◉', group: '战争迷雾', modes: ['exploration'], asset: '', layer: 'reveals' },
    collision_damage: { name: '碰撞伤害障碍', icon: '◆', group: '战斗 · 3D', modes: ['battle'], asset: 'rock', layer: 'collisions' },
    pit: { name: '落穴陷阱', icon: '◎', group: '战斗 · 3D', modes: ['battle'], asset: 'pit', layer: 'effects' },
    thorns: { name: '荆棘减速区', icon: '♜', group: '战斗 · 3D', modes: ['battle'], asset: 'thorns', layer: 'effects' },
    mud: { name: '泥潭减速区', icon: '≈', group: '战斗 · 3D', modes: ['battle'], asset: 'mud', layer: 'effects' },
    web: { name: '蛛网控制区', icon: '▧', group: '战斗 · 3D', modes: ['battle'], asset: 'web', layer: 'effects' },
    edge_decoration: { name: '边缘自然贴片', icon: '◇', group: '战斗 · 边缘', modes: ['battle'], asset: 'rock', layer: 'decoration' },
    broken_barricade: { name: '破损路障残骸', icon: '╱', group: '战斗 · 边缘', modes: ['battle'], asset: 'rubble', layer: 'decoration' },
    deployment: { name: '己方部署区', icon: '▦', group: '战斗配置', modes: ['battle'], asset: '', layer: 'deployment' },
    enemy: { name: '敌方预制怪兽', icon: '●', group: '战斗配置', modes: ['battle'], asset: 'monster', layer: 'deployment' },
    post_battle: { name: '战后中心交互点', icon: '✦', group: '战斗配置', modes: ['battle'], asset: 'altar', layer: 'landmarks' }
  };
  for (const type of ['destructible', 'traversable', 'indestructible', 'collision_damage', 'pit', 'thorns', 'mud', 'web']) TYPES[type].layer = 'props';
  const LAYERS = { cloth: '衬布', decoration: '装饰', props: '障碍 / 陷阱视觉', roads: '道路', landmarks: '地标 / 点击范围', fog: '战争迷雾', reveals: '初始揭示区', collisions: '实体碰撞', effects: '陷阱 / 效果区', boundary: '战场边界', deployment: '部署区 / 敌方' };
  const vec = (path, label) => f(path, label, 'vector');
  const shapeFields = (prefix, title) => [
    f(prefix + '.enabled', title + '启用', 'boolean'), select(prefix + '.shape', title + '形状', ['rect', 'circle', 'polygon']),
    vec(prefix + '.offset', title + '独立偏移'), vec(prefix + '.size', title + '尺寸 / 直径'),
    number(prefix + '.rotation', title + '旋转 °', -360, 360), f(prefix + '.points', title + '多边形节点', 'points'),
    number(prefix + '.height', title + '高度', 0.01, 10000, 0.1), number(prefix + '.depth', title + '深度', 0, 10000, 0.1)
  ];
  const commonFields = () => [
    f('id', '唯一 ID'), f('name', '显示名称'), vec('position', '位置 X / Y（战场 X / Z）'),
    number('height', '离地高度 Y', -1000, 1000, 0.1), number('rotation', '旋转 °', -360, 360), vec('scale', '缩放 X / Y'),
    reference('visual.asset', '视觉素材', 'assets'), vec('visual.size', '视觉尺寸'), number('visual.z_index', '显示层级', -1000, 1000),
    f('visual.visible', '视觉显隐', 'boolean'), number('visual.opacity', '透明度', 0, 1, 0.05), f('visual.tint', '占位颜色', 'color')
  ];
  const discoveryFields = () => [
    f('discovery.initially_visible', '初始显示标记', 'boolean'), reference('discovery.condition_ref', '发现条件引用', 'conditions'),
    number('discovery.radius', '发现距离（世界单位）', 0, 10000, 1), select('discovery.marker_layer', '与迷雾的层级', ['above', 'below']),
    f('discovery.allow_hidden_interaction', '未发现也可点击', 'boolean')
  ];
  function fieldsFor(object) {
    let fields = commonFields();
    const type = object.type;
    if (type === 'road') return fields.concat([
      f('points', '中心线节点（局部坐标）', 'points'), number('width', '道路宽度', 1, 1000), select('style_ref', '道路样式', ['gravel', 'dirt', 'stone']),
      f('connection_ids', '连接 ID 列表', 'strings'), number('snap_margin', '现有移动吸附距离', 0, 500), number('speed_multiplier', '现有移动倍率', 0.01, 20, 0.1)
    ]);
    if (['destructible', 'traversable', 'indestructible', 'collision_damage'].includes(type)) fields.push(...shapeFields('collision', '碰撞'), number('collision.layer', '物理层位掩码', 1, 1048575));
    if (['destructible', 'traversable', 'indestructible', 'house', 'camp', 'town'].includes(type)) fields.push(...discoveryFields());
    if (['destructible', 'traversable', 'indestructible'].includes(type)) fields.push(f('hint', '提示文本'), f('blocked_ids', '仅阻挡这些地点 / 连接 ID', 'strings'));
    if (type === 'destructible') fields.push(reference('condition_ref', '破坏条件引用', 'conditions'), reference('broken_asset', '破损素材', 'assets'));
    if (type === 'traversable') fields.push(reference('condition_ref', '跨越条件引用', 'conditions'), vec('landing', '跨越落点'), f('crossing_connection', '跨越连接 ID'));
    if (['house', 'camp', 'town', 'post_battle'].includes(type)) fields.push(...shapeFields('click_area', '点击范围'), reference('condition_ref', '交互 / 解锁条件', 'conditions'), reference('event_id', '事件 ID', 'events'), f('target_scene', 'Godot 目标场景路径'));
    if (['house', 'camp', 'town'].includes(type)) fields.push(vec('interaction_offset', '大地图交互点偏移'), number('interaction_radius', '交互半径', 0, 500), f('repeatable', '允许重复交互', 'boolean'), select('completion_behavior', '非重复完成行为', ['KEEP', 'HIDE_SESSION', 'REMOVE_PERMANENTLY', 'RESPAWNABLE']));
    if (type === 'camp') fields.push(
      f('blocking_obstacle_ids', '关联阻挡障碍 ID', 'strings'), reference('battle_map_id', '目标战场', 'battles'), reference('enemy_config_id', '敌方配置 ID', 'enemy_configs'),
      reference('deployment_id', '己方部署区域 ID', 'battle_deployments'), reference('post_event_id', '战后事件 ID', 'events'),
      number('transition.duration', '转场时长（秒）', 0, 20, 0.05), number('transition.zoom', '焦点放大倍率', 1, 20, 0.1), number('transition.fade', '渐变时长（秒）', 0, 10, 0.05)
    );
    if (['pit', 'thorns', 'mud', 'web', 'deployment', 'reveal_area'].includes(type)) fields.push(...shapeFields('region', type === 'reveal_area' ? '揭示区域' : '效果 / 部署区域'));
    if (['pit', 'thorns', 'mud', 'web', 'collision_damage'].includes(type)) fields.push(select('targets', '作用对象', ['all', 'ground', 'flying', 'player', 'enemy']), reference('effect_ref', '效果引用（不写死规则）', 'effects'));
    if (type === 'collision_damage') fields.push(number('damage', '碰撞伤害值', 0, 100000, 0.1), number('interval', '触发间隔（秒）', 0.01, 10000, 0.1));
    if (['thorns', 'mud'].includes(type)) fields.push(number('slow_ratio', '减速比例 0～1', 0, 1, 0.05), number('linger', '离开后持续（秒）', 0, 10000, 0.1));
    if (type === 'web') fields.push(number('min_height', '最低生效高度', 0, 1000, 0.1), number('max_height', '最高生效高度', 0, 1000, 0.1), number('duration', '控制时长（秒）', 0, 10000, 0.1), number('interval', '重复触发间隔（秒）', 0.01, 10000, 0.1));
    if (type === 'deployment') fields.push(number('facing', '部署朝向 °', -360, 360), f('slots', '部署槽位（局部坐标）', 'points'), reference('rule_ref', '部署规则引用', 'deployment_rules'));
    if (type === 'enemy') fields.push(reference('monster_config_id', '怪兽配置 ID', 'monster_configs'), number('facing', '朝向 °', -360, 360), f('team_group', '编队分组'));
    if (type === 'tree') fields.push(f('linked_collision_id', '另行关联的碰撞对象 ID'));
    if (type === 'post_battle') fields.push(reference('summon_option_ref', '召唤选项引用', 'options'), reference('upgrade_option_ref', '升级选项引用', 'options'));
    return fields;
  }
  function mapFields(map) {
    let fields = [f('id', '地图 ID'), f('name', '地图名称'), reference('ground_asset', '地面素材（可空）', 'assets'), f('ground_color', '地面颜色', 'color'), reference('background_asset', '背景素材（可空）', 'assets')];
    if (map.kind === 'battle') return fields.concat([
      number('radius', '六边形半径', 3, 200, 0.5), select('orientation', '六边形朝向', ['flat', 'pointy']), number('background_blur', '外部背景虚化', 0, 30, 0.5), number('edge_feather', '边缘羽化宽度', 0, 10, 0.1),
      number('wall.thickness', '空气墙厚度', 0.05, 10, 0.05), number('wall.height', '空气墙高度', 0.1, 1000, 0.1), number('wall.layer', '空气墙碰撞层位掩码', 1, 1048575), f('natural_border', '自动自然边缘装饰', 'boolean')
    ]);
    return fields.concat([
      vec('bounds.position', '地图范围起点'), vec('bounds.size', '地图范围尺寸'), f('outline', '可选自定义外轮廓（空=矩形）', 'points'),
      number('native.width', '后台 Hex 列数', 1, 100), number('native.height', '后台 Hex 行数', 1, 100), number('native.hex_size', '后台 Hex 大小', 8, 200), f('native.disabled_hexes', '禁用 axial Hex', 'points'),
      f('native.default_spawn_id', '默认出生点 ID'), vec('spawn', '默认出生位置'), number('native.discovery_radius', '默认发现距离', 0, 10000), number('native.interaction_radius', '默认交互半径', 0, 1000),
      f('fog.enabled', '迷雾启用', 'boolean'), f('fog.source_ref', '揭示来源引用'), number('fog.radius', '探索揭示半径', 0.1, 10000),
      f('fog.unknown_color', '未探索颜色', 'color'), number('fog.unknown_opacity', '未探索透明度', 0, 1, 0.05), reference('fog.texture_ref', '可选迷雾纹理', 'assets'),
      select('fog.retention', '探索保留模式', ['permanent', 'recover']), f('fog.explored_color', '已探索颜色', 'color'), number('fog.explored_opacity', '已探索透明度', 0, 1, 0.05),
      number('fog.feather', '迷雾羽化宽度', 0, 1000), number('fog.fade_duration', '显隐渐变（秒）', 0, 20, 0.05)
    ]);
  }
  const get = (object, path) => path.split('.').reduce((value, key) => value == null ? undefined : value[key], object);
  function set(object, path, value) {
    const keys = path.split('.'); let current = object;
    keys.slice(0, -1).forEach(key => { if (!current[key] || typeof current[key] !== 'object') current[key] = {}; current = current[key]; });
    current[keys[keys.length - 1]] = value;
  }
  const region = (size, enabled = true) => ({ enabled, shape: 'rect', offset: [0, 0], size: size.slice(), rotation: 0, points: [], height: 2, depth: 0 });
  function uniqueId(project, prefix) {
    const ids = new Set(project.maps.flatMap(map => [map.id, ...map.objects.map(object => object.id)]));
    let index = 1; while (ids.has(prefix + '_' + String(index).padStart(2, '0'))) index++;
    return prefix + '_' + String(index).padStart(2, '0');
  }
  function createObject(type, map, project, position = [0, 0]) {
    if (!TYPES[type] || !TYPES[type].modes.includes(map.kind)) throw Error('当前地图不支持这种对象类型');
    const small = map.kind === 'battle', size = small ? [2.2, 2.2] : [78, 78];
    const object = {
      id: uniqueId(project, type), name: TYPES[type].name, type, layer: TYPES[type].layer, position: position.slice(), height: 0, rotation: 0, scale: [1, 1],
      visual: { asset: TYPES[type].asset, size, visible: true, opacity: 1, z_index: 0, tint: '#9fba8d' }
    };
    if (type === 'road') Object.assign(object, { points: [[-100, 0], [0, 0], [100, -45]], width: 48, style_ref: 'gravel', connection_ids: [], snap_margin: 24, speed_multiplier: 1.5 });
    if (['destructible', 'traversable', 'indestructible', 'collision_damage'].includes(type)) object.collision = { ...region(size), height: small ? 3 : 2, layer: 1 };
    if (['destructible', 'traversable', 'indestructible', 'house', 'camp', 'town'].includes(type)) object.discovery = { initially_visible: false, condition_ref: '', radius: 240, marker_layer: 'above', allow_hidden_interaction: false };
    if (['destructible', 'traversable', 'indestructible'].includes(type)) Object.assign(object, { hint: '当前无法通过', blocked_ids: [] });
    if (type === 'destructible') Object.assign(object, { condition_ref: 'has_monster', broken_asset: 'rubble', hint: '至少持有一只怪兽才能破坏路障' });
    if (type === 'traversable') Object.assign(object, { condition_ref: '', landing: null, crossing_connection: '' });
    if (['house', 'camp', 'town', 'post_battle'].includes(type)) Object.assign(object, { click_area: { ...region(size), shape: 'circle' }, condition_ref: '', event_id: '', target_scene: '' });
    if (['house', 'camp', 'town'].includes(type)) Object.assign(object, { interaction_offset: [0, 35], interaction_radius: 42, repeatable: type === 'town', completion_behavior: 'KEEP' });
    if (type === 'camp') Object.assign(object, { blocking_obstacle_ids: [], battle_map_id: '', enemy_config_id: '', deployment_id: '', post_event_id: '', transition: { duration: 1.2, zoom: 3, fade: 0.3 } });
    if (['pit', 'thorns', 'mud', 'web', 'deployment', 'reveal_area'].includes(type)) object.region = region(type === 'reveal_area' ? [340, 340] : small ? [4, 3] : size);
    if (type === 'reveal_area') object.region.shape = 'circle';
    if (['pit', 'thorns', 'mud', 'web', 'collision_damage'].includes(type)) Object.assign(object, { targets: type === 'web' ? 'flying' : 'all', effect_ref: '', interval: 1 });
    if (type === 'collision_damage') object.damage = 0;
    if (type === 'pit') object.region.depth = 2;
    if (['thorns', 'mud'].includes(type)) Object.assign(object, { slow_ratio: 0.3, linger: 0 });
    if (type === 'web') Object.assign(object, { min_height: 0, max_height: 5, duration: 1, interval: 1 });
    if (type === 'deployment') Object.assign(object, { facing: 0, slots: [[-1, 0], [1, 0]], rule_ref: '' });
    if (type === 'enemy') Object.assign(object, { monster_config_id: '', facing: 180, team_group: 'enemy' });
    if (type === 'tree') object.linked_collision_id = '';
    if (type === 'post_battle') Object.assign(object, { summon_option_ref: '', upgrade_option_ref: '', condition_ref: 'battle_won' });
    if (type === 'cloth') Object.assign(object.visual, { size: [1650, 1450], opacity: 0.7, z_index: -100 });
    return object;
  }
  function createMap(kind, id, name) {
    if (kind === 'battle') return { id, name, kind, radius: 18, orientation: 'flat', ground_asset: '', background_asset: '', ground_color: '#6b8060', background_blur: 9, edge_feather: 0.8, natural_border: true, wall: { thickness: 0.5, height: 12, layer: 1 }, objects: [] };
    return { id, name, kind: 'exploration', ground_asset: '', background_asset: '', ground_color: '#465d49', bounds: { position: [-64, -64], size: [1568, 1385.64] }, outline: [], spawn: [120, 220],
      native: { source_scene: 'res://world_map/demo/WorldMapDemo.tscn', definition_path: 'res://world_map/demo/data/frontier.tres', map_id: id, width: 16, height: 12, hex_size: 64, disabled_hexes: [[0, 0], [1, 0], [0, 1], [15, 4], [14, 4], [7, 4], [8, 3]], default_spawn_id: 'harbor', spawns: { harbor: [120, 220] }, discovery_radius: 240, interaction_radius: 42, vision_radius: 210, generator_config: {} },
      fog: { enabled: true, source_ref: 'player', radius: 210, unknown_color: '#101c20', unknown_opacity: 0.94, texture_ref: '', retention: 'recover', explored_color: '#172d2b', explored_opacity: 0.5, feather: 36, fade_duration: 0.3 }, objects: [] };
  }
  function createProject() {
    const project = { format: 'frontier-map-editor', version: VERSION, name: '边境地图工作集', assets: clone(ASSETS),
      catalogs: { conditions: [{ id: 'has_monster', name: '至少持有一只怪兽', kind: 'monster_count', minimum: 1 }, { id: 'battle_won', name: '战斗已胜利', kind: 'external' }],
        events: [{ id: 'town_visit', name: '城镇访问' }, { id: 'camp_reward', name: '营地战后事件' }], effects: [], options: [{ id: 'summon', name: '召唤' }, { id: 'upgrade', name: '升级' }],
        monster_configs: [{ id: 'demo_guard', name: '示意守卫' }], enemy_configs: [{ id: 'camp_guards', name: '营地守卫队' }], deployment_rules: [] }, maps: [] };
    const exploration = createMap('exploration', 'frontier', '边境 · 探索大地图'), battle = createMap('battle', 'camp_battle_01', '林地营地 · 战斗地图');
    project.maps.push(exploration, battle);
    function add(type, map, position, overrides = {}) { const item = createObject(type, map, project, position); Object.assign(item, overrides); map.objects.push(item); return item; }
    add('cloth', exploration, [700, 600]);
    const road = add('road', exploration, [0, 0], { id: 'frontier_road', name: '营地主路', points: [[120, 220], [200, 340], [200, 490], [520, 490], [640, 490], [740, 450], [900, 420], [1150, 415]], width: 64 });
    road.visual.z_index = 1;
    add('road', exploration, [0, 0], { id: 'frontier_south_road', name: '南方支路', points: [[200, 490], [240, 650], [260, 800], [330, 895]], width: 52 });
    const ridge = add('indestructible', exploration, [0, 0], { id: 'rock_ridge', name: '山脊', native_obstacle: true });
    ridge.collision.shape = 'polygon'; ridge.collision.points = [[420, 220], [520, 195], [585, 280], [545, 375], [465, 420], [405, 335]];
    ridge.discovery.initially_visible = true;
    const town = add('town', exploration, [260, 265], { id: 'town', name: 'Test Town', event_id: 'town_visit', target_scene: 'res://scenario_2_5d/demo/Scenario25DDemo.tscn' }); town.discovery.initially_visible = true;
    const camp = add('camp', exploration, [900, 420], { id: 'monster_camp_01', name: '林地怪兽营地', battle_map_id: battle.id, enemy_config_id: 'camp_guards', deployment_id: 'player_deploy_01', post_event_id: 'camp_reward', blocking_obstacle_ids: ['camp_barrier_01'] }); camp.discovery.initially_visible = true;
    const barrier = add('destructible', exploration, [790, 450], { id: 'camp_barrier_01', name: '营地前方路障', blocked_ids: [camp.id] }); barrier.discovery.initially_visible = true; barrier.visual.size = [115, 65]; barrier.collision.size = [100, 40];
    add('house', exploration, [330, 860], { id: 'monument', name: 'Ancient Monument', target_scene: '', native_type_id: 'event', native_definition_path: 'res://world_map/demo/data/event.tres', completion_behavior: 'HIDE_SESSION' });
    add('reveal_area', exploration, [120, 220], { id: 'initial_harbor', name: '港口初始揭示' });
    const deployment = add('deployment', battle, [-8, 7], { id: 'player_deploy_01', name: '己方入口部署区', facing: -35 }); deployment.region.size = [6, 4];
    add('broken_barricade', battle, [-11.8, 8.2], { id: 'entry_rubble_01', name: '左下入口路障残骸' }).visual.size = [4.2, 2.4];
    const rock = add('collision_damage', battle, [-2, -3], { id: 'arena_rock_01', name: '战场岩石', damage: 0 }); rock.visual.size = [3.2, 3]; rock.collision.size = [2.6, 2.5];
    add('mud', battle, [4, 3], { id: 'arena_mud_01', name: '可穿越泥潭' }).visual.size = [5, 3.5];
    add('web', battle, [5, -4], { id: 'arena_web_01', name: '飞行单位蛛网' });
    add('tree', battle, [-6, -7], { id: 'arena_tree_01', name: '场内装饰树' });
    add('enemy', battle, [7, -6], { id: 'camp_guard_01', name: '营地守卫', monster_config_id: 'demo_guard' });
    add('enemy', battle, [10, -2], { id: 'camp_guard_02', name: '营地守卫', monster_config_id: 'demo_guard' });
    add('post_battle', battle, [0, 0], { id: 'camp_altar_01', name: '战后中心祭坛', event_id: 'camp_reward', summon_option_ref: 'summon', upgrade_option_ref: 'upgrade' });
    return project;
  }
  function polygon(map) {
    if (map.kind === 'exploration') {
      if (map.outline && map.outline.length >= 3) return map.outline.map(point => point.slice());
      const [x, y] = map.bounds.position, [w, h] = map.bounds.size;
      return [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];
    }
    const start = map.orientation === 'pointy' ? -Math.PI / 2 : 0;
    return Array.from({ length: 6 }, (_, i) => [Math.cos(start + i * Math.PI / 3) * map.radius, Math.sin(start + i * Math.PI / 3) * map.radius]);
  }
  function pointInPolygon(point, points) {
    let inside = false;
    for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
      const a = points[i], b = points[j];
      if (distanceToSegment(point, a, b) < 1e-7) return true;
      if ((a[1] > point[1]) !== (b[1] > point[1]) && point[0] < (b[0] - a[0]) * (point[1] - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
    }
    return inside;
  }
  function distanceToSegment(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1], length = dx * dx + dy * dy;
    const t = length ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length)) : 0;
    return Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy);
  }
  function localPoint(object, point) {
    const angle = -object.rotation * Math.PI / 180, dx = point[0] - object.position[0], dy = point[1] - object.position[1];
    return [(dx * Math.cos(angle) - dy * Math.sin(angle)) / object.scale[0], (dx * Math.sin(angle) + dy * Math.cos(angle)) / object.scale[1]];
  }
  function worldPoint(object, point) {
    const angle = object.rotation * Math.PI / 180, x = point[0] * object.scale[0], y = point[1] * object.scale[1];
    return [object.position[0] + x * Math.cos(angle) - y * Math.sin(angle), object.position[1] + x * Math.sin(angle) + y * Math.cos(angle)];
  }
  function shapeContains(shape, p) {
    if (!shape || !shape.enabled) return false;
    const angle = -shape.rotation * Math.PI / 180, dx = p[0] - shape.offset[0], dy = p[1] - shape.offset[1];
    const local = [dx * Math.cos(angle) - dy * Math.sin(angle), dx * Math.sin(angle) + dy * Math.cos(angle)];
    if (shape.shape === 'polygon') return pointInPolygon(local, shape.points || []);
    if (shape.shape === 'circle') return Math.hypot(local[0] / (shape.size[0] / 2), local[1] / (shape.size[1] / 2)) <= 1;
    return Math.abs(local[0]) <= shape.size[0] / 2 && Math.abs(local[1]) <= shape.size[1] / 2;
  }
  function hit(object, point, tolerance = 0) {
    const local = localPoint(object, point);
    if (object.type === 'road') return object.points.slice(1).some((p, i) => distanceToSegment(local, object.points[i], p) <= object.width / 2 + tolerance);
    if (object.type === 'reveal_area' || object.type === 'deployment') return shapeContains(object.region, local);
    if (object.native_obstacle) return shapeContains(object.collision, local);
    if (object.click_area && shapeContains(object.click_area, local)) return true;
    return Math.abs(local[0]) <= object.visual.size[0] / 2 + tolerance && Math.abs(local[1]) <= object.visual.size[1] / 2 + tolerance;
  }
  function refs(project, ref, object) {
    if (ref === 'assets') return project.assets;
    if (ref === 'battles') return project.maps.filter(map => map.kind === 'battle');
    if (ref === 'battle_deployments') return project.maps.filter(map => map.id === object.battle_map_id).flatMap(map => map.objects.filter(item => item.type === 'deployment'));
    return project.catalogs[ref] || [];
  }
  function validate(project) {
    const issues = [], ids = new Set();
    const report = (map, object, message, severity = 'error') => issues.push({ map_id: map.id, object_id: object ? object.id : '', message, severity });
    const finite = value => typeof value === 'number' && Number.isFinite(value);
    const vector = value => Array.isArray(value) && value.length === 2 && value.every(finite);
    const unique = (id, map, object) => { if (!id || !/^[\w.-]+$/.test(id)) report(map, object, 'ID 不能为空，且应仅含英文、数字、下划线、点或横线'); if (ids.has(id)) report(map, object, '重复 ID：' + id); ids.add(id); };
    for (const key of Object.keys(project.catalogs)) {
      const seen = new Set();
      for (const entry of project.catalogs[key]) { if (!entry.id || seen.has(entry.id)) report(project.maps[0], null, `${key} 引用表中 ID 缺失或重复：${entry.id}`); seen.add(entry.id); }
    }
    const assetIds = new Set(project.assets.map(asset => asset.id));
    if (assetIds.size !== project.assets.length) report(project.maps[0], null, '素材 ID 重复');
    for (const asset of project.assets) if (!asset.path && !asset.data) report(project.maps[0], null, '素材缺少路径或嵌入数据：' + asset.id);
    for (const map of project.maps) {
      unique(map.id, map, null);
      for (const field of mapFields(map)) {
        const value = get(map, field.path);
        if (field.kind === 'number' && (!finite(value) || value < field.min || value > field.max)) report(map, null, field.label + ' 超出有效范围');
        if (field.kind === 'vector' && !vector(value)) report(map, null, field.label + ' 应为两个有效数值');
        if (field.kind === 'reference' && value && !refs(project, field.ref, map).some(entry => entry.id === value)) report(map, null, field.label + ' 引用不存在：' + value);
        if (field.kind === 'select' && !field.options.includes(value)) report(map, null, field.label + ' 选项无效');
      }
      if (map.kind === 'exploration' && map.bounds.size.some(value => value <= 0)) report(map, null, '地图范围尺寸必须大于零');
      if (map.kind === 'exploration' && !pointInPolygon(map.spawn, polygon(map))) report(map, null, '默认出生点位于地图外');
      const mapIds = new Set(map.objects.map(object => object.id)), connectionIds = new Set(map.objects.filter(o => o.type === 'road').flatMap(o => o.connection_ids || []));
      for (const object of map.objects) {
        unique(object.id, map, object);
        if (!TYPES[object.type] || !TYPES[object.type].modes.includes(map.kind)) { report(map, object, '对象类型与地图模式不兼容'); continue; }
        for (const field of fieldsFor(object)) {
          const value = get(object, field.path);
          if (field.kind === 'number' && (!finite(value) || value < field.min || value > field.max)) report(map, object, field.label + ' 超出有效范围');
          if (field.kind === 'vector' && !vector(value)) report(map, object, field.label + ' 未设置或不是有效坐标');
          if (field.kind === 'reference' && value && !refs(project, field.ref, object).some(entry => entry.id === value)) report(map, object, field.label + ' 引用不存在：' + value);
          if (field.kind === 'select' && !field.options.includes(value)) report(map, object, field.label + ' 选项无效');
          if (field.kind === 'points' && value && (!Array.isArray(value) || !value.every(vector))) report(map, object, field.label + ' 节点格式无效');
        }
        if (object.scale.some(value => value <= 0)) report(map, object, '缩放必须为正数');
        if (object.visual.size.some(value => value <= 0)) report(map, object, '视觉尺寸必须为正数');
        if (object.type === 'traversable' && (!object.condition_ref || !vector(object.landing))) report(map, object, '可跨越障碍必须填写条件引用及落点');
        if (object.landing && !pointInPolygon(object.landing, polygon(map))) report(map, object, '跨越落点越界');
        if (object.type === 'indestructible' && (object.broken_asset || object.destroy_reward)) report(map, object, '不可破坏障碍不能配置破损素材或破坏奖励');
        if (object.type === 'road' && (object.points.length < 2 || !object.points.slice(1).some((p, i) => Math.hypot(p[0] - object.points[i][0], p[1] - object.points[i][1]) > 0.01))) report(map, object, '道路至少需要两个不同的节点');
        if (object.type === 'web' && object.max_height < object.min_height) report(map, object, '蛛网最高生效高度小于最低高度');
        if (object.type === 'web' && object.targets !== 'flying') report(map, object, '蛛网当前作用对象不是 flying，请确认配置', 'warning');
        for (const key of ['collision', 'region', 'click_area']) {
          const shape = object[key]; if (!shape || !shape.enabled) continue;
          if (shape.size.some(value => value <= 0)) report(map, object, key + ' 尺寸必须为正数');
          if (shape.shape === 'polygon' && (shape.points.length < 3 || selfIntersects(shape.points))) report(map, object, key + ' 多边形节点不足或轮廓自交');
        }
        for (const id of object.blocked_ids || []) if (!mapIds.has(id) && !connectionIds.has(id)) report(map, object, '被阻挡地点或连接不存在：' + id);
        for (const id of object.blocking_obstacle_ids || []) if (!map.objects.some(o => o.id === id && ['destructible', 'traversable', 'indestructible'].includes(o.type))) report(map, object, '关联障碍不存在或类型不正确：' + id);
        if (object.linked_collision_id && !map.objects.some(o => o.id === object.linked_collision_id && o.collision?.enabled)) report(map, object, '关联碰撞对象不存在或未启用');
        if (object.target_scene && !/^res:\/\/.+\.tscn$/.test(object.target_scene)) report(map, object, '目标场景应填写 res:// 路径的 .tscn 文件');
        if (object.type === 'camp' && !object.battle_map_id) report(map, object, '营地未关联战斗地图');
        if (object.type === 'post_battle' && (!object.event_id || !object.summon_option_ref || !object.upgrade_option_ref)) report(map, object, '战后交互必须配置事件、召唤和升级选项');
        if (object.type === 'enemy' && !object.monster_config_id) report(map, object, '敌方怪兽配置 ID 未设置');
        if (map.kind === 'battle') {
          if (!pointInPolygon(object.position, polygon(map))) report(map, object, '对象中心位于战场外；调整尺寸不会自动删除或缩放它');
          if (object.type === 'deployment') {
            const slots = object.slots.map(slot => worldPoint(object, slot));
            slots.forEach((slot, index) => {
              if (!pointInPolygon(slot, polygon(map)) || !shapeContains(object.region, localPoint(object, slot))) report(map, object, `部署槽位 ${index + 1} 不在战场 / 部署区内`);
              for (const obstacle of map.objects) if ((obstacle.collision?.enabled && shapeContains(obstacle.collision, localPoint(obstacle, slot))) || (obstacle.type === 'pit' && shapeContains(obstacle.region, localPoint(obstacle, slot)))) report(map, object, `部署槽位 ${index + 1} 落入 ${obstacle.id} 的障碍或坑洞`);
              for (const other of map.objects.filter(o => o.type === 'deployment')) for (let j = 0; j < other.slots.length; j++) if ((other !== object || j !== index) && Math.hypot(...worldPoint(other, other.slots[j]).map((v, k) => v - slot[k])) < 0.15) report(map, object, `部署槽位 ${index + 1} 与 ${other.id} 的槽位重叠`);
            });
          }
        }
      }
    }
    return issues;
  }
  function selfIntersects(points) {
    const cross = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
    for (let i = 0; i < points.length; i++) for (let j = i + 2; j < points.length; j++) {
      if (i === 0 && j === points.length - 1) continue;
      const a = points[i], b = points[(i + 1) % points.length], c = points[j], d = points[(j + 1) % points.length];
      if (cross(a, b, c) * cross(a, b, d) < 0 && cross(c, d, a) * cross(c, d, b) < 0) return true;
    }
    return false;
  }
  function parseDocument(text) {
    const project = JSON.parse(text);
    if (project.format !== 'frontier-map-editor' || project.version !== VERSION || !Array.isArray(project.maps) || !project.maps.length || !Array.isArray(project.assets) || !project.catalogs) throw Error('不是受支持的编辑器工作集，或版本不兼容');
    for (const map of project.maps) {
      if (!['battle', 'exploration'].includes(map.kind) || !Array.isArray(map.objects)) throw Error('地图结构无效');
      if (map.kind === 'exploration' && (!map.bounds || !map.native || !map.fog)) throw Error('探索地图配置缺失');
      if (map.kind === 'battle' && !map.wall) throw Error('战场边界配置缺失');
      for (const object of map.objects) if (!TYPES[object.type] || !Array.isArray(object.position) || !Array.isArray(object.scale) || !object.visual) throw Error('对象结构无效：' + (object.id || '无 ID'));
    }
    // Reject malformed shape records before rendering or editing them.
    for (const map of project.maps) for (const object of map.objects) {
      for (const key of ['collision', 'region', 'click_area']) if (object[key]) {
        const shape = object[key];
        if (!Array.isArray(shape.size) || !Array.isArray(shape.offset) || !Array.isArray(shape.points)) throw Error('区域结构无效：' + object.id);
      }
    }
    validate(project); // Structural errors must fail before replacing the current document.
    return project;
  }
  function serialize(project) { return JSON.stringify(project, null, 2); }
  class History {
    constructor(project) { this.document = clone(project); this.undoStack = []; this.redoStack = []; this.limit = 100; }
    change(label, operation) {
      const before = clone(this.document); operation(this.document);
      if (serialize(before) === serialize(this.document)) return false;
      this.undoStack.push({ label, value: before }); if (this.undoStack.length > this.limit) this.undoStack.shift(); this.redoStack = []; return true;
    }
    commit(label, before) { if (serialize(before) === serialize(this.document)) return; this.undoStack.push({ label, value: clone(before) }); this.redoStack = []; }
    undo() { const state = this.undoStack.pop(); if (!state) return false; this.redoStack.push({ label: state.label, value: clone(this.document) }); this.document = state.value; return true; }
    redo() { const state = this.redoStack.pop(); if (!state) return false; this.undoStack.push({ label: state.label, value: clone(this.document) }); this.document = state.value; return true; }
  }
  class FogPreview {
    constructor(map) { this.reset(map); }
    reset(map) { this.mapId = map.id; this.player = (map.spawn || [0, 0]).slice(); this.samples = []; this.discovered = new Set(); this.destroyed = new Set(); this.crossed = new Set(); this.rewards = new Set(); this.fullReveal = false; this.won = false; this.move(this.player, map, null, false); }
    importSave(save, map) {
      if (save.save_version !== 1 || save.map_id !== map.id || !save.player_position || !Array.isArray(save.exploration_samples)) throw Error('存档版本或地图 ID 不匹配');
      const player = [save.player_position.x, save.player_position.y]; if (!player.every(Number.isFinite)) throw Error('玩家位置无效');
      const samples = [];
      for (const sample of save.exploration_samples) {
        const start = sample.from || sample.position, end = sample.position, radius = sample.radius;
        if (!start || !end || ![start.x, start.y, end.x, end.y, radius].every(Number.isFinite) || radius <= 0) throw Error('探索记录无效');
        const count = Math.max(1, Math.ceil(Math.hypot(end.x - start.x, end.y - start.y) / Math.max(1, radius / 3)));
        if (count > 20000) throw Error('存档探索段过长');
        for (let i = 0; i <= count; i++) samples.push([start.x + (end.x - start.x) * i / count, start.y + (end.y - start.y) * i / count, radius]);
      }
      this.player = player; this.samples = samples; this.discovered = new Set(Object.entries(save.location_runtime_states || {}).filter(([, state]) => state.discovered).map(([id]) => id)); this.fullReveal = false;
    }
    condition(project, id, monsters = 0, enabled = []) {
      if (!id) return true;
      const rule = project.catalogs.conditions.find(entry => entry.id === id);
      if (!rule) return false;
      if (rule.kind === 'monster_count') return monsters >= Number(rule.minimum || 1);
      if (id === 'battle_won') return this.won;
      return enabled.includes(id);
    }
    move(point, map, project, record = true, monsters = 0, enabled = []) {
      if (record && map.fog?.enabled) {
        const distance = Math.hypot(point[0] - this.player[0], point[1] - this.player[1]), count = Math.max(1, Math.ceil(distance / Math.max(1, map.fog.radius / 3)));
        for (let i = 1; i <= count; i++) this.samples.push([this.player[0] + (point[0] - this.player[0]) * i / count, this.player[1] + (point[1] - this.player[1]) * i / count, map.fog.radius]);
      }
      this.player = point.slice();
      if (project) for (const object of map.objects) if (object.discovery && Math.hypot(point[0] - object.position[0], point[1] - object.position[1]) <= object.discovery.radius && this.condition(project, object.discovery.condition_ref, monsters, enabled)) this.discovered.add(object.id);
    }
    explored(point, map) { return this.samples.some(sample => Math.hypot(point[0] - sample[0], point[1] - sample[1]) <= sample[2]) || map.objects.some(object => object.type === 'reveal_area' && shapeContains(object.region, localPoint(object, point))); }
    visibility(point, map) {
      if (this.fullReveal) return 'visible';
      if (Math.hypot(point[0] - this.player[0], point[1] - this.player[1]) <= map.fog.radius) return 'visible';
      return this.explored(point, map) ? 'explored' : 'unknown';
    }
    objectVisible(object) { return !object.discovery || object.discovery.initially_visible || this.discovered.has(object.id); }
    canClick(object) { return this.objectVisible(object) || !!object.discovery?.allow_hidden_interaction; }
    canEnter(project, map, camp, monsters = 0, enabled = []) {
      if (!this.canClick(camp) || !this.condition(project, camp.condition_ref, monsters, enabled)) return false;
      const blockers = map.objects.filter(object => (camp.blocking_obstacle_ids || []).includes(object.id) || (object.blocked_ids || []).includes(camp.id));
      return blockers.every(object => this.destroyed.has(object.id) || this.crossed.has(object.id));
    }
  }
  return { VERSION, TYPES, LAYERS, ASSETS, clone, f, get, set, region, fieldsFor, mapFields, createMap, createObject, createProject, uniqueId, polygon, pointInPolygon, distanceToSegment, worldPoint, localPoint, shapeContains, hit, refs, validate, parseDocument, serialize, History, FogPreview, selfIntersects };
});
