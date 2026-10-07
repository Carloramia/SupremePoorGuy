(()=>{
 'use strict';const S=EventSchema,M=EventModel,KEY='supreme-poor-guy.event-editor.v1';
 const $=id=>document.getElementById(id),esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 let project,initialWarning='',selectedEvent,tab='events',selectedRecord='',undo=[],redo=[],toastTimer;
 try{project=M.normalize(JSON.parse(localStorage.getItem(KEY))||EventSeed);}catch(e){project=M.normalize(EventSeed);initialWarning='本机草稿无法读取，已显示内置示例。原草稿未覆盖；请导入备份。';}
 selectedEvent=project.tables.events[0].id;
 let writing=true;
 const mode=document.createElement('div');mode.className='writing-mode';mode.innerHTML='<button id="writing-mode" class="primary">✎ 情节写作</button><button id="config-mode">结构化配置（后续整理）</button><span>先写故事，条件可用自然语言；不要求 Godot 字段。</span>';
 document.querySelector('.event-heading').after(mode);
 const storyPanel=document.createElement('section');storyPanel.id='story-panel';mode.after(storyPanel);
 $('runtime').hidden=true;$('save').textContent='保存情节项目';
 $('writing-mode').onclick=()=>{writing=true;render();};$('config-mode').onclick=()=>{writing=false;render();};
 const rowEvent=r=>tab==='events'?r.id:r.event_id;
 const currentEvent=()=>project.tables.events.find(r=>r.id===selectedEvent);
 const records=()=>tab==='events'?[currentEvent()].filter(Boolean):project.tables[tab].filter(r=>r.event_id===selectedEvent);
 const current=()=>records().find(r=>r.id===selectedRecord)||records()[0];
 function toast(text){$('toast').textContent=text;$('toast').style.display='block';clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').style.display='none',3500);}
 function persist(){try{const prev=localStorage.getItem(KEY);if(prev)localStorage.setItem(KEY+'.backup',prev);localStorage.setItem(KEY,JSON.stringify(project));$('save-status').textContent='已自动保存到本机 · '+new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'});$('save-status').classList.remove('status-warning');}catch(e){$('save-status').textContent='自动保存不可用，请保存项目文件';$('save-status').classList.add('status-warning');toast('浏览器无法保存草稿，请点击“保存项目”备份。');}}
 function change(fn){const before=M.copy(project);try{fn();undo.push(before);if(undo.length>80)undo.shift();redo=[];persist();render();}catch(e){project=before;render();toast(e.message);}}
 function modal(title,body,buttons){$('dialog-content').innerHTML=`<h2>${esc(title)}</h2>${body}<div class="buttons">${buttons.map((b,i)=>`<button data-modal="${i}" class="${b.primary?'primary':''}">${esc(b.text)}</button>`).join('')}</div>`;if(!$('dialog').open)$('dialog').showModal();buttons.forEach((b,i)=>$('dialog-content').querySelector(`[data-modal="${i}"]`).onclick=()=>{const result=b.action?.();if(result!==false)$('dialog').close();});}
 function confirmAction(title,text,action){modal(title,`<p>${esc(text)}</p>`,[{text:'取消'},{text:'确认',primary:true,action}]);}
 function download(name,data,type){const url=URL.createObjectURL(data instanceof Blob?data:new Blob([data],{type:type||'application/json;charset=utf-8'})),a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),300000);
  if(!$('dialog').open)modal('文件已生成',`<p>浏览器会尝试下载文件。如果没有开始，请点击下面的下载链接。</p><p><a style="color:var(--gold)" href="${esc(url)}" download="${esc(name)}">下载 ${esc(name)}</a></p><p>链接有效期5分钟；请保存到你的配表工作目录。</p>`,[{text:'完成',primary:true}]);else toast('文件已生成，已交给浏览器下载。');}
 function titleOf(r){return r.name||r.description||r.text||r.note||r.field||r.target||r.id;}
 function render(){
  if(!currentEvent())selectedEvent=project.tables.events[0].id;
  $('project-name').value=project.name;$('event-count').textContent=project.tables.events.length;
  const search=$('search').value.toLowerCase();$('event-list').innerHTML=project.tables.events.filter(r=>(r.name+' '+r.id).toLowerCase().includes(search)).map(r=>`<button class="event-card ${r.id===selectedEvent?'active':''}" data-event="${esc(r.id)}"><div class="meta"><span>${esc(r.category||'未分类')}</span><span>${esc(r.status)}</span></div><strong>${esc(r.name)}</strong><code>${esc(r.id)}</code></button>`).join('')||'<div class="empty">没有匹配的事件</div>';
  $('event-title').textContent=currentEvent()?.name||'未命名事件';$('event-id').textContent=selectedEvent;
  $('tabs').innerHTML=Object.entries(S).map(([key,t])=>`<button data-tab="${key}" class="${key===tab?'active':''}">${t.label}<small>${key==='events'?'':project.tables[key].filter(r=>r.event_id===selectedEvent).length}</small></button>`).join('');
  const rows=records(),r=current();selectedRecord=r?.id||'';$('table-title').textContent=S[tab].label;$('table-note').textContent=S[tab].note;$('add-record').hidden=tab==='events';
  $('record-list').innerHTML=rows.map((row,i)=>`<button class="record-card ${row.id===selectedRecord?'active':''}" data-record="${esc(row.id)}"><span class="badge">${esc(row.type||row.status||String(i+1).padStart(2,'0'))}</span><strong>${esc(String(titleOf(row)).slice(0,90))}</strong><code>${esc(row.id)}</code>${row.group_id?`<small>${esc(row.group_id)}</small>`:''}</button>`).join('')||'<div class="empty">这里还没有配置。<br>点击“添加”，ID会自动生成。</div>';
  for(const id of ['delete-record','clone-record','move-up','move-down'])$(id).hidden=tab==='events';
  for(const id of ['delete-record','clone-record','move-up','move-down'])$(id).disabled=!r;
  renderFields(r);const issues=M.validate(project);$('issue-count').textContent=issues.length;$('summary').textContent=`${rows.length} 条${S[tab].label} · ${issues.filter(i=>i.level==='error').length} 个错误 / ${issues.filter(i=>i.level==='warning').length} 项待补 · v0.1`;
  $('undo').disabled=!undo.length;$('redo').disabled=!redo.length;
  $('tabs').hidden=writing;document.querySelector('.editing').hidden=writing;storyPanel.hidden=!writing;$('validate').hidden=writing;$('runtime').hidden=writing;
  $('writing-mode').classList.toggle('primary',writing);$('config-mode').classList.toggle('primary',!writing);
  if(writing){renderStory();$('summary').textContent=`${EventStory.get(project,selectedEvent).length} 段情节 · 自由写作 · 条件暂不校验`;} 
 }
 function renderStory(){
  const e=currentEvent(),rows=EventStory.get(project,selectedEvent);
  storyPanel.innerHTML=`<div class="story-intro">内容会实时保存到当前浏览器。点击“保存情节项目”下载完整备份，之后可导入继续写。此模式独立于结构化配置，不自动生成条件或覆盖旧配置。</div><div class="story-meta">${[['name','事件名'],['summary','概览'],['entry','地点']].map(([k,label])=>`<label>${label}<textarea data-story-event="${k}" rows="${k==='summary'?3:1}">${esc(e[k])}</textarea></label>`).join('')}</div><div class="story-head"><h2>情节流程 · 从上到下阅读</h2><button id="story-add" class="primary">＋ 添加情节段落</button></div>${rows.map((r,i)=>`<article class="story-row"><div class="story-row-head"><strong>第 ${i+1} 段</strong><div><button data-story-op="up" data-index="${i}" ${i===0?'disabled':''}>↑</button><button data-story-op="down" data-index="${i}" ${i===rows.length-1?'disabled':''}>↓</button><button data-story-op="copy" data-index="${i}">复制</button><button data-story-op="delete" data-index="${i}" class="danger-text">删除</button></div></div><div class="story-fields">${EventStory.columns.map(([k,label])=>`<label class="${k==='text'?'story-body':''}">${label}<textarea aria-label="第${i+1}段${label}" data-story-index="${i}" data-story-key="${k}" rows="${k==='text'?5:2}" placeholder="${k==='stage'?'例如：任务进行中 / 完成前一事件后10日；可留空':k==='text'?'直接填写对话、旁白或玩家选项内容':'可留空'}">${esc(r[k])}</textarea></label>`).join('')}</div></article>`).join('')}<button id="story-add-bottom">＋ 继续写下一段</button>`;
  storyPanel.querySelectorAll('textarea').forEach(input=>{
   let captured=false;
   input.oninput=()=>{if(!captured){undo.push(M.copy(project));if(undo.length>80)undo.shift();redo=[];captured=true;}if(input.dataset.storyEvent)e[input.dataset.storyEvent]=input.value;else EventStory.ensure(project,selectedEvent)[Number(input.dataset.storyIndex)][input.dataset.storyKey]=input.value;persist();$('undo').disabled=false;$('redo').disabled=true;};
   input.onblur=()=>{captured=false;if(input.dataset.storyEvent==='name'){if(!e.name)e.name='未命名事件';$('event-title').textContent=e.name;const card=$('event-list').querySelector('.active strong');if(card)card.textContent=e.name;}};
  });
  const add=()=>change(()=>EventStory.ensure(project,selectedEvent).push(Object.fromEntries(EventStory.columns.map(([k])=>[k,'']))));$('story-add').onclick=add;$('story-add-bottom').onclick=add;
  storyPanel.querySelectorAll('[data-story-op]').forEach(button=>button.onclick=()=>{const i=Number(button.dataset.index),op=button.dataset.storyOp;const act=()=>change(()=>{const rows=EventStory.ensure(project,selectedEvent);if(op==='delete')rows.splice(i,1);else if(op==='copy')rows.splice(i+1,0,M.copy(rows[i]));else{const j=i+(op==='up'?-1:1);[rows[i],rows[j]]=[rows[j],rows[i]];}});if(op==='delete')confirmAction('删除情节段落','删除这段情节？可撤销。',act);else act();});
 }
 function renderFields(row){
  if(!row){$('fields').innerHTML='<div class="empty">添加一条配置后开始编辑。</div>';return;}
  $('fields').innerHTML=S[tab].fields.map(f=>{
   let control;const value=row[f.key]??'',fieldId='field-'+f.key;
   if(f.enum||f.ref){let options=f.enum?f.enum.map(v=>({id:v,label:v})):M.options(project,f.ref,row.event_id||row.id);for(const v of f.special||[])options.unshift({id:v,label:v+' · 结束播放'});if(value&&!options.some(o=>o.id===value))options.unshift({id:value,label:'⚠ 未找到引用：'+value});control=`<select id="${fieldId}" data-field="${f.key}" ${f.key==='event_id'?'disabled':''}><option value="">— 未填写 —</option>${options.map(o=>`<option value="${esc(o.id)}" ${String(o.id)===String(value)?'selected':''}>${esc(o.label)}</option>`).join('')}</select>`;}
   else if(f.type==='text')control=`<textarea id="${fieldId}" data-field="${f.key}" rows="4">${esc(value)}</textarea>`;
   else control=`<input id="${fieldId}" data-field="${f.key}" type="${f.type==='int'?'number':'text'}" ${f.type==='int'?`min="${f.min??0}" step="1"`:''} value="${esc(value)}">`;
   return `<div class="field ${f.type==='text'?'wide':''}"><label for="${fieldId}">${esc(f.label)}${f.required?'<span class="required">*</span>':''}<span class="key">${f.key}</span></label>${control}${f.tip?`<div class="tip">${esc(f.tip)}</div>`:''}</div>`;
  }).join('');
  $('fields').querySelectorAll('[data-field]').forEach(input=>input.onchange=()=>{
   const f=S[tab].fields.find(f=>f.key===input.dataset.field),oldId=row.id;let value=input.value;
   if(f.type==='int')value=value===''?'':Number(value);
   if(f.type==='value'){if(row.value_type==='NUMBER'&&value.trim()!=='')value=Number(value);else if(row.value_type==='BOOL'){if(value==='true'||value==='TRUE')value=true;else if(value==='false'||value==='FALSE')value=false;}}
   change(()=>{
    const target=project.tables[tab].find(r=>r.id===oldId);
    if(f.key==='id'){M.rename(project,tab,oldId,value);target.id=value;selectedRecord=value;if(tab==='events')selectedEvent=value;}
    else{target[f.key]=value;if(f.key==='value_type'&&target.value!==''){if(value==='NUMBER'&&Number.isFinite(Number(target.value)))target.value=Number(target.value);if(value==='BOOL'){if(['true','TRUE',true].includes(target.value))target.value=true;else if(['false','FALSE',false].includes(target.value))target.value=false;}}}
   });
  });
 }
 $('event-list').onclick=e=>{const b=e.target.closest('[data-event]');if(b){selectedEvent=b.dataset.event;selectedRecord='';render();}};
 $('tabs').onclick=e=>{const b=e.target.closest('[data-tab]');if(b){tab=b.dataset.tab;selectedRecord='';render();}};
 $('record-list').onclick=e=>{const b=e.target.closest('[data-record]');if(b){selectedRecord=b.dataset.record;render();}};
 $('search').oninput=render;$('project-name').onchange=e=>change(()=>project.name=e.target.value||'未命名项目');
 $('new-event').onclick=()=>modal('新建事件','<p>创建草稿后按各分类填写。也可以先复制已有事件再修改。</p><label>事件名称<input id="new-name" value="新的事件"></label>',[{text:'取消'},{text:'创建事件',primary:true,action:()=>change(()=>{const r=M.create(project,'events');r.name=$('new-name').value.trim()||'新的事件';project.tables.events.push(r);selectedEvent=r.id;selectedRecord=r.id;tab='events';})}]);
 $('add-record').onclick=()=>change(()=>{const row=M.create(project,tab,selectedEvent);if(tab==='goals'){const list=records();if(list.length){row.stage_id=list[list.length-1].stage_id;row.stage_order=list[list.length-1].stage_order;row.completion=list[list.length-1].completion;row.next_stage=list[list.length-1].next_stage;row.result_group=list[list.length-1].result_group;}}if(tab==='nodes')row.next_node='END';if(tab==='choices')row.node_id=project.tables.nodes.find(r=>r.event_id===selectedEvent&&r.type==='选项')?.id||'';project.tables[tab].push(row);selectedRecord=row.id;});
 $('clone-event').onclick=()=>change(()=>{selectedEvent=M.cloneEvent(project,selectedEvent);selectedRecord='';});
 $('delete-event').onclick=()=>{if(project.tables.events.length===1){toast('至少保留一个事件。');return;}confirmAction('删除整个事件',`删除“${currentEvent().name}”及其全部配置。其他事件若引用它会显示错误；可撤销。`,()=>change(()=>{for(const key of Object.keys(S))project.tables[key]=project.tables[key].filter(r=>(key==='events'?r.id:r.event_id)!==selectedEvent);if(project.stories)delete project.stories[selectedEvent];selectedEvent=project.tables.events[0].id;selectedRecord='';}));};
 $('clone-record').onclick=()=>change(()=>{const row=M.copy(current());row.id=M.create(project,tab,selectedEvent).id;if(row.once_key)row.once_key+='.'+row.id;project.tables[tab].push(row);selectedRecord=row.id;});
 $('delete-record').onclick=()=>{const row=current();if(row)confirmAction('删除这条配置',`删除 ${row.id}。引用此记录的字段需要修复；可撤销。`,()=>change(()=>{project.tables[tab]=project.tables[tab].filter(r=>r.id!==row.id);selectedRecord='';}));};
 function move(delta){const list=records(),i=list.findIndex(r=>r.id===selectedRecord);if(i+delta<0||i+delta>=list.length)return;change(()=>{const all=project.tables[tab],a=all.indexOf(list[i]),b=all.indexOf(list[i+delta]);[all[a],all[b]]=[all[b],all[a]];});}
 $('move-up').onclick=()=>move(-1);$('move-down').onclick=()=>move(1);
 $('undo').onclick=()=>{if(undo.length){redo.push(M.copy(project));project=undo.pop();persist();render();}};
 $('redo').onclick=()=>{if(redo.length){undo.push(M.copy(project));project=redo.pop();persist();render();}};
 function showIssues(){const issues=M.validate(project);modal('配置检查',issues.length?`<p>错误必须修复；草稿的待补项不妨碍保存项目。点击一条可定位到字段。</p>${issues.map((i,n)=>`<button class="issue ${i.level}" data-issue="${n}">${i.level==='error'?'错误':'待补'} · ${esc(S[i.table].label)} · ${esc(i.id)}<small>${esc(i.message)}</small></button>`).join('')}`:'<p>没有发现结构或引用问题。地图与资源是否存在仍需在游戏中验证。</p>',[{text:'关闭',primary:true}]);$('dialog-content').querySelectorAll('[data-issue]').forEach(b=>b.onclick=()=>{const issue=issues[Number(b.dataset.issue)];selectedEvent=issue.event_id||selectedEvent;tab=issue.table;selectedRecord=issue.id;$('dialog').close();render();$('field-'+issue.field)?.focus();});}
 $('validate').onclick=showIssues;
 $('save').onclick=()=>{document.activeElement?.blur();persist();download(project.name.replace(/[<>:"/\\|?*]/g,'_')+'.events.json',JSON.stringify(project,null,2));};
 $('excel').onclick=async()=>{try{$('excel').disabled=true;const blob=await EventXlsx.write(project);download(project.name.replace(/[<>:"/\\|?*]/g,'_')+'.xlsx',blob);}catch(e){toast('导出失败：'+e.message);}finally{$('excel').disabled=false;}};
 $('runtime').onclick=()=>{
  const published=new Set(project.tables.events.filter(r=>r.status==='可发布').map(r=>r.id));if(!published.size){modal('还没有可发布事件','<p>在事件总览中把配置完整的事件标为“可发布”。导出Godot数据只包含这些事件；草稿请用“保存项目”或“导出Excel”。</p>',[{text:'知道了',primary:true}]);return;}
  const issues=M.validate(project).filter(i=>i.level==='error'&&published.has(i.event_id));if(issues.length){showIssues();toast('有错误，暂不能导出运行配置。');return;}
  const tables={};for(const key of Object.keys(S))tables['T_'+key.toUpperCase()]=project.tables[key].filter(r=>published.has(key==='events'?r.id:r.event_id));
  download('narrative_config.godot.json',JSON.stringify({schema_version:1,name:project.name,format:'structured_event_tables',tables},null,2));
 };
 $('import').onclick=()=>$('file-input').click();
 $('file-input').onchange=async e=>{const file=e.target.files[0];if(!file)return;try{if(file.size>15*1024*1024)throw Error('文件超过15MB');let incoming;if(file.name.toLowerCase().endsWith('.xlsx'))incoming=M.fromSheets(await EventXlsx.read(file));else incoming=M.normalize(JSON.parse(await file.text()));
  modal('确认导入项目',`<p>导入会替换当前工作区，支持撤销。建议先保存项目文件。</p><p>${esc(file.name)}</p><div class="import-preview">${Object.entries(S).map(([key,t])=>`<div>${t.label}：${incoming.tables[key].length} 条</div>`).join('')}</div>`,[{text:'取消'},{text:'先保存当前项目',action:()=>{download(project.name+'.events.json',JSON.stringify(project,null,2));return false;}},{text:'替换工作区',primary:true,action:()=>change(()=>{project=incoming;selectedEvent=project.tables.events[0].id;tab='events';selectedRecord='';})}]);
 }catch(error){modal('无法导入',`<p>${esc(error.message)}</p><p>当前项目没有改变。支持本工具项目JSON、配表模板Excel和原始剧情Excel。</p>`,[{text:'关闭',primary:true}]);}finally{e.target.value='';}};
 $('help').onclick=()=>modal('使用说明',`<p>先选左侧事件，再切换配置分类。字段改完离开输入框会自动保存到当前浏览器。</p><table class="help-table"><tr><th>功能</th><th>使用方法</th></tr><tr><td>阶段目标</td><td>一行一个目标；同阶段共用阶段ID。下一阶段留空表示最后阶段。</td></tr><tr><td>条件组</td><td>同组ALL＝且，ANY＝或；先创建条件，再从目标中选择引用。</td></tr><tr><td>结果组</td><td>先创建奖励、天气或完成事件结果，再关联阶段。一次性键不能重复。</td></tr><tr><td>剧情节点</td><td>下一节点选择END表示结束播放。选项节点需在选项分类添加分支。</td></tr><tr><td>地图</td><td>填写实际格子与交互物ID，并将绑定状态改为已绑定。</td></tr><tr><td>保存项目</td><td>完整JSON备份，包含草稿。自动保存不等于文件备份。</td></tr><tr><td>导出Excel</td><td>8张表：字段说明＋7类配置，重新导入可继续编辑。</td></tr><tr><td>Godot JSON</td><td>只导出可发布事件，阻止缺必填项或断引用。需要程序编写配置加载与事件运行器。</td></tr></table><p>血祭日：三项均完成；飞行或快速移动3个、皮毛7个、无手脚1个。献祭与永久血雨都只在祭坛格。分批和每只只计一项是建议。</p><p>内置事件是草稿/待绑定示例。快速移动与格子ID要对接游戏正式数据。工具不执行献祭，也不修改游戏存档。</p>`,[{text:'关闭',primary:true}]);
 const configHelp=$('help').onclick;$('help').onclick=()=>writing?modal('情节写作说明','<p>选择事件后直接编辑概览、地点和每段正文。阶段、选项、条件、奖励均可先用自然语言写，不必填写程序 ID。</p><p>输入实时保存到本机浏览器；“保存情节项目”下载 JSON 备份，“导入”可重新打开。导出 Excel 新增“情节写作”表，结构与新版事件稿一致，也保留旧配置。</p><p>可以添加、复制、删除和调整段落顺序。写作内容不会自动同步为 Godot 配置，待你写完后再整理规范。</p><p>导入新版事件 Excel 会替换当前工作区，请先保存备份。</p>',[{text:'知道了',primary:true}]):configHelp();
 document.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='s'){e.preventDefault();$('save').click();}if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'&&!['INPUT','TEXTAREA'].includes(e.target.tagName)){e.preventDefault();(e.shiftKey?$('redo'):$('undo')).click();}});
 window.addEventListener('beforeunload',e=>{const active=document.activeElement;if(active?.dataset.field)active.dispatchEvent(new Event('change'));});
 render();if(initialWarning)toast(initialWarning);
})();
