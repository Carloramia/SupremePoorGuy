'use strict';
const M=HexBattleModel,L=M.L,$=id=>document.getElementById(id),canvas=$('battle-canvas'),ctx=canvas.getContext('2d');
let project,etag='',server=false,active='',saved='',selection=null,tab='object',tool='select',space=false,gesture=null,hover=null,preview=false,renderPending=false,w=1,h=1;
const histories=new Map(),views=new Map(),visible={ground:true,decorations:true,collisions:true,effects:true,deployment:true,events:true,control:true,grid:true,ranges:true,names:true,halo:true};
const pendingFields=new Set();
function flushFields(){for(const apply of [...pendingFields]){pendingFields.delete(apply);apply();}}
function trackField(input,apply){const commit=()=>{pendingFields.delete(commit);apply();};input.onchange=commit;input.oninput=()=>pendingFields.add(commit);}
const labels={ground:'地面涂色',decorations:'装饰与围边',collisions:'实体障碍',effects:'陷阱与效果',deployment:'部署区与敌方',events:'战后事件',control:'边缘控制',grid:'蜂窝网格',ranges:'原始范围辅助线',names:'点位名称',halo:'场景外光晕'};
const drawingTools=new Set(['indestructible','destructible','traversable','collision_damage','pit','thorns','mud','web','deployment','tree','decoration','edge_decoration','broken_barricade']);
const map=()=>histories.get(active)?.map;
const view=()=>views.get(active);
const selected=()=>selection?.kind==='object'?map().objects.find(o=>o.id===selection.id):null;
function sync(){if(project)project.maps=project.maps.map(m=>histories.get(m.id)?.map||m);}
function signature(){sync();return JSON.stringify(project);}
function dirty(){return !!project&&signature()!==saved;}
function message(text){$('status').textContent=text;}
function requestDraw(){if(!renderPending){renderPending=true;requestAnimationFrame(draw);}}
function screen(p){const v=view();return [(p[0]-v.camera[0])*v.zoom+w/2,(p[1]-v.camera[1])*v.zoom+h/2];}
function world(p){const v=view();return [(p[0]-w/2)/v.zoom+v.camera[0],(p[1]-h/2)/v.zoom+v.camera[1]];}
function path(points){ctx.beginPath();points.forEach((p,i)=>{const v=screen(p);i?ctx.lineTo(...v):ctx.moveTo(...v);});ctx.closePath();}
function cellPath(p){path(M.corners(map(),p));}
function color(type){return M.types[type]?.[1]||'#829775';}
function refresh(){sync();$('save-state').textContent=dirty()?'● 有未保存修改':'战场已保存';$('undo').disabled=!histories.get(active)?.undoStack.length;$('redo').disabled=!histories.get(active)?.redoStack.length;$('view-title').textContent=map().name;$('dimensions').textContent=`半径 ${map().radius} · 单格 ${map().hex_grid.cell_width} · ${M.grid(map()).length} 格`;$('zoom').textContent=Math.round(view().zoom*10)+'%';requestDraw();}
function updateMap(fn){const hist=histories.get(active),before=JSON.stringify(hist.map);try{fn(hist.map);sync();M.validate(project);hist.commit(before);refresh();}catch(e){hist.map=JSON.parse(before);sync();message(e.message);throw e;}}
function fit(){const v=view(),rect=canvas.getBoundingClientRect();if(rect.width<=1||rect.height<=1){v.needsFit=true;return;}v.camera=[0,0];v.zoom=Math.max(1,Math.min(rect.width,rect.height)/(map().radius*2.65));v.needsFit=false;refresh();}
function resize(){const rect=canvas.getBoundingClientRect(),ratio=devicePixelRatio||1;if(rect.width<=1||rect.height<=1)return;w=rect.width;h=rect.height;canvas.width=Math.max(1,Math.round(w*ratio));canvas.height=Math.max(1,Math.round(h*ratio));ctx.setTransform(ratio,0,0,ratio,0,0);if(project){if(view()?.needsFit)fit();else requestDraw();}}
function rebuildPicker(){const previous=active;$('battle-select').replaceChildren();for(const m of project.maps){const o=document.createElement('option');o.value=m.id;o.textContent=m.name;$('battle-select').append(o);}$('battle-select').value=previous;}
function activate(id){if(!histories.has(id)){message('未找到战场：'+id);return;}endGesture();active=id;selection=null;$('battle-select').value=id;if(!views.has(id)){views.set(id,{camera:[0,0],zoom:1});fit();}refresh();properties();list();}
function objectsAt(p){const m=map();return m.objects.filter(o=>visible[M.category(o)]&&M.contains(m,o,p)).sort((a,b)=>{
  const distance=o=>Math.hypot(o.position[0]-p[0],o.position[1]-p[1]);
  const rank=o=>['enemy','post_battle'].includes(o.type)?0:o.type==='deployment'?1:M.category(o)==='decorations'?3:2;
  return rank(a)-rank(b)||distance(a)-distance(b);
});}
function drawShape(o,s){if(!s?.enabled)return;let points;if(s.shape==='polygon')points=s.points;else if(s.shape==='circle')points=Array.from({length:32},(_,i)=>[Math.cos(i*Math.PI/16)*s.size[0]/2,Math.sin(i*Math.PI/16)*s.size[1]/2]);else points=[[-s.size[0]/2,-s.size[1]/2],[s.size[0]/2,-s.size[1]/2],[s.size[0]/2,s.size[1]/2],[-s.size[0]/2,s.size[1]/2]];path(points.map(p=>M.L.worldPoint(o,M.L.worldPoint({position:s.offset,rotation:s.rotation,scale:[1,1]},p))));ctx.stroke();}
function draw(){
  renderPending=false;if(!project||!map())return;const m=map(),v=view(),grid=M.grid(m);ctx.clearRect(0,0,w,h);ctx.fillStyle='#17201e';ctx.fillRect(0,0,w,h);
  if(visible.halo){ctx.save();ctx.shadowBlur=m.background_blur*3+m.edge_feather*8;ctx.shadowColor=m.background_color||'#5c7853';path(L.polygon(m).map(p=>p.map(x=>x*1.1)));ctx.fillStyle=m.background_color||'#344732';ctx.fill();ctx.restore();}
  ctx.save();path(L.polygon(m));ctx.clip();ctx.fillStyle=m.ground_color;ctx.fillRect(0,0,w,h);
  const records=new Map(m.hex_cells.map(c=>[M.key(c.q,c.r),c]));
  for(const c of grid){const record=records.get(M.key(c.q,c.r));if(visible.ground&&record?.ground){cellPath(c.p);ctx.fillStyle=m.ground_palette?.[record.ground]||M.grounds.find(g=>g[0]===record.ground)[2];ctx.fill();}}
  const ordered=m.objects.slice().sort((a,b)=>(a.visual.z_index||0)-(b.visual.z_index||0));
  for(const o of ordered){if(!visible[M.category(o)]||(M.category(o)==='decorations'||preview&&M.category(o)!=='deployment')&&(o.visual.visible===false||browserArtPath(project.assets.find(a=>a.id===o.visual.asset))))continue;const tint=color(o.type);ctx.fillStyle=tint;ctx.globalAlpha=M.category(o)==='decorations'?.28:.64;
    if(o.hex_footprint){for(const p of o.hex_footprint){path(M.corners(m,p).map(q=>L.worldPoint(o,q)));ctx.fill();}}
    else for(const c of grid)if(M.contains(m,o,c.p,M.category(o)!=='decorations')){cellPath(c.p);ctx.fill();}
    ctx.globalAlpha=1;
  }
  if(visible.control)for(const c of grid){const record=records.get(M.key(c.q,c.r));if(!record?.control)continue;cellPath(c.p);ctx.fillStyle={outside:'#ba5d63',allowed:'#64ac84',breakable:'#e59c44'}[record.control];ctx.globalAlpha=.38;ctx.fill();ctx.globalAlpha=.8;ctx.strokeStyle=ctx.fillStyle;ctx.lineWidth=1.5;ctx.stroke();ctx.globalAlpha=1;}
  if(visible.grid&&!preview){ctx.strokeStyle='#20342980';ctx.lineWidth=.7;for(const c of grid){cellPath(c.p);ctx.stroke();}}
  if(visible.ranges&&!preview){ctx.save();ctx.setLineDash([4,4]);ctx.lineWidth=1;for(const o of ordered){if(!visible[M.category(o)]||o.hex_footprint||M.category(o)==='decorations')continue;ctx.strokeStyle=color(o.type);drawShape(o,o.region||o.collision||o.click_area);}ctx.restore();}
  // Environment art stays below deployment slots, actors and interaction markers.
  for(const artObject of ordered.slice().sort((a,b)=>(a.visual.z_index||0)-(b.visual.z_index||0)||a.position[1]-b.position[1]))drawImportedArt(artObject);
  for(const o of ordered){if(!visible[M.category(o)])continue;const p=screen(o.position),isPoint=['enemy','post_battle'].includes(o.type);
    if(o.type==='deployment')for(const [i,slot] of (o.slots||[]).entries()){const s=screen(L.worldPoint(o,slot));ctx.beginPath();ctx.arc(...s,Math.max(5,Math.min(10,v.zoom*.35)),0,Math.PI*2);ctx.fillStyle='#c0e8c5';ctx.fill();ctx.strokeStyle='#244735';ctx.lineWidth=1.5;ctx.stroke();ctx.fillStyle='#21402e';ctx.textAlign='center';ctx.textBaseline='middle';ctx.font='bold 9px sans-serif';ctx.fillText(String(i+1),...s);}
    if(isPoint||!preview&&(o===selected()||visible.names&&!o.hide_name_label&&M.category(o)!=='decorations')){
      ctx.fillStyle=color(o.type);ctx.strokeStyle='#14221b';ctx.lineWidth=2;
      ctx.beginPath();ctx.arc(...p,isPoint?10:7,0,Math.PI*2);ctx.fill();ctx.stroke();
      ctx.font='bold 10px Microsoft YaHei';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillStyle='#17231c';ctx.fillText(o.type==='enemy'?(M.families.find(f=>f[0]===o.monster_type)?.[1]?.[0]||'敌'):M.types[o.type][2],...p);
      if(visible.names&&!preview){ctx.font='11px Microsoft YaHei';ctx.fillStyle='#edf2df';ctx.strokeStyle='#17231c';ctx.lineWidth=3;ctx.strokeText(o.name,p[0],p[1]-16);ctx.fillText(o.name,p[0],p[1]-16);}
      if(isPoint){const d=M.L.worldPoint({position:o.position,scale:[1,1],rotation:o.facing||0},[0,-m.hex_grid.cell_width*.7]),end=screen(d);ctx.beginPath();ctx.moveTo(...p);ctx.lineTo(...end);ctx.strokeStyle=color(o.type);ctx.lineWidth=2;ctx.stroke();}
    }
  }
  const o=selected();if(o&&!preview){ctx.save();ctx.strokeStyle='#f1eab9';ctx.lineWidth=2;if(o.hex_footprint)for(const p of o.hex_footprint){path(M.corners(m,p).map(q=>L.worldPoint(o,q)));ctx.stroke();}else{drawShape(o,o.region||o.collision||o.click_area||{enabled:true,shape:'rect',size:o.visual.size,offset:[0,0],rotation:0,points:[]});}ctx.restore();}
  if(selection?.kind==='cell'&&!preview){cellPath(M.center(m,selection.q,selection.r));ctx.strokeStyle='#f4e9ae';ctx.lineWidth=2.5;ctx.stroke();}
  if(gesture?.points?.length){ctx.fillStyle=color(tool);ctx.globalAlpha=.65;for(const p of gesture.points){cellPath(p);ctx.fill();}ctx.globalAlpha=1;}
  if(hover&&!preview&&tool!=='select'){const [q,r]=M.axial(m,hover);ctx.fillStyle='#f5f2bf';ctx.strokeStyle='#f6efbc';ctx.globalAlpha=.2;for(const [x,z] of M.neighbors(q,r,Number($('brush').value))){const p=M.center(m,x,z);if(!M.inside(m,p))continue;cellPath(p);ctx.fill();ctx.stroke();}ctx.globalAlpha=1;}
  ctx.restore();path(L.polygon(m));ctx.strokeStyle='#b4c39b';ctx.lineWidth=2;ctx.stroke();
}
function setTool(value){tool=value;preview=false;$('preview').classList.remove('active');for(const b of $('tools').querySelectorAll('button'))b.classList.toggle('active',b.dataset.tool===tool);$('ground').parentElement.hidden=tool!=='ground';$('control').parentElement.hidden=tool!=='control';$('brush').parentElement.hidden=['select','enemy','post_battle','slot'].includes(tool);$('erase-layer').parentElement.hidden=tool!=='erase';$('tool-help').textContent=tool==='slot'?'先选部署区，再点击蜂窝添加槽位；槽位的精确坐标可在右侧编辑。':tool==='control'?'控制层独立于地面与障碍；橙色需要破坏后才可通过。':drawingTools.has(tool)?'拖动涂色，一笔组成一个对象；右侧设置范围、效果与美术引用。':tool==='erase'?'只擦除所选图层；一笔操作可整体撤销。':'单击选择，拖动对象吸附蜂窝；中键 / 空格平移，滚轮缩放。';canvas.style.cursor=tool==='select'?'default':'crosshair';requestDraw();}
function toolButton(value,name,swatch){const b=document.createElement('button');b.type='button';b.dataset.tool=value;const i=document.createElement('i');i.style.setProperty('--swatch',swatch);b.append(i,document.createTextNode(name));b.onclick=()=>setTool(value);$('tools').append(b);}
function initTools(){
  const group=name=>{const title=document.createElement('div');title.className='tool-group';title.textContent=name;$('tools').append(title);};
  toolButton('select','选择 / 移动','#bdcaac');toolButton('ground','地面涂色','#9aaf78');toolButton('control','边缘控制','#dd9451');
  for(const [name,values] of [['障碍与效果',['indestructible','destructible','traversable','collision_damage','pit','thorns','mud','web']],['部署与交互',['deployment','slot','enemy','post_battle']],['环境与围边',['tree','decoration','edge_decoration','broken_barricade']]]){group(name);for(const t of values)toolButton(t,t==='slot'?'添加己方槽位':M.types[t][0],t==='slot'?'#b2d5aa':color(t));}
  toolButton('erase','擦除图层','#adb8a2');
  const label=document.createElement('label');label.textContent='擦除目标';const select=document.createElement('select');select.id='erase-layer';for(const k of ['ground','collisions','effects','deployment','events','decorations','control']){const o=document.createElement('option');o.value=k;o.textContent=labels[k];select.append(o);}label.append(select);$('paint-options').append(label);
  for(const g of M.grounds){const o=document.createElement('option');o.value=g[0];o.textContent=g[1];$('ground').append(o);}
  for(const [name,value] of Object.entries(visible)){const label=document.createElement('label');label.className='check';const input=document.createElement('input');input.type='checkbox';input.checked=value;input.onchange=()=>{visible[name]=input.checked;requestDraw();};label.append(input,document.createTextNode(labels[name]));$('layers').append(label);}setTool('select');
}
function cellRecord(m,q,r){let c=m.hex_cells.find(c=>c.q===q&&c.r===r);if(!c){c={q,r};m.hex_cells.push(c);}return c;}
function cleanCells(m){m.hex_cells=m.hex_cells.filter(c=>Object.keys(c).length>2);}
function applyBrushAt(p){const m=map(),[q,r]=M.axial(m,p),points=M.neighbors(q,r,Number($('brush').value));
  for(const [x,z] of points){const k=M.key(x,z),pos=M.center(m,x,z);if(!M.inside(m,pos)||gesture.seen.has(k))continue;gesture.seen.add(k);
    if(drawingTools.has(tool))gesture.points.push(pos);
    else if(tool==='ground'){cellRecord(m,x,z).ground=$('ground').value;}
    else if(tool==='control'){const c=cellRecord(m,x,z),mode=$('control').value;if(mode==='clear'){delete c.control;delete c.condition_ref;delete c.event_id;}else{c.control=mode;if(mode==='breakable')c.condition_ref??='has_monster';}}
    else if(tool==='erase'){const layer=$('erase-layer').value,c=cellRecord(m,x,z);if(layer==='ground')delete c.ground;else if(layer==='control'){delete c.control;delete c.condition_ref;delete c.event_id;}else{m.objects=m.objects.filter(o=>{if(M.category(o)!==layer)return true;if(o.hex_footprint){o.hex_footprint=o.hex_footprint.filter(v=>!M.L.pointInPolygon(M.L.localPoint(o,pos),M.corners(m,v)));if(o.type==='deployment')o.slots=(o.slots||[]).filter(v=>M.contains(m,o,L.worldPoint(o,v),true));return o.hex_footprint.length>0;}return !M.contains(m,o,pos);});}}
  }
  cleanCells(m);requestDraw();
}
function applyBrush(p){const from=gesture.last||p,steps=Math.max(1,Math.ceil(Math.hypot(p[0]-from[0],p[1]-from[1])/(map().hex_grid.cell_width*.35)));for(let i=1;i<=steps;i++)applyBrushAt(from.map((v,j)=>v+(p[j]-v)*i/steps));gesture.last=p.slice();}
function startPaint(p){gesture={kind:'paint',before:JSON.stringify(map()),seen:new Set(),points:[]};applyBrush(p);}
function endGesture(){flushFields();if(!gesture||!project)return;const g=gesture;gesture=null;
  if(g.kind==='paint'&&g.points.length){const o=M.paint(project,map(),tool,g.points);map().objects.push(o);selection={kind:'object',id:o.id};tab='object';}
  if(g.before){histories.get(active).commit(g.before);refresh();properties();list();}
  canvas.style.cursor=tool==='select'?'default':'crosshair';
}
function pointer(e){const rect=canvas.getBoundingClientRect();return [e.clientX-rect.left,e.clientY-rect.top];}
canvas.addEventListener('pointerdown',e=>{
  if(!project)return;flushFields();const p=pointer(e),pos=world(p);canvas.focus();canvas.setPointerCapture(e.pointerId);
  if(e.button===1||space){e.preventDefault();gesture={kind:'pan',start:p,camera:view().camera.slice()};canvas.style.cursor='grabbing';return;}
  if(e.button!==0)return;
  if(preview){message('灰盒预览中，点击“布局编辑”后修改。');return;}
  if(!M.inside(map(),pos)){message('此处在战场外；可在场景设置调整半径。');return;}
  if(tool==='select'){
    const o=objectsAt(pos)[0];if(o){selection={kind:'object',id:o.id};gesture={kind:'move',id:o.id,start:pos,position:o.position.slice(),before:JSON.stringify(map()),moved:false};}
    else{const [q,r]=M.axial(map(),pos);selection={kind:'cell',q,r};}tab='object';properties();list();requestDraw();return;
  }
  if(tool==='slot'){
    let o=selected();if(o?.type!=='deployment')o=map().objects.find(o=>o.type==='deployment'&&M.contains(map(),o,pos,true));
    if(!o){message('请先选中部署区，或在部署区内点击。');return;}const point=M.center(map(),...M.axial(map(),pos));if(!M.contains(map(),o,point,true)){message('槽位需要放在所选部署区内。');return;}
    const slot=L.localPoint(o,point);if(o.slots.some(v=>Math.hypot(v[0]-slot[0],v[1]-slot[1])<.01)){message('此处已有槽位。');return;}
    updateMap(()=>o.slots.push(slot));selection={kind:'object',id:o.id};properties();message('已添加己方槽位。');return;
  }
  if(['enemy','post_battle'].includes(tool)){const point=M.center(map(),...M.axial(map(),pos));if(!M.inside(map(),point))return;const o=M.make(project,map(),tool,point);updateMap(m=>m.objects.push(o));selection={kind:'object',id:o.id};tab='object';properties();list();message('已放置'+M.types[tool][0]+'，右侧填写配置。');return;}
  startPaint(pos);
});
canvas.addEventListener('pointermove',e=>{if(!project)return;const p=pointer(e),pos=world(p);hover=pos;const [q,r]=M.axial(map(),pos);$('cursor').textContent=`X ${pos[0].toFixed(1)} / Z ${pos[1].toFixed(1)} · ${q}, ${r}`;
  if(gesture?.kind==='pan'){view().camera=gesture.camera.map((v,i)=>v-(p[i]-gesture.start[i])/view().zoom);requestDraw();return;}
  if(gesture?.kind==='move'){const o=map().objects.find(o=>o.id===gesture.id),distance=Math.hypot(pos[0]-gesture.start[0],pos[1]-gesture.start[1]);if(distance>.15){o.position=M.center(map(),...M.axial(map(),gesture.position.map((v,i)=>v+pos[i]-gesture.start[i])));gesture.moved=true;}requestDraw();return;}
  if(gesture?.kind==='paint')applyBrush(pos);else requestDraw();
});
canvas.addEventListener('pointerup',endGesture);canvas.addEventListener('pointercancel',endGesture);canvas.addEventListener('lostpointercapture',endGesture);canvas.addEventListener('pointerleave',()=>{hover=null;requestDraw();});canvas.addEventListener('contextmenu',e=>e.preventDefault());
canvas.addEventListener('wheel',e=>{if(!project)return;e.preventDefault();const p=pointer(e),before=world(p),v=view();v.zoom=Math.max(1,Math.min(150,v.zoom*Math.exp(-e.deltaY*.001)));const after=world(p);v.camera=v.camera.map((value,i)=>value+before[i]-after[i]);refresh();},{passive:false});
function option(input,value,label){const o=document.createElement('option');o.value=value;o.textContent=label;input.append(o);}
function renderField(f,object,apply){
  const label=document.createElement('label');label.textContent=f.label;const value=L.get(object,f.path);let input;
  if(f.kind==='boolean'){input=document.createElement('input');input.type='checkbox';input.checked=!!value;label.className='check';label.prepend(input);}
  else if(f.kind==='vector'){input=document.createElement('div');input.className='vector';for(let i=0;i<2;i++){const n=document.createElement('input');n.type='number';n.step='.1';n.value=Array.isArray(value)?value[i]:0;n.setAttribute('aria-label',f.label+' '+(i?'Z':'X'));trackField(n,()=>{const values=[...input.children].map(n=>Number(n.value));try{apply(values);}catch(e){message(e.message);}});input.append(n);}label.append(input);return label;}
  else if(f.kind==='reference'&&f.ref==='assets'){input=document.createElement('input');input.value=value||'';input.setAttribute('list','asset-refs');input.placeholder='输入素材 ID，可搜索已有素材';}
  else if(['select','reference','enum'].includes(f.kind)){input=document.createElement('select');
    if(f.kind==='enum')for(const [v,t] of f.options)option(input,v,t);
    else if(f.kind==='select')for(const v of f.options)option(input,v,({flat:'平顶',pointy:'尖顶',all:'全部',ground:'地面单位',flying:'飞行单位',player:'己方',enemy:'敌方',rect:'矩形',circle:'圆 / 椭圆',polygon:'多边形'})[v]||v);
    else{option(input,'','留空 / 待配置');for(const v of L.refs(project,f.ref,object))option(input,v.id,v.name||v.id);}
    if(value!=null&&![...input.options].some(o=>o.value===String(value)))option(input,value,value+' · 自定义引用');input.value=value??'';
    if(f.kind==='reference'){const wrap=document.createElement('div');const free=document.createElement('input');free.value=value??'';free.placeholder='或填写自定义 ID';free.setAttribute('aria-label',f.label+' 自定义引用');trackField(free,()=>{try{apply(free.value.trim());input.value=free.value;}catch(e){message(e.message);}});input.onchange=()=>{try{apply(input.value);free.value=input.value;}catch(e){message(e.message);}};wrap.append(input,free);label.append(wrap);return label;}
  }
  else if(f.kind==='points'||f.kind==='strings'){input=document.createElement('textarea');input.value=JSON.stringify(value||[],null,1);input.spellcheck=false;}
  else{input=document.createElement('input');input.type=f.kind==='number'?'number':f.kind==='color'?'color':'text';input.value=value??(f.kind==='color'?'#344732':'');if(f.kind==='readonly')input.readOnly=true;if(f.kind==='number'){input.min=f.min;input.max=f.max;input.step=f.step||1;}}
  input.setAttribute('aria-label',f.label);input.dataset.path=f.path;
  trackField(input,()=>{try{let v=f.kind==='boolean'?input.checked:f.kind==='number'?Number(input.value):['points','strings'].includes(f.kind)?JSON.parse(input.value):input.value;if(f.kind==='number'&&(!Number.isFinite(v)||v<f.min||v>f.max))throw Error(`${f.label} 应在 ${f.min}～${f.max} 之间`);apply(v);}catch(e){message('参数未应用：'+e.message);}});
  if(f.kind!=='boolean')label.append(input);return label;
}
function properties(){
  if(!project)return;flushFields();const out=$('properties');out.replaceChildren();$('issues').hidden=tab!=='issues';$('object-actions').hidden=true;$('advanced').hidden=true;
  for(const [id,name] of [['object-tab','object'],['map-tab','map'],['issues-tab','issues']])$(id).classList.toggle('active',tab===name);
  if(tab==='issues'){out.hidden=true;$('selection-title').textContent='部署与配置检查';showIssues();return;}out.hidden=false;
  let object,fields,apply;
  if(tab==='map'){object=map();fields=M.mapFields(object);$('selection-title').textContent='战场范围与外部效果';apply=(f,v)=>updateMap(m=>L.set(m,f.path,v));}
  else if(selection?.kind==='cell'){
    const {q,r}=selection;object=map().hex_cells.find(c=>c.q===q&&c.r===r)||{q,r};$('selection-title').textContent=`蜂窝 ${q}, ${r}`;
    fields=[{path:'ground',label:'地面涂色',kind:'enum',options:[['','默认地面'],...M.grounds.map(g=>g.slice(0,2))]},{path:'control',label:'边缘控制',kind:'enum',options:[['','未设置'],['allowed','绿色 · 允许区域'],['outside','红色 · 禁止进入'],['breakable','橙色 · 破坏后通过']]},{path:'condition_ref',label:'破坏条件 ID',kind:'text'},{path:'event_id',label:'边缘事件 ID',kind:'text'}];
    apply=(f,v)=>updateMap(m=>{const c=cellRecord(m,q,r);if(v==='')delete c[f.path];else c[f.path]=v;if(f.path==='control'&&v==='breakable')c.condition_ref??='has_monster';cleanCells(m);});
  }
  else {object=selected();if(!object){$('selection-title').textContent='选择蜂窝或对象';const p=document.createElement('p');p.className='muted';p.textContent='左侧选择工具，直接在蜂窝上涂色或摆放。历史对象保留原坐标；移动时吸附蜂窝。右上“场景设置”可修改战场大小、围边与光晕。';out.append(p);return;}
    fields=M.fields(object);$('selection-title').textContent=object.name;$('object-actions').hidden=false;$('advanced').hidden=false;$('advanced-json').value=JSON.stringify(object,null,2);
    const objectId=object.id;apply=(f,v)=>updateMap(m=>L.set(m.objects.find(o=>o.id===objectId),f.path,v));
    if(object.hex_footprint){const p=document.createElement('p');p.className='muted';p.textContent=`蜂窝占地：${object.hex_footprint.length} 格。效果与碰撞沿蜂窝轮廓；高度和规则可独立调整。`;out.append(p);const b=document.createElement('button');b.textContent='转为独立矩形范围';b.onclick=()=>{updateMap(()=>{const points=object.hex_footprint.flatMap(p=>M.corners(map(),p)),lo=[0,1].map(i=>Math.min(...points.map(p=>p[i]))),hi=[0,1].map(i=>Math.max(...points.map(p=>p[i])));for(const s of [object.region,object.collision,object.click_area].filter(Boolean)){s.shape='rect';s.offset=lo.map((v,i)=>(v+hi[i])/2);s.size=lo.map((v,i)=>hi[i]-v);s.rotation=0;}delete object.hex_footprint;});properties();};out.append(b);}
  }
  let section='';for(const f of fields){const prefix=f.path.split('.')[0];if(prefix!==section&&['visual','collision','region','click_area','hex_grid','wall','hex_footprint'].includes(prefix)){section=prefix;const title=document.createElement('div');title.className='field-section';title.textContent=({visual:'美术置换接口',collision:'碰撞范围',region:'效果 / 部署范围',click_area:'事件点击范围',wall:'空气墙',hex_grid:'蜂窝尺寸',hex_footprint:'蜂窝占地'})[prefix];out.append(title);}
    out.append(renderField(f,object,v=>{apply(f,v);if(f.path==='name')rebuildPicker();requestDraw();list();}));}
}
function list(){const out=$('object-list');out.replaceChildren();const title=document.createElement('h2');title.textContent=`对象列表 · ${map().objects.length}`;out.append(title);for(const o of map().objects){const b=document.createElement('button');b.className='object-row'+(selection?.id===o.id?' active':'');const tag=document.createElement('small');tag.textContent=M.types[o.type][2];const name=document.createElement('span');name.textContent=o.name;b.append(tag,name);b.onclick=()=>{selection={kind:'object',id:o.id};tab='object';properties();list();requestDraw();};b.ondblclick=()=>{view().camera=o.position.slice();requestDraw();};out.append(b);}}
function showIssues(){const out=$('issues');out.replaceChildren();const found=M.issues(map()),errors=found.filter(v=>v.level==='error').length;const p=document.createElement('p');p.className='muted';p.textContent=`${errors} 项布局错误 · ${found.length-errors} 项业务引用待配置。草稿可以保存；接入配置需先解决布局错误。`;out.append(p);for(const v of found){const b=document.createElement('button');b.className='issue '+v.level;b.textContent=v.message;b.onclick=()=>{if(v.id){selection={kind:'object',id:v.id};const o=selected();if(o)view().camera=o.position.slice();tab='object';properties();requestDraw();}};out.append(b);}if(!found.length){p.textContent='检查通过：部署槽位、障碍与战场范围有效。';}}
function remove(){flushFields();const o=selected();if(!o)return;updateMap(m=>m.objects=m.objects.filter(v=>v.id!==o.id));selection=null;properties();list();message('已删除，可 Ctrl+Z 撤销。');}
function duplicate(){flushFields();const o=selected();if(!o)return;const copy=M.clone(o);copy.id=M.unique(project,o.type);copy.name=o.name+' 副本';const [q,r]=M.axial(map(),o.position);copy.position=M.center(map(),q+1,r);updateMap(m=>m.objects.push(copy));selection={kind:'object',id:copy.id};properties();list();}
function undo(redo=false){endGesture();const hist=histories.get(active);if((redo?hist.redo():hist.undo())){sync();if(selection?.kind==='object'&&!selected())selection=null;refresh();properties();list();message(redo?'已重做。':'已撤销。');}}
function download(name,data){const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),3000);}
async function save(){endGesture();document.activeElement?.blur();try{sync();M.validate(project);if(server){const response=await fetch('/api/battles',{method:'POST',headers:{'Content-Type':'application/json','If-Match':etag},body:JSON.stringify(project)}),result=await response.json();if(!response.ok)throw Error(result.error||'保存失败');etag=response.headers.get('ETag')||'';saved=signature();refresh();message('已保存到 Data/Maps/hex_battles.json，已有版本自动备份。');parent.postMessage({type:'battle-catalog',maps:project.maps.map(m=>({id:m.id,name:m.name})),encounters:project.maps.map(m=>({id:m.id,name:m.name,encounter:m.encounter,objects:m.objects.filter(o=>o.type==='enemy')}))},location.origin);}else{download('战斗场景.hex-battles.json',project);message('静态模式：已导出工作集；使用启动脚本可直接保存到工程。');}}catch(e){message('保存失败：'+e.message);}}
function compile(){endGesture();sync();try{M.validate(project);const errors=M.issues(map()).filter(i=>i.level==='error');if(errors.length){tab='issues';properties();document.body.classList.add('show-properties');message('请先修正 '+errors.length+' 项布局错误，再导出当前战场。');return;}download(map().id+'.battlelevel.json',{format:'frontier-battle-level',version:1,map:M.compileMap(map()),assets:project.assets,art_bindings:Object.fromEntries(M.compileMap(map()).objects.filter(o=>o.visual.asset).map(o=>[o.id,o.visual.asset])),catalogs:project.catalogs});message('已导出当前战场的接入配置；蜂窝效果被展开为多边形。');}catch(e){message(e.message);}}
function newMap(copy=false){endGesture();const m=copy?M.clone(map()):L.createMap('battle',M.unique(project,'battle_hex'),'新蜂窝战场');m.id=M.unique(project,'battle_hex');m.name=copy?map().name+' 副本':'新蜂窝战场';m.hex_grid??={cell_width:2.2,origin:[0,0]};m.hex_cells??=[];m.background_color??='#344732';
  if(copy){const ids=new Map(m.objects.map((o,i)=>[o.id,`${m.id}_object_${i+1}`]));for(const o of m.objects){o.id=ids.get(o.id);if(o.linked_collision_id&&ids.has(o.linked_collision_id))o.linked_collision_id=ids.get(o.linked_collision_id);}project.art_bindings??={};project.art_bindings[m.id]=Object.fromEntries(Object.entries(project.art_bindings[active]||{}).map(([id,asset])=>[ids.get(id)||id,asset]));}
  project.maps.push(m);histories.set(m.id,new M.History(m));rebuildPicker();activate(m.id);tab='map';properties();document.body.classList.add('show-properties');message('已'+(copy?'复制':'新建')+'战场；各战场保留独立撤销记录。');}
