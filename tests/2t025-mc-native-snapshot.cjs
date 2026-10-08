
'use strict';
// PUBLIC-ONLY: pinned smogon/pokemon-showdown M-C native snapshot/future RNG probe.
// No private AI, DB, training corpus, logs, user account, or secrets are used.
// Running this proves ONLY this public Showdown commit's simulator behaviour.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const path = require('node:path');
const showdownRoot = process.env.SHOWDOWN_ROOT || process.cwd();
const {Battle, Dex, PRNG, Teams} = require(path.join(showdownRoot, 'dist/sim'));

const FORMAT = '[Gen 9 Champions] BSS Reg M-C';
const PIN = 'aa17ca0fac8bc5605df673bd8774c2d0e91efa43';
const format = Dex.formats.get(FORMAT);
assert(format.exists && format.mod === 'champions', 'Required M-C format/mod absent');
const sha = value => crypto.createHash('sha256').update(typeof value === 'string' ? value : JSON.stringify(value)).digest('hex');
const teamOne = [
  {name:'Garchomp',species:'Garchomp',ability:'Rough Skin',item:'Sitrus Berry',level:50,moves:['Earthquake','Dragon Claw','Protect','Swords Dance']},
  {name:'Mimikyu',species:'Mimikyu',ability:'Disguise',item:'Life Orb',level:50,moves:['Play Rough','Shadow Claw','Protect','Swords Dance']},
  {name:'Archaludon',species:'Archaludon',ability:'Sturdy',item:'White Herb',level:50,moves:['Flash Cannon','Dragon Pulse','Thunderbolt','Protect']},
];
const teamTwo = [
  {name:'Sylveon',species:'Sylveon',ability:'Pixilate',item:'Leftovers',level:50,moves:['Moonblast','Hyper Voice','Protect','Quick Attack']},
  {name:'Gyarados',species:'Gyarados',ability:'Intimidate',item:'Lum Berry',level:50,moves:['Waterfall','Crunch','Protect','Dragon Dance']},
  {name:'Delphox',species:'Delphox',ability:'Blaze',item:'Choice Scarf',level:50,moves:['Flamethrower','Psychic','Shadow Ball','Grass Knot']},
];

const battle = new Battle({formatid:format.id, seed:'123,456,789,101112',strictChoices:true});
battle.setPlayer('p1',{name:'PublicA',team:Teams.pack(teamOne)});
battle.setPlayer('p2',{name:'PublicB',team:Teams.pack(teamTwo)});
if (battle.requestState === 'teampreview') {
  assert.equal(battle.choose('p1','team 123'),true,'P1 3v3 selection failed');
  assert.equal(battle.choose('p2','team 123'),true,'P2 3v3 selection failed');
  console.log('PASS MC_THREE_V_THREE_TEAM_PREVIEW');
}
assert.equal(battle.requestState,'move','Test must snapshot immediately before a legal move turn');

// Full simulator snapshot must never be exposed to the AI observation API.
const frozenJSON = JSON.stringify(battle.toJSON());
const frozenDigest = sha(frozenJSON);
const inputPrefix = [...battle.inputLog];
const logPrefix = [...battle.log];
assert(inputPrefix.length > 0 && logPrefix.length > 0);
const restore = () => Battle.fromJSON(frozenJSON);
const a = restore();
const b = restore();
assert.equal(JSON.stringify(a.toJSON()),frozenJSON,'Snapshot A roundtrip drift');
assert.equal(JSON.stringify(b.toJSON()),frozenJSON,'Snapshot B roundtrip drift');
console.log('PASS SNAPSHOT_ROUNDTRIP',frozenDigest);

function prefixInvariant(branch) {
  assert.deepEqual(branch.log.slice(0,logPrefix.length),logPrefix,'Observed battle protocol mutated');
  assert.deepEqual(branch.inputLog.slice(0,inputPrefix.length),inputPrefix,'Observed choices mutated');
  assert.equal(JSON.stringify(battle.toJSON()),frozenJSON,'Original live battle was mutated');
  assert.equal(sha(frozenJSON),frozenDigest,'Frozen snapshot bytes mutated');
}
function future(seed, moves=['move 1','move 1']) {
  const clone=restore();
  prefixInvariant(clone);
  clone.prng=new PRNG(seed);
  assert.equal(clone.choose('p1',moves[0]),true,'P1 illegal choice');
  assert.equal(clone.choose('p2',moves[1]),true,'P2 illegal choice');
  prefixInvariant(clone);
  return {state:JSON.stringify(clone.toJSON()),
    futureLog:clone.log.slice(logPrefix.length),
    hp:clone.sides.map(side=>side.active.map(mon=>mon ? mon.hp : null))};
}

const first=future('11,22,33,44');
const second=future('11,22,33,44');
assert.deepEqual(first,second,'Same snapshot + future seed must produce identical outcomes');
console.log('PASS IDENTICAL_FUTURE_SEED');

const signatures = new Set();
for(let i=1;i<=64;i++) {
  const f=future(`${i*1009},${i*1367},${i*7919},${i*104729}`);
  signatures.add(JSON.stringify({log:f.futureLog,hp:f.hp}));
}
assert(signatures.size > 1,'64 distinct future seeds failed to branch at observed state');
console.log('PASS FUTURE_SEED_DIVERGENCE','unique_outcomes='+signatures.size);

const switched=future('5,6,7,8',['switch 2','move 1']);
const switchClone=restore();
switchClone.prng=new PRNG('5,6,7,8');
assert.equal(switchClone.choose('p1','switch 2'),true);
assert.equal(switchClone.choose('p2','move 1'),true);
assert.equal(switchClone.sides[0].active[0].species.name,'Mimikyu');
assert.deepEqual(switched.state,JSON.stringify(switchClone.toJSON()));
prefixInvariant(switchClone);
assert.equal(JSON.stringify(b.toJSON()),frozenJSON,'Sibling clone mutated by separate branch');
console.log('PASS LEGAL_SWITCH_CLONE_ISOLATION');
console.log('PASS OBSERVED_PREFIX_IMMUTABLE');
console.log('T025_PUBLIC_PINNED_MC_SNAPSHOT_SMOKE_PASS commit='+PIN);
console.log('NOT_CERTIFIED: no in-game M-C parity; no Native33/Exact34 progress; no private AI provider binding');
