/* Hex authoring over the original battle model; art and gameplay references stay intact. */
(function(root,factory){const api=factory(typeof module==='object'&&module.exports?require('./battle-legacy.js'):root.MapEditorModel);if(typeof module==='object'&&module.exports)module.exports=api;else root.HexBattleModel=api;})(globalThis,function(L){
  'use strict';
  const clone=L.clone,key=(q,r)=>`${q},${r}`;
  const types={
    indestructible:['固定障碍','#525962','山'],destructible:['可破坏障碍','#ce9557','破'],traversable:['跨越障碍','#709aa0','跨'],collision_damage:['碰撞伤害','#b5736e','伤'],
    pit:['深坑','#30303c','坑'],thorns:['荆棘','#868956','荆'],mud:['泥潭','#8c7458','泥'],web:['蛛网','#a298bd','网'],
    deployment:['己方部署区','#599a83','己'],enemy:['敌方点位','#c47470','敌'],post_battle:['战后事件','#d5bc73','事'],
    tree:['树丛','#557454','树'],decoration:['地表装饰','#789361','草'],edge_decoration:['围边装饰','#647c68','边'],broken_barricade:['路障残骸','#99836c','残']
  };
  const families=[['unassigned','待选择形态'],['snake','蛇形'],['humanoid','人形'],['beast','兽形'],['spider','蜘蛛形'],['flying','飞行类']];
  const sizes=[['','待选择尺寸'],['tiny','微型'],['small','小型'],['medium','中型'],['large','大型'],['huge','巨型']];
  const grounds=[['plain','地面','#78816a'],['grass','草地','#779060'],['soil','裸土','#9b805e'],['stone','岩地','#747b7d'],['sand','沙地','#ba9e6c'],['water','浅水','#527e91']];
  function center(m,q,r){const R=m.hex_grid.cell_width/2,p=[1.5*R*q,Math.sqrt(3)*R*(r+q/2)];return rotate(p,m.orientation==='pointy'?30:0).map((v,i)=>v+m.hex_grid.origin[i]);}
  function rotate(p,degrees){const a=degrees*Math.PI/180;return [p[0]*Math.cos(a)-p[1]*Math.sin(a),p[0]*Math.sin(a)+p[1]*Math.cos(a)];}
  function axial(m,p){const v=rotate(p.map((v,i)=>v-m.hex_grid.origin[i]),m.orientation==='pointy'?-30:0),R=m.hex_grid.cell_width/2,q=2*v[0]/3/R,r=(-v[0]/3+Math.sqrt(3)*v[1]/3)/R,s=-q-r;let Q=Math.round(q),T=Math.round(r),S=Math.round(s);const a=Math.abs(Q-q),b=Math.abs(T-r),c=Math.abs(S-s);if(a>b&&a>c)Q=-T-S;else if(b>c)T=-Q-S;return [Q||0,T||0];}
  function corners(m,p=[0,0]){const R=m.hex_grid.cell_width/2;return Array.from({length:6},(_,i)=>rotate([R*Math.cos(i*Math.PI/3),R*Math.sin(i*Math.PI/3)],m.orientation==='pointy'?30:0).map((v,j)=>v+p[j]));}
  function inside(m,p){return L.pointInPolygon(p,L.polygon(m));}
  function grid(m){const n=Math.ceil(m.radius/m.hex_grid.cell_width*2)+2,out=[];for(let q=-n;q<=n;q++)for(let r=-n;r<=n;r++){const p=center(m,q,r);if(inside(m,p))out.push({q,r,p});}return out;}
  function neighbors(q,r,n){const out=[];for(let x=-n;x<=n;x++)for(let y=Math.max(-n,-x-n);y<=Math.min(n,-x+n);y++)out.push([q+x,r+y]);return out;}
  function category(o){if(o.type==='deployment'||o.type==='enemy')return 'deployment';if(o.type==='post_battle')return 'events';if(['tree','decoration','edge_decoration','broken_barricade'].includes(o.type))return 'decorations';if(o.region)return 'effects';return 'collisions';}
  function contains(m,o,p,shapeOnly=false){
    const local=L.localPoint(o,p);
    if(o.hex_footprint)return o.hex_footprint.some(v=>L.pointInPolygon(local,corners(m,v)));
    const shape=o.region||o.collision||o.click_area;
    if(shape&&L.shapeContains(shape,local))return true;
    return !shapeOnly&&L.hit(o,p,m.hex_grid.cell_width*.1);
  }
  function blocked(m,p){const c=m.hex_cells.find(c=>key(c.q,c.r)===key(...axial(m,p)));if(c?.control&&c.control!=='allowed')return true;return m.objects.some(o=>['indestructible','destructible','collision_damage','pit'].includes(o.type)&&(o.type==='pit'?o.region?.enabled:o.collision?.enabled)!==false&&contains(m,o,p,true));}
  function unique(project,prefix){const ids=new Set(project.maps.flatMap(m=>[m.id,...m.objects.map(o=>o.id)]));let n=1;while(ids.has(prefix+'_'+n))n++;return prefix+'_'+n;}
  function make(project,m,type,p){
    // These two obstacle types also make sense inside a battle arena.
    let o;
    if(['indestructible','destructible','traversable'].includes(type)){o=L.createObject('collision_damage',m,project,p);o.type=type;o.id=unique(project,type);delete o.damage;delete o.interval;delete o.targets;delete o.effect_ref;o.condition_ref=type==='destructible'?'has_monster':'';o.broken_asset='rubble';o.blocked_ids=[];o.landing=type==='traversable'?p.slice():undefined;}
    else o=L.createObject(type,m,project,p);
    o.id=unique(project,type);o.name=types[type][0];o.visual.tint=types[type][1];o.visual.size=[m.hex_grid.cell_width,m.hex_grid.cell_width];
    if(type==='deployment')o.slots=[[0,0]];
    if(type==='enemy')Object.assign(o,{monster_type:'unassigned',monster_size:'',grouped:false,count:1});
    return o;
  }
  function paint(project,m,type,points){
    const o=make(project,m,type,points[0]);
    o.hex_footprint=points.map(p=>p.map((v,i)=>v-o.position[i]));
    if(type==='deployment')o.slots=o.hex_footprint.map(p=>p.slice());
    const width=Math.max(...o.hex_footprint.map(p=>Math.abs(p[0])))*2+m.hex_grid.cell_width;
    const depth=Math.max(...o.hex_footprint.map(p=>Math.abs(p[1])))*2+m.hex_grid.cell_width;
    for(const s of [o.region,o.collision,o.click_area].filter(Boolean))s.size=[width,depth];
    return o;
  }
  function fields(o){let out=L.fieldsFor(o).filter(f=>f.path!=='id');const art=out.filter(f=>f.path.startsWith('visual.'));out=out.filter(f=>!f.path.startsWith('visual.'));out.unshift({path:'id',label:'唯一 ID',kind:'readonly'});if(o.hex_footprint)out.push({path:'hex_footprint',label:'蜂窝占地（相对坐标 X/Z）',kind:'points'});if(o.type==='enemy')out.splice(3,0,{path:'monster_type',label:'怪物形态',kind:'enum',options:families},{path:'monster_size',label:'怪物尺寸',kind:'enum',options:sizes},{path:'grouped',label:'群体点位',kind:'boolean'},{path:'count',label:'数量',kind:'number',min:1,max:999,step:1});art.push({path:'visual.surface_mode',label:'Godot 美术摆放',kind:'enum',options:[['auto','按要素自动'],['tilted','倾斜立起'],['ground','贴合地面']]},{path:'visual.tilt_degrees',label:'离地倾角（0贴地 / 90直立）',kind:'number',min:0,max:90,step:1});return out.concat(art);}
  function mapFields(m){return L.mapFields(m).map(f=>f.path==='id'?{...f,kind:'readonly'}:f).concat([{path:'hex_grid.cell_width',label:'蜂窝单块宽度',kind:'number',min:1,max:10,step:.1},{path:'background_color',label:'外部光晕底色',kind:'color'}]);}
  function validate(doc){
    if(!doc||doc.format!=='frontier_hex_battles'||doc.version!==1||!Array.isArray(doc.maps)||!doc.maps.length||doc.maps.length>100||!Array.isArray(doc.assets)||!doc.catalogs||!doc.source_maps||typeof doc.source_sha256!=='string')throw Error('不是兼容的蜂窝战场工作集。');
    const ids=new Set(),finite=(v,n)=>Array.isArray(v)&&v.length===n&&v.every(Number.isFinite),num=(v,min,max)=>Number.isFinite(v)&&v>=min&&v<=max;
    for(const m of doc.maps){
      if(typeof m.id!=='string'||!/^[A-Za-z0-9_-]{1,80}$/.test(m.id)||ids.has(m.id)||m.kind!=='battle'||typeof m.name!=='string'||!num(m.radius,3,200)||!['flat','pointy'].includes(m.orientation)||!m.wall||!num(m.wall.thickness,.05,10)||!num(m.wall.height,.1,1000)||!Number.isInteger(m.wall.layer)||m.wall.layer<1||m.wall.layer>1048575||!num(m.background_blur,0,30)||!num(m.edge_feather,0,10)||!m.hex_grid||!num(m.hex_grid.cell_width,1,10)||!finite(m.hex_grid.origin,2)||!Array.isArray(m.objects)||m.objects.length>10000||!Array.isArray(m.hex_cells)||m.hex_cells.length>100000)throw Error('战场范围、网格或对象结构无效：'+m.id);
      if(m.radius/m.hex_grid.cell_width>100)throw Error('战场过密，请增大蜂窝尺寸。');ids.add(m.id);const cells=new Set();
      for(const c of m.hex_cells){const k=key(c.q,c.r);if(!Number.isInteger(c.q)||!Number.isInteger(c.r)||Math.abs(c.q)>1000||Math.abs(c.r)>1000||cells.has(k)||c.ground&&!grounds.some(g=>g[0]===c.ground)||c.control&&!['allowed','outside','breakable'].includes(c.control))throw Error('蜂窝涂色或控制层无效');cells.add(k);for(const f of ['condition_ref','event_id'])if(c[f]!=null&&typeof c[f]!=='string')throw Error('控制层业务引用须为文本');}
      for(const o of m.objects){
        if(!types[o.type]||typeof o.id!=='string'||!o.id||ids.has(o.id)||typeof o.name!=='string'||!finite(o.position,2)||!finite(o.scale,2)||o.scale.some(v=>v<=0)||!num(o.height,-1000,1000)||!num(o.rotation,-360,360)||!o.visual||!finite(o.visual.size,2)||o.visual.size.some(v=>v<=0)||!num(o.visual.opacity,0,1))throw Error('对象结构无效：'+o.id);ids.add(o.id);
        if(o.visual.surface_mode&&!['auto','tilted','ground'].includes(o.visual.surface_mode)||o.visual.tilt_degrees!=null&&!num(o.visual.tilt_degrees,0,90))throw Error('Godot 美术倾角或摆放模式无效：'+o.id);
        for(const f of ['region','collision','click_area'])if(o[f]){const s=o[f];if(!['rect','circle','polygon'].includes(s.shape)||!finite(s.offset,2)||!finite(s.size,2)||s.size.some(v=>v<=0)||!Array.isArray(s.points)||!s.points.every(p=>finite(p,2))||!num(s.rotation,-360,360)||!num(s.height,.01,10000)||!num(s.depth,0,10000))throw Error('效果或碰撞范围无效：'+o.id);}
        if(o.hex_footprint&&(!Array.isArray(o.hex_footprint)||!o.hex_footprint.length||o.hex_footprint.length>10000||!o.hex_footprint.every(p=>finite(p,2))))throw Error('蜂窝占地无效：'+o.id);
        if(o.slots&&(!Array.isArray(o.slots)||!o.slots.every(p=>finite(p,2))))throw Error('部署槽位无效');
        if(o.type==='enemy'&&((o.monster_type&&!families.some(t=>t[0]===o.monster_type))||(o.monster_size&&!sizes.some(t=>t[0]===o.monster_size))||o.count!=null&&(!Number.isInteger(o.count)||o.count<1||o.count>999)))throw Error('怪物分类或数量无效');
      }
    }
    for(const m of doc.maps)if(m.encounter){
      const p=m.encounter,enemies=m.objects.filter(o=>o.type==='enemy'),total=enemies.reduce((n,o)=>n+(o.count||1),0),groups=new Map();
      if(!Number.isInteger(p.minimum_count)||!Number.isInteger(p.maximum_count)||p.minimum_count<1||p.maximum_count>10||p.minimum_count>p.maximum_count||total<p.minimum_count||total>p.maximum_count)throw Error('此战场敌军总数须为'+p.minimum_count+'至'+p.maximum_count+'只');
      for(const o of enemies){if((o.monster_type==='spider'||o.monster_species==='spider')&&p.region!=='spider')throw Error('蜘蛛仅允许部署在蜘蛛森林');if(!o.monster_config_id||!o.monster_type||o.monster_type==='unassigned')throw Error('敌军配置或形态未完成');const signature=JSON.stringify([o.monster_type,o.monster_size,o.grouped]);if(groups.has(o.team_group)&&groups.get(o.team_group)!==signature)throw Error('同组怪物的形态尺寸和群体属性须一致');groups.set(o.team_group,signature);}
      if(groups.size>2||groups.size>1&&!(p.difficulty===3||p.difficulty===2&&p.sublevel==='upper'))throw Error('复合敌群仅在二级高段或三级开放，最多两组');
      if(groups.size===2&&new Set(groups.values()).size===1)throw Error('主副组不能完全相同');
    }
    return doc;
  }
  function issues(m){const out=[];const add=(o,message,level='error')=>out.push({id:o?.id||'',message,level});const occupied=[];
    for(const o of m.objects){
      if(!['edge_decoration','decoration','tree','broken_barricade'].includes(o.type)&&!inside(m,o.position))add(o,'对象中心超出战场：'+o.name);
      if(o.hex_footprint&&!['edge_decoration','decoration'].includes(o.type)&&o.hex_footprint.some(p=>!inside(m,L.worldPoint(o,p))))add(o,'部分蜂窝占地超出战场：'+o.name);
      if(o.type==='deployment'){
        if(!o.slots?.length)add(o,'部署区没有槽位：'+o.name);
        for(const [i,s] of (o.slots||[]).entries()){const p=L.worldPoint(o,s);if(!inside(m,p)||!contains(m,o,p,true))add(o,`槽位 ${i+1} 不在场内或部署区内`);if(blocked(m,p))add(o,`槽位 ${i+1} 与障碍、深坑或控制层重叠`);if(occupied.some(v=>Math.hypot(v[0]-p[0],v[1]-p[1])<.01))add(o,`槽位 ${i+1} 与其他槽位重叠`);occupied.push(p);}
      }
      if(o.type==='enemy'){if(blocked(m,o.position))add(o,'敌方点位落在障碍或深坑内：'+o.name);if(!o.monster_config_id)add(o,'敌方配置 ID 待填写：'+o.name,'warning');}
      if(['pit','web','mud','thorns','collision_damage'].includes(o.type)&&!o.effect_ref)add(o,'效果引用待同事配置：'+o.name,'warning');
      if(o.type==='web'&&(o.min_height>o.max_height))add(o,'蛛网最低高度高于最高高度');
    }
    if(!m.objects.some(o=>o.type==='deployment'))add(null,'尚未设置己方部署区');
    for(const c of m.hex_cells)if(!inside(m,center(m,c.q,c.r)))add(null,`蜂窝 ${c.q},${c.r} 超出战场（范围改变后保留原坐标）`);
    return out;
  }
  // Compile multi-cell effects into original-model polygons, never their bounding box.
  function compileMap(map){const m=clone(map),extra=[];
    m.objects=m.objects.flatMap(o=>{
      if(!o.hex_footprint)return [o];
      const footprint=o.hex_footprint;delete o.hex_footprint;
      const shapeKey=o.region?'region':o.collision?'collision':o.click_area?'click_area':null;
      if(!shapeKey)return footprint.map((p,i)=>({...clone(o),id:i?`${o.id}__hex_${i}`:o.id,position:L.worldPoint(o,p)}));
      const parts=footprint.map((p,i)=>{const v=clone(o);v.id=i?`${o.id}__hex_${i}`:o.id;v.semantic_group=o.id;v[shapeKey]={...v[shapeKey],shape:'polygon',offset:[0,0],rotation:0,points:corners(m,p)};if(i)v.visual.visible=false;return v;});
      // Partition deployment slots across polygons so the original runtime can consume them.
      if(o.type==='deployment')for(const part of parts)part.slots=(o.slots||[]).filter(slot=>L.shapeContains(part.region,slot));
      return parts;
    });
    for(const c of m.hex_cells)if(c.control==='outside'||c.control==='breakable'){
      const o=make({maps:[m]},m,c.control==='breakable'?'destructible':'indestructible',center(m,c.q,c.r));o.id=`hex_boundary_${c.q}_${c.r}`;o.name=c.control==='breakable'?'可破坏边缘':'禁止进入';o.collision={...o.collision,shape:'polygon',points:corners(m),size:[m.hex_grid.cell_width,m.hex_grid.cell_width]};o.condition_ref=c.condition_ref||'';o.event_id=c.event_id||'';o.visual.visible=false;extra.push(o);
    }
    m.objects.push(...extra);return m;
  }
  class History{constructor(map){this.map=clone(map);this.undoStack=[];this.redoStack=[];}commit(before){const value=typeof before==='string'?before:JSON.stringify(before);if(value===JSON.stringify(this.map))return false;this.undoStack.push(value);if(this.undoStack.length>60)this.undoStack.shift();this.redoStack=[];return true;}change(fn){const before=JSON.stringify(this.map);fn(this.map);return this.commit(before);}undo(){if(!this.undoStack.length)return false;this.redoStack.push(JSON.stringify(this.map));this.map=JSON.parse(this.undoStack.pop());return true;}redo(){if(!this.redoStack.length)return false;this.undoStack.push(JSON.stringify(this.map));this.map=JSON.parse(this.redoStack.pop());return true;}}
  return {L,clone,key,types,families,sizes,grounds,center,axial,corners,grid,neighbors,inside,category,contains,blocked,unique,make,paint,fields,mapFields,validate,issues,compileMap,History};
});
