const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const M=require('../battle-model.js'),D=require('../battle-deployment.js');
const doc=JSON.parse(fs.readFileSync(path.join(__dirname,'../../../Data/Maps/hex_battles.json')));
test('every configured battle starts left versus right at the same horizontal centre',()=>{
  for(const map of doc.maps){const p=D.centers(map,M);assert.ok(p.friendly,map.id);if(p.enemy){assert.ok(p.friendly[0]<p.enemy[0],map.id);assert.ok(Math.abs(p.friendly[1]-p.enemy[1])<1e-6,map.id);}assert.equal(M.issues(map).filter(i=>i.level==='error').length,0,map.id);}
});
test('both teams have a walkable route and safe spawn positions',()=>{
  for(const map of doc.maps){
    const points=M.grid(map).filter(c=>!M.blocked(map,c.p)),byKey=new Map(points.map(c=>[M.key(c.q,c.r),c]));
    const nearest=p=>points.reduce((a,b)=>Math.hypot(a.p[0]-p[0],a.p[1]-p[1])<Math.hypot(b.p[0]-p[0],b.p[1]-p[1])?a:b);
    const c=D.centers(map,M),start=nearest(c.friendly),seen=new Set([M.key(start.q,start.r)]),queue=[start];
    for(let i=0;i<queue.length;i++){const at=queue[i];for(const [dq,dr] of [[1,0],[0,1],[-1,1],[-1,0],[0,-1],[1,-1]]){const key=M.key(at.q+dq,at.r+dr);if(byKey.has(key)&&!seen.has(key)){seen.add(key);queue.push(byKey.get(key));}}}
    for(const o of map.objects.filter(o=>o.type==='enemy')){assert.ok(!M.blocked(map,o.position),o.id);const n=nearest(o.position);assert.ok(seen.has(M.key(n.q,n.r)),map.id+' unreachable enemy '+o.id);}
  }
});
test('visual pose exports preserve geometry and explicitly keep mud grounded',()=>{
  let raised=0,grounded=0;
  for(const map of doc.maps){
    const compiled=M.compileMap(map);assert.deepEqual(compiled.deployment_layout,map.deployment_layout);
    for(const o of map.objects){
      if(o.type==='mud'||o.type==='pit'){assert.equal(o.visual.surface_mode,'ground',o.id);grounded++;}
      if(['tree','web','collision_damage','indestructible'].includes(o.type)){assert.equal(o.visual.surface_mode,'tilted',o.id);assert.equal(o.visual.tilt_degrees,60,o.id);raised++;}
    }
  }
  assert.ok(raised>0&&grounded>0);
});
test('alignment can be undone without losing the original roster or art settings',()=>{
  const h=new M.History(doc.maps.find(m=>m.objects.some(o=>o.type==='enemy'))),before=JSON.stringify(h.map);
  h.change(m=>{m.objects.find(o=>o.type==='deployment').position[1]+=3;});const changed=JSON.stringify(h.map);
  h.change(m=>D.align(m,M));assert.ok(h.undo());assert.equal(JSON.stringify(h.map),changed);assert.ok(h.undo());assert.equal(JSON.stringify(h.map),before);
});
