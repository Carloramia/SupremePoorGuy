(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.HexModel=api;})(typeof globalThis!=='undefined'?globalThis:this,()=>{
  'use strict';
  const regions=[['forest','普通森林','#667d64'],['spider','蜘蛛森林','#4b626c'],['sparse','稀树草原','#a5ab76'],['grass','普通草原','#b49e70'],['pit','坑洞草原','#9b876a'],['desert','黑沙沙漠','#4a4546']];
  const types=[['snake','蛇形','蛇'],['humanoid','人形','人'],['beast','兽形','兽'],['spider','蜘蛛形','蛛'],['flying','飞行类','飞']];
  const sizes=[['','待设定'],['tiny','微型'],['small','小型'],['medium','中型'],['large','大型'],['huge','巨型']];
  function inferForm(site){const text=(String(site.name||'')+' '+String(site.source_id||'')+' '+(String(site.id||'').startsWith('hex_')?'':String(site.id||''))).toLowerCase();for(const [type,tokens] of [['spider',['spider','蜘蛛']],['snake',['snake','serpent','蛇']],['humanoid',['bandit','强盗','人形']],['beast',['wolf','rat','beast','狼','鼠','巨兽','兽形']]])if(tokens.some(token=>text.includes(token)))return type;return 'unassigned';}
  function upgradeSite(site){if(site.kind!=='camp'||site.monster_taxonomy_version>=2)return site;const legacy={small_swarm:'small',medium:'medium',large:'large'};for(const role of ['primary','secondary']){const field=role+'_type',old=site[field]||'';if(role==='secondary'&&!old){site[role+'_size']??='';site[role+'_grouped']??=false;continue;}if(old in legacy){site['legacy_'+field]??=old;site[field]=role==='primary'?inferForm(site):'unassigned';site[role+'_size']??=legacy[old];site[role+'_grouped']??=old==='small_swarm';}else{if(role==='primary'&&!old)site[field]='unassigned';site[role+'_size']??='';site[role+'_grouped']??=false;}}site.monster_taxonomy_version=2;return site;}
  function spawnPosition(doc){const s=doc.sites?.find(s=>s.id===(doc.spawn_site_id||'layout_summoning_hut'));if(!s)return doc.spawn.slice();const a=doc.assets?.find(a=>a.id===s.visual?.asset_id);if(!a)return s.position.slice();const v=s.visual,w=v.width,h=w*a.height/a.width*(v.height_scale||1),anchor=v.anchor||a.anchor||[.5,1],entry=doc.spawn_site_anchor||[0.33125,0.8263119402908841],x=(entry[0]-anchor[0])*w,y=(entry[1]-anchor[1])*h,angle=(v.rotation||0)*Math.PI/180,o=v.offset||[0,0];return [s.position[0]+o[0]+x*Math.cos(angle)-y*Math.sin(angle),s.position[1]+o[1]+x*Math.sin(angle)+y*Math.cos(angle)];}
  function syncSpawn(doc){const hut=doc.sites?.find(s=>s.id===(doc.spawn_site_id||'layout_summoning_hut'));if(hut){doc.spawn_site_id=hut.id;doc.spawn_site_anchor??=[0.33125,0.8263119402908841];doc.spawn=spawnPosition(doc);}return doc;}
  function upgradeDocument(doc){for(const site of doc.sites||[])upgradeSite(site);doc.monster_taxonomy_version=2;return syncSpawn(doc);}
  function duplicateRoles(site){return !!site.secondary_type&&site.primary_type!=='unassigned'&&site.secondary_type!=='unassigned'&&['type','size','grouped'].every(key=>(site['primary_'+key]??(key==='grouped'?false:''))===(site['secondary_'+key]??(key==='grouped'?false:'')));}

  const clone=v=>JSON.parse(JSON.stringify(v));
  const key=(q,r)=>`${q},${r}`;
  function center(grid,q,r){const R=grid.cell_width/2;return [grid.origin[0]+1.5*R*q,grid.origin[1]+Math.sqrt(3)*R*(r+q/2)];}
  function axial(grid,p){const R=grid.cell_width/2,x=(p[0]-grid.origin[0])/R,y=(p[1]-grid.origin[1])/R;let q=2*x/3,r=-x/3+Math.sqrt(3)*y/3,s=-q-r;let Q=Math.round(q),S=Math.round(s),T=Math.round(r);const a=Math.abs(Q-q),b=Math.abs(T-r),c=Math.abs(S-s);if(a>b&&a>c)Q=-T-S;else if(b>c)T=-Q-S;return [Q||0,T||0];}
  function corners(grid,q,r){const p=center(grid,q,r),R=grid.cell_width/2;return Array.from({length:6},(_,i)=>[p[0]+R*Math.cos(i*Math.PI/3),p[1]+R*Math.sin(i*Math.PI/3)]);}
  function neighbors(q,r,size=0){const out=[];for(let x=-size;x<=size;x++)for(let y=Math.max(-size,-x-size);y<=Math.min(size,-x+size);y++)out.push([q+x,r+y]);return out;}
  function distance(p,a,b){let x=b[0]-a[0],y=b[1]-a[1],t=Math.max(0,Math.min(1,((p[0]-a[0])*x+(p[1]-a[1])*y)/(x*x+y*y||1)));return Math.hypot(p[0]-a[0]-t*x,p[1]-a[1]-t*y);}
  function normalizeSite(site){upgradeSite(site);site.difficulty=Number(site.difficulty);if(![0,1,2,3].includes(site.difficulty))site.difficulty=1;site.sublevel=site.difficulty===2&&site.sublevel==='upper'?'upper':'normal';if(site.difficulty===3)site.auto_trigger=false;if(!(site.difficulty===3||site.difficulty===2&&site.sublevel==='upper') ){site.secondary_type='';site.secondary_size='';site.secondary_grouped=false;}if(!site.secondary_type){site.secondary_size='';site.secondary_grouped=false;}return site;}
  function inside(doc,p){const b=doc.bounds;return p[0]>=b.position[0]&&p[1]>=b.position[1]&&p[0]<=b.position[0]+b.size[0]&&p[1]<=b.position[1]+b.size[1];}
  function validate(doc){
    if(!doc||doc.format!=='frontier_hex_layout'||doc.version!==1)throw Error('不是兼容的蜂窝布局文件（需要 version 1）。');
    upgradeDocument(doc);
    const finite=(a,n)=>Array.isArray(a)&&a.length===n&&a.every(Number.isFinite);
    if(!doc.grid||!Number.isFinite(doc.grid.cell_width)||doc.grid.cell_width<32||doc.grid.cell_width>1024||!finite(doc.grid.origin,2)||!doc.bounds||!finite(doc.bounds.position,2)||!finite(doc.bounds.size,2)||doc.bounds.size.some(x=>x<=0||x>100000))throw Error('地图范围或网格尺寸无效。');
    if(doc.spawn_site_anchor&&!finite(doc.spawn_site_anchor,2))throw Error('小屋出生点锚点无效。');
    if(!finite(doc.spawn,2)||!inside(doc,doc.spawn)||!Number.isFinite(doc.vision_radius)||doc.vision_radius<=0)throw Error('起点或视野参数无效。');
    if(!Array.isArray(doc.cells)||doc.cells.length>150000||!Array.isArray(doc.sites)||doc.sites.length>5000||!Array.isArray(doc.roads)||doc.roads.length>5000)throw Error('布局数量无效或超过编辑器上限。');
    const keys=new Set(),ids=new Set();
    for(const cell of doc.cells){const k=key(cell.q,cell.r);if(!Number.isInteger(cell.q)||!Number.isInteger(cell.r)||Math.abs(cell.q)>10000||Math.abs(cell.r)>10000||keys.has(k)||!regions.some(v=>v[0]===cell.region)||!inside(doc,center(doc.grid,cell.q,cell.r)))throw Error('区域网格无效或重复。');keys.add(k);if(cell.feature&&!['river','wall','breakable','bridge'].includes(cell.feature))throw Error('未知通行类型。');if(cell.event_id!=null&&typeof cell.event_id!=='string'||cell.condition_ref!=null&&typeof cell.condition_ref!=='string')throw Error('事件与条件必须为文本。');}
    for(const site of doc.sites){if(typeof site.id!=='string'||!site.id||ids.has(site.id)||typeof site.name!=='string'||!finite(site.position,2)||!inside(doc,site.position)||!['camp','house','town','event','destructible','decoration'].includes(site.kind)||!Number.isFinite(site.radius)||site.radius<0||site.radius>10000||![0,1,2,3].includes(site.difficulty)||site.primary_type&&site.primary_type!=='unassigned'&&!types.some(t=>t[0]===site.primary_type)||site.secondary_type&&site.secondary_type!=='unassigned'&&!types.some(t=>t[0]===site.secondary_type))throw Error('点位字段、难度、类型或触发范围无效。');ids.add(site.id);if(site.difficulty===3&&site.auto_trigger)throw Error('三级点位不能自动触发遭遇。');if(site.secondary_type&&!(site.difficulty===3||site.difficulty===2&&site.sublevel==='upper')||site.secondary_type&&duplicateRoles(site))throw Error('复合点位需为二级高段或三级，主副组不能完全相同。');for(const role of ['primary','secondary']){if(!sizes.some(s=>s[0]===(site[role+'_size']===undefined?'':site[role+'_size']))||site[role+'_grouped']!=null&&typeof site[role+'_grouped']!=='boolean')throw Error('怪物尺寸或群体属性无效。');}for(const f of ['event_id','condition_ref','battle_map_id','enemy_config_id'])if(site[f]!=null&&typeof site[f]!=='string')throw Error('点位引用必须为文本。');}
    for(const road of doc.roads){if(typeof road.id!=='string'||ids.has(road.id)||!Array.isArray(road.points)||road.points.length<2||road.points.length>2000||!road.points.every(p=>finite(p,2)&&inside(doc,p))||!Number.isFinite(road.width)||road.width<=0||road.width>1024)throw Error('道路至少需要两个有效节点。');ids.add(road.id);}
    for(const c of doc.cells)if(c.control&&!['allowed','outside','breakable'].includes(c.control))throw Error('边缘控制状态无效。');
    for(const crossing of doc.crossings||[])if(!Array.isArray(crossing.points)||crossing.points.length<2||!crossing.points.every(p=>finite(p,2)&&inside(doc,p))||!Number.isFinite(crossing.width)||crossing.width<=0)throw Error('跨河点无效。');
    for(const c of doc.cells)for(const field of ['control_condition_ref','control_event_id'])if(c[field]!=null&&typeof c[field]!=='string')throw Error('边缘破坏条件和事件必须为文本。');
    const boundary=typeof module==='object'&&module.exports?require('./mountain-boundary.js'):globalThis.HexMountainBoundary;boundary?.validate(doc);if(typeof HexContentModel!=='undefined')HexContentModel.validate(doc);
    return doc;
  }
  function siteRule(site,from){if(site.kind==='camp')return site.auto_trigger&&site.difficulty<3&&Math.hypot(site.position[0]-from[0],site.position[1]-from[1])<=site.radius?'encounter':'challenge';return site.kind==='destructible'?'break':'event';}
  function wallKinds(doc){
    const boundary=typeof module==='object'&&module.exports?require('./mountain-boundary.js'):globalThis.HexMountainBoundary,state=boundary?.index(doc);
    const cells=new Map(doc.cells.filter(c=>c.feature==='wall'&&!(state&&boundary.gridReplaced(c,state))).map(c=>[key(c.q,c.r),c])),remaining=new Set(cells.keys()),kinds=new Map();
    const directions=[[1,0],[0,1],[-1,1],[-1,0],[0,-1],[1,-1]];
    while(remaining.size){const start=remaining.values().next().value,pending=[start],component=[];remaining.delete(start);let allPit=true;
      while(pending.length){const id=pending.pop(),c=cells.get(id);component.push(id);allPit=allPit&&c.region==='pit'&&c.wall_material!=='source_mountain';for(const [q,r] of directions){const neighbor=key(c.q+q,c.r+r);if(remaining.delete(neighbor))pending.push(neighbor);}}
      const kind=allPit&&component.length<=7?'pit':'mountain';for(const id of component)kinds.set(id,kind);
    }
    return kinds;
  }
  function visionPolygon(doc,from=spawnPosition(doc),radius=doc.vision_radius,kinds=wallKinds(doc)){
    const R=doc.grid.cell_width/2,boundary=typeof module==='object'&&module.exports?require('./mountain-boundary.js'):globalThis.HexMountainBoundary,state=boundary?.index(doc);
    const origin=axial(doc.grid,from);
    if(kinds.get(key(...origin))==='mountain'||state?.shapes.some(s=>s.site.terrain.blocks_vision!==false&&boundary.contains(s,from)))return Array.from({length:256},()=>from.slice());
    const polygons=doc.cells.filter(c=>kinds.get(key(c.q,c.r))==='mountain').map(c=>({p:center(doc.grid,c.q,c.r),c})).filter(({p})=>Math.abs(p[0]-from[0])<=radius+R&&Math.abs(p[1]-from[1])<=radius+R).map(({c})=>corners(doc.grid,c.q,c.r));
    for(const shape of state?.shapes||[])if(shape.site.terrain.blocks_vision!==false&&shape.bounds[0]<=from[0]+radius&&shape.bounds[2]>=from[0]-radius&&shape.bounds[1]<=from[1]+radius&&shape.bounds[3]>=from[1]-radius)polygons.push(...shape.rings);
    const cross=(a,b)=>a[0]*b[1]-a[1]*b[0];
    return Array.from({length:256},(_,i)=>{
      const angle=i*Math.PI*2/256,ray=[Math.cos(angle)*radius,Math.sin(angle)*radius];let limit=1;
      for(const polygon of polygons)for(let j=0;j<polygon.length;j++){
        const a=polygon[j],b=polygon[(j+1)%polygon.length],edge=[b[0]-a[0],b[1]-a[1]],offset=[a[0]-from[0],a[1]-from[1]],denominator=cross(ray,edge);
        if(Math.abs(denominator)<1e-9)continue;
        const t=cross(offset,edge)/denominator,u=cross(offset,ray)/denominator;
        if(t>=0&&t<limit&&u>=0&&u<=1)limit=t;
      }
      return from.map((v,j)=>v+ray[j]*limit);
    });
  }
  class History{
    constructor(doc){this.doc=clone(validate(doc));this.undoStack=[];this.redoStack=[];this.before=null;this.roadDraft=[];this.roadRedo=[];this.redoActions=[];this.resumedRoad=null;this.lastAction='';}
    begin(){if(!this.before)this.before=JSON.stringify(this.doc);}
    clearRedo(){this.redoStack=[];this.roadRedo=[];this.redoActions=[];}
    commit(){if(!this.before)return false;syncSpawn(this.doc);const previous=this.before;this.before=null;if(previous===JSON.stringify(this.doc))return false;this.undoStack.push(previous);if(this.undoStack.length>45)this.undoStack.shift();this.clearRedo();return true;}
    change(fn){this.begin();fn(this.doc);return this.commit();}
    get canUndo(){return !!(this.roadDraft.length||this.undoStack.length||this.before);}
    get canRedo(){return this.redoActions.length>0;}
    addRoadPoint(point){this.commit();if(this.roadDraft.length&&this.roadDraft.at(-1).every((v,i)=>v===point[i]))return false;this.roadDraft.push(clone(point));this.clearRedo();return true;}
    cancelRoad(){this.roadDraft.length=0;this.roadRedo=[];this.redoActions=this.redoActions.filter(a=>a!=='road');this.resumedRoad=null;}
    resumeRoad(id){const road=this.doc.roads.find(r=>r.id===id);if(!road)return false;this.cancelRoad();this.resumedRoad=clone(road);this.roadDraft.push(...clone(road.points));this.doc.roads=this.doc.roads.filter(r=>r.id!==id);this.clearRedo();return true;}
    finishRoad(metadata){if(this.roadDraft.length<2)return false;const road={...(this.resumedRoad||{}),...metadata,points:clone(this.roadDraft)};if(this.resumedRoad)road.id=this.resumedRoad.id;this.change(doc=>doc.roads.push(road));this.cancelRoad();return true;}
    undo(){this.commit();if(this.roadDraft.length){this.roadRedo.push(this.roadDraft.pop());this.redoActions.push('road');this.lastAction='road';return true;}if(!this.undoStack.length)return false;this.redoStack.push(JSON.stringify(this.doc));this.doc=JSON.parse(this.undoStack.pop());this.redoActions.push('document');this.lastAction='document';return true;}
    redo(){this.commit();const action=this.redoActions.pop();if(action==='road'){this.roadDraft.push(this.roadRedo.pop());this.lastAction='road';return true;}if(action==='document'&&this.redoStack.length){this.undoStack.push(JSON.stringify(this.doc));this.doc=JSON.parse(this.redoStack.pop());this.lastAction='document';return true;}return false;}
  }
  return {regions,types,sizes,upgradeSite,upgradeDocument,spawnPosition,syncSpawn,duplicateRoles,clone,key,center,axial,corners,neighbors,distance,normalizeSite,inside,validate,siteRule,wallKinds,visionPolygon,History};
});
