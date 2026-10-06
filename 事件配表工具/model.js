(function(root){
 'use strict';const S=root.EventSchema;
 const copy=x=>JSON.parse(JSON.stringify(x));
 function normalize(raw){
  if(!raw||typeof raw!=='object'||Array.isArray(raw))throw Error('项目必须是JSON对象。');
  if(raw.schema_version!==undefined&&raw.schema_version!==1)throw Error('暂不支持此项目版本。');
  const source=raw.tables||raw.data;if(!source||!Array.isArray(source.events))throw Error('不是事件项目：缺少 events 表。');
  const project={schema_version:1,name:String(raw.name||'我的叙事事件').slice(0,150),tables:{},stories:root.EventStory?root.EventStory.clean(raw.stories):raw.stories||{}};
  for(const [key,table] of Object.entries(S)){
   const rows=source[key]||[];if(!Array.isArray(rows)||rows.length>5000)throw Error(`${table.label}表格式错误或超过5000行。`);
   project.tables[key]=rows.map(row=>{
    if(!row||typeof row!=='object'||Array.isArray(row))throw Error(`${table.label}含有无效行。`);
    const result={};for(const f of table.fields){let v=row[f.key]??'';if(!['string','number','boolean'].includes(typeof v))throw Error(`${table.label}.${f.label}必须是文本、数字或布尔值。`);if(String(v).length>100000)throw Error('文本超过长度限制。');result[f.key]=v;}return result;
   });
  }
  if(!project.tables.events.length)throw Error('项目至少需要一个事件。');
  const existingEvents=new Set(project.tables.events.map(e=>e.id));for(const id of Object.keys(project.stories))if(!existingEvents.has(id))delete project.stories[id];
  const nodes=new Map(project.tables.nodes.map(r=>[r.id,r.event_id]));for(const r of project.tables.choices)if(!r.event_id)r.event_id=nodes.get(r.node_id)||'';
  return project;
 }
 function makeId(project,key){const used=new Set(project.tables[key].map(r=>r.id));let n=1;while(used.has(`${S[key].prefix}_${String(n).padStart(3,'0')}`))n++;return `${S[key].prefix}_${String(n).padStart(3,'0')}`;}
 function create(project,key,eventId){const row={};for(const f of S[key].fields)row[f.key]=f.default??(f.enum?f.enum[0]:'');row.id=makeId(project,key);if(key==='events'){row.name='未命名事件';row.status='草稿';row.repeat='一次性';row.accept='确认';}else row.event_id=eventId;
  if(key==='goals'){row.stage_id=`STAGE_${row.id}`;row.completion='ALL';}if(key==='conditions')row.group_id=`CG_${row.id}`;if(key==='actions'){row.group_id=`RG_${row.id}`;row.once_key=`once.${row.id}`;}return row;
 }
 function options(project,ref,eventId){
  if(['condition_groups','stage_groups','action_groups'].includes(ref)){const [key,field]=ref==='condition_groups'?['conditions','group_id']:ref==='stage_groups'?['goals','stage_id']:['actions','group_id'];return [...new Set(project.tables[key].filter(r=>r.event_id===eventId).map(r=>r[field]).filter(Boolean))].map(id=>({id,label:id}));}
  return project.tables[ref].filter(r=>ref==='events'||r.event_id===eventId).map(r=>({id:r.id,label:ref==='events'?`${r.name} · ${r.id}`:`${r.id}${r.text?' · '+String(r.text).slice(0,20):''}`}));
 }
 function rename(project,key,oldId,newId){if(!/^[A-Za-z][A-Za-z0-9_.:-]*$/.test(newId))throw Error('ID须以英文字母开头，只包含英文、数字、下划线、点、冒号或短横线。');if(project.tables[key].some(r=>r.id===newId&&r.id!==oldId))throw Error('同表已有这个ID。');
  if(key==='events'&&project.stories?.[oldId]){project.stories[newId]=project.stories[oldId];delete project.stories[oldId];}
  for(const [table,rows] of Object.entries(project.tables))for(const row of rows)for(const f of S[table].fields){if(f.key==='id')continue;if(f.ref===key&&row[f.key]===oldId)row[f.key]=newId;
   if(table==='conditions'&&f.key==='field'&&typeof row.field==='string'&&row.field.startsWith(oldId+'.'))row.field=newId+row.field.slice(oldId.length);
   if(table==='actions'&&f.key==='target'&&row.target===oldId&&['完成事件','开放事件'].includes(row.type))row.target=newId;
  }
 }
 function cloneEvent(project,eventId){
  const source=project.tables.events.find(r=>r.id===eventId),newId=makeId(project,'events'),map=new Map([[eventId,newId]]),owned={};
  for(const key of Object.keys(S))if(key!=='events'){owned[key]=project.tables[key].filter(r=>r.event_id===eventId).map(copy);for(const r of owned[key]){let id=r.id+'_COPY';let n=1;while(project.tables[key].some(x=>x.id===id)||[...map.values()].includes(id))id=r.id+'_COPY_'+n++;map.set(r.id,id);for(const field of ['stage_id','group_id'])if(r[field]&&!map.has(r[field]))map.set(r[field],r[field]+'_'+newId);if(r.once_key)map.set(r.once_key,r.once_key+'_'+newId);}}
  function translate(row,key){for(const f of S[key].fields){const v=row[f.key];if(map.has(v))row[f.key]=map.get(v);else if(key==='conditions'&&f.key==='field'&&typeof v==='string')for(const [old,neo] of map)if(v.startsWith(old+'.')){row[f.key]=neo+v.slice(old.length);break;}}return row;}
  const e=translate(copy(source),'events');e.id=newId;e.name=source.name+'（副本）';e.status='草稿';project.tables.events.push(e);
  for(const [key,rows]of Object.entries(owned))project.tables[key].push(...rows.map(r=>translate(r,key)));if(project.stories?.[eventId])project.stories[newId]=copy(project.stories[eventId]);return newId;
 }
 function validate(project){const issues=[],add=(level,table,row,field,message)=>issues.push({level,table,id:row.id,event_id:table==='events'?row.id:row.event_id,field,message});
  for(const [key,table]of Object.entries(S)){
   const seen=new Set();for(const r of project.tables[key]){
    const e=project.tables.events.find(x=>x.id===(key==='events'?r.id:r.event_id));const requiredLevel=e?.status==='可发布'?'error':'warning';
    if(seen.has(r.id))add('error',key,r,'id','记录ID重复');seen.add(r.id);
    for(const f of table.fields){const v=r[f.key];if(f.required&&(v===''||v===null||v===undefined))add(requiredLevel,key,r,f.key,`缺少${f.label}`);
     if(f.key==='id'&&v&&!/^[A-Za-z][A-Za-z0-9_.:-]*$/.test(v))add('error',key,r,f.key,'ID格式不合法');
     if(f.enum&&v&&!f.enum.includes(v))add('error',key,r,f.key,`${f.label}不在允许选项内`);
     if(f.type==='int'&&(v===''||!Number.isInteger(Number(v))||Number(v)<(f.min??0)))add('error',key,r,f.key,`${f.label}须为不小于${f.min??0}的整数`);
     if(f.ref&&v&&!(f.special||[]).includes(v)&&!options(project,f.ref,r.event_id||r.id).some(o=>o.id===v))add('error',key,r,f.key,`${f.label}引用不存在或属于其他事件：${v}`);
    }
    if(['conditions','actions'].includes(key)){
     if(r.value_type==='NUMBER'&&(r.value===''||!Number.isFinite(Number(r.value))))add('error',key,r,'value','值应为有效数字');
     if(r.value_type==='BOOL'&&r.value!==true&&r.value!==false)add('error',key,r,'value','布尔值只能填 true 或 false');
    }
    if(key==='nodes'){
     if(r.type==='选项'&&!project.tables.choices.some(c=>c.node_id===r.id))add(requiredLevel,key,r,'type','选项节点没有选项');
     if(r.type!=='选项'&&!r.next_node)add(requiredLevel,key,r,'next_node','缺少下一节点；播放结束填写END');
     if(['对话','旁白','笔记'].includes(r.type)&&!r.text)add(requiredLevel,key,r,'text','文本节点缺少正文');
     if(/【\s*】/.test(r.text))add(requiredLevel,key,r,'text','正文仍有【】占位符');
    }
    if(key==='choices'){if(r.confirm==='是'&&!r.confirm_text)add(requiredLevel,key,r,'confirm_text','不可逆选项缺少确认提示');if(!r.target_node)add(requiredLevel,key,r,'target_node','缺少选项目标节点');}
    if(key==='maps'&&e?.status==='可发布'&&r.status!=='已绑定')add('error',key,r,'status','可发布事件仍有未绑定地图');
    if(key==='actions'&&['完成事件','开放事件'].includes(r.type)&&!project.tables.events.some(e=>e.id===r.target))add('error',key,r,'target','目标事件不存在');
   }
  }
  for(const e of project.tables.events){for(const key of ['initial_stage','start_node'])if(!e[key])add(e.status==='可发布'?'error':'warning','events',e,key,`请填写${key==='initial_stage'?'初始阶段':'起始节点'}`);
   if(e.status==='可发布'){if(!e.trigger)add('error','events',e,'trigger','可发布事件缺少触发类型');if(e.trigger==='交互'&&!e.entry)add('error','events',e,'entry','交互事件缺少入口ID');if(!e.repeat)add('error','events',e,'repeat','缺少重复规则');
    for(const r of project.tables.actions.filter(r=>r.event_id===e.id)){if(!r.type)add('error','actions',r,'type','结果缺少类型');if(!r.timing)add('error','actions',r,'timing','结果缺少执行时机');if(r.type==='设置天气'&&(!r.scope||!r.duration))add('error','actions',r,'scope','天气必须填写作用范围与持续规则');}
    for(const r of project.tables.goals.filter(r=>r.event_id===e.id&&r.type==='献祭')){if(!r.monster_condition)add('error','goals',r,'monster_condition','献祭目标必须指定怪物条件');if(!r.location_condition)add('error','goals',r,'location_condition','献祭目标必须指定地点条件');}
   }
  }
  for(const [key,group,fields]of [['goals','stage_id',['completion','next_stage','result_group']],['conditions','group_id',['relation']],['actions','group_id',['timing','condition_group']]]){
   const groups=new Map();for(const r of project.tables[key]){const id=r.event_id+'|'+r[group];if(!groups.has(id))groups.set(id,[]);groups.get(id).push(r);}for(const rows of groups.values())for(const f of fields)if(new Set(rows.map(r=>r[f]||'')).size>1)add('error',key,rows[0],f,`同一${group}的${f}填写不一致`);
  }
  const once=new Set();for(const r of project.tables.actions){if(r.once_key&&once.has(r.once_key))add('error','actions',r,'once_key','一次性键重复，会干扰结果记录');once.add(r.once_key);}
  // 不含玩家选择或外部等待出口的纯自动节点闭环不能发布。
  for(const e of project.tables.events){const nodes=project.tables.nodes.filter(r=>r.event_id===e.id),byId=new Map(nodes.map(r=>[r.id,r]));let path=new Set(),node=byId.get(e.start_node);
   while(node&&!['选项','交互'].includes(node.type)&&node.next_node!=='END'){if(path.has(node.id)){add('error','nodes',node,'next_node','起始流程存在无交互出口的循环');break;}path.add(node.id);node=byId.get(node.next_node);}
  }
  return issues;
 }
 function fromSheets(sheets){
  const writing=sheets.find(s=>s.rows[0]?.includes('所处阶段')&&s.rows[0]?.includes('对话对象')&&s.rows[0]?.includes('事件名'));
  if(writing){
   const p={schema_version:1,name:sheets.find(s=>s.name==='字段说明')?.rows.find(r=>r[0]==='项目名称')?.[1]||'导入的情节稿',tables:{},stories:{}};for(const key of Object.keys(S))p.tables[key]=[];
   const headers=writing.rows[0];const val=(row,label)=>String(row[headers.indexOf(label)]??'');let e;
   for(const row of writing.rows.slice(1)){if(val(row,'事件名')){e=create(p,'events');e.name=val(row,'事件名');e.summary=val(row,'概览');e.entry=val(row,'地点');p.tables.events.push(e);p.stories[e.id]=[];}if(e&&row.some(v=>v!==''&&v!==undefined&&v!==null))p.stories[e.id].push({stage:val(row,'所处阶段'),speaker:val(row,'对话对象'),text:val(row,'内容'),reward:val(row,'奖励'),effect:val(row,'效果'),assets:val(row,'需要内容')});}
   // 本工具导出的 Excel 同时保留结构化配置；手写稿则只创建写作草稿。
   if(sheets.some(s=>s.name===S.events.label)){const structured=fromSheets(sheets.filter(s=>s!==writing));const available=[...p.tables.events];for(const e of structured.tables.events){const i=available.findIndex(x=>x.name===e.name);if(i>=0){const [match]=available.splice(i,1);structured.stories[e.id]=p.stories[match.id];}}return normalize(structured);}
   return normalize(p);
  }
  const raw={schema_version:1,name:sheets.find(s=>s.name==='字段说明')?.rows.find(r=>r[0]==='项目名称')?.[1]||'导入的事件表',tables:{}};
  if(sheets.some(s=>s.rows[0]?.includes('事件名')&&s.rows[0]?.includes('概览')&&!s.rows[0]?.includes('事件ID')&&!s.rows[0]?.includes('记录 ID'))){
   for(const key of Object.keys(S))raw.tables[key]=[];
   const sheet=sheets.find(s=>s.rows[0]?.includes('事件名')),rows=sheet.rows;let current=null,previous=null;
   for(let i=1;i<rows.length;i++){const row=rows[i];if(row[0]){current=create(raw,'events');current.name=String(row[0]);current.summary=row[1]||'';current.entry=row[2]||'';current.source_reward=row[4]||'';current.source_effect=row[5]||'';current.source_assets=row[6]||'';raw.tables.events.push(current);previous=null;}
    else if(current&&row[3]){const node=create(raw,'nodes',current.id);node.speaker=row[2]||'';node.text=String(row[3]);node.type=row[2]==='玩家选项'?'笔记':'对话';node.next_node='END';node.note=(row[2]==='玩家选项'?'原稿玩家选项，需手动转为选项；':'')+(row[4]?'原稿结果说明：'+row[4]:'');raw.tables.nodes.push(node);if(previous)previous.next_node=node.id;else current.start_node=node.id;previous=node;}}
   return normalize(raw);
  }
  const idLabels={events:'事件ID',goals:'目标ID',nodes:'节点ID',choices:'选项ID',conditions:'条件ID',actions:'结果ID',maps:'绑定ID'};
  for(const [key,table]of Object.entries(S)){const sh=sheets.find(s=>s.name===table.label);if(!sh){raw.tables[key]=[];continue;}const hi=sh.rows.findIndex(r=>r.includes(table.fields[0].label)||r.includes(idLabels[key]));if(hi<0)throw Error(`${table.label}没有找到表头`);const headers=sh.rows[hi];raw.tables[key]=sh.rows.slice(hi+1).filter(r=>r[0]).map(r=>Object.fromEntries(table.fields.map(f=>{let idx=headers.indexOf(f.label);if(idx<0&&f.key==='id')idx=headers.indexOf(idLabels[key]);if(idx<0&&f.key==='event_id')idx=headers.indexOf('事件ID');if(idx<0&&key==='choices'&&f.key==='node_id')idx=headers.indexOf('所属节点ID');if(idx<0&&key==='choices'&&f.key==='target_node')idx=headers.indexOf('目标节点ID');return [f.key,r[idx]??''];})));}
  // 兼容先前模板中未附所属事件字段的条件和结果。
  for(const key of ['conditions','actions'])for(const r of raw.tables[key])if(!r.event_id){const refs=key==='conditions'?['condition_group','monster_condition','location_condition','submit_condition','visible_condition','enabled_condition']:['result_group'];const groups=key==='conditions'?r.group_id:r.group_id;let found;
   for(const table of Object.keys(S))for(const row of raw.tables[table])if(refs.some(f=>row[f]===groups)){found=row.event_id||(table==='events'?row.id:null);if(found)break;}r.event_id=found||raw.tables.events.find(e=>e.name==='血祭日')?.id||'';}
  return normalize(raw);
 }
 root.EventModel={copy,normalize,create,options,rename,cloneEvent,validate,fromSheets};
 if(typeof module!=='undefined')module.exports=root.EventModel;
})(globalThis);
