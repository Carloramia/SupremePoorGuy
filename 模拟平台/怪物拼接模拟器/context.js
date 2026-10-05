'use strict';
// Points carry positions only. Asset type belongs to the attached part, not a point.
function neutralPoints(s){for(const b of s.parts.filter(p=>p.type==='body')){Object.keys(b.ports).forEach((k,i)=>{b.portTypes[k]='any';const n=b.portNames[k];if(!n||Object.values(PORTS).includes(n)||['后续躯干','蛇头','下一躯干'].includes(n)||n.startsWith('四足·')||/^(头|手|脚|翅膀|自由)连接点 \d+$/.test(n))b.portNames[k]='连接点 '+(i+1)})}return s}
const typedFresh=freshPart;
freshPart=function(a,patch={}){const p=typedFresh(a,patch);if(p.type==='body')neutralPoints({parts:[p]});return p};
newPort=function(b,_type='any',xy=[.5,.5]){if(Object.keys(b.ports).length>=40)throw new Error('单躯干最多 40 个连接点');const k='point_'+uid();b.ports[k]=xy;b.portNames[k]='连接点 '+(Object.keys(b.ports).length);b.portTypes[k]='any';return k};
compatible=function(b,_type){return Object.keys(b.ports)};
const typedTemplate=template;
template=function(kind){typedTemplate(kind);neutralPoints(state)};
const typedValidate=validateProject;
validateProject=function(data){return neutralPoints(typedValidate(data))};
const typedRefresh=refresh;
refresh=function(){neutralPoints(state);typedRefresh();$('portType').value='any';$('portType').disabled=true};
const typedPortEditor=portEditor;
portEditor=function(){typedPortEditor();$('portType').value='any';$('portType').disabled=true};
neutralPoints(state);refresh();persist();
$('status').textContent='拖动空白处 / 按住鼠标中键平移画布；滚轮缩放；右键布点与挂接；左键拖部件或点微调。';
let contextTarget=null;
const menu=$('pointMenu');
function closePointMenu(){menu.hidden=true;contextTarget=null}
function torsoUV(b,pt){const tr=transform(b),dx=pt.x-tr.x,dy=pt.y-tr.y;return [clamp(((dx*Math.cos(tr.angle)+dy*Math.sin(tr.angle))*(tr.mirror?-1:1))/tr.w+.5,0,1),clamp((-dx*Math.sin(tr.angle)+dy*Math.cos(tr.angle))/tr.h+.5,0,1)]}
function pointHit(pt){for(const b of sorted().reverse().filter(p=>p.type==='body')){for(const [key,uv]of Object.entries(b.ports)){const q=point(transform(b),...uv);if(Math.hypot(pt.x-q.x,pt.y-q.y)<=12/view.scale)return {bodyId:b.id,key}}}return null}
function attachAtPoint(bodyId,key,assetId){const b=state.parts.find(p=>p.id===bodyId&&p.type==='body'),a=asset(assetId);if(!b?.ports[key]||!a)throw new Error('连接点或素材已不存在');if(state.parts.length>=60)throw new Error('组合最多 60 件');const p=freshPart(a);p.parentId=b.id;p.mount=key;p.mirror=p.type!=='body'&&b.ports[key][0]>.5;if(p.type==='body'){p.anchor=[.24,.5];p.width=b.width;p.heightScale=b.heightScale}state.parts.push(p);selected=p.id;return p}
function deleteAtPoint(bodyId,key){const b=state.parts.find(p=>p.id===bodyId);if(!b?.ports?.[key])throw new Error('连接点已不存在');for(const p of state.parts.filter(p=>p.parentId===bodyId&&p.mount===key))detach(p);delete b.ports[key];delete b.portNames[key];delete b.portTypes[key];selected=b.id}
function openPointMenu(target,x,y){contextTarget=target;selected=target.bodyId;$('showAnchors').checked=true;refresh();if(target.key){$('portSelect').value=target.key;portEditor();draw()}
 $('pointMenuTitle').textContent=target.key?'连接点 · 选择要挂接的素材':'躯干 · 在右键位置增点';$('contextAdd').hidden=!!target.key;$('pointAttachControls').hidden=!target.key;
 options($('pointAsset'),[['','请选择素材（不预设部位）'],...state.assets.map(a=>[a.id,TYPES[a.type]+' · '+a.name])],'');$('contextAttach').disabled=true;
 const attached=state.parts.filter(p=>p.parentId===target.bodyId&&p.mount===target.key);$('pointAttached').textContent=target.key?(attached.length?'已挂接：'+attached.map(p=>p.name).join('、'):'此点尚未挂接部件；可选择任意类型素材。'):'';
 $('contextDetach').disabled=!attached.length;menu.hidden=false;menu.style.left=Math.max(8,Math.min(x,window.innerWidth-310))+'px';menu.style.top=Math.max(8,Math.min(y,window.innerHeight-350))+'px';}
canvas.addEventListener('contextmenu',e=>{e.preventDefault();e.stopImmediatePropagation();const pt=pointer(e),target=$('showAnchors').checked?pointHit(pt):null;if(target){openPointMenu(target,e.clientX,e.clientY);return}const b=sorted().reverse().find(p=>p.type==='body'&&hit(p,pt));if(!b){closePointMenu();say('请在躯干或连接点上右键。');return}openPointMenu({bodyId:b.id,uv:torsoUV(b,pt)},e.clientX,e.clientY)});
$('contextAdd').onclick=()=>{const t=contextTarget;if(!t)return;let key;const ok=change('右键位置新增连接点',()=>{const b=state.parts.find(p=>p.id===t.bodyId);if(!b)throw new Error('躯干已不存在');key=newPort(b,'any',t.uv);selected=b.id});if(ok)openPointMenu({bodyId:t.bodyId,key},parseFloat(menu.style.left),parseFloat(menu.style.top))};
$('contextAttach').onclick=()=>{const t=contextTarget;if(!t?.key)return;const id=$('pointAsset').value;if(change('右键连接点挂接素材',()=>attachAtPoint(t.bodyId,t.key,id))){closePointMenu();say('已挂接到所选连接点；可拖动部件微调。')}};
$('contextDelete').onclick=()=>{const t=contextTarget;if(!t?.key)return;if(change('右键删除连接点（保留部件）',()=>deleteAtPoint(t.bodyId,t.key))){closePointMenu();say('已删除连接点，所挂部件原地解除连接；可撤销。')}};
$('contextDetach').onclick=()=>{const t=contextTarget;if(!t?.key)return;if(change('解除此点所挂部件',()=>{for(const p of state.parts.filter(p=>p.parentId===t.bodyId&&p.mount===t.key))detach(p)}))openPointMenu(t,parseFloat(menu.style.left),parseFloat(menu.style.top))};
$('contextClose').onclick=closePointMenu;
$('pointAsset').onchange=()=>{$('contextAttach').disabled=!asset($('pointAsset').value)};
document.addEventListener('pointerdown',e=>{if(!menu.hidden&&!menu.contains(e.target))closePointMenu()});
document.addEventListener('keydown',e=>{if(e.key==='Escape')closePointMenu()});
