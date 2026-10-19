(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.HexBattleDeployment=api;})(globalThis,()=>{
  'use strict';
  const mean=points=>points.reduce((s,p)=>[s[0]+p[0]/points.length,s[1]+p[1]/points.length],[0,0]);
  function centers(map,M){
    const slots=map.objects.filter(o=>o.type==='deployment').flatMap(o=>(o.slots||[]).map(p=>M.L.worldPoint(o,p)));
    const enemies=map.objects.filter(o=>o.type==='enemy').flatMap(o=>Array.from({length:o.count||1},()=>o.position));
    return {friendly:slots.length?mean(slots):null,enemy:enemies.length?mean(enemies):null};
  }
  function align(map,M){
    const allies=map.objects.filter(o=>o.type==='deployment'),enemies=map.objects.filter(o=>o.type==='enemy');
    const initial=centers(map,M),cell=map.hex_grid.cell_width;
    if(!initial.friendly)throw Error('战场没有可用的己方部署槽位。');
    const enemyOrigin=initial.enemy||[map.radius*.4,0];
    const offsets=enemies.map(o=>o.position.map((n,i)=>n-enemyOrigin[i]));
    const regions=allies.flatMap(o=>{
      const shape=o.region||{},points=shape.shape==='polygon'?shape.points:shape.shape==='circle'?Array.from({length:16},(_,i)=>[Math.cos(i*Math.PI/8)*shape.size[0]/2,Math.sin(i*Math.PI/8)*shape.size[1]/2]):[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]].map(p=>p.map((n,i)=>n*shape.size[i]));
      const angle=(shape.rotation||0)*Math.PI/180,off=shape.offset||[0,0];
      const local=points.map(([x,y])=>[x*Math.cos(angle)-y*Math.sin(angle)+off[0],x*Math.sin(angle)+y*Math.cos(angle)+off[1]]);
      // Include the interior so a deployment area cannot straddle a rock or pit.
      const min=local.reduce((v,p)=>v.map((n,i)=>Math.min(n,p[i])),[Infinity,Infinity]);
      const max=local.reduce((v,p)=>v.map((n,i)=>Math.max(n,p[i])),[-Infinity,-Infinity]);
      for(let x=min[0];x<=max[0];x+=cell*.35)for(let z=min[1];z<=max[1];z+=cell*.35)if(M.L.shapeContains(shape,[x,z]))local.push([x,z]);
      return local.concat(o.slots||[]).map(p=>M.L.worldPoint(o,p));
    });
    const hazards=map.objects.filter(o=>['mud','web','thorns'].includes(o.type)&&o.region?.enabled!==false);
    const safe=p=>M.inside(map,p)&&!M.blocked(map,p)&&!hazards.some(o=>M.contains(map,o,p,true));
    const nearBoundary=p=>[0,90,180,270].every(deg=>M.inside(map,[p[0]+Math.cos(deg*Math.PI/180)*cell*.3,p[1]+Math.sin(deg*Math.PI/180)*cell*.3]));
    const rows=[0];for(let z=cell*.5;z<=map.radius*.5;z+=cell*.5)rows.push(z,-z);
    const xs=[.46,.38,.54,.30,.62,.22].map(f=>map.radius*f);
    let result=null;
    for(const z of rows){
      for(const ax of xs){
        const friendly=[-ax,z],delta=friendly.map((n,i)=>n-initial.friendly[i]);
        const samples=regions.map(p=>p.map((n,i)=>n+delta[i]));
        if(!samples.every(safe)||!samples.every(nearBoundary))continue;
        const slots=allies.flatMap(o=>o.slots.map(p=>M.L.worldPoint(o,p).map((n,i)=>n+delta[i])));
        for(const ex of xs){
          const enemy=[ex,z],positions=offsets.map(p=>p.map((n,i)=>n+enemy[i]));
          if(!positions.length)positions.push(enemy);
          if(!positions.every(safe)||!positions.every(nearBoundary))continue;
          if(positions.some(p=>slots.some(s=>Math.hypot(p[0]-s[0],p[1]-s[1])<cell*2.5)))continue;
          if(positions.some(p=>allies.some(o=>M.contains(map,{...o,position:o.position.map((n,i)=>n+delta[i])},p,true))))continue;
          result={friendly,enemy,delta,positions};break;
        }
        if(result)break;
      }
      if(result)break;
    }
    if(!result)throw Error('没有找到同水平且不与障碍或陷阱重叠的双方部署区，请先留出部署空间。');
    for(const o of allies){o.position=o.position.map((n,i)=>n+result.delta[i]);o.facing=0;}
    for(const [i,o] of enemies.entries()){o.position=result.positions[i];o.facing=180;}
    map.deployment_layout={version:1,axis:'x',center_z:result.friendly[1],friendly_center:result.friendly,enemy_center:result.enemy,enemy_reserved:!enemies.length};
    return map.deployment_layout;
  }
  return {align,centers};
});
