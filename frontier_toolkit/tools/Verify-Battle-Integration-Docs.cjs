// Validates this documentation's proposed contracts and local source/link references.
// Implements only the JSON Schema keywords used by the two shipped schemas.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const base = path.join(root, 'docs/battle_integration');
const read = p => JSON.parse(fs.readFileSync(path.join(base,p),'utf8'));
const requestSchema = read('schemas/battle_request.schema.json');
const resultSchema = read('schemas/battle_result.schema.json');
const request = read('examples/battle_request.json');
const result = read('examples/battle_result.json');
const clone = x => JSON.parse(JSON.stringify(x));
const keywords = new Set(['$schema','$defs','$ref','title','type','const','enum','required','properties','additionalProperties','items','minItems','maxItems','minimum','maximum','exclusiveMinimum','minLength','maxLength','pattern']);
function supported(schema) {
  for (const key of Object.keys(schema)) if (!keywords.has(key)) throw new Error(`Unsupported schema keyword: ${key}`);
  for (const group of ['$defs','properties']) for (const child of Object.values(schema[group] || {})) supported(child);
  if (schema.items) supported(schema.items);
}
supported(requestSchema); supported(resultSchema);
function validate(schema, value, top = schema, at = '$', errors = []) {
  if (schema.$ref) {
    if (!schema.$ref.startsWith('#/')) throw new Error('Only local JSON pointers are supported');
    const target = schema.$ref.slice(2).split('/').reduce((s,k)=>s[k.replaceAll('~1','/').replaceAll('~0','~')],top);
    if (!target) throw new Error(`Unresolved ref: ${schema.$ref}`);
    return validate(target,value,top,at,errors);
  }
  const typeOK = {object:value !== null && typeof value === 'object' && !Array.isArray(value), array:Array.isArray(value), string:typeof value === 'string', number:typeof value === 'number' && Number.isFinite(value), integer:Number.isSafeInteger(value), boolean:typeof value === 'boolean'};
  if (schema.type && !typeOK[schema.type]) { errors.push(`${at}: expected ${schema.type}`); return errors; }
  if ('const' in schema && value !== schema.const) errors.push(`${at}: const mismatch`);
  if (schema.enum && !schema.enum.includes(value)) errors.push(`${at}: enum mismatch`);
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) errors.push(`${at}: nonfinite`);
    if ('minimum' in schema && value < schema.minimum) errors.push(`${at}: below minimum`);
    if ('maximum' in schema && value > schema.maximum) errors.push(`${at}: above maximum`);
    if ('exclusiveMinimum' in schema && value <= schema.exclusiveMinimum) errors.push(`${at}: must exceed minimum`);
  }
  if (typeof value === 'string') {
    if (schema.minLength && [...value].length < schema.minLength) errors.push(`${at}: too short`);
    if (schema.maxLength && [...value].length > schema.maxLength) errors.push(`${at}: too long`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) errors.push(`${at}: invalid pattern`);
  }
  if (Array.isArray(value)) {
    if (schema.minItems && value.length < schema.minItems) errors.push(`${at}: too few items`);
    if (schema.maxItems && value.length > schema.maxItems) errors.push(`${at}: too many items`);
    if (schema.items) value.forEach((v,i)=>validate(schema.items,v,top,`${at}[${i}]`,errors));
  }
  if (schema.type === 'object') {
    for (const k of schema.required || []) if (!Object.hasOwn(value,k)) errors.push(`${at}.${k}: required`);
    for (const [k,v] of Object.entries(value)) {
      if (schema.properties?.[k]) validate(schema.properties[k],v,top,`${at}.${k}`,errors);
      else if (schema.additionalProperties === false) errors.push(`${at}.${k}: unexpected property`);
    }
  }
  return errors;
}
function unique(values, label, errors) { if (new Set(values).size !== values.length) errors.push(`${label}: duplicate`); }
function checkRequest(r) {
  const errors = validate(requestSchema,r);
  if (errors.length) return errors;
  if (r.return_context.location_id !== r.location_id) errors.push('Return location mismatch');
  unique(r.party.map(u=>u.monster_id),'monster_id',errors);
  unique([...r.party,...r.waves.flatMap(w=>w.enemies)].map(u=>u.actor_id),'actor_id',errors);
  unique(r.waves.map(w=>w.wave_id),'wave_id',errors);
  const groups = new Map(), tinyBatches = new Map(), groupSizes = new Map();
  for (const u of r.party) {
    const expected = u.mode === 'giant' ? 2 : u.mode === 'ultra' ? 5 : 1;
    if (u.slot_cost !== expected) errors.push(`Slot cost mismatch: ${u.monster_id}`);
    if (u.mode === 'tiny' && u.recoverable) errors.push('Tiny recoverable mismatch');
    groupSizes.set(u.slot_group,(groupSizes.get(u.slot_group)||0)+1);
    if (u.mode === 'tiny') {
      if (tinyBatches.has(u.batch_id) && tinyBatches.get(u.batch_id) !== u.slot_group) errors.push('Tiny batch split across groups');
      tinyBatches.set(u.batch_id,u.slot_group);
      if (groupSizes.get(u.slot_group) > 5) errors.push('Tiny batch exceeds five members');
    }
    if (groups.has(u.slot_group)) {
      const first = groups.get(u.slot_group);
      if (u.mode !== 'tiny' || first.mode !== 'tiny' || first.batch_id !== u.batch_id || first.slot_cost !== u.slot_cost) errors.push('Invalid shared slot group');
    } else groups.set(u.slot_group,u);
  }
  if ([...groups.values()].reduce((sum,u)=>sum+u.slot_cost,0) > r.party_slots_limit) errors.push('Party slot overflow');
  const factions = new Set(r.party.map(u=>u.faction_id));
  if (factions.size !== 1) errors.push('MVP party must share one faction');
  r.waves.forEach((w,i) => {
    if (w.trigger !== (i === 0 ? 'on_start' : 'after_previous')) errors.push('Wave trigger order');
    for (const e of w.enemies) if (factions.has(e.faction_id)) errors.push('Enemy shares allied faction');
  });
  return errors;
}
function checkResult(r,q) {
  const errors = validate(resultSchema,r);
  if (errors.length) return errors;
  for (const k of ['battle_id','map_id','location_id','party_revision','health_policy']) if (r[k] !== q[k]) errors.push(`Request/result mismatch: ${k}`);
  unique(r.unit_results.map(u=>u.monster_id),'result monster_id',errors);
  unique(r.unit_results.map(u=>u.actor_id),'result actor_id',errors);
  if (r.unit_results.length !== q.party.length) errors.push('Result roster count mismatch');
  for (const u of r.unit_results) {
    if (!q.party.some(p=>p.monster_id === u.monster_id && p.actor_id === u.actor_id)) errors.push('Result roster member mismatch');
    unique(u.parts.map(p=>p.part_key),'part_key',errors);
    if (u.status !== 'unspawned' && !u.parts.length) errors.push('Spawned unit has no parts');
    if (u.status === 'unspawned' && u.parts.length) errors.push('Unspawned unit has parts');
    if (u.status === 'unspawned' && !['canceled','error'].includes(r.outcome)) errors.push('Unspawned unit in completed gameplay');
    for (const p of u.parts) if (p.current_hp > p.max_hp || (p.broken && p.current_hp !== 0)) errors.push('Invalid part HP/broken relationship');
  }
  unique(r.rewards.items.map(i=>i.item_id),'reward item_id',errors);
  if (r.outcome !== 'victory' && (r.rewards.magic !== 0 || r.rewards.items.length)) errors.push('MVP nonvictory reward forbidden');
  const expectedEnemies = q.waves.reduce((sum,w)=>sum+w.enemies.length,0);
  if (r.metrics.enemy_defeated > expectedEnemies) errors.push('Enemy metrics overflow');
  if (r.outcome === 'victory' && r.metrics.enemy_defeated !== expectedEnemies) errors.push('Victory before all enemies defeated');
  if (r.metrics.ally_disabled !== r.unit_results.filter(u=>u.status === 'dead').length) errors.push('Ally disabled metrics mismatch');
  return errors;
}
const errors = [...checkRequest(request),...checkResult(result,request)];
let cases = 2;
function probe(name, mutation, target = 'request', expectedValid = false) {
  const q=clone(request), r=clone(result); mutation(q,r);
  const found = target === 'request' ? checkRequest(q) : checkResult(r,q);
  if ((found.length === 0) !== expectedValid) errors.push(`Probe failed: ${name}: ${found.join('; ')}`);
  cases++;
}
probe('duplicate actor',(q)=>q.waves[0].enemies[0].actor_id=q.party[0].actor_id);
probe('empty enemies',(q)=>q.waves[0].enemies=[]);
probe('bad version',(q)=>q.schema_version=99);
probe('fractional revision',(q)=>q.party_revision=1.5);
probe('unexpected field',(q)=>q.node_path='res://test');
probe('faction collision',(q)=>q.waves[0].enemies[0].faction_id=1);
probe('return mismatch',(q)=>q.return_context.location_id='other');
probe('wrong slot cost',(q)=>q.party[0].mode='ultra');
probe('nonfinite stats',(q)=>q.party[0].stat_profile.hp=Infinity);
probe('slot overflow',(q)=>{ q.party[0].mode='ultra'; q.party[0].slot_cost=5; const u=clone(q.party[0]); u.actor_id='ally-2'; u.monster_id='summon_2'; u.slot_group='g2'; q.party.push(u); });
probe('tiny shared group',(q)=>{ const u=q.party[0]; u.mode='tiny'; u.recoverable=false; const v=clone(u); v.monster_id='tiny-2'; v.actor_id='ally-2'; q.party.push(v); },'request',true);
probe('tiny mixed batch',(q)=>{ const u=q.party[0]; u.mode='tiny'; u.recoverable=false; const v=clone(u); v.monster_id='tiny-2'; v.actor_id='ally-2'; v.batch_id='batch_2'; q.party.push(v); });
probe('tiny split batch',(q)=>{ const u=q.party[0]; u.mode='tiny'; u.recoverable=false; const v=clone(u); v.monster_id='tiny-2'; v.actor_id='ally-2'; v.slot_group='second-group'; q.party.push(v); });
probe('mixed allied faction',(q)=>{ const v=clone(q.party[0]); v.monster_id='ally-2'; v.actor_id='ally-2'; v.slot_group='group-2'; v.faction_id=3; q.party.push(v); });
probe('wrong battle',(q,r)=>r.battle_id='other','result');
probe('result revision conflict',(q,r)=>r.party_revision++,'result');
probe('duplicate result',(q,r)=>r.unit_results.push(clone(r.unit_results[0])),'result');
probe('broken positive hp',(q,r)=>r.unit_results[0].parts[2].current_hp=1,'result');
probe('hp overflow',(q,r)=>r.unit_results[0].parts[0].current_hp=999,'result');
probe('defeat rewards',(q,r)=>r.outcome='defeat','result');
probe('premature victory',(q,r)=>r.metrics.enemy_defeated=0,'result');
probe('unspawned error',(q,r)=>{ r.outcome='error'; r.rewards.magic=0; r.metrics.enemy_defeated=0; r.unit_results[0].status='unspawned'; r.unit_results[0].parts=[]; },'result',true);
probe('unspawned victory',(q,r)=>{ r.unit_results[0].status='unspawned'; r.unit_results[0].parts=[]; },'result');

