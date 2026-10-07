(function(root){
 'use strict';
 const columns=[['stage','阶段 / 触发条件'],['speaker','对话对象 / 类型'],['text','情节正文'],['reward','奖励'],['effect','效果'],['assets','需要内容 / 备注']];
 function clean(raw){const result={};if(!raw)return result;if(typeof raw!=='object'||Array.isArray(raw))throw Error('情节草稿格式错误');for(const [id,rows]of Object.entries(raw)){if(!Array.isArray(rows)||rows.length>5000)throw Error('情节段落过多');result[id]=rows.map(row=>Object.fromEntries(columns.map(([key])=>{const value=row[key]??'';if(typeof value!=='string'||value.length>100000)throw Error('情节字段必须是文本，且不超过10万字');return [key,value];})));}return result;}
 function get(project,id){if(project.stories?.[id])return project.stories[id];const e=project.tables.events.find(e=>e.id===id);const nodes=project.tables.nodes.filter(n=>n.event_id===id);return nodes.length?nodes.map((n,i)=>({stage:n.stage_id||'',speaker:n.speaker||n.type||'',text:n.text||'',reward:i===0?e.source_reward||'':'',effect:i===0?e.source_effect||'':'',assets:[i===0?e.source_assets:'',n.note].filter(Boolean).join('\n')})):[{stage:e.time_rule||e.trigger||'',speaker:'',text:'',reward:e.source_reward||'',effect:e.source_effect||'',assets:e.source_assets||''}];}
 function ensure(project,id){project.stories??={};return project.stories[id]??=get(project,id);}
 function sheet(project){const rows=[['事件名','概览','地点','所处阶段','对话对象','内容','奖励','效果','需要内容']];for(const e of project.tables.events){const paragraphs=get(project,e.id);(paragraphs.length?paragraphs:[{}]).forEach((r,i)=>rows.push([i?'':e.name,i?'':e.summary,i?'':e.entry,...columns.map(([k])=>r[k]||'')]));rows.push([]);}return {name:'情节写作',rows};}
 root.EventStory={columns,clean,get,ensure,sheet};if(typeof module!=='undefined')module.exports=root.EventStory;
})(globalThis);
