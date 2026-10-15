(function () {
  'use strict';
  const M = MapEditorModel;
  function path(ctx, points, close = true) { ctx.beginPath(); points.forEach((point, index) => index ? ctx.lineTo(...point) : ctx.moveTo(...point)); if (close) ctx.closePath(); }
  function objectTransform(ctx, object) { ctx.translate(...object.position); ctx.rotate(object.rotation * Math.PI / 180); ctx.scale(...object.scale); }
  function regionPath(ctx, shape) {
    ctx.translate(...shape.offset); ctx.rotate(shape.rotation * Math.PI / 180);
    if (shape.shape === 'polygon') path(ctx, shape.points);
    else if (shape.shape === 'circle') { ctx.beginPath(); ctx.ellipse(0, 0, shape.size[0] / 2, shape.size[1] / 2, 0, 0, Math.PI * 2); }
    else { ctx.beginPath(); ctx.rect(-shape.size[0] / 2, -shape.size[1] / 2, ...shape.size); }
  }
  class Renderer {
    constructor(app) { this.app = app; this.canvas = app.canvas; this.ctx = this.canvas.getContext('2d'); this.images = new Map(); }
    image(assetId) {
      const asset = this.app.project.assets.find(entry => entry.id === assetId);
      if (!asset) return null;
      const source = asset.data || this.assetUrl(asset.path);
      if (!this.images.has(source)) {
        const image = new Image(); image.onload = () => this.draw(); image.onerror = () => { image.failed = true; this.app.missingAssets.add(asset.id); this.app.toast('素材无法读取：' + asset.name); this.app.refreshIssues(); }; image.src = source; this.images.set(source, image);
      }
      const image = this.images.get(source); return image.complete && image.naturalWidth && !image.failed ? image : null;
    }
    assetUrl(resourcePath) { return resourcePath?.startsWith('res://') ? '../' + resourcePath.slice(6) : resourcePath; }
    screen(point) { const view = this.app.view; return [point[0] * view.zoom + view.pan[0], point[1] * view.zoom + view.pan[1]]; }
    world(point) { const view = this.app.view; return [(point[0] - view.pan[0]) / view.zoom, (point[1] - view.pan[1]) / view.zoom]; }
    fit() {
      const points = M.polygon(this.app.map), xs = points.map(p => p[0]), ys = points.map(p => p[1]);
      const minX = Math.min(...xs), minY = Math.min(...ys), width = Math.max(...xs) - minX, height = Math.max(...ys) - minY;
      const size = this.canvas.getBoundingClientRect();
      this.app.view.zoom = Math.min((size.width - 90) / width, (size.height - 150) / height);
      this.app.view.pan = [size.width / 2 - (minX + width / 2) * this.app.view.zoom, size.height / 2 + 20 - (minY + height / 2) * this.app.view.zoom];
      this.draw();
    }
    resize() {
      const rect = this.canvas.getBoundingClientRect(), ratio = window.devicePixelRatio || 1;
      this.canvas.width = Math.round(rect.width * ratio); this.canvas.height = Math.round(rect.height * ratio); this.draw();
    }
    draw() {
      const app = this.app, map = app.map; if (!map) return;
      const ctx = this.ctx, view = app.view, ratio = window.devicePixelRatio || 1, rect = this.canvas.getBoundingClientRect();
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0); ctx.clearRect(0, 0, rect.width, rect.height);
      ctx.fillStyle = '#111d17'; ctx.fillRect(0, 0, rect.width, rect.height);
      ctx.save(); ctx.translate(...view.pan); ctx.scale(view.zoom, view.zoom);
      if (map.kind === 'battle') this.background(ctx, map);
      const cloths = map.objects.filter(o => o.type === 'cloth'); if (app.layers.cloth) for (const object of cloths) this.object(ctx, object);
      const outline = M.polygon(map);
      ctx.save(); ctx.shadowColor = '#09160d99'; ctx.shadowBlur = map.kind === 'battle' ? map.edge_feather * view.zoom : 25;
      path(ctx, outline); ctx.fillStyle = map.ground_color; ctx.fill(); ctx.restore();
      ctx.save(); path(ctx, outline); ctx.clip();
      const texture = this.image(map.ground_asset);
      if (texture) { const pattern = ctx.createPattern(texture, 'repeat'); ctx.fillStyle = pattern; ctx.globalAlpha = 0.7; ctx.fill(); ctx.globalAlpha = 1; }
      this.terrain(ctx, map);
      if (map.kind === 'exploration') {
        for (const object of map.objects.filter(o => !['cloth', 'reveal_area', 'deployment'].includes(o.type) && o.discovery?.marker_layer !== 'above').sort((a, b) => a.visual.z_index - b.visual.z_index)) this.object(ctx, object);
      } else {
        for (const object of map.objects.filter(o => !['deployment'].includes(o.type)).sort((a, b) => a.visual.z_index - b.visual.z_index || a.position[1] - b.position[1])) this.object(ctx, object);
      }
      ctx.restore();
      if (map.kind === 'exploration' && app.mode !== 'edit' && app.layers.fog && map.fog.enabled && !app.preview.fullReveal) this.fog(map, rect);
      if (map.kind === 'exploration') for (const object of map.objects.filter(o => o.discovery?.marker_layer === 'above').sort((a, b) => a.visual.z_index - b.visual.z_index)) this.object(ctx, object);
      if (map.kind === 'battle' && map.natural_border) this.naturalBorder(ctx, map);
      if (app.mode === 'edit') {
        for (const object of map.objects) this.guides(ctx, object);
        if (app.layers.boundary) { path(ctx, outline); ctx.strokeStyle = '#d4b579'; ctx.setLineDash([6 / view.zoom, 5 / view.zoom]); ctx.lineWidth = 1 / view.zoom; ctx.stroke(); ctx.setLineDash([]); }
        if (app.selected) this.selection(ctx, app.selected);
      }
      if (app.mode !== 'edit' && map.kind === 'exploration') {
        ctx.beginPath(); ctx.arc(...app.preview.player, 6 / view.zoom, 0, Math.PI * 2); ctx.fillStyle = '#f6e3a3'; ctx.fill(); ctx.strokeStyle = '#213529'; ctx.lineWidth = 2 / view.zoom; ctx.stroke();
      }
      ctx.restore();
      const vignette = ctx.createLinearGradient(0, 0, 0, 135); vignette.addColorStop(0, '#0c1917b5'); vignette.addColorStop(1, '#0c191700'); ctx.fillStyle = vignette; ctx.fillRect(0, 0, rect.width, 135);
      document.getElementById('zoom-label').textContent = Math.round(view.zoom * (map.kind === 'battle' ? 3 : 100)) + '%';
    }
    terrain(ctx, map) {
      const bounds = map.kind === 'battle' ? [-map.radius, -map.radius, map.radius * 2, map.radius * 2] : [...map.bounds.position, ...map.bounds.size];
      let seed = 17; const random = () => { seed = seed * 16807 % 2147483647; return seed / 2147483647; };
      const size = map.kind === 'battle' ? 0.05 : 2.5;
      ctx.globalAlpha = 0.12; ctx.fillStyle = '#d8ddae';
      for (let i = 0; i < 450; i++) { const x = bounds[0] + random() * bounds[2], y = bounds[1] + random() * bounds[3]; ctx.beginPath(); ctx.ellipse(x, y, size * (1 + random() * 2), size, random() * 3, 0, 7); ctx.fill(); }
      ctx.globalAlpha = 1;
    }
    background(ctx, map) {
      ctx.save(); ctx.filter = `blur(${map.background_blur}px)`;
      const size = map.radius * 3, texture = this.image(map.background_asset);
      ctx.fillStyle = '#344732'; ctx.fillRect(-size, -size, size * 2, size * 2);
      if (texture) ctx.drawImage(texture, -size, -size, size * 2, size * 2);
      else {
        ctx.fillStyle = '#60734e';
        for (let i = 0; i < 42; i++) { const angle = i * 2.39, radius = map.radius * (1.15 + (i % 7) / 5); ctx.beginPath(); ctx.ellipse(Math.cos(angle) * radius, Math.sin(angle) * radius, map.radius * 0.18, map.radius * 0.25, angle, 0, 7); ctx.fill(); }
      }
      ctx.restore();
    }
    naturalBorder(ctx, map) {
      const points = M.polygon(map), image = this.image('rock'), tree = this.image('tree');
      ctx.save();
      points.forEach((a, index) => { const b = points[(index + 1) % 6], count = Math.ceil(Math.hypot(a[0] - b[0], a[1] - b[1]) / 1.7);
        for (let i = 0; i <= count; i++) { const t = i / count, x = a[0] + (b[0] - a[0]) * t, y = a[1] + (b[1] - a[1]) * t, chosen = i % 9 === 3 ? tree : image, size = i % 9 === 3 ? 2.5 : 1.3 + i % 3 * 0.3; if (chosen) ctx.drawImage(chosen, x - size / 2, y - size / 2, size, size); }
      }); ctx.restore();
    }
    object(ctx, object) {
      const app = this.app;
      if (!app.layers[object.layer] || !object.visual.visible || (app.mode !== 'edit' && !app.preview.objectVisible(object))) return;
      if (['reveal_area', 'deployment'].includes(object.type)) return;
      ctx.save(); objectTransform(ctx, object); ctx.globalAlpha = object.visual.opacity;
      if (object.type === 'road') {
        const palette = object.style_ref === 'stone' ? ['#505b51', '#8a9380'] : object.style_ref === 'dirt' ? ['#655036', '#98764e'] : ['#5c553d', '#a18a61'];
        path(ctx, object.points, false); ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.strokeStyle = palette[0]; ctx.lineWidth = object.width + 5; ctx.stroke(); ctx.strokeStyle = palette[1]; ctx.lineWidth = object.width; ctx.stroke();
        if (app.mode === 'edit') { ctx.strokeStyle = '#c5b17c55'; ctx.lineWidth = 2 / app.view.zoom; ctx.setLineDash([8 / app.view.zoom, 8 / app.view.zoom]); ctx.stroke(); }
      } else if (object.native_obstacle) {
        ctx.save(); regionPath(ctx, object.collision); ctx.fillStyle = '#626c59'; ctx.fill(); ctx.strokeStyle = '#35432b'; ctx.lineWidth = 3 / app.view.zoom; ctx.stroke(); ctx.restore();
      } else {
        const destroyed = app.mode !== 'edit' && app.preview.destroyed.has(object.id), asset = destroyed ? object.broken_asset : object.visual.asset, image = this.image(asset);
        const [w, h] = object.visual.size;
        if (image) ctx.drawImage(image, -w / 2, -h / 2, w, h);
        else { ctx.fillStyle = object.visual.tint; ctx.fillRect(-w / 2, -h / 2, w, h); ctx.fillStyle = '#142a1c'; ctx.font = `${14 / app.view.zoom}px sans-serif`; ctx.textAlign = 'center'; ctx.fillText(M.TYPES[object.type].icon, 0, 5 / app.view.zoom); }
        if (['house', 'town', 'camp', 'post_battle'].includes(object.type)) {
          ctx.save(); ctx.scale(1 / object.scale[0], 1 / object.scale[1]); ctx.font = `${10 / app.view.zoom}px 'Microsoft YaHei',sans-serif`; ctx.textAlign = 'center';
          const metrics = ctx.measureText(object.name), y = h / 2 + 11 / app.view.zoom; ctx.fillStyle = '#102419dc'; ctx.fillRect(-metrics.width / 2 - 5 / app.view.zoom, y - 10 / app.view.zoom, metrics.width + 10 / app.view.zoom, 15 / app.view.zoom); ctx.fillStyle = '#d8dec1'; ctx.fillText(object.name, 0, y); ctx.restore();
        }
      }
      ctx.restore();
    }
    guideRegion(ctx, object, shape, color) {
      if (!shape?.enabled) return;
      ctx.save(); objectTransform(ctx, object); regionPath(ctx, shape); ctx.fillStyle = color + '20'; ctx.fill(); ctx.strokeStyle = color; ctx.lineWidth = 1 / this.app.view.zoom; ctx.setLineDash([5 / this.app.view.zoom, 3 / this.app.view.zoom]); ctx.stroke(); ctx.restore();
    }
    guides(ctx, object) {
      const app = this.app;
      if (app.layers.collisions) this.guideRegion(ctx, object, object.collision, '#e49a73');
      if (app.layers.landmarks) this.guideRegion(ctx, object, object.click_area, '#79c4d1');
      if (app.layers.effects && !['deployment', 'reveal_area'].includes(object.type)) this.guideRegion(ctx, object, object.region, '#bb95d3');
      if (app.layers.deployment && object.type === 'deployment') {
        this.guideRegion(ctx, object, object.region, '#b6cf77');
        for (const slot of object.slots) { ctx.save(); objectTransform(ctx, object); ctx.beginPath(); ctx.arc(...slot, 0.35, 0, 7); ctx.strokeStyle = '#dbe6a6'; ctx.lineWidth = 1 / app.view.zoom; ctx.stroke(); ctx.restore(); }
      }
      if (app.layers.reveals && object.type === 'reveal_area') this.guideRegion(ctx, object, object.region, '#e5ce84');
      if (app.layers.landmarks && object.interaction_offset) { const p = M.worldPoint(object, object.interaction_offset); ctx.beginPath(); ctx.arc(...p, 3 / app.view.zoom, 0, 7); ctx.fillStyle = '#75c9c1'; ctx.fill(); }
    }
    pointHandles(object) {
      const app = this.app, pointPath = app.pointPath || (object.type === 'road' ? 'points' : null);
      if (!pointPath || !Array.isArray(M.get(object, pointPath))) return [];
      const shapeKey = pointPath.split('.')[0], shape = object[shapeKey];
      return M.get(object, pointPath).map((p, index) => {
        let local = p;
        if (pointPath.includes('.') && shape?.offset) { const angle = shape.rotation * Math.PI / 180; local = [p[0] * Math.cos(angle) - p[1] * Math.sin(angle) + shape.offset[0], p[0] * Math.sin(angle) + p[1] * Math.cos(angle) + shape.offset[1]]; }
        return { position: M.worldPoint(object, local), index, path: pointPath };
      });
    }
    selection(ctx, object) {
      const app = this.app;
      ctx.save(); objectTransform(ctx, object); const [w, h] = object.visual.size; ctx.strokeStyle = '#e5cf8c'; ctx.lineWidth = 1.5 / app.view.zoom; ctx.setLineDash([5 / app.view.zoom, 3 / app.view.zoom]); if (object.type !== 'road') ctx.strokeRect(-w / 2 - 4 / app.view.zoom, -h / 2 - 4 / app.view.zoom, w + 8 / app.view.zoom, h + 8 / app.view.zoom); ctx.restore();
      for (const handle of this.pointHandles(object)) { ctx.beginPath(); ctx.arc(...handle.position, 5 / app.view.zoom, 0, 7); ctx.fillStyle = handle.index === app.pointIndex ? '#f2d58b' : '#80d2c3'; ctx.fill(); ctx.strokeStyle = '#172c22'; ctx.lineWidth = 2 / app.view.zoom; ctx.stroke(); }
    }
    fog(map, rect) {
      const app = this.app, view = app.view;
      const make = () => { const canvas = document.createElement('canvas'); canvas.width = Math.ceil(rect.width); canvas.height = Math.ceil(rect.height); return canvas; };
      const explored = make(), visible = make(), unknown = make(), covered = make();
      const ex = explored.getContext('2d'), vis = visible.getContext('2d');
      const stamp = (ctx, point, radius) => { const screen = this.screen(point), r = Math.max(0.1, radius * view.zoom), inner = Math.max(0, r - map.fog.feather * view.zoom); const gradient = ctx.createRadialGradient(...screen, inner, ...screen, r); gradient.addColorStop(0, '#fff'); gradient.addColorStop(1, '#fff0'); ctx.fillStyle = gradient; ctx.beginPath(); ctx.arc(...screen, r, 0, 7); ctx.fill(); };
      for (const sample of app.preview.samples) stamp(ex, sample, sample[2]);
      for (const object of map.objects.filter(o => o.type === 'reveal_area')) { ex.save(); ex.translate(...view.pan); ex.scale(view.zoom, view.zoom); objectTransform(ex, object); regionPath(ex, object.region); ex.fillStyle = '#fff'; ex.shadowColor = '#fff'; ex.shadowBlur = 0; ex.fill(); ex.restore(); }
      stamp(vis, app.preview.player, map.fog.radius); ex.drawImage(visible, 0, 0);
      const un = unknown.getContext('2d'); un.fillStyle = map.fog.unknown_color; un.globalAlpha = map.fog.unknown_opacity; un.fillRect(0, 0, rect.width, rect.height);
      const texture = this.image(map.fog.texture_ref); if (texture) { un.globalAlpha = 0.2; un.fillStyle = un.createPattern(texture, 'repeat'); un.fillRect(0, 0, rect.width, rect.height); }
      un.globalAlpha = 1; un.globalCompositeOperation = 'destination-out'; un.drawImage(explored, 0, 0);
      if (map.fog.retention === 'recover') { const co = covered.getContext('2d'); co.fillStyle = map.fog.explored_color; co.globalAlpha = map.fog.explored_opacity; co.fillRect(0, 0, rect.width, rect.height); co.globalAlpha = 1; co.globalCompositeOperation = 'destination-in'; co.drawImage(explored, 0, 0); co.globalCompositeOperation = 'destination-out'; co.drawImage(visible, 0, 0); }
      const final = make(), finalCtx = final.getContext('2d'); finalCtx.drawImage(unknown, 0, 0); finalCtx.drawImage(covered, 0, 0);
      const alpha = app.fogFadeAlpha(), mix = make(), mixCtx = mix.getContext('2d');
      if (this.fogFrom && alpha < 1) { mixCtx.globalAlpha = 1 - alpha; mixCtx.drawImage(this.fogFrom, 0, 0); mixCtx.globalCompositeOperation = 'lighter'; mixCtx.globalAlpha = alpha; mixCtx.drawImage(final, 0, 0); } else { mixCtx.drawImage(final, 0, 0); this.fogFrom = null; }
      this.lastFog = final;
      const ctx = this.ctx; ctx.save(); const ratio = window.devicePixelRatio || 1; ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      path(ctx, M.polygon(map).map(point => this.screen(point))); ctx.clip(); ctx.drawImage(mix, 0, 0); ctx.restore();
    }
  }
  window.MapEditorRenderer = Renderer;
})();
