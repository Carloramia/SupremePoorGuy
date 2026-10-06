(function(root){
 'use strict';
 const f=(key,label,type='string',extra={})=>({key,label,type,...extra});
 const id=f('id','记录 ID','string',{required:true,tip:'自动生成；修改后会同步已知引用。不要使用空格或中文。'});
 const owner=f('event_id','所属事件','string',{required:true,ref:'events'});
 const choice=(key,label,values,extra={})=>f(key,label,'string',{enum:values,...extra});
 const ref=(key,label,table,extra={})=>f(key,label,'string',{ref:table,...extra});
 const S={
 events:{label:'事件总览',prefix:'EVENT',note:'设置事件入口和流程。未配置完整时保留为草稿。',fields:[
 id,f('name','事件名','string',{required:true}),choice('category','类别',['主线','支线','教学']),f('summary','概览','text'),choice('trigger','触发类型',['新游戏','交互','进入小地图','接近地点','战斗结算','召唤完成','前置完成']),f('entry','入口 ID','string',{tip:'NPC或交互物的正式ID；不是地点的显示名称。'}),ref('condition_group','开放条件组','condition_groups'),choice('accept','接取方式',['自动','确认']),ref('initial_stage','初始阶段','stage_groups'),ref('start_node','起始节点','nodes'),choice('repeat','重复规则',['一次性','可重复']),choice('time_rule','时间规则',['暂停探索','不暂停']),ref('result_group','完成结果组','action_groups'),choice('status','发布状态',['草稿','待绑定','可发布','禁用']),f('source_reward','原稿奖励说明','text'),f('source_effect','原稿效果说明','text'),f('source_assets','原稿美术需求','text')
 ]},
 goals:{label:'阶段目标',prefix:'OBJ',note:'一行一个目标。同阶段 ALL 表示所有目标均需达成。',fields:[
 id,owner,f('stage_id','阶段 ID','string',{required:true,tip:'同一阶段多个目标填写同一个阶段ID。'}),f('stage_order','阶段序号','int',{min:1,default:1}),f('description','玩家目标','text',{required:true}),choice('type','目标类型',['交互完成','战斗胜利','探索发现','召唤成功','献祭','回报','拥有物品']),f('target','目标对象'),f('quantity','需求数量','int',{min:1,default:1}),ref('monster_condition','怪物条件组','condition_groups'),ref('location_condition','地点条件组','condition_groups'),choice('completion','完成关系',['ALL','ANY'],{tip:'ALL＝全部，ANY＝任一。同阶段各行要一致。'}),ref('next_stage','下一阶段','stage_groups'),ref('result_group','阶段完成结果组','action_groups'),f('submit_rule','提交规则','text'),ref('submit_condition','提交前置条件组','condition_groups')
 ]},
 nodes:{label:'剧情节点',prefix:'D',note:'按下一节点连接，不依靠行号。END结束播放，不代表完成事件。',fields:[
 id,owner,ref('stage_id','所属阶段','stage_groups'),choice('type','节点类型',['对话','旁白','笔记','交互','选项','结果']),f('speaker','说话者 ID'),f('text','正文','text'),f('portrait','立绘资源'),f('interaction','交互目标'),ref('result_group','执行结果组','action_groups'),ref('next_node','下一节点','nodes',{special:['END']}),f('note','备注','text')
 ]},
 choices:{label:'选项',prefix:'CHOICE',note:'只有真实需要玩家选择时才添加；不可逆选择需要二次确认。',fields:[
 id,ref('node_id','所属节点','nodes',{required:true}),f('text','选项文本','text',{required:true}),ref('visible_condition','显示条件组','condition_groups'),ref('enabled_condition','可选条件组','condition_groups'),f('disabled_hint','不可选提示','text'),ref('result_group','执行结果组','action_groups'),ref('target_node','目标节点','nodes',{special:['END']}),choice('confirm','需要确认',['是','否']),f('confirm_text','确认提示','text'),owner
 ]},
 conditions:{label:'条件',prefix:'COND',note:'把一句条件拆成字段、比较关系和数值。ANY＝或，ALL＝且。',fields:[
 id,f('group_id','条件组 ID','string',{required:true}),choice('relation','组关系',['ALL','ANY']),choice('object','读取对象',['map_context','candidate_monster','event_state','objective_state','inventory','world_state'],{tip:'candidate_monster＝当前候选怪物；map_context＝地图上下文。'}),f('field','对象字段','string',{required:true,tip:'例如 has_flying、has_fur、hand_component_count。快速移动需正式能力标记。'}),choice('operator','比较关系',['EQ','NE','GT','GTE','LT','LTE','HAS'],{tip:'EQ等于，NE不等于，GT大于，GTE大于等于，LT小于，LTE小于等于，HAS包含。'}),f('value','比较值','value',{tip:'按下面的数据类型填写。布尔类型只接受 true / false。'}),choice('value_type','数据类型',['ID','TEXT','NUMBER','BOOL']),f('scope','作用范围'),f('note','说明','text'),owner
 ]},
 actions:{label:'结果',prefix:'ACTION',note:'奖励、任务完成和世界变化是不同结果。同组只提交一次。',fields:[
 id,f('group_id','结果组 ID','string',{required:true}),choice('type','类型',['增加魔力','扣除魔力','给予奇物','给予物品','解锁符文','开放事件','完成事件','设置标记','设置天气']),f('target','目标 ID','string',{required:true}),f('value','数值或状态','value'),choice('value_type','数据类型',['ID','TEXT','NUMBER','BOOL']),choice('timing','触发时机',['节点确认','阶段完成','事件完成']),ref('condition_group','执行条件组','condition_groups'),f('scope','作用范围','string',{tip:'血祭天气必须填写祭坛格子ID，不填地区ID。'}),choice('duration','持续规则',['永久','限时','本次交互']),f('once_key','一次性键','string',{required:true,tip:'每条结果独立且唯一，用于防止重复领奖。'}),f('note','备注','text'),owner
 ]},
 maps:{label:'地图绑定',prefix:'MAP',note:'地区、格子、地点、交互物是不同ID。未绑定的示例不能直接发布。',fields:[
 id,owner,f('region_id','地区 ID'),f('cell_id','格子 ID','string',{required:true}),f('location_id','地点 ID'),f('interaction_id','交互物 ID','string',{required:true}),f('name','显示名'),ref('first_node','首次入口节点','nodes'),ref('active_node','进行中入口节点','nodes'),f('completed_text','完成后回应','text'),f('change_scope','地图变化范围'),choice('status','绑定状态',['待绑定','已绑定'])
 ]}
 };
 root.EventSchema=S;
 if(typeof module!=='undefined')module.exports=S;
})(globalThis);