function install(doc){M.validate(doc);$('battle-art-library').disabled=false;pendingFields.clear();project=M.clone(doc);histories.clear();views.clear();for(const m of project.maps)histories.set(m.id,new M.History(m));active=project.maps[0].id;views.set(active,{camera:[0,0],zoom:1});let refs=$('asset-refs');if(!refs){refs=document.createElement('datalist');refs.id='asset-refs';document.body.append(refs);}refs.replaceChildren();for(const a of project.assets)option(refs,a.id,a.name||a.id);rebuildPicker();activate(active);fit();}
function importDoc(doc){if(doc.format==='frontier-map-editor'){const maps=doc.maps.filter(m=>m.kind==='battle').map(m=>({...m,hex_grid:m.hex_grid||{cell_width:2.2,origin:[0,0]},hex_cells:m.hex_cells||[]}));if(!maps.length)throw Error('工作集中没有战场');doc={...project,maps,assets:doc.assets||project.assets,catalogs:doc.catalogs||project.catalogs};}install(doc);refresh();message('已导入战场工作集；请检查后保存。');}
initTools();
$('battle-select').onchange=()=>{activate($('battle-select').value);$('source').textContent='手动选择战场：'+map().name;parent.postMessage({type:'switch-editor',mode:'battle'},location.origin);};$('fit').onclick=fit;$('zoom-in').onclick=()=>{view().zoom=Math.min(150,view().zoom*1.25);refresh();};$('zoom-out').onclick=()=>{view().zoom=Math.max(1,view().zoom/1.25);refresh();};$('undo').onclick=()=>undo();$('redo').onclick=()=>undo(true);$('save').onclick=save;$('export').onclick=()=>{endGesture();sync();download('战斗场景.hex-battles.json',project);};$('compile').onclick=compile;$('import').onclick=()=>$('file').click();$('file').onchange=async()=>{try{const file=$('file').files[0];if(file){if(file.size>30000000)throw Error('文件超过 30 MB');importDoc(JSON.parse(await file.text()));}}catch(e){message('导入失败：'+e.message);}$('file').value='';};
for(const [id,name] of [['object-tab','object'],['map-tab','map'],['issues-tab','issues']])$(id).onclick=()=>{tab=name;properties();};$('check').onclick=()=>{tab='issues';properties();document.body.classList.add('show-properties');};$('delete').onclick=remove;$('duplicate').onclick=duplicate;$('new-map').onclick=()=>newMap();$('copy-map').onclick=()=>newMap(true);
$('apply-json').onclick=()=>{try{const old=selected(),o=JSON.parse($('advanced-json').value);if(!old)throw Error('请先选择对象');if(o.id!==old.id)throw Error('对象 ID 需保持不变');updateMap(m=>m.objects[m.objects.findIndex(v=>v.id===old.id)]=o);properties();list();message('已应用高级配置。');}catch(e){message('JSON 未应用：'+e.message);}};
$('preview').onclick=()=>{endGesture();preview=!preview;$('preview').textContent=preview?'布局编辑':'灰盒预览';$('preview').classList.toggle('active',preview);$('canvas-tip').textContent=preview?'灰盒预览 · 回到布局编辑继续修改':'己方 / 敌方 / 效果 / 围边 · 独立涂层';requestDraw();};$('toggle-properties').onclick=()=>document.body.classList.toggle('show-properties');$('toggle-tools').onclick=()=>document.body.classList.toggle('show-tools');$('return-world').onclick=()=>parent.postMessage({type:'switch-editor',mode:'world'},location.origin);
window.addEventListener('message',e=>{if(e.origin!==location.origin||e.source!==parent)return;if(e.data?.type==='open-battle'&&project){activate(e.data.battle_id);$('source').textContent=e.data.site_name?'来自大地图：'+e.data.site_name:'从大地图进入战场';message('已进入关联战场；返回大地图保留原视角和修改。');parent.postMessage({type:'battle-opened'},location.origin);}});
window.addEventListener('keydown',e=>{if(e.isComposing)return;if(e.altKey&&['1','2'].includes(e.key)){e.preventDefault();parent.postMessage({type:'switch-editor',mode:e.key==='1'?'world':'battle'},location.origin);return;}const mod=(e.ctrlKey||e.metaKey)&&!e.altKey,key=e.key.toLowerCase(),input=['INPUT','SELECT','TEXTAREA'].includes(document.activeElement.tagName);if(mod&&key==='s'){e.preventDefault();save();return;}if(input)return;if(mod&&key==='z'){e.preventDefault();undo(e.shiftKey);return;}if(mod&&key==='d'){e.preventDefault();duplicate();return;}if(e.code==='Space'){space=true;e.preventDefault();}if(e.key==='Delete'){e.preventDefault();remove();}if(e.key==='Escape'){endGesture();setTool('select');document.body.classList.remove('show-properties','show-tools');}});
window.addEventListener('keyup',e=>{if(e.code==='Space')space=false;});window.addEventListener('blur',()=>{space=false;endGesture();});window.addEventListener('beforeunload',e=>{if(dirty()){e.preventDefault();e.returnValue='';}});
(async()=>{try{let response=await fetch('/api/battles');if(response.ok&&response.headers.get('Content-Type')?.includes('application/json')){server=true;etag=response.headers.get('ETag')||'';}else response=await fetch('battles.json');const doc=await response.json();install(doc);saved=signature();new ResizeObserver(resize).observe(canvas);resize();fit();refresh();message(server?'已连接战场工作集，切换编辑器保留未保存修改。':'静态模式：导出工作集保存修改。');parent.postMessage({type:'battle-ready'},location.origin);}catch(e){$('save-state').textContent='加载失败';message(e.message);}})();

