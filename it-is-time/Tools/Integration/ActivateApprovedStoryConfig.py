"""Materialize the first-playable configuration approved on 2026-10-19."""
import json
from pathlib import Path
P=Path(__file__).resolve().parents[2]
def load(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,d): p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
proposal=load(P/'Content/Events/Proposals/FirstPlayable20261019.json')
proposal['status']='approved_2026-10-19'
write(P/'Content/Events/Proposals/FirstPlayable20261019.json',proposal)
cfg=load(P/'Content/Events/GrasslandEvents.json')
cfg['approval']='FirstPlayable20261019 approved by user 2026-10-19'
b=cfg['bindings']
for key,r in proposal['rewards'].items():
    b['rewards'][key]={'magic':r.get('magic',0),'runes':r.get('runes',[]),'relics':r.get('relics',[]),**{k:r[k] for k in ['items','monsters'] if k in r}}
b['rewards']['carlod']={'magic':30,'runes':[],'relics':[]}
b['rewards']['wolves']={'magic':30,'runes':[],'relics':[]}
b['rewards']['strong_wolf']={'magic':0,'runes':[],'relics':[],'monsters':[{'id':'reward_two_head_wolf','count':1}]}
b['rewards']['strong_beast']={'magic':0,'runes':[],'relics':[],'monsters':[{'id':'reward_magic_eye_beast','count':1}]}
b.update(attack_threshold=130,engine_max_stage=4,bet_loss_policy='lose_stake',bet_draw_policy='refund_stake_without_round',bet_abort_policy='refund_stake_without_round',approved_failure_rules=True)
b['monster_fields']={k:k for k in ['attack','large','fur','flying','snake','hands','feet']}
world=load(P/'Content/Maps/HexFrontier_20261019/hex_layout.json')
maps=load(P/'Content/Maps/HexFrontier_20261019/hex_battles.json')['maps']
sites={s['id']:s for s in world['sites']}
def nearest(site_id):
    at=sites[site_id]['position']
    s=min((s for s in world['sites'] if s.get('battle_map_id')),key=lambda s:sum((s['position'][i]-at[i])**2 for i in range(2)))
    return s['battle_map_id']
profiles={
 'carlod':{'species':'wolf','hp':.65,'attack':.7},
 'wolf':{'species':'wolf'}, 'rat':{'species':'rat','hp':.7,'attack':.7},
 'bird':{'species':'bird','hp':.8,'attack':.8},
 'scarecrow':{'species':'scarecrow','hp':.75,'attack':.8},
 'giant':{'species':'horned_beast','hp':2,'attack':1.25,'scale':3},
 'magic_eye':{'species':'magic_eye_beast','hp':1.5,'attack':1.2},
 'two_head':{'species':'two_head_wolf','hp':1.5,'attack':1.2},
 'beast':{'species':'horned_beast'},'snake':{'species':'snake'},
 'stump_beast':{'species':'stump_beast'},'spider':{'species':'spider'},
 'reward_two_head_wolf':{'species':'two_head_wolf','hp':1.8,'attack':1.38},
 'reward_magic_eye_beast':{'species':'magic_eye_beast','hp':1.8,'attack':1.38},
 'defense_snake':{'species':'snake','hp':.75,'attack':.8},
 'defense_beast':{'species':'horned_beast','hp':.75,'attack':.8},
}
def battle(key,map_id,roster,other=None):
    b['battles'][key]={'battle_map_id':map_id,'enemy_config_id':'story_'+key,'profiles':roster}
    if other: b['battles'][key]['other_side']={'battle_map_id':map_id,'enemy_config_id':'story_'+key+'_other','profiles':other}
battle('carlod',sites['layout_wolf_den_001']['battle_map_id'],['carlod'])
battle('defense','battle_hex_camp_mv9za92d_38',['defense_snake']*5+['defense_beast']*3)
battle('wolves',nearest('event_stone_tower'),['wolf']*3)
battle('giant',sites['layout_forest_wolf_den_001']['battle_map_id'],['giant'])
battle('rats',nearest('layout_forgotten_mine'),['rat']*4)
battle('scarecrows',nearest('event_diligent_farm'),['scarecrow']*3)
battle('magic_eye',nearest('event_circus'),['magic_eye'])
battle('birds',nearest('event_north_bridge'),['bird']*3)
battle('help_wolf',nearest('layout_forest_cave_001'),['magic_eye','beast','beast'])
battle('help_beast',nearest('layout_forest_cave_001'),['two_head','wolf','wolf'])
battle('watch_wolf_beast',nearest('layout_forest_cave_001'),['magic_eye','beast','beast'],['two_head','wolf','wolf'])
aliases={'elite_two_head_wolf':'two_head','elite_magic_eye_beast':'magic_eye','horned_beast':'beast'}
for i,r in enumerate(proposal['bet']['rosters']):
    target=nearest('event_knight_bet')
    b['bet_rounds'][i]={'stake':[10,20,50,100][i],**{side:{'battle_map_id':target,'enemy_config_id':f'story_bet_{i+1}_{side}','profiles':[aliases.get(s,s) for s in r[side]]} for side in ['one','two']}}
cfg['events'][5]['operations']['battle']['reward']='wolves'
cfg['events'][15]['operations']['away']['next']='available'
write(P/'Content/Events/GrasslandEvents.json',cfg)
write(P/'Content/Events/ApprovedStoryProfiles.json',{'version':1,'profiles':profiles,'items':{'royal-order':{'name':'国王特令','description':'王国特使签发的通行与协助凭证。'}},'clock':proposal['clock'],'blood_rain':proposal['blood_rain'],'defense_site_id':'hex_camp_mv9za92d_38'})
print('APPROVED_STORY_CONFIG_ACTIVATED')
