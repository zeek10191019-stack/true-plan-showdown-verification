#!/usr/bin/env python3
import copy
import json
from pathlib import Path
from r651_asset_guard import verify

root=Path(__file__).resolve().parent
D=json.loads((root/'R651_MEGA_CHAMPIONS_ASSET_INDEX.json').read_text())
R=json.loads((root/'mega_m_c_81_registry.json').read_text())
assert verify(D,R)

def rejected(change):
    x=copy.deepcopy(D)
    change(x)
    try:verify(x,R)
    except AssertionError:return True
    raise AssertionError('MUTATION_WAS_ACCEPTED')

changes=[
  lambda x: x['forms'].pop(),
  lambda x: x['forms'][0].update(form_id='made-up-mega'),
  lambda x: x['forms'][1].update(form_id=x['forms'][2]['form_id']),
  lambda x: x['forms'][1].update(variant='Y'),
  lambda x: x['forms'][0]['visual_classes'][0].update(pokeapi_pokemon_id=10034),
  lambda x: x['forms'][0]['visual_classes'][0]['assets']['front'].update(verified_present=False),
  lambda x: x['forms'][0]['visual_classes'][0]['assets']['front'].update(url='https://example.org/image'),
  lambda x: x['forms'][0].update(mega_identification_certified=True),
  lambda x: x['forms'][0].update(champions_gameplay_verified=True),
  lambda x: x['rights'].update(licenses_for_public_dataset='LICENSED'),
  lambda x: x['interpretation'].update(allowed_as_certification_evidence=True),
  lambda x: x['counts'].update(separately_verified_in_game_battle_frames=1),
  lambda x: x['forms'][53].update(visual_classes=x['forms'][53]['visual_classes'][:1]),
  lambda x: x['gender_edge_case'].update(female_pokemon_id=10314),
  lambda x: x['source_snapshots']['champions_sprite_index'].update(commit='main'),
  lambda x: x.update(base_species_not_present_by_simple_id=[]),
  lambda x: x['forms'][0]['visual_classes'][0]['assets']['back_shiny'].update(binary_retrieved=True),
  lambda x: x['forms'][0]['visual_classes'][0]['assets']['icon'].update(relative_path='../../x.png'),
]
for c in changes: assert rejected(c)
print('R651_FAIL_CLOSED_MUTATIONS_PASS',len(changes))
