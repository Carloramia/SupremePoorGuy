'use strict';
// Browser-side port of CreatureGenerator's layout rules. Coordinates stay in Godot
// units (X forward, Y up, Z left/right) until the editable side view is assembled.
const BEAST_DEFAULTS={seed:'',overallScale:4,partWidth:.2,rearLegCount:4,forelegCount:2,unsymmetrie:50,inhomogeneity:50,
 torsoCount:6,bodyLength:4,torsoOverlapPercent:20,torsoMinimumHeight:.5,torsoMaximumHeight:.7,torsoConnectionDistance:.3,fixedTorsoSizes:false,fixedTorsoSmallHeight:.3,fixedTorsoMediumHeight:.6,fixedTorsoLargeHeight:1.2,
 upperCurve:'0:0.37377048, 0.44817924:1, 1:0.55081964',lowerCurve:'0:-0.32458997, 0.4803922:-2.0163934, 0.9397759:-0.60000014, 1:-0.46229506',offsetCurve:'0:0, 1:0',supportCurve:'0:0, 1:0',
 supportX:.5,supportY:.4,footBaseX:.6,footBaseY:.3,footMinX:.4,footMaxX:.8,footMinY:.6,footMaxY:.6,minimumFeetDistance:.2,
 baseLimbLength:1.5,segmentMin:.4,segmentMax:.8,bendMin:.1,bendMax:.4,limbMinX:.4,limbMaxX:.4,limbMinY:.4,limbMaxY:.8,limbMatches:true,fixedLegSizes:false,rearLegSegments:3,forelegSegments:2,
 fixedLegShortLength:1.125,fixedLegMediumLength:1.5,fixedLegLongLength:1.875,fixedLegShortWidth:.3,fixedLegMediumWidth:.4,fixedLegLongWidth:.5,
 neckNumber:1,neckSegmentCount:3,neckMin:.8,neckMax:2,neckAngle:60,neckThickness:.4,neckOverlap:.5,headMinX:.3,headMaxX:.7,headMinY:.3,headMaxY:.7,
 sideSpread:.12,showNetwork:false,endpointMergeDistance:.2,extraEndpointCount:4,extraEndpointPadding:.5,networkCenterBias:.65,coreExtraConnections:3};