const importedArtCache=new Map();
function browserArtPath(a){const p=a?.browser_path||a?.path;return typeof p==='string'&&p.startsWith('assets/')&&!p.split('/').includes('..')?p:null;}
function drawImportedArt(o){const a=project.assets.find(a=>a.id===o.visual?.asset),src=browserArtPath(a);if(!src||o.visual.visible===false||!visible[M.category(o)])return;let im=importedArtCache.get(src);if(!im){im=new Image();im.onload=requestDraw;im.src=src;importedArtCache.set(src,im);}if(!im.complete||!im.naturalWidth)return;const p=screen(o.position),width=o.visual.size[0]*o.scale[0]*view().zoom,height=o.visual.size[1]*o.scale[1]*view().zoom;ctx.save();ctx.translate(...p);ctx.rotate(o.rotation*Math.PI/180);ctx.globalAlpha=o.visual.opacity;ctx.drawImage(im,-width/2,-height/2,width,height);ctx.restore();}

let battleArtLimit=60;
function showBattleArt(){const h=$('battle-art-list'),q=$('battle-art-search').value.toLowerCase();h.replaceChildren();for(const a of project.assets.filter(a=>browserArtPath(a)&&(!q||(a.name+' '+a.id).toLowerCase().includes(q))).slice(0,battleArtLimit)){const b=document.createElement('button');b.className='asset-card';const im=document.createElement('img');im.src=a.path;im.loading='lazy';im.alt=a.name;const name=document.createElement('b');name.textContent=a.name;const id=document.createElement('small');id.textContent=a.id;b.append(im,name,id);b.onclick=()=>{const o=selected();if(!o){message('请先选择一个战场对象再套用素材');return;}updateMap(()=>{o.visual.asset=a.id;o.visual.size[1]=o.visual.size[0]*a.height/a.width;});properties();$('battle-art-dialog').close();message('已替换战场视觉素材；布局与碰撞未改变');};h.append(b);}if(project.assets.filter(a=>browserArtPath(a)&&(!q||(a.name+' '+a.id).toLowerCase().includes(q))).length>battleArtLimit){const more=document.createElement('button');more.textContent='继续显示';more.onclick=()=>{battleArtLimit+=60;showBattleArt();};h.append(more);}}
$('battle-art-library').onclick=()=>{battleArtLimit=60;showBattleArt();$('battle-art-dialog').showModal();};$('close-battle-art').onclick=()=>$('battle-art-dialog').close();$('battle-art-search').oninput=()=>{battleArtLimit=60;showBattleArt();};

$('align-deployment').onclick=()=>{endGesture();try{updateMap(()=>HexBattleDeployment.align(map(),M));properties();message('双方部署已左右水平对齐，避开障碍与陷阱；Ctrl+Z 撤销，Ctrl+S 保存。');}catch(e){message(e.message);}};