const docs = [path.join(root,'docs/BATTLE_INTEGRATION_GUIDE.md'),...fs.readdirSync(base).filter(p=>p.endsWith('.md')).map(p=>path.join(base,p))];
let links = 0;
for (const file of docs) for (const m of fs.readFileSync(file,'utf8').matchAll(/\[[^\]\n]+\]\(([^)]+)\)/g)) {
  const url=m[1]; if (/^(https?:|#)/.test(url)) continue;
  const target=path.resolve(path.dirname(file),decodeURIComponent(url.split('#')[0]));
  links++;
  if (!fs.existsSync(target)) errors.push(`Missing documentation link: ${path.relative(root,file)} -> ${url}`);
}
const index=read('SOURCE_INDEX.json');
let sources=0, unavailable=0;
for (const entry of process.argv.includes('--contracts-only') ? [] : index.entries) {
  const file=path.join(root,entry.workspace_path);
  if (!fs.existsSync(file)) { unavailable++; continue; }
  sources++;
  if (crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') !== entry.sha256) errors.push(`Source drift: ${entry.path}; rebuild and review index`);
}
if (errors.length) { console.error(errors.join('\n')); process.exitCode=1; }
else console.log(`Battle integration docs OK: ${cases} contract checks; ${links} local links; ${sources} source hashes checked; ${unavailable} sources unavailable.${process.argv.includes('--contracts-only') ? ' Historical source hashes intentionally skipped (contracts-only).' : ''} Runtime combat is not exercised.`);