const BEAST_FIELDS=[
 ['整体与随机性',[['seed','随机种子（留空每次随机）','text'],['overallScale','整体缩放',.1,10,.1],['partWidth','统一 Z 宽度',.01,10,.01],['unsymmetrie','不对称 %',0,100,1],['inhomogeneity','尺寸差异 %',0,100,1],['sideSpread','侧视左右展开',0,.5,.01]]],
 ['主躯干',[['fixedTorsoSizes','固定三档正方形躯干（按轮廓适配）','checkbox'],['fixedTorsoSmallHeight','固定小档边长',.01,10,.01],['fixedTorsoMediumHeight','固定中档边长',.01,10,.01],['fixedTorsoLargeHeight','固定大档边长',.01,10,.01],['torsoCount','主躯干数量',1,32,1],['bodyLength','身体总长度（普通模式）',.1,20,.1],['torsoOverlapPercent','相邻重叠 %',0,95,1],['torsoMinimumHeight','参考高度下限',.01,10,.01],['torsoMaximumHeight','参考高度上限',.01,10,.01],['torsoConnectionDistance','连接容差',0,10,.01],['upperCurve','上轮廓','curve'],['lowerCurve','下轮廓','curve'],['offsetCurve','高度偏移','curve']]],
 ['辅助躯干与脚',[['rearLegCount','后腿数量',0,10,1],['forelegCount','前腿数量',0,10,1],['supportX','辅助躯干 X 尺寸',.01,10,.01],['supportY','辅助躯干 Y 尺寸',.01,10,.01],['supportCurve','支撑挂接高度（0–1）','curve'],['footBaseX','脚基准 X 尺寸',.01,10,.01],['footBaseY','脚基准 Y 尺寸',.01,10,.01],['footMinX','脚 X 下限',.01,10,.01],['footMaxX','脚 X 上限',.01,10,.01],['footMinY','脚 Y 下限',.01,10,.01],['footMaxY','脚 Y 上限',.01,10,.01],['minimumFeetDistance','脚表面最小间距',0,10,.01]]],
 ['分段肢体',[['fixedLegSizes','固定三档腿部（按主躯干适配）','checkbox'],['fixedLegShortLength','固定短档总腿长',.01,10,.01],['fixedLegMediumLength','固定中档总腿长',.01,10,.01],['fixedLegLongLength','固定长档总腿长',.01,10,.01],['fixedLegShortWidth','固定短档肢段粗细',.01,10,.01],['fixedLegMediumWidth','固定中档肢段粗细',.01,10,.01],['fixedLegLongWidth','固定长档肢段粗细',.01,10,.01],['rearLegSegments','每条后腿节数',1,10,1],['forelegSegments','每条前腿节数',1,10,1],['baseLimbLength','标称腿长（普通模式）',.01,10,.01],['segmentMin','折线段高度下限',.01,10,.01],['segmentMax','折线段高度上限',.01,10,.01],['bendMin','折弯偏移下限',.01,10,.01],['bendMax','折弯偏移上限',.01,10,.01],['limbMinX','肢段 X 下限',.01,10,.01],['limbMaxX','肢段 X 上限',.01,10,.01],['limbMinY','肢段 Y 下限',.01,10,.01],['limbMaxY','肢段 Y 上限',.01,10,.01],['limbMatches','肢段长度匹配连接线','checkbox']]],
 ['颈部与头部',[['neckNumber','头颈组数量',0,256,1],['neckSegmentCount','每条颈部段数',0,10,1],['neckMin','颈长下限',.01,10,.01],['neckMax','颈长上限',.01,10,.01],['neckAngle','中间段角度 °',0,85,1],['neckThickness','颈部厚度',.01,10,.01],['neckOverlap','允许重叠直径（XY）',0,10,.01],['headMinX','头 X 下限',.01,10,.01],['headMaxX','头 X 上限',.01,10,.01],['headMinY','头 Y 下限',.01,10,.01],['headMaxY','头 Y 上限',.01,10,.01]]],
 ['肢端网络预览',[['showNetwork','显示生成时的网络参考线','checkbox'],['endpointMergeDistance','交汇点合并距离',0,10,.01],['extraEndpointCount','额外端点数量',0,32,1],['extraEndpointPadding','端点区域扩展',0,10,.01],['networkCenterBias','中央偏好',0,1,.01],['coreExtraConnections','额外核心连接',0,32,1]]]
];
function beastParametersPanel(){const panel=document.createElement('details');panel.className='beast-settings';panel.id='beastPanel';panel.innerHTML='<summary>兽形生成参数</summary><p class="hint">X 向前、Y 向上；单位与生物生成器一致。默认生成 6 段主躯干、4 后腿、2 前腿、1 头。左右肢体按层级区分。</p><div id="beastSettings"></div><p class="hint">曲线格式：0:数值, 0.5:数值, 1:数值；横向进度从尾部 0 到前部 1，点间平滑过渡。侧视左右展开只影响显示位置。</p><div class="actions"><button id="generateBeast">生成兽形</button><button id="randomBeast">换种子生成</button><button id="resetBeastSettings">恢复生成参数</button></div><p id="beastResult" class="hint" role="status"></p>';$('bodyCount').parentElement.before(panel);const root=$('beastSettings');for(const [title,fields]of BEAST_FIELDS){const section=document.createElement('details'),heading=document.createElement('summary');heading.textContent=title;section.append(heading);for(const [key,label,type,max,step]of fields){const row=document.createElement('label'),input=document.createElement(type==='curve'?'textarea':'input');row.textContent=label;input.id='beast_'+key;if(type==='curve'){input.rows=2;input.title='逗号分隔的 横向进度:数值；进度范围 0–1；点间使用平滑曲线'}else{input.type=typeof type==='string'?type:'number';if(typeof type==='number'){input.min=type;input.max=max;input.step=step}}row.append(input);section.append(row)}root.append(section)}setBeastControls(state.beastGeneration?.settings||BEAST_DEFAULTS);$('generateBeast').onclick=generateBrowserBeast;$('randomBeast').onclick=()=>{$('beast_seed').value='';generateBrowserBeast()};$('resetBeastSettings').onclick=()=>setBeastControls(BEAST_DEFAULTS)}
function setBeastControls(settings){for(const [key,value]of Object.entries({...BEAST_DEFAULTS,...settings})){const el=$('beast_'+key);if(!el)continue;if(typeof value==='boolean')el.checked=value;else el.value=value}syncFixedLegControls();syncFixedTorsoControls()}
function syncFixedTorsoControls(){const fixed=$('beast_fixedTorsoSizes').checked,length=$('beast_bodyLength');length.disabled=fixed;if(length.parentElement)length.parentElement.hidden=fixed;length.title=fixed?'正方形模式的身体总长由三档边长、数量和重叠比例计算':''}
function syncFixedLegControls(){const fixed=$('beast_fixedLegSizes').checked;for(const key of ['baseLimbLength','limbMinX','limbMaxX','limbMinY','limbMaxY','limbMatches']){const input=$('beast_'+key);input.disabled=fixed;if(input.parentElement)input.parentElement.hidden=fixed;input.title=fixed?'固定模式使用三档预设，尺寸不随机、不拉伸':''}}
function readBeastControls(){const s={};for(const [key,value]of Object.entries(BEAST_DEFAULTS)){const el=$('beast_'+key);s[key]=typeof value==='boolean'?el.checked:typeof value==='number'?Number(el.value):el.value.trim()}return s}
function beastCurve(text){const points=String(text).split(/[,，]/).map(pair=>pair.trim().split(/[:：]/).map(v=>v.trim()===''?NaN:Number(v)));if(points.length<2||points.some(p=>p.length!==2||!p.every(Number.isFinite)||p[0]<0||p[0]>1)||points.some((p,i)=>i&&p[0]<=points[i-1][0])||points[0][0]!==0||points.at(-1)[0]!==1)throw new Error('曲线需从 0 到 1，格式如 0:0, 0.5:1, 1:0；进度严格递增');return Object.assign(t=>{const i=points.findIndex(p=>p[0]>=t);if(i<=0)return points[0][1];const a=points[i-1],b=points[i],u=clamp((t-a[0])/(b[0]-a[0]),0,1);return a[1]+(b[1]-a[1])*(u*u*(3-2*u))},{points})}
// Exact extrema of two summed piecewise smoothstep curves, including interior
// derivative roots. Checking only a torso's centre can miss narrow contour dips.
function beastContourRange(curve,offset,start,end){
 const knots=[...new Set([start,end,...curve.points.map(p=>p[0]),...offset.points.map(p=>p[0])].filter(t=>t>=start&&t<=end))].sort((a,b)=>a-b),samples=knots.map(t=>curve(t)+offset(t));
 for(let i=1;i<knots.length;i++){
  const a=knots[i-1],width=knots[i]-a,derivative=[0,0,0];
  for(const fn of [curve,offset]){const j=fn.points.findIndex(p=>p[0]>a+width/2),p=fn.points[j-1],q=fn.points[j],span=q[0]-p[0],v=(a-p[0])/span,w=width/span,k=6*(q[1]-p[1])*w;derivative[0]+=k*v*(1-v);derivative[1]+=k*w*(1-2*v);derivative[2]-=k*w*w}
  const [c,b,d]=derivative,roots=[];
  if(Math.abs(d)<1e-12){if(Math.abs(b)>1e-12)roots.push(-c/b)}else{const disc=b*b-4*d*c;if(disc>=0)roots.push((-b-Math.sqrt(disc))/(2*d),(-b+Math.sqrt(disc))/(2*d))}
  for(const u of roots)if(u>0&&u<1){const t=a+width*u;samples.push(curve(t)+offset(t))}
 }
 return{min:Math.min(...samples),max:Math.max(...samples)};
}
// Solve width/contour interdependence without RNG. Start large, downgrade
// violations, then try deterministic single-part upgrades that preserve every
// contour constraint. Each phase changes a tier at most twice per torso.
function beastSquareLayout(s,upper,lower,offset){
 const height=(s.torsoMinimumHeight+s.torsoMaximumHeight)/2,overlap=s.torsoOverlapPercent/100,tiers=[['大',s.fixedTorsoLargeHeight],['中',s.fixedTorsoMediumHeight],['小',s.fixedTorsoSmallHeight]],indices=Array(s.torsoCount).fill(0);
 const evaluate=()=>{
  let right=0;const spans=indices.map((tier,i)=>{const size=tiers[tier][1],left=right-(i?overlap*Math.min(size,tiers[indices[i-1]][1]):0);right=left+size;return{left,right,size,tier}}),bodyLength=right;
  const torsos=spans.map(({left,right,size,tier})=>{const start=left/bodyLength,end=right/bodyLength,ceiling=beastContourRange(upper,offset,start,end).min*height,floor=beastContourRange(lower,offset,start,end).max*height;return{...beastBox(beastV((left+right-bodyLength)/2,(ceiling+floor)/2,0),beastV(size,size,s.partWidth),'Torso'),progress:(start+end)/2,sizeTier:tiers[tier][0],fits:size<=ceiling-floor+1e-9}});
  return{bodyLength,torsos};
 };
 let result=evaluate();
 while(result.torsos.some(t=>!t.fits)){
  const i=result.torsos.findIndex((t,i)=>!t.fits&&indices[i]<2);
  if(i<0)throw new Error('固定小档正方形仍无法适配完整上下轮廓；请调整轮廓、参考高度、躯干数量或三档边长');
  indices[i]++;result=evaluate();
 }
 let changed=true;
 while(changed){changed=false;for(let i=0;i<indices.length;i++)if(indices[i]>0){const before=indices[i];indices[i]--;const candidate=evaluate();if(candidate.torsos.every(t=>t.fits)){result=candidate;changed=true}else indices[i]=before}}
 for(const t of result.torsos)delete t.fits;
 return result;
}
function beastRandom(seed){let n=2166136261;for(const c of String(seed))n=Math.imul(n^c.charCodeAt(0),16777619);return()=>{n+=0x6D2B79F5;let t=Math.imul(n^n>>>15,1|n);t^=t+Math.imul(t^t>>>7,61|t);return((t^t>>>14)>>>0)/4294967296}}
const beastV=(x=0,y=0,z=0)=>({x,y,z});
const beastAdd=(a,b)=>beastV(a.x+b.x,a.y+b.y,a.z+b.z);
const beastSub=(a,b)=>beastV(a.x-b.x,a.y-b.y,a.z-b.z);
const beastMul=(a,s)=>beastV(a.x*s,a.y*s,a.z*s);
const beastLerp=(a,b,t)=>beastAdd(a,beastMul(beastSub(b,a),t));
const beastLength=a=>Math.hypot(a.x,a.y,a.z);
function beastBox(position,size,role,angle=0){return{position,size,role,angle}}
// Convex XY intersection of oriented cuboids, restricted to their shared Z slab.
function beastCorners(b){const c=Math.cos(b.angle),s=Math.sin(b.angle);return[[-1,-1],[1,-1],[1,1],[-1,1]].map(([x,y])=>({x:b.position.x+x*b.size.x*.5*c-y*b.size.y*.5*s,y:b.position.y+x*b.size.x*.5*s+y*b.size.y*.5*c}))}
function beastOverlap(a,b){if(Math.min(a.position.z+a.size.z/2,b.position.z+b.size.z/2)<=Math.max(a.position.z-a.size.z/2,b.position.z-b.size.z/2)+1e-8)return 0;let poly=beastCorners(a);const clip=beastCorners(b),cross=(u,v,p)=>(v.x-u.x)*(p.y-u.y)-(v.y-u.y)*(p.x-u.x);for(let i=0;i<4&&poly.length;i++){const u=clip[i],v=clip[(i+1)%4],out=[];for(let j=0;j<poly.length;j++){const p=poly[j],q=poly[(j+1)%poly.length],dp=cross(u,v,p),dq=cross(u,v,q);if(dp>=-1e-9)out.push(p);if((dp>=0)!==(dq>=0)){const t=dp/(dp-dq);out.push({x:p.x+(q.x-p.x)*t,y:p.y+(q.y-p.y)*t})}}poly=out}let area=0,diameter=0;for(let i=0;i<poly.length;i++){const p=poly[i],q=poly[(i+1)%poly.length];area+=p.x*q.y-p.y*q.x;for(const r of poly)diameter=Math.max(diameter,Math.hypot(p.x-r.x,p.y-r.y))}return Math.abs(area)<1e-9?0:diameter}
function beastConnected(a,b,tolerance){return Math.hypot(...['x','y','z'].map(k=>Math.max(Math.abs(a.position[k]-b.position[k])-(a.size[k]+b.size[k])/2,0)))<=tolerance+1e-8}
// Fixed modes use deterministic presets, never random dimension samples.
function beastFeetClear(feet,distance){return !feet.some((a,i)=>feet.slice(0,i).some(b=>{const dx=Math.max(Math.abs(a.position.x-b.position.x)-(a.size.x+b.size.x)/2,0),dz=Math.max(Math.abs(a.position.z-b.position.z)-(a.size.z+b.size.z)/2,0);return(dx===0&&dz===0)||Math.hypot(dx,dz)<distance-1e-5}))}
function beastLimbPoints(role,count,footHeight,totalLength,s,sample,random,fixed){
 const sampleShape=fixed?(a,b)=>(a+b)/2:sample,shapeRandom=fixed?()=>.5:random;
 const start=beastV(0,footHeight/2,0),points=[start],rear=sampleShape(s.bendMin,s.bendMax);
 let front=rear;
 for(let i=0;i<count;i++){
  let dx;
  if(i===0)dx=-rear;
  else if(role==='ForeLeg')dx=(i%2?1:-1)*rear*(.25+.5*shapeRandom());
  else if(i%2){front=sampleShape(s.bendMin,s.bendMax);dx=front}
  else dx=-front*(.25+.5*shapeRandom());
  points.push(beastAdd(points.at(-1),beastV(dx,sampleShape(s.segmentMin,s.segmentMax),0)));
 }
 const raw=points.slice(1).reduce((sum,p,j)=>sum+beastLength(beastSub(p,points[j])),0);
 return points.map(p=>beastAdd(start,beastMul(beastSub(p,start),totalLength/raw)));
}
function beastFitLegTiers(feet,supports,torsos,s){
 const tiers=[['短',s.fixedLegShortLength,s.fixedLegShortWidth,.75],['中',s.fixedLegMediumLength,s.fixedLegMediumWidth,1],['长',s.fixedLegLongLength,s.fixedLegLongWidth,1.25]],groups=[];
 for(let i=0;i<feet.length;i++)if(feet[i].partner<0){const members=[i,...feet.map((f,j)=>f.partner===i?j:-1).filter(j=>j>=0)],candidates=[];
  for(const [name,length,width,factor]of tiers){let score=0;const choices=[];
   for(const j of members){const f=feet[j],b=supports[j],parent=torsos[b.parent];if(width>Math.min(parent.size.x,b.size.x)+1e-9)break;
    const size=beastV(s.footBaseX*factor,s.footBaseY*factor,s.partWidth),count=f.role==='Leg'?s.rearLegSegments:s.forelegSegments,points=beastLimbPoints(f.role,count,size.y,length,s,null,null,true),position=beastSub(beastV(b.position.x,b.position.y-b.size.y/2,b.position.z),points.at(-1)),target=s.fixedLegMediumLength*Math.sqrt(parent.size.x*parent.size.y)/s.fixedTorsoMediumHeight;
    // Proportion to the parent dominates; available ground clearance breaks
    // near ties. Feet may be raised, never stretched to force them onto ground.
    score+=Math.abs(length-target)/s.fixedLegMediumLength+.25*Math.abs(position.y-size.y/2)/s.fixedLegMediumLength;
    choices.push({index:j,size,points,position,sizeTier:name,sizeFactor:factor,legLengthPreset:length,limbWidth:width});
   }
   if(choices.length===members.length)candidates.push({score,choices});
  }
  candidates.sort((a,b)=>a.score-b.score||a.choices[0].legLengthPreset-b.choices[0].legLengthPreset);
  if(!candidates.length)throw new Error('第 '+(i+1)+' 条腿的三档粗细均无法适配主躯干／支撑宽度；请调整三档粗细或躯干／支撑尺寸');
  groups.push(candidates);
 }
 // At most ten pairs and three choices per pair. Deterministic backtracking
 // considers neighbouring feet rather than failing on the first preferred tier.
 const selected=[];
 const solve=i=>{if(i===groups.length)return true;for(const candidate of groups[i]){const n=selected.length;selected.push(...candidate.choices);if(beastFeetClear(selected,s.minimumFeetDistance)&&solve(i+1))return true;selected.length=n}return false};
 if(!solve(0))throw new Error('固定腿三档无法同时满足脚部间距；请减少腿数、调整脚尺寸／间距或主躯干布局');
 for(const choice of selected){const {index,...patch}=choice;Object.assign(feet[index],patch)}
}
function createBeastNetwork(feet,s,random){const tips=feet.map(f=>beastAdd(f.position,f.points.at(-1))),extra=[],edges=[];if(!tips.length)return{tips,extra,junctions:[],edges};const low=beastV(),high=beastV();for(const k of ['x','y','z']){low[k]=Math.min(...tips.map(p=>p[k]))-s.extraEndpointPadding;high[k]=Math.max(...tips.map(p=>p[k]))+s.extraEndpointPadding;if(low[k]===high[k]){low[k]-=.01;high[k]+=.01}}const center=beastMul(beastAdd(low,high),.5),asym=s.unsymmetrie/100;
 for(let i=0;i<s.extraEndpointCount;i++){let p=beastV(...['x','y','z'].map(k=>low[k]+random()*(high[k]-low[k])));p=beastLerp(p,center,s.networkCenterBias);if(i%2)p=beastLerp(beastV(extra[i-1].x,extra[i-1].y,-extra[i-1].z),p,asym);else if(i===s.extraEndpointCount-1)p.z*=asym;extra.push(p)}
 const endpoints=[...tips,...extra],parents=endpoints.map((_,i)=>i),root=i=>{while(parents[i]!==i)i=parents[i];return i},clusters=new Map(),add=(a,b)=>{if(beastLength(beastSub(a,b))<1e-9)return;const same=(p,q)=>beastLength(beastSub(p,q))<1e-9;if(!edges.some(e=>same(e[0],a)&&same(e[1],b)||same(e[0],b)&&same(e[1],a)))edges.push([a,b])};for(let i=0;i<endpoints.length;i++)for(let j=0;j<i;j++)if(beastLength(beastSub(endpoints[i],endpoints[j]))<Math.max(s.endpointMergeDistance,1e-9))parents[root(i)]=root(j);for(let i=0;i<endpoints.length;i++){const r=root(i);if(!clusters.has(r))clusters.set(r,[]);clusters.get(r).push(endpoints[i])}const junctions=[...clusters.values()].map(list=>beastMul(list.reduce(beastAdd,beastV()),1/list.length));[...clusters.values()].forEach((list,i)=>list.forEach(p=>add(p,junctions[i])));
 const coreCenter=beastMul(tips.reduce(beastAdd,beastV()),1/tips.length),radius=Math.max(.01,...tips.map(p=>beastLength(beastSub(p,coreCenter)))),weight=p=>clamp(1-beastLength(beastSub(p,coreCenter))/radius,0,1);parents.splice(0,parents.length,...junctions.map((_,i)=>i));for(let n=0;n<junctions.length-1;n++){const candidates=[];let total=0;for(let i=0;i<junctions.length;i++)for(let j=0;j<i;j++)if(root(i)!==root(j)){const central=(weight(junctions[i])+weight(junctions[j]))/2,w=(1-s.networkCenterBias)+s.networkCenterBias*(.1+central*central*10);total+=w;candidates.push({i,j,w})}let r=random()*total,pick=candidates.at(-1);for(const c of candidates){r-=c.w;if(r<=0){pick=c;break}}parents[root(pick.i)]=root(pick.j);add(junctions[pick.i],junctions[pick.j])}const order=extra.slice();for(let i=order.length-1;i>0;i--){const j=Math.floor(random()*(i+1));[order[i],order[j]]=[order[j],order[i]]}for(let i=1;i<order.length;i++)add(order[i-1],order[i]);const core=[];for(let i=0;i<junctions.length;i++)for(let j=0;j<i;j++)if(weight(junctions[i])>=.5&&weight(junctions[j])>=.5)core.push([junctions[i],junctions[j]]);let added=0;while(core.length&&added<s.coreExtraConnections){const pair=core.splice(Math.floor(random()*core.length),1)[0],before=edges.length;add(...pair);if(edges.length>before)added++}for(const edge of edges.slice())if(random()>=asym){const nearest=p=>endpoints.concat(junctions).reduce((best,q)=>beastLength(beastSub(q,beastV(p.x,p.y,-p.z)))<beastLength(beastSub(best,beastV(p.x,p.y,-p.z)))?q:best,p);add(nearest(edge[0]),nearest(edge[1]))}return{tips,extra,junctions,edges};
}
function createBeastPlan(settings){const s={...BEAST_DEFAULTS,...settings};for(const [,fields]of BEAST_FIELDS)for(const [key,,min,max,step]of fields)if(!(s.fixedTorsoSizes&&key==='bodyLength')&&!(s.fixedLegSizes&&['baseLimbLength','limbMinX','limbMaxX','limbMinY','limbMaxY'].includes(key))&&typeof min==='number'&&(!Number.isFinite(s[key])||s[key]<min||s[key]>max||(step===1&&!Number.isInteger(s[key]))))throw new Error('兽形参数越界：'+key);
 if(s.fixedTorsoSizes&&!(s.fixedTorsoSmallHeight<s.fixedTorsoMediumHeight&&s.fixedTorsoMediumHeight<s.fixedTorsoLargeHeight))throw new Error('固定躯干边长必须满足：小档 < 中档 < 大档');
 if(s.fixedLegSizes){for(const suffix of ['Length','Width'])if(!(s['fixedLegShort'+suffix]<s['fixedLegMedium'+suffix]&&s['fixedLegMedium'+suffix]<s['fixedLegLong'+suffix]))throw new Error('固定腿长和粗细必须满足：短档 < 中档 < 长档');for(const key of ['baseLimbLength','limbMinX','limbMaxX','limbMinY','limbMaxY'])if(!Number.isFinite(s[key]))s[key]=BEAST_DEFAULTS[key]}
 const expected=s.torsoCount+s.rearLegCount*(s.rearLegSegments+2)+s.forelegCount*(s.forelegSegments+2)+s.neckNumber*(s.neckSegmentCount+1);if(expected>CONFIG.maxParts)throw new Error('当前参数需要 '+expected+' 件，超过组合上限 60；请减少腿、躯干或腿／颈节数');
 const upper=beastCurve(s.upperCurve),lower=beastCurve(s.lowerCurve),offset=beastCurve(s.offsetCurve),support=beastCurve(s.supportCurve),seed=String(s.seed||uid()),random=beastRandom(seed),sample=(a,b)=>Math.max(.01,Math.min(a,b))+random()*Math.abs(a-b),asym=s.unsymmetrie/100,mix=(a,b,t)=>a+(b-a)*t;
 const square=s.fixedTorsoSizes?beastSquareLayout(s,upper,lower,offset):null,bodyLength=square?square.bodyLength:s.bodyLength;
 if(square&&(!Number.isFinite(s.bodyLength)||s.bodyLength<.1||s.bodyLength>20))s.bodyLength=BEAST_DEFAULTS.bodyLength; // Inactive legacy input, retained only for switching back to ordinary mode.
 const footSize=()=>beastV(mix(s.footBaseX,sample(Math.min(s.footBaseX,s.footMinX,s.footMaxX),Math.max(s.footBaseX,s.footMinX,s.footMaxX)),s.inhomogeneity/100),mix(s.footBaseY,sample(Math.min(s.footBaseY,s.footMinY,s.footMaxY),Math.max(s.footBaseY,s.footMinY,s.footMaxY)),s.inhomogeneity/100),s.partWidth);
 for(let attempt=1;attempt<=128;attempt++){
  const height=s.fixedTorsoSizes||s.fixedLegSizes?(s.torsoMinimumHeight+s.torsoMaximumHeight)/2:sample(s.torsoMinimumHeight,s.torsoMaximumHeight),feet=[];
  for(const [role,count,side]of [['Leg',s.rearLegCount,-1],['ForeLeg',s.forelegCount,1]]){const rows=Math.ceil(count/2);for(let row=0;row<rows;row++){
   const x=side*(rows===1?bodyLength*.25:mix(bodyLength*.08,bodyLength*.42,row/(rows-1))),paired=row*2+1<count;
   const size=s.fixedLegSizes?beastV(s.footBaseX,s.footBaseY,s.partWidth):footSize(),pairIndex=feet.length;
   for(let member=0;member<(paired?2:1);member++){const sz=!s.fixedLegSizes&&member?beastLerp(size,footSize(),asym):clone(size),z=paired?(member?-1:1)*(s.partWidth+s.minimumFeetDistance+.1):0,amount=asym*Math.min(bodyLength*.08,s.baseLimbLength*.25),dx=s.fixedLegSizes?0:(random()*2-1)*amount,dz=s.fixedLegSizes?0:(random()*2-1)*amount;feet.push({role,size:sz,position:beastV(x+dx,sz.y/2,z+dz),side:paired?(member?-1:1):0,partner:member?pairIndex:-1,sizeTier:null,sizeFactor:1})}
  }}
  const bottom=(s.fixedLegSizes?s.footBaseY*1.25:Math.max(0,...feet.map(f=>f.size.y)))+Math.max((s.fixedLegSizes?s.fixedLegMediumLength:s.baseLimbLength)*.65,.1)+s.supportY,values=[];let lowest=Infinity;
  for(let i=0;i<s.torsoCount;i++){const t=s.torsoCount===1?.5:i/(s.torsoCount-1),u=upper(t),l=lower(t),o=offset(t);if((u-l)*height<.01)throw new Error('身体上轮廓必须高于下轮廓（第 '+(i+1)+' 段）');values.push({u:u+o,l:l+o,t});lowest=Math.min(lowest,l+o)}
  const baseline=bottom-Math.min(lowest,0)*height,overlap=s.torsoOverlapPercent/100;
  const len=bodyLength/(s.torsoCount-overlap*(s.torsoCount-1));
  let previousEnd=-bodyLength/2;
  const torsos=square?square.torsos.map(t=>({...t,position:beastAdd(t.position,beastV(0,baseline,0))})):values.map((v,i)=>{const left=previousEnd-(i?overlap*len:0);previousEnd=left+len;return{...beastBox(beastV(left+len/2,baseline+(v.u+v.l)*height/2,0),beastV(len,(v.u-v.l)*height,s.partWidth),'Torso'),progress:v.t,sizeTier:null}});
  if(torsos.some((t,i)=>i&&!beastConnected(t,torsos[i-1],s.torsoConnectionDistance)))throw new Error('相邻躯干断开；请平缓轮廓或增加连接容差');
  const supports=feet.map((f,i)=>{let parent=0;for(let j=1;j<torsos.length;j++)if(Math.abs(f.position.x-torsos[j].position.x)<Math.abs(f.position.x-torsos[parent].position.x))parent=j;const t=torsos[parent],x=clamp(f.position.x,t.position.x-t.size.x/2,t.position.x+t.size.x/2),z=f.side*s.partWidth,low=t.position.y-t.size.y/2+(f.side?s.supportY/2:-s.supportY/2),y=mix(low,t.position.y+t.size.y/2-s.supportY/2,clamp(support(t.progress),0,1));f.position.x=x;f.position.z=z;return{...beastBox(beastV(x,y,z),beastV(s.supportX,s.supportY,s.partWidth),'SubTorso'),parent,foot:i}});
  if(s.fixedLegSizes)beastFitLegTiers(feet,supports,torsos,s);
  if(!s.fixedLegSizes&&!beastFeetClear(feet,s.minimumFeetDistance))continue;
  for(let i=0;i<feet.length;i++){
   const f=feet[i],count=f.role==='Leg'?s.rearLegSegments:s.forelegSegments;
   const nominal=s.fixedLegSizes?f.legLengthPreset:s.baseLimbLength*(1+mix(-.25,.25,random())*s.inhomogeneity/100);
   let points=s.fixedLegSizes?f.points:beastLimbPoints(f.role,count,f.size.y,nominal,s,sample,random,false);
   if(s.fixedLegSizes){
    // Fit placement, not segment lengths: stretching to the support would erase tiers.
    f.position=beastSub(beastV(supports[i].position.x,supports[i].position.y-s.supportY/2,supports[i].position.z),points.at(-1));
   }else if(f.partner>=0&&asym===0)points=clone(feet[f.partner].points);
   else{const target=beastV(clamp(f.position.x+points.at(-1).x,supports[i].position.x-s.supportX/2,supports[i].position.x+s.supportX/2),supports[i].position.y-s.supportY/2,f.position.z),correction=beastSub(beastSub(target,f.position),points.at(-1));points=points.map((p,j)=>beastAdd(p,beastMul(correction,j/(points.length-1))))}
   f.points=points;f.limbLength=points.slice(1).reduce((sum,p,j)=>sum+beastLength(beastSub(p,points[j])),0);
   f.segments=points.slice(1).map((p,j)=>{
    const direction=beastSub(p,points[j]),length=beastLength(direction),size=s.fixedLegSizes?beastV(f.limbWidth,length,s.partWidth):beastV(sample(s.limbMinX,s.limbMaxX),sample(s.limbMinY,s.limbMaxY),s.partWidth);
    if(!s.fixedLegSizes&&f.partner>=0){const partner=feet[f.partner].segments[j].size;size.x=mix(partner.x,size.x,asym);size.y=mix(partner.y,size.y,asym)}
    if(s.limbMatches||s.fixedLegSizes)size.y=length;
    return{...beastBox(beastAdd(f.position,beastMul(beastAdd(p,points[j]),.5)),size,f.role+'Limb',Math.atan2(-direction.x,direction.y)),sizeTier:f.sizeTier};
   });
  }
  if(s.fixedLegSizes){
   if(!beastFeetClear(feet,s.minimumFeetDistance))continue;
   const lift=Math.max(0,...feet.map(f=>f.size.y/2-f.position.y));
   if(lift)for(const box of [...torsos,...supports,...feet,...feet.flatMap(f=>f.segments)])box.position.y+=lift;
  }
  const necks=[],body=[...torsos,...supports];let legal=true;
  for(let n=0;n<s.neckNumber&&legal;){const single=n===0&&s.neckNumber%2===1;let accepted=false;for(let trial=0;trial<128&&!accepted;trial++){const t=torsos.at(-1),origin=()=>beastV(t.position.x+t.size.x/2,t.position.y+mix(-t.size.y*.25,t.size.y*.25,random()),mix(-t.size.z/2,t.size.z/2,random())),first=origin();if(single)first.z*=asym;const length=s.neckSegmentCount?sample(s.neckMin,s.neckMax):0,head=beastV(sample(s.headMinX,s.headMaxX),sample(s.headMinY,s.headMaxY),s.partWidth),batch=[];
    for(let member=0;member<(single?1:2);member++){const start=member?beastLerp(beastV(first.x,first.y,-first.z),origin(),asym):first,total=member?mix(length,s.neckSegmentCount?sample(s.neckMin,s.neckMax):0,asym):length,hs=member?beastV(mix(head.x,sample(s.headMinX,s.headMaxX),asym),mix(head.y,sample(s.headMinY,s.headMaxY),asym),s.partWidth):head,weights=Array.from({length:s.neckSegmentCount},(_,i)=>mix(1,.35,i/Math.max(s.neckSegmentCount-1,1))),sum=weights.reduce((a,b)=>a+b,0),points=[start],blocks=[];for(let i=0;i<weights.length;i++){const angle=i>0&&i<weights.length-1?s.neckAngle*Math.PI/180:0,end=beastAdd(points.at(-1),beastV(Math.cos(angle)*total*weights[i]/sum,Math.sin(angle)*total*weights[i]/sum,0)),d=beastSub(end,points.at(-1));blocks.push(beastBox(beastMul(beastAdd(points.at(-1),end),.5),beastV(s.neckThickness,beastLength(d),s.partWidth),'Neck',Math.atan2(-d.x,d.y)));points.push(end)}blocks.push(beastBox(beastAdd(points.at(-1),beastV(hs.x/2,0,0)),hs,'Head'));batch.push({points,blocks,side:single?0:member?-1:1,length:total})}
    const existing=[...body,...necks.flatMap(n=>n.blocks)];let ok=true;for(const neck of batch){for(let j=1;j<neck.points.length&&ok;j++){const a=neck.points[j-1],b=neck.points[j];for(const box of body){let lo=0,hi=1;for(const k of ['x','y','z']){const d=b[k]-a[k],min=k==='x'?-Infinity:box.position[k]-box.size[k]/2+1e-5,max=box.position[k]+box.size[k]/2-1e-5;if(Math.abs(d)<1e-9){if(a[k]<min||a[k]>max){hi=-1;break}}else{const u=(min-a[k])/d,v=(max-a[k])/d;lo=Math.max(lo,Math.min(u,v));hi=Math.min(hi,Math.max(u,v))}}if(lo<=hi){ok=false;break}}}for(const block of neck.blocks){if(existing.some(b=>beastOverlap(block,b)>s.neckOverlap+1e-5)){ok=false;break}existing.push(block)}if(!ok)break}if(ok){necks.push(...batch);n+=batch.length;accepted=true}}
    if(!accepted)legal=false;
  }
  if(!legal)continue;return{settings:{...s,seed},seed,attempts:attempt,bodyLength,torsos,supports,feet,necks,network:createBeastNetwork(feet,s,random)};
 }
 throw new Error('128 次尝试仍无合法结构；请'+(s.fixedTorsoSizes?'增加正方形躯干数量／边长或调整轮廓':'增加身体长度')+'、降低脚间距／数量，或放宽颈部重叠限制');
}
function assembleBeast(plan){const s=plan.settings,unit=40*s.overallScale,parts=[],assets=[],groups=['远侧肢体','主躯干','近侧肢体'].map(name=>({id:uid(),name}));
 const make=(box,name,type='body',side=0)=>{const w=box.size.x*unit,h=box.size.y*unit,x=(box.position.x+side*s.sideSpread)*unit,y=-box.position.y*unit;if(w<10||w>1000||Math.abs(x)>2000||Math.abs(y)>2000)throw new Error('生成尺寸超出编辑范围，请调整整体缩放或尺寸（部件宽度需在 10–1000 像素内）');const color={Torso:'#879e83',SubTorso:'#ac9974',LegLimb:'#a1b6a0',ForeLegLimb:'#c5aa86',Neck:'#bcb08a',Head:'#d4ab88',Leg:'#81977c',ForeLeg:'#b39c77'}[box.role],svg=`<svg xmlns="http://www.w3.org/2000/svg" width="200" height="${200*h/w}" viewBox="0 0 200 ${200*h/w}"><rect x="1" y="1" width="198" height="${Math.max(1,200*h/w-2)}" rx="4" fill="${color}" stroke="#34443f" stroke-width="2"/></svg>`,a={id:uid(),type,name,ratio:h/w,src:'data:image/svg+xml;charset=utf-8,'+encodeURIComponent(svg),generatedBeast:true},p=freshPart(a,{name,width:w,heightScale:1,rotation:-box.angle*180/Math.PI,x,y,anchor:[.5,.5],z:side<0?1:side>0?3:2,layerId:groups[side<0?0:side>0?2:1].id,layerOrder:parts.length,generatorRole:box.role,generatorZ:box.position.z});assets.push(a);parts.push(p);return p};
 // Connection points are stored on structural body parts, retaining the existing v2 format.
 const local=(p,world)=>{const dx=world.x-p.x,dy=world.y-p.y,angle=p.rotation*Math.PI/180;return[clamp((dx*Math.cos(angle)+dy*Math.sin(angle))/p.width+.5,0,1),clamp((-dx*Math.sin(angle)+dy*Math.cos(angle))/(p.width*assets.find(a=>a.id===p.assetId).ratio)+.5,0,1)]};
 const attach=(p,parent,world={x:p.x,y:p.y})=>{const key='link_'+Object.keys(parent.ports).length;templatePoint(parent,key,local(parent,world));p.anchor=local(p,world);p.parentId=parent.id;p.mount=key;const tr=q=>({x:q.x,y:q.y,w:q.width,h:q.width*assets.find(a=>a.id===q.assetId).ratio,angle:q.rotation*Math.PI/180,mirror:false}),target=point(tr(parent),...parent.ports[key]),anchor=point(tr(p),...p.anchor);p.offsetX=anchor.x-target.x;p.offsetY=anchor.y-target.y;if(Math.abs(p.offsetX)>1000||Math.abs(p.offsetY)>1000)throw new Error('连接偏移超出范围，请降低整体缩放');};
 const tagTier=(p,tier)=>{if(tier){p.generatorSizeTier=tier;p.name+='（'+tier+'）'}return p};
 const torsos=plan.torsos.map((box,i)=>{const p=tagTier(make(box,'兽形·主躯干 '+(i+1)),box.sizeTier);if(i)attach(p,parts[i-1]);return p});
 const roleCounts={Leg:0,ForeLeg:0};
 for(let i=0;i<plan.feet.length;i++){const foot=plan.feet[i],side=foot.side,label=(foot.role==='Leg'?'后腿':'前腿')+' '+(++roleCounts[foot.role]),support=make(plan.supports[i],'兽形·支撑 '+label,'body',side);attach(support,torsos[plan.supports[i].parent]);let parent=support;for(let j=foot.segments.length-1;j>=0;j--){const p=tagTier(make(foot.segments[j],'兽形·'+label+'·肢段 '+(j+1),'body',side),foot.sizeTier),v=beastAdd(foot.position,foot.points[j+1]);attach(p,parent,{x:(v.x+side*s.sideSpread)*unit,y:-v.y*unit});parent=p}const p=tagTier(make(beastBox(foot.position,foot.size,foot.role),'兽形·'+label+'·脚','foot',side),foot.sizeTier),v=beastAdd(foot.position,foot.points[0]);attach(p,parent,{x:(v.x+side*s.sideSpread)*unit,y:-v.y*unit});}
 for(let i=0;i<plan.necks.length;i++){const neck=plan.necks[i];let parent=torsos.at(-1);for(let j=0;j<neck.blocks.length;j++){const b=neck.blocks[j],p=make(b,'兽形·'+(b.role==='Head'?'头 '+(i+1):'颈 '+(i+1)+'·段 '+(j+1)),b.role==='Head'?'head':'body',neck.side),v=neck.points[j];attach(p,parent,{x:(v.x+neck.side*s.sideSpread)*unit,y:-v.y*unit});parent=p}}
 const candidate={...clone(state),version:2,parts,assets:state.assets.filter(a=>!a.generatedBeast).concat(assets),layerGroups:groups,template:'beast',beastGeneration:{settings:s,seed:plan.seed,attempts:plan.attempts,bodyLength:plan.bodyLength,network:plan.network}};
 return validateProject(candidate);
}
const beforeGeneratedBeastTemplate=template;
template=function(kind){if(kind!=='beast')return beforeGeneratedBeastTemplate(kind);const plan=createBeastPlan(readBeastControls()),candidate=assembleBeast(plan);state=candidate;selected=state.parts.find(p=>p.generatorRole==='Torso').id;setBeastControls(plan.settings);$('beastResult').textContent='已生成 '+state.parts.length+' 件 · 种子 '+plan.seed+' · 尝试 '+plan.attempts+' 次 · 实际总长 '+plan.bodyLength.toFixed(3);};
$('beastTemplate').onclick=()=>generateBrowserBeast();
function generateBrowserBeast(){const settings=readBeastControls();if(state.parts.length&&!confirm('生成兽形会替换当前组合，保留素材库，可撤销。继续？'))return;const ok=change('按生物生成规则生成兽形',()=>{template('beast')});if(ok){fit();say('兽形已生成；选择结构部件可调整连接点或替换素材。')}else setBeastControls(settings);return ok}
const beforeBeastRefresh=refresh;
let beastControlsStamp='';
refresh=function(){beforeBeastRefresh();const b=state.beastGeneration;$('bodyCount').disabled=state.template==='beast';$('bodyCount').title=state.template==='beast'?'包含辅助躯干、肢段与颈段；数量请在兽形生成参数中调整':'';if(state.template==='beast'&&b){const stamp=JSON.stringify(b.settings);if(stamp!==beastControlsStamp){setBeastControls(b.settings);beastControlsStamp=stamp}$('beastResult').textContent='兽形 '+state.parts.length+' 件 · 种子 '+b.seed+' · 尝试 '+b.attempts+' 次'+(Number.isFinite(b.bodyLength)?' · 实际总长 '+b.bodyLength.toFixed(3):'')}};
const beforeBeastPaint=paint;
paint=function(context,selection=true){beforeBeastPaint(context,selection);const b=state.beastGeneration;if(!selection||state.template!=='beast'||!b?.settings?.showNetwork||!Array.isArray(b.network?.edges))return;const unit=40*b.settings.overallScale;context.save();context.strokeStyle='#f2c96f';context.lineWidth=1/view.scale;context.setLineDash([4/view.scale,4/view.scale]);for(const edge of b.network.edges){if(!Array.isArray(edge)||edge.length!==2||edge.some(p=>!p||!Number.isFinite(p.x)||!Number.isFinite(p.y)))continue;context.beginPath();context.moveTo(edge[0].x*unit,-edge[0].y*unit);context.lineTo(edge[1].x*unit,-edge[1].y*unit);context.stroke()}context.restore()};
beastParametersPanel();
$('beast_fixedLegSizes').onchange=syncFixedLegControls;
$('beast_fixedTorsoSizes').onchange=syncFixedTorsoControls;
for(const [title,text]of [
 ['主躯干','固定模式中 X 长度 = Y 高度，使用小 / 中 / 大三档正方形边长，Z 厚度独立，整体缩放照常生效。不使用身体总长输入，总长由数量、选档和重叠比例自动计算。按完整上下轮廓（含高度偏移）确定性调整选档，再尝试增大档位且不破坏其他段约束，不使用随机数、不拉伸。参考高度均值仅缩放约束曲线。无法适配或连接时提示失败，原方案保持不变。'],
 ['分段肢体','固定腿使用短 / 中 / 长三档总腿长与肢段粗细，不使用标称腿长或随机尺寸上下限。按主躯干等效尺寸相对中档躯干的比例优先选档，结合支撑高度检查适配；粗细不能超过主躯干或支撑宽度，并检查所有脚的间距。左右成对同档，脚基准尺寸随短 / 中 / 长乘 0.75 / 1 / 1.25。挂接位置、选档和折弯不使用随机数；参考高度取均值。节数独立，腿长不拉伸，脚高度可不同，必要时整体抬高避免穿地。整体缩放统一生效。']
]){const index=BEAST_FIELDS.findIndex(([name])=>name===title),section=$('beastSettings').children[index];if(section){const note=document.createElement('p');note.className='hint';note.textContent=text;section.append(note)}}
refresh();
