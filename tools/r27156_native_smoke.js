
// R27.156 - public/synthetic pinned Showdown community simulator probe.
// NOT Pokemon Champions official mechanics certification.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const repo = fs.realpathSync(process.argv[2] || 'pokemon-showdown');
const {Battle} = require(path.join(repo, 'dist/sim/battle.js'));
const {Teams} = require(path.join(repo, 'dist/sim/teams.js'));
const {Dex} = require(path.join(repo, 'dist/sim/index.js'));

const format = Dex.formats.get('[Gen 9 Champions] BSS Reg M-C');
assert.ok(format.exists && format.mod === 'champions', 'CHAMPIONS_MC_FORMAT_MISSING');

const PIN = 'aa17ca0fac8bc5605df673bd8774c2d0e91efa43';

const mkTeam = () => [
  {
    name:'Garchomp',
    species:'Garchomp',
    item:'',
    ability:'Rough Skin',
    moves:['Protect','Earthquake','Dragon Claw','Rock Slide'],
    nature:'Jolly',
    level:50,
    evs:{hp:0,atk:252,def:0,spa:0,spd:0,spe:252}
  },
  {
    name:'Sylveon',
    species:'Sylveon',
    item:'',
    ability:'Pixilate',
    moves:['Hyper Voice','Protect','Wish','Quick Attack'],
    nature:'Modest',
    level:50,
    evs:{hp:252,atk:0,def:0,spa:252,spd:0,spe:4}
  },
  {
    name:'Gyarados',
    species:'Gyarados',
    item:'',
    ability:'Intimidate',
    moves:['Waterfall','Protect','Dragon Dance','Crunch'],
    nature:'Jolly',
    level:50,
    evs:{hp:4,atk:252,def:0,spa:0,spd:0,spe:252}
  }
];

const runSeed = (seed) => {
  const battle = new Battle({formatid:format.id, seed, send:()=>{}});
  for (const side of ['p1','p2']) {
    battle.setPlayer(side,{name:side,team:Teams.pack(mkTeam())});
  }

  if (battle.requestState === 'teampreview' || battle.sides[0].activeRequest?.teamPreview) {
    assert.equal(battle.choose('p1','team 123'),true,'P1_TEAM_PREVIEW_REJECTED');
    assert.equal(battle.choose('p2','team 123'),true,'P2_TEAM_PREVIEW_REJECTED');
  }

  for (let i=0;i<3 && !battle.ended;i++) {
    assert.equal(battle.choose('p1','move 1'),true,'P1_MOVE_REJECTED');
    assert.equal(battle.choose('p2','move 1'),true,'P2_MOVE_REJECTED');
  }

  const log = battle.log.join('\n');
  const lines = log.split('\n');
  const turns = lines.filter(x=>x.startsWith('|turn|')).map(x=>Number(x.slice(6)));
  const moves = lines.filter(x=>x.startsWith('|move|')).length;

  assert.ok(turns.length >= 1 && turns[0] === 1, 'NO_VALID_TURN');
  assert.ok(turns.every((x,i)=>i===0 || x > turns[i-1]), 'NONMONOTONIC_TURNS');
  assert.ok(moves >= 1 && !lines.some(x=>x.startsWith('|error|')), 'NO_VALID_MOVES');

  return {
    seed,
    turns,
    moves,
    log_sha256:crypto.createHash('sha256').update(log).digest('hex'),
    battle_log:log
  };
};

const payload={
  schema:'R27156_PINNED_SHOWDOWN_TRANSITION_V1',
  pinned_commit:PIN,
  community_simulator_only:true,
  actual_champions_engine:false,
  source_build_equivalence_certified:false,
  official_champions_parity:false,
  native33:'0/33',
  exact34:'0/34',
  field:'0/30',
  formal:'DENY',
  scenario_exact_9_executed:0,
  engine_format:format.id,
  node_version:process.version,
  runs:[
    runSeed([1234,5678,9012,3456]),
    runSeed([444,555,666,777])
  ]
};

process.stdout.write(JSON.stringify(payload)+'\n');
