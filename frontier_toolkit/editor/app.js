(function () {
  'use strict';
  const M = MapEditorModel, $ = id => document.getElementById(id);
  const node = (tag, text, className) => { const element = document.createElement(tag); if (text != null) element.textContent = text; if (className) element.className = className; return element; };
  class EditorApp {
    constructor() {
      this.history = new M.History(M.createProject()); this.mapId = this.project.maps[0].id; this.selectedId = ''; this.mode = 'edit'; this.libraryTab = 'elements'; this.tool = ''; this.assetTool = ''; this.pointPath = ''; this.pointIndex = -1; this.addingPoints = false; this.space = false; this.drag = null; this.transitioning = false;
      this.canvas = $('map-canvas'); this.view = { zoom: 1, pan: [0, 0] }; this.layers = Object.fromEntries(Object.keys(M.LAYERS).map(key => [key, true])); this.preview = new M.FogPreview(this.map); this.enabledConditions = []; this.missingAssets = new Set(); this.savedText = M.serialize(this.project); this.fileHandle = null;
      this.renderer = new MapEditorRenderer(this); this.bind(); this.refresh();
      new ResizeObserver(() => this.renderer.resize()).observe($('canvas-shell'));
      requestAnimationFrame(() => { this.renderer.resize(); this.renderer.fit(); });
      window.addEventListener('beforeunload', event => { if (this.isDirty()) { event.preventDefault(); event.returnValue = ''; } });
    }
    get project() { return this.history.document; }
    get map() { return this.project.maps.find(map => map.id === this.mapId) || this.project.maps[0]; }
    get selected() { return this.map.objects.find(object => object.id === this.selectedId); }
    get monsters() { return Math.max(0, Number($('sim-monsters').value)); }
    isDirty() { return M.serialize(this.project) !== this.savedText; }
    toast(message) { $('toast').textContent = message; $('toast').classList.add('show'); clearTimeout(this.toastTimer); this.toastTimer = setTimeout(() => $('toast').classList.remove('show'), 4000); }
    commit(label, operation, rebuild = true) { this.history.change(label, operation); this.missingAssets.clear(); if (rebuild) this.refresh(); else { this.refreshIssues(); this.renderer.draw(); this.updateDirty(); } }
    updateDirty() { $('dirty').textContent = this.isDirty() ? '· 未保存' : '· 已保存'; $('undo').disabled = !this.history.undoStack.length; $('redo').disabled = !this.history.redoStack.length; }
    refresh() {
      if (!this.project.maps.some(map => map.id === this.mapId)) this.mapId = this.project.maps[0].id;
      $('project-name').textContent = this.project.name; $('map-title').textContent = this.map.name; $('map-kind').textContent = this.map.kind === 'battle' ? 'BATTLEFIELD / 独立六边形战场' : 'EXPLORATION / 连续探索大地图';
      $('simulation').hidden = this.mode === 'edit'; $('sim-victory').hidden = this.map.kind !== 'battle'; $('reveal-all').hidden = $('load-save').hidden = this.map.kind === 'battle';
      document.querySelector('[data-mode="fog"]').disabled = this.map.kind === 'battle';
      this.refreshMaps(); this.refreshLibrary(); this.refreshLayers(); this.refreshInspector(); this.refreshObjects(); this.refreshIssues(); this.updateDirty(); this.renderer.draw();
    }
    refreshMaps() {
      const list = $('map-list'); list.replaceChildren();
      for (const map of this.project.maps) {
        const card = node('div', null, 'map-card' + (map.id === this.map.id ? ' active' : '')); card.setAttribute('role', 'button'); card.tabIndex = 0;
        card.append(node('i', map.kind === 'battle' ? '⬡' : '▧')); const info = node('div'); info.append(node('span', map.name), node('small', (map.kind === 'battle' ? '战斗地图' : '探索地图') + ' · ' + map.objects.length + ' 个对象')); card.append(info);
        card.onclick = () => this.switchMap(map.id); card.onkeydown = event => { if (event.key === 'Enter') this.switchMap(map.id); }; list.append(card);
      }
    }
    switchMap(id, preserveMode = false) {
      this.mapId = id; this.selectedId = ''; this.tool = ''; this.pointPath = ''; this.addingPoints = false; this.preview = new M.FogPreview(this.map); if (!preserveMode) this.mode = 'edit'; if (this.mode === 'fog' && this.map.kind === 'battle') this.mode = 'preview';
      this.refreshModeButtons(); this.refresh(); this.renderer.fit(); this.banner();
    }
    refreshLibrary() {
      const library = $('asset-library'), search = $('library-search').value.trim(); library.replaceChildren();
      if (this.libraryTab === 'assets') {
        const grid = node('div', null, 'asset-grid');
        for (const asset of this.project.assets.filter(entry => !search || (entry.name + entry.id).includes(search))) {
          const tile = node('div', null, 'asset-tile' + (this.assetTool === asset.id ? ' selected' : '')); tile.draggable = true; tile.title = asset.path || '嵌入图片';
          const image = node('img'); image.src = asset.data || this.renderer.assetUrl(asset.path); image.alt = asset.name; tile.append(image, node('span', asset.name));
          tile.onclick = () => { if (this.selected) this.updateField('visual.asset', asset.id); else { this.tool = this.map.kind === 'battle' ? 'decoration' : 'decoration'; this.assetTool = asset.id; this.banner(); } };
          tile.ondragstart = event => event.dataTransfer.setData('application/frontier-asset', asset.id); grid.append(tile);
        }
        library.append(grid); return;
      }
      const entries = Object.entries(M.TYPES).filter(([id, spec]) => spec.modes.includes(this.map.kind) && (!search || (id + spec.name).includes(search)));
      $('type-count').textContent = entries.length;
      for (const group of [...new Set(entries.map(([, spec]) => spec.group))]) {
        library.append(node('div', group, 'asset-group')); const grid = node('div', null, 'asset-grid');
        for (const [id, spec] of entries.filter(([, spec]) => spec.group === group)) {
          const tile = node('div', null, 'asset-tile' + (this.tool === id ? ' selected' : '')); tile.draggable = true; tile.tabIndex = 0; tile.setAttribute('role', 'button'); tile.setAttribute('aria-label', '放置' + spec.name);
          const asset = this.project.assets.find(entry => entry.id === spec.asset);
          if (asset) { const image = node('img'); image.src = asset.data || this.renderer.assetUrl(asset.path); image.alt = ''; tile.append(image); } else tile.append(node('i', spec.icon));
          tile.append(node('span', spec.name)); tile.onclick = () => { this.tool = id; this.assetTool = ''; this.setMode('edit'); this.refreshLibrary(); this.banner(); };
          tile.onkeydown = event => { if (event.key === 'Enter') tile.click(); }; tile.ondragstart = event => event.dataTransfer.setData('application/frontier-type', id); grid.append(tile);
        }
        library.append(grid);
      }
    }
    refreshLayers() {
      const list = $('layers'); list.replaceChildren();
      for (const [key, name] of Object.entries(M.LAYERS)) {
        const label = node('label', null, 'layer-row'), checkbox = node('input'); checkbox.type = 'checkbox'; checkbox.checked = this.layers[key]; checkbox.onchange = () => { this.layers[key] = checkbox.checked; this.renderer.draw(); }; label.append(checkbox, node('span', name)); list.append(label);
      }
    }
    refreshObjects() {
      const list = $('object-list'); list.replaceChildren(); $('object-count').textContent = this.map.objects.length;
      for (const object of this.map.objects) {
        const chip = node('div', null, 'object-chip' + (this.selectedId === object.id ? ' active' : '')); chip.tabIndex = 0;
        const text = node('div'); text.append(node('strong', object.name), node('small', object.id)); chip.append(node('i', M.TYPES[object.type].icon), text); chip.onclick = () => this.select(object.id); chip.ondblclick = () => this.focusObject(object); list.append(chip);
      }
    }
    refreshInspector() {
      const target = this.selected || this.map, fields = this.selected ? M.fieldsFor(target) : M.mapFields(target);
      $('inspector-title').textContent = this.selected ? M.TYPES[target.type].name : '地图设置'; $('duplicate').disabled = $('delete').disabled = !this.selected || this.mode !== 'edit';
      const list = $('inspector-fields'); list.replaceChildren();
      const intro = node('div', this.selected ? `ID · ${target.id}` : this.map.kind === 'battle' ? '改变半径只重算边界，不缩放已有对象。' : '连续地图 · 后台 Hex 不作为可见格线。', 'section-label'); list.append(intro);
      for (const spec of fields) {
        const field = node('div', null, 'field'), label = node('label', spec.label); field.append(label);
        field.dataset.path = spec.path; field.dataset.kind = spec.kind;
        const value = M.get(target, spec.path), update = newValue => this.updateField(spec.path, newValue);
        if (spec.kind === 'vector') {
          const row = node('div', null, 'vector');
          for (let axis = 0; axis < 2; axis++) { const input = node('input'); input.type = 'number'; input.step = 'any'; input.value = value?.[axis] ?? ''; input.placeholder = axis ? 'Y / Z' : 'X'; input.setAttribute('aria-label', spec.label + ' ' + axis); input.onchange = () => { const vector = value ? value.slice() : [0, 0]; vector[axis] = Number(input.value); update(vector); }; row.append(input); } field.append(row);
        } else if (spec.kind === 'points') this.pointEditor(field, spec, value || [], update);
        else if (spec.kind === 'select' || spec.kind === 'reference') {
          const input = node('select'); let choices = spec.kind === 'select' ? spec.options.map(id => ({ id, name: id })) : [{ id: '', name: '未设置 / 无' }, ...M.refs(this.project, spec.ref, target)];
          if (value && !choices.some(entry => entry.id === value)) choices.push({ id: value, name: value + '（引用缺失）' });
          for (const entry of choices) { const option = node('option', entry.name || entry.id); option.value = entry.id; input.append(option); }
          input.value = value || ''; input.onchange = () => update(input.value); input.setAttribute('aria-label', spec.label); field.append(input);
        } else {
          const input = node('input'); input.type = spec.kind === 'boolean' ? 'checkbox' : spec.kind === 'number' ? 'number' : spec.kind === 'color' ? 'color' : 'text';
          if (spec.kind === 'boolean') input.checked = !!value; else input.value = spec.kind === 'strings' ? (value || []).join(', ') : value ?? '';
            if (spec.kind === 'number') { if (spec.min !== undefined) input.min = spec.min; if (spec.max !== undefined) input.max = spec.max; input.step = 'any'; }
          input.setAttribute('aria-label', spec.label);
          input.onchange = () => { if (spec.kind === 'number' && (!input.validity.valid || !Number.isFinite(Number(input.value)))) { this.toast('请输入范围内的数值'); return; } update(spec.kind === 'boolean' ? input.checked : spec.kind === 'number' ? Number(input.value) : spec.kind === 'strings' ? input.value.split(',').map(v => v.trim()).filter(Boolean) : input.value); };
          field.append(input);
        }
        for (const control of field.querySelectorAll('input,select')) control.onblur = () => { if (control.isConnected) control.onchange?.(); };
        list.append(field);
      }
      $('advanced-json').value = JSON.stringify(target, null, 2);
    }
    pointEditor(field, spec, points, update) {
      points.forEach((point, index) => {
        const row = node('div', null, 'point-row'); row.append(node('span', index + 1));
        for (let axis = 0; axis < 2; axis++) { const input = node('input'); input.type = 'number'; input.step = 'any'; input.value = point[axis]; input.onchange = () => { const next = M.clone(points); next[index][axis] = Number(input.value); update(next); }; row.append(input); }
        const up = node('button', '↑'), down = node('button', '↓'), remove = node('button', '×'); up.title = '上移节点'; down.title = '下移节点'; remove.title = '删除节点';
        up.disabled = index === 0; down.disabled = index === points.length - 1;
        up.onclick = () => { const next = M.clone(points); [next[index - 1], next[index]] = [next[index], next[index - 1]]; update(next); };
        down.onclick = () => { const next = M.clone(points); [next[index + 1], next[index]] = [next[index], next[index + 1]]; update(next); };
        remove.onclick = () => update(points.filter((_, i) => i !== index)); row.append(up, down, remove); field.append(row);
      });
      const tools = node('div', null, 'point-tools'), add = node('button', '＋ 添加节点'); add.onclick = () => update([...points, points.length ? [points.at(-1)[0] + (this.map.kind === 'battle' ? 1 : 40), points.at(-1)[1]] : [0, 0]]); tools.append(add);
      if (this.selected && !spec.path.includes('native')) {
        const edit = node('button', '画布编辑'); edit.onclick = () => { this.pointPath = spec.path; this.pointIndex = -1; this.addingPoints = false; this.tool = ''; this.banner(); this.renderer.draw(); this.toast('拖动青色节点；使用“画布加点”添加；Delete 删除选中的节点'); };
        const draw = node('button', '画布加点'); draw.onclick = () => { this.pointPath = spec.path; this.addingPoints = true; this.tool = ''; this.banner(); };
        tools.append(edit, draw);
      }
      field.append(tools);
    }
    updateField(path, value) {
      if (this.mode !== 'edit') { this.toast('请先切回布局编辑模式'); this.refreshInspector(); return; }
      const selectedId = this.selectedId, mapId = this.map.id;
      this.commit('修改 ' + path, project => {
        const map = project.maps.find(entry => entry.id === mapId), target = selectedId ? map.objects.find(entry => entry.id === selectedId) : map;
        if (path === 'id') {
          const old = target.id; this.renameReferences(project, old, value);
          if (selectedId) this.selectedId = value; else this.mapId = value;
        }
        M.set(target, path, value);
        if (!selectedId && path === 'id' && map.native) map.native.map_id = value;
        if (!selectedId && path === 'spawn' && map.native) map.native.spawns[map.native.default_spawn_id] = value.slice();
      });
      if (!selectedId && path.startsWith('fog.')) this.preview.reset(this.map);
      if (!selectedId && ['radius', 'orientation'].includes(path)) this.toast('已重算六边形与空气墙边界；已有对象保持原坐标，请检查越界提示');
    }
    applyFields() {
      if (this.mode !== 'edit') { this.toast('请先切回布局编辑'); return; }
      const value = M.clone(this.selected || this.map), oldId = value.id, selected = !!this.selected;
      for (const field of $('inspector-fields').querySelectorAll('.field')) {
        const path = field.dataset.path, kind = field.dataset.kind, input = field.querySelector('input,select'); let next;
        if (kind === 'points') next = [...field.querySelectorAll('.point-row')].map(row => [...row.querySelectorAll('input')].map(control => Number(control.value)));
        else if (kind === 'vector') { const inputs = [...field.querySelectorAll('input')]; next = inputs.every(control => control.value === '') ? null : inputs.map(control => Number(control.value)); }
        else if (kind === 'number') { if (!input.validity.valid) { this.toast('请检查数值范围：' + path); return; } next = Number(input.value); }
        else if (kind === 'boolean') next = input.checked;
        else if (kind === 'strings') next = input.value.split(',').map(text => text.trim()).filter(Boolean);
        else next = input.value;
        M.set(value, path, next);
      }
      if (!selected && value.native) { value.native.map_id = value.id; value.native.spawns[value.native.default_spawn_id] = value.spawn.slice(); }
      this.commit('应用参数', project => { const map = project.maps.find(entry => entry.id === this.mapId); if (selected) map.objects[map.objects.findIndex(object => object.id === oldId)] = value; else project.maps[project.maps.indexOf(map)] = value; this.renameReferences(project, oldId, value.id); if (selected) this.selectedId = value.id; else this.mapId = value.id; });
      if (!selected) this.preview.reset(this.map);
      this.toast('参数已应用，可撤销');
    }
    renameReferences(project, oldId, newId) {
      for (const map of project.maps) for (const object of map.objects) {
        for (const key of ['blocked_ids', 'blocking_obstacle_ids']) if (object[key]) object[key] = object[key].map(id => id === oldId ? newId : id);
        for (const key of ['battle_map_id', 'deployment_id', 'linked_collision_id']) if (object[key] === oldId) object[key] = newId;
      }
    }
    select(id) { this.selectedId = id; this.pointPath = ''; this.pointIndex = -1; this.addingPoints = false; this.tool = ''; this.banner(); this.refreshInspector(); this.refreshObjects(); this.renderer.draw(); $('selection-hint').textContent = this.selected ? this.selected.name + ' · ' + this.selected.id : '未选中对象'; }
    focusObject(object) { const rect = this.canvas.getBoundingClientRect(); this.view.pan = [rect.width / 2 - object.position[0] * this.view.zoom, rect.height / 2 - object.position[1] * this.view.zoom]; this.renderer.draw(); }
    refreshIssues() {
      this.issues = M.validate(this.project);
      for (const id of this.missingAssets) this.issues.push({ map_id: this.map.id, object_id: '', message: '素材文件无法读取：' + id, severity: 'error' });
      const errors = this.issues.filter(issue => issue.severity === 'error'); $('issue-count').textContent = errors.length; $('error-count').textContent = this.issues.length;
      const list = $('issues'); list.replaceChildren();
      if (!this.issues.length) list.append(node('div', '✓ 配置检查通过。导入 Godot 时还会检查资源路径是否真实存在。', 'empty'));
      for (const issue of this.issues) { const row = node('div', `${issue.severity === 'error' ? '●' : '△'} ${issue.map_id} / ${issue.object_id || '地图设置'} · ${issue.message}`, 'issue ' + issue.severity); row.onclick = () => { if (this.map.id !== issue.map_id) this.switchMap(issue.map_id); this.select(issue.object_id); if (this.selected) this.focusObject(this.selected); }; list.append(row); }
    }
    banner() { $('placement-banner').hidden = !(this.tool || this.addingPoints); $('placement-banner').textContent = this.addingPoints ? '正在添加节点 · 点击画布追加 · Esc 结束' : this.tool ? '正在放置：' + M.TYPES[this.tool].name + ' · 点击放置 · Esc 取消' : ''; this.canvas.style.cursor = this.tool || this.addingPoints ? 'crosshair' : 'default'; }
    place(type, point, asset = '') {
      if (this.mode !== 'edit') this.setMode('edit');
      let id;
      this.commit('放置 ' + M.TYPES[type].name, project => { const map = project.maps.find(entry => entry.id === this.mapId), object = M.createObject(type, map, project, this.snap(point)); if (asset) object.visual.asset = asset; map.objects.push(object); id = object.id; });
      this.selectedId = id; this.pointPath = type === 'road' ? 'points' : ''; this.refreshInspector(); this.refreshObjects(); this.renderer.draw(); this.toast('已放置 ' + M.TYPES[type].name + '；可拖动或在右侧填写参数');

	  this.tool = ''; this.assetTool = ''; this.banner(); this.refreshLibrary();
    }
    snap(point) { const step = Number($('snap-size').value); return $('snap').checked && step > 0 ? point.map(value => Math.round(value / step) * step) : point; }
    duplicate() { if (!this.selected || this.mode !== 'edit') return; let id; const source = M.clone(this.selected);
      this.commit('复制对象', project => { const copy = M.clone(source); copy.id = M.uniqueId(project, copy.type); copy.name += ' 副本'; copy.position = copy.position.map(value => value + (this.map.kind === 'battle' ? 1 : 30)); project.maps.find(map => map.id === this.mapId).objects.push(copy); id = copy.id; }); this.select(id); this.toast('已生成新 ID；关联引用保持原值，请按需修改'); }
    remove() {
      if (!this.selected || this.mode !== 'edit') return;
      if (this.pointPath && this.pointIndex >= 0) { const points = M.clone(M.get(this.selected, this.pointPath)); points.splice(this.pointIndex, 1); this.updateField(this.pointPath, points); this.pointIndex = -1; return; }
      const id = this.selectedId; this.commit('删除对象', project => { const map = project.maps.find(entry => entry.id === this.mapId); map.objects = map.objects.filter(object => object.id !== id); }); this.select('');
    }
    setMode(mode) { this.mode = mode; if (mode !== 'edit') { this.tool = ''; this.addingPoints = false; this.pointIndex = -1; } this.refreshModeButtons(); this.refresh(); this.banner(); if (mode !== 'edit' && this.map.kind === 'exploration') this.preview.move(this.preview.player, this.map, this.project, false, this.monsters, this.enabledConditions); }
    refreshModeButtons() { document.querySelectorAll('[data-mode]').forEach(button => button.classList.toggle('active', button.dataset.mode === this.mode)); $('canvas-hint').textContent = this.mode === 'edit' ? '选择要素后点击放置 · 拖动移动 · 滚轮缩放 · 中键 / 空格拖动画布' : '临时预览：点击地面模拟探索 · 点击路障 / 营地验证关联 · 所有模拟状态不导出'; }
    fogFadeAlpha() { return this.fadeStart ? Math.min(1, (performance.now() - this.fadeStart) / Math.max(1, this.map.fog?.fade_duration * 1000)) : 1; }
    animateFog() { this.renderer.fogFrom = this.renderer.lastFog; this.fadeStart = performance.now(); const frame = () => { this.renderer.draw(); if (this.fogFadeAlpha() < 1) requestAnimationFrame(frame); }; requestAnimationFrame(frame); }
    pointerPoint(event) { const rect = this.canvas.getBoundingClientRect(); return [event.clientX - rect.left, event.clientY - rect.top]; }
    pointLocal(object, point, path) {
      const local = M.localPoint(object, point), key = path.split('.')[0], shape = object[key];
      if (!path.includes('.') || !shape?.offset) return this.snap(local);
      const angle = -shape.rotation * Math.PI / 180, dx = local[0] - shape.offset[0], dy = local[1] - shape.offset[1];
      return this.snap([dx * Math.cos(angle) - dy * Math.sin(angle), dx * Math.sin(angle) + dy * Math.cos(angle)]);
    }
    hitObject(point) { return this.map.objects.slice().sort((a, b) => a.visual.z_index - b.visual.z_index).reverse().find(object => this.layers[object.layer] && (this.mode === 'edit' || this.preview.canClick(object)) && M.hit(object, point, 3 / this.view.zoom)); }
    bind() {
      this.canvas.oncontextmenu = event => event.preventDefault();
      this.canvas.onpointerdown = event => {
        if (this.transitioning) return;
        const screen = this.pointerPoint(event), world = this.renderer.world(screen); this.canvas.focus();
        if (event.button === 1 || event.button === 2 || this.space) { this.drag = { kind: 'pan', screen, pan: this.view.pan.slice() }; this.canvas.setPointerCapture(event.pointerId); return; }
        if (event.button !== 0) return;
        if (this.mode !== 'edit') { this.previewClick(world); return; }
        if (this.addingPoints && this.selected) { const points = M.clone(M.get(this.selected, this.pointPath)); points.push(this.pointLocal(this.selected, world, this.pointPath)); this.updateField(this.pointPath, points); return; }
        if (this.tool) { this.place(this.tool, world, this.assetTool); return; }
        const handle = this.selected && this.renderer.pointHandles(this.selected).find(entry => Math.hypot(...entry.position.map((value, i) => value - world[i])) < 10 / this.view.zoom);
        if (handle) { this.pointPath = handle.path; this.pointIndex = handle.index; this.drag = { kind: 'point', before: M.clone(this.project), objectId: this.selectedId, path: handle.path, index: handle.index }; }
        else { const object = this.hitObject(world); this.select(object?.id || ''); if (object) this.drag = { kind: 'object', before: M.clone(this.project), objectId: object.id, start: world, position: object.position.slice() }; }
        if (this.drag) this.canvas.setPointerCapture(event.pointerId);
      };
      this.canvas.onpointermove = event => {
        const screen = this.pointerPoint(event), world = this.renderer.world(screen); $('coordinate').textContent = `X ${world[0].toFixed(1)} · ${this.map.kind === 'battle' ? 'Z' : 'Y'} ${world[1].toFixed(1)}`;
        if (!this.drag) return;
        if (this.drag.kind === 'pan') this.view.pan = screen.map((value, i) => this.drag.pan[i] + value - this.drag.screen[i]);
        else { const object = this.map.objects.find(entry => entry.id === this.drag.objectId); if (this.drag.kind === 'point') M.get(object, this.drag.path)[this.drag.index] = this.pointLocal(object, world, this.drag.path); else object.position = this.snap(this.drag.position.map((value, i) => value + world[i] - this.drag.start[i])); }
        this.renderer.draw();
      };
      const stopDrag = () => { if (this.drag?.before) { this.history.commit(this.drag.kind === 'point' ? '移动路径节点' : '移动对象', this.drag.before); this.refresh(); } this.drag = null; };
      this.canvas.onpointerup = stopDrag; this.canvas.onpointercancel = stopDrag;
      this.canvas.onwheel = event => { event.preventDefault(); const screen = this.pointerPoint(event), before = this.renderer.world(screen), multiplier = event.deltaY > 0 ? 0.9 : 1.1; this.view.zoom = Math.max(this.map.kind === 'battle' ? 2 : 0.05, Math.min(this.map.kind === 'battle' ? 150 : 8, this.view.zoom * multiplier)); this.view.pan = screen.map((value, i) => value - before[i] * this.view.zoom); this.renderer.draw(); };
      this.canvas.ondragover = event => { if (this.mode === 'edit') event.preventDefault(); };
      this.canvas.ondrop = event => { event.preventDefault(); if (this.mode !== 'edit') return; const type = event.dataTransfer.getData('application/frontier-type'), asset = event.dataTransfer.getData('application/frontier-asset'); if (type && M.TYPES[type]) this.place(type, this.renderer.world(this.pointerPoint(event))); else if (asset) this.place('decoration', this.renderer.world(this.pointerPoint(event)), asset); };
      document.querySelectorAll('[data-mode]').forEach(button => button.onclick = () => this.setMode(button.dataset.mode));
      document.querySelectorAll('[data-library]').forEach(button => button.onclick = () => { this.libraryTab = button.dataset.library; document.querySelectorAll('[data-library]').forEach(item => item.classList.toggle('active', item === button)); this.refreshLibrary(); });
      document.querySelectorAll('[data-bottom]').forEach(button => button.onclick = () => { document.querySelectorAll('[data-bottom]').forEach(item => item.classList.toggle('active', item === button)); $('object-list').hidden = button.dataset.bottom !== 'objects'; $('issues').hidden = button.dataset.bottom !== 'issues'; });
      $('check').onclick = () => { this.refreshIssues(); document.querySelector('[data-bottom="issues"]').click(); this.toast(this.issues.length ? '点击检查结果可定位对象' : '配置检查通过'); };
      $('library-search').oninput = () => this.refreshLibrary(); $('map-settings').onclick = () => this.select(''); $('duplicate').onclick = () => this.duplicate(); $('delete').onclick = () => this.remove();
      $('apply-fields').onclick = () => this.applyFields();
      $('undo').onclick = () => { this.history.undo(); this.selectedId = ''; this.refresh(); }; $('redo').onclick = () => { this.history.redo(); this.selectedId = ''; this.refresh(); };
      $('fit').onclick = () => this.renderer.fit(); $('zoom-in').onclick = () => { this.view.zoom *= 1.15; this.renderer.draw(); }; $('zoom-out').onclick = () => { this.view.zoom /= 1.15; this.renderer.draw(); };
      $('save-project').onclick = () => this.save(false); $('export-project').onclick = () => this.save(true); $('open-project').onclick = () => this.open(); $('new-project').onclick = () => this.newProject(); $('add-map').onclick = () => this.addMapDialog();
      $('file-open').onchange = event => this.readFile(event.target.files[0]); $('import-assets').onclick = () => $('asset-open').click(); $('asset-open').onchange = event => this.importAssets(event.target.files);
      $('catalogs').onclick = () => this.editCatalogs(); $('apply-json').onclick = () => this.applyAdvanced();
      $('reveal-all').onclick = () => { this.preview.fullReveal = !this.preview.fullReveal; $('reveal-all').textContent = this.preview.fullReveal ? '关闭全揭示' : '临时全揭示'; this.renderer.draw(); };
      $('reset-preview').onclick = () => { this.preview.reset(this.map); $('reveal-all').textContent = '临时全揭示'; this.renderer.draw(); this.toast('临时探索、发现、破障和奖励状态已重置'); };
      $('sim-monsters').onchange = () => { if (this.map.kind === 'exploration') this.preview.move(this.preview.player, this.map, this.project, false, this.monsters, this.enabledConditions); this.renderer.draw(); };
      $('sim-conditions').onclick = () => this.conditionDialog(); $('sim-victory').onclick = () => { this.preview.won = true; this.toast('胜利条件已开启，可点击中心祭坛检查召唤 / 升级事件'); this.renderer.draw(); };
      $('load-save').onclick = () => { $('save-open').value = ''; $('save-open').click(); };
      $('save-open').onchange = async event => { const file = event.target.files[0]; if (!file) return; try { this.preview.importSave(JSON.parse(await file.text()), this.map); this.renderer.draw(); this.toast('已只读载入探索轨迹与独立地点发现状态；源配置及游戏存档均未修改'); } catch (error) { this.toast('存档未载入：' + error.message); } };
      document.addEventListener('keydown', event => {
        if (!$('dialog').open && (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') { event.preventDefault(); document.activeElement.blur(); this.save(false); return; }
        if ($('dialog').open || ['INPUT', 'SELECT', 'TEXTAREA'].includes(event.target.tagName)) return;
        if (event.code === 'Space') { event.preventDefault(); this.space = true; }
        if (event.key === 'Escape') { this.tool = ''; this.addingPoints = false; this.pointIndex = -1; this.banner(); this.refreshLibrary(); }
        if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') { event.preventDefault(); this.save(false); }
        if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'z') { event.preventDefault(); (event.shiftKey ? $('redo') : $('undo')).click(); }
        if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'd') { event.preventDefault(); this.duplicate(); }
        if (event.key === 'Delete' || event.key === 'Backspace') { event.preventDefault(); this.remove(); }
      }); document.addEventListener('keyup', event => { if (event.code === 'Space') this.space = false; }); window.addEventListener('blur', () => { this.space = false; });
    }
    previewClick(point) {
      const object = this.hitObject(point);
      if (!object || ['road', 'decoration', 'tree', 'cloth', 'reveal_area'].includes(object.type)) {
        if (this.map.kind === 'exploration' && M.pointInPolygon(point, M.polygon(this.map))) { this.preview.move(point, this.map, this.project, true, this.monsters, this.enabledConditions); this.animateFog(); } return;
      }
      if (object.type === 'destructible') {
        if (this.preview.destroyed.has(object.id)) { this.toast('路障已破坏，仅关联的地点 / 连接被解锁'); return; }
        if (!this.preview.condition(this.project, object.condition_ref, this.monsters, this.enabledConditions)) { this.toast(object.hint || '未满足破坏条件'); return; }
        this.preview.destroyed.add(object.id); this.toast('模拟破坏成功 · 保留残骸 · 解锁：' + object.blocked_ids.join(', ')); this.renderer.draw(); return;
      }
      if (object.type === 'traversable') {
        if (!this.preview.condition(this.project, object.condition_ref, this.monsters, this.enabledConditions) || !object.landing) { this.toast(object.hint || '未满足跨越条件 / 未设置落点'); return; }
        this.preview.crossed.add(object.id); this.preview.move(object.landing, this.map, this.project, true, this.monsters, this.enabledConditions); this.toast('模拟跨越到配置落点，障碍仍保留'); this.renderer.draw(); return;
      }
      if (object.type === 'indestructible') { this.toast(object.hint || '不可破坏的障碍'); return; }
      if (object.type === 'camp') {
        if (!this.preview.canEnter(this.project, this.map, object, this.monsters, this.enabledConditions)) { this.toast('营地入口仍被关联障碍阻挡，或交互条件未满足'); return; }
        const battle = this.project.maps.find(map => map.id === object.battle_map_id && map.kind === 'battle'); if (!battle) { this.toast('目标战场不存在'); return; }
        this.enterBattle(object, battle); return;
      }
      if (object.type === 'post_battle') {
        if (!this.preview.condition(this.project, object.condition_ref, this.monsters, this.enabledConditions)) { this.toast('解锁条件未满足：先模拟战斗胜利'); return; }
        if (this.preview.rewards.has(object.id)) { this.toast('本轮模拟已领取，防止重复触发'); return; }
        this.dialog('战后事件 · ' + object.name, node('p', '事件 ID：' + object.event_id + '。以下按钮仅验证选项引用和防重复领取，不执行队伍或数值变化。'), [
          ['召唤 · ' + object.summon_option_ref, () => { this.preview.rewards.add(object.id); this.toast('模拟召唤请求已发出'); }], ['升级 · ' + object.upgrade_option_ref, () => { this.preview.rewards.add(object.id); this.toast('模拟升级请求已发出'); }]
        ]); return;
      }
      this.toast(object.name + ' · ' + (object.event_id || object.effect_ref || object.monster_config_id || '仅预览配置') + (object.target_scene ? ' → ' + object.target_scene : ''));
    }
    enterBattle(camp, battle) {
      this.transitioning = true; const before = M.clone(this.view), start = performance.now(), duration = Math.max(1, camp.transition.duration * 1000), rect = this.canvas.getBoundingClientRect();
      const frame = () => {
        const t = Math.min(1, (performance.now() - start) / duration), smooth = t * t * (3 - 2 * t), zoom = before.zoom * (1 + (camp.transition.zoom - 1) * smooth);
        this.view.zoom = zoom; this.view.pan = before.pan.map((value, index) => value * (1 - smooth) + ([(rect.width / 2), (rect.height / 2)][index] - camp.position[index] * zoom) * smooth); this.renderer.draw();
        this.canvas.style.opacity = String(1 - Math.max(0, t - (1 - camp.transition.fade / Math.max(camp.transition.duration, .01))) * .85);
        if (t < 1) requestAnimationFrame(frame); else { this.canvas.style.opacity = '1'; this.transitioning = false; this.switchMap(battle.id, true); this.toast('营地焦点转场预览完成 · 战斗运行与自动部署由游戏程序接入'); }
      }; requestAnimationFrame(frame);
    }
    dialog(title, body, actions = []) {
      $('dialog-title').textContent = title; $('dialog-body').replaceChildren(body); $('dialog-actions').replaceChildren();
      for (const [label, action] of actions) { const button = node('button', label, 'primary'); button.type = 'button'; button.onclick = () => { try { const result = action(); if (result !== false) $('dialog').close(); } catch (error) { this.toast(error.message); } }; $('dialog-actions').append(button); }
      const cancel = node('button', '关闭'); cancel.value = 'cancel'; $('dialog-actions').append(cancel); $('dialog').showModal();
    }
    conditionDialog() {
      const box = node('div'); box.append(node('p', '条件来自引用表。未实现的外部条件使用临时开关，不写入源配置。monster_count 条件使用底部怪兽数量。'));
      for (const condition of this.project.catalogs.conditions.filter(rule => rule.kind !== 'monster_count')) {
        const label = node('label', null, 'layer-row'), input = node('input'); input.type = 'checkbox'; input.checked = this.enabledConditions.includes(condition.id); input.style.width = 'auto'; input.onchange = () => { this.enabledConditions = this.enabledConditions.filter(id => id !== condition.id); if (input.checked) this.enabledConditions.push(condition.id); }; label.append(input, node('span', condition.name + ' / ' + condition.id)); box.append(label);
      } this.dialog('模拟外部条件', box);
    }
    editCatalogs() {
      const box = node('div'); box.append(node('p', '维护条件、事件、效果、怪兽、敌方队伍、部署规则和选项的 ID。编辑器负责引用校验；具体业务由游戏执行。'));
      const text = node('textarea'); text.value = JSON.stringify(this.project.catalogs, null, 2); text.spellcheck = false; box.append(text);
      this.dialog('条件与事件引用表', box, [['保存引用表', () => {
        const value = JSON.parse(text.value); for (const key of Object.keys(this.project.catalogs)) if (!Array.isArray(value[key]) || value[key].some(entry => !entry || typeof entry.id !== 'string')) throw Error(key + ' 应为包含 id 的数组'); this.commit('修改引用表', project => project.catalogs = value);
      }]]);
    }
    addMapDialog() {
      const box = node('div'), name = node('input'), kind = node('select'); name.placeholder = '地图名称'; name.value = '新战斗地图';
      for (const [id, label] of [['battle', '独立六边形战斗地图'], ['exploration', '连续 2D 探索地图']]) { const option = node('option', label); option.value = id; kind.append(option); } box.append(name, kind);
      this.dialog('新增地图', box, [['创建', () => { let id; this.commit('新增地图', project => { id = M.uniqueId(project, kind.value === 'battle' ? 'battle' : 'world'); project.maps.push(M.createMap(kind.value, id, name.value || '未命名地图')); }); this.switchMap(id); }]]);
    }
    newProject() {
      this.dialog('新建工作集', node('p', '新建将替换当前工作集。请先保存尚未保存的修改。'), [['建立空工作集', () => {
        const project = M.createProject(); project.name = '新地图工作集'; project.maps = [M.createMap('exploration', 'world_01', '新探索地图')]; this.loadProject(project, null); this.savedText = ''; this.updateDirty();
      }], ['载入示例工作集', () => this.loadProject(M.createProject(), null)]]);
    }
    async open() {
      if (this.isDirty()) { this.dialog('打开工作集', node('p', '当前有未保存修改。打开前请先保存；继续打开将替换当前工作集。'), [['继续选择文件', () => { $('file-open').value = ''; $('file-open').click(); }]]); return; }
      $('file-open').value = ''; $('file-open').click();
    }
    async readFile(file) { if (!file) return; try { const project = M.parseDocument(await file.text()); this.loadProject(project, null); this.toast('已载入 ' + file.name); } catch (error) { this.toast('打开失败，当前工作集未改变：' + error.message); } }
    loadProject(project, handle) { this.history = new M.History(project); this.fileHandle = handle; this.savedText = M.serialize(project); this.missingAssets.clear(); this.enabledConditions = []; this.switchMap(project.maps[0].id); }
    async save(exporting) {
      if (exporting) { this.refreshIssues(); if (this.issues.some(issue => issue.severity === 'error')) { document.querySelector('[data-bottom="issues"]').click(); this.toast('请修复错误后导出；未完成工作可正常保存工作集'); return; } }
      const text = M.serialize(this.project), filename = (this.project.maps[0].id || 'frontier') + (exporting ? '.level.json' : '.mapproject.json');
      try {
        if (!exporting && window.showSaveFilePicker) {
          const handle = this.fileHandle || await window.showSaveFilePicker({ suggestedName: filename, types: [{ description: '地图工作集', accept: { 'application/json': ['.json'] } }] });
          const writer = await handle.createWritable(); await writer.write(text); await writer.close(); this.fileHandle = handle;
        } else this.download(text, filename);
        if (!exporting) { this.savedText = text; this.updateDirty(); }
        this.toast(exporting ? '已导出初始配置；用 editor/tools/Import-Level.ps1 生成 Godot 资源与场景' : '工作集已保存');
        } catch (error) {
          if (['SecurityError', 'NotAllowedError'].includes(error.name)) {
            this.download(text, filename);
            if (!exporting) { this.savedText = text; this.updateDirty(); }
            this.toast('浏览器不允许直接写文件，已改为下载；请保留下载文件');
          } else if (error.name !== 'AbortError') this.toast('保存失败：' + error.message);
        }
    }
    download(text, filename) { const blob = new Blob([text], { type: 'application/json' }), url = URL.createObjectURL(blob), link = node('a'); link.href = url; link.download = filename; link.click(); setTimeout(() => URL.revokeObjectURL(url), 2000); }
    async importAssets(files) {
      const assets = [];
      for (const file of files) {
        if (file.size > 8 * 1024 * 1024) { this.toast(file.name + ' 超过 8 MB，请使用项目资源路径'); continue; }
        const data = await new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = reject; reader.readAsDataURL(file); });
        // SVG remains an asset, never inserted as HTML or executed as script.
        const id = 'asset_' + Date.now().toString(36) + '_' + assets.length; assets.push({ id, name: file.name, path: '', data, category: '导入素材' });
      }
      if (assets.length) { this.commit('导入素材', project => project.assets.push(...assets)); this.libraryTab = 'assets'; document.querySelector('[data-library="assets"]').click(); }
    }
    applyAdvanced() {
      if (this.mode !== 'edit') { this.toast('请切回布局编辑'); return; }
      try {
        const value = JSON.parse($('advanced-json').value), draft = M.clone(this.project), map = draft.maps.find(entry => entry.id === this.mapId);
        if (this.selected) { if (value.type !== this.selected.type) throw Error('不能通过 JSON 更改对象类型'); map.objects[map.objects.findIndex(entry => entry.id === this.selectedId)] = value; }
        else { if (value.kind !== this.map.kind) throw Error('不能通过 JSON 更改地图类型'); draft.maps[draft.maps.indexOf(map)] = value; }
        M.parseDocument(JSON.stringify(draft)); const oldId = this.selected ? this.selected.id : this.map.id; this.renameReferences(draft, oldId, value.id);
        this.commit('修改高级配置', project => { Object.keys(project).forEach(key => delete project[key]); Object.assign(project, draft); }); if (this.selectedId) this.selectedId = value.id; else this.mapId = value.id; this.refresh();
      } catch (error) { this.toast('JSON 未应用：' + error.message); }
    }
  }
  window.frontierEditor = new EditorApp();
})();
