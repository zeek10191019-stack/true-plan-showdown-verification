#!/usr/bin/env python3
"""Offline fail-closed audit of source-pinned asset PRESENCE metadata.
No image retrieval, training, or live-game form certification.
"""
from pathlib import Path
import json
import re
import sys

HERE = Path(__file__).resolve().parent
SOURCE = '1dd55c0436d2a5b6e324c0b780e1b1b416fbfb64'
PARENT = '7601b4874e1ff1e31e8c405e43d46ec8de4abe39'
KIND = {
    'front': ('', '.webp'),
    'back': ('back/', '.webp'),
    'front_shiny': ('shiny/', '.webp'),
    'back_shiny': ('back/shiny/', '.webp'),
    'icon': ('icons/', '.png'),
    'icon_shiny': ('icons/shiny/', '.png'),
}
PREFIX = 'sprites/pokemon/versions/generation-ix/champions/'
URL = 'https://raw.githubusercontent.com/PokeAPI/sprites/' + SOURCE + '/'


def verify(index, official):
    assert index['schema'] == 'trueplan.r651.champions-mega-asset-presence.v1'
    assert index['parent_commit'] == PARENT
    assert index['source_snapshots']['champions_sprite_index']['commit'] == SOURCE
    assert index['rights']['no_binary_distribution'] is True
    assert index['rights']['metadata_index_only'] is True
    assert index['rights']['licenses_for_public_dataset'] == 'NOT_VERIFIED'
    assert index['interpretation']['allowed_as_certification_evidence'] is False
    assert index['counts']['separately_verified_in_game_battle_frames'] == 0
    assert index['base_species_not_present_by_simple_id'] == ['floette:670']
    forms = index['forms']
    original = official['forms']
    assert len(forms) == len(original) == 81
    assert official['regulation'] == 'M-C'
    assert [sum(r['introduction'] == k for r in forms)
            for k in ('M-A','M-B','M-C')] == [59,16,6]
    assert [r['form_id'] for r in forms] == [r['id'] for r in original]
    assert len({r['species'] for r in forms}) == 76
    assert len({r['form_id'] for r in forms}) == 81
    ids=set()
    for r, original_form in zip(forms, original):
        assert r['name_ja'] == original_form['label']
        assert r['variant'] == original_form['variant']
        assert r['species'] == original_form['species']
        assert r['champions_gameplay_verified'] is False
        assert r['mega_identification_certified'] is False
        cls = r['visual_classes']
        assert len(cls) == (2 if r['form_id'] == 'meowstic-mega' else 1)
        for v in cls:
            number = v['pokeapi_pokemon_id']
            assert type(number) is int and 10000 <= number <= 20000
            assert number not in ids
            ids.add(number)
            assert set(v['assets']) == set(KIND)
            for kind, (sub, ext) in KIND.items():
                a=v['assets'][kind]
                rel = PREFIX + sub + str(number) + ext
                assert a['relative_path'] == rel
                assert a['url'] == URL + rel
                assert a['verified_present'] is True
                assert a['binary_retrieved'] is False
                assert a['gameplay_ground_truth'] is False
    assert len(ids) == 82
    assert index['counts']['legal_mega_form_ids'] == 81
    assert index['counts']['distinct_visual_class_ids'] == 82
    assert index['counts']['six_way_asset_records'] == 492
    assert index['counts']['forms_with_six_way_assets'] == 81
    assert index['counts']['base_species_six_way_assets_found'] == 75
    assert index['counts']['base_species_six_way_assets_checked'] == 76
    edge = index['gender_edge_case']
    assert edge['male_pokemon_id'] == 10314
    assert edge['female_pokemon_id'] == 10326
    assert edge['additional_female_directory_10314_visual_identity'] == 'UNINSPECTED'
    assert edge['policy'] == 'NEVER_MERGE_GENDER_LABELS_FROM_DIRECTORY_NAME_ALONE'
    return True


def run():
    p=HERE/'R651_MEGA_CHAMPIONS_ASSET_INDEX.json'
    q=HERE/'mega_m_c_81_registry.json'
    assert verify(json.loads(p.read_text()),json.loads(q.read_text()))
    print('R651_SOURCE_PINNED_81_FORMS_82_CLASSES_492_LINKS_PASS')
    print('R651_REAL_GAME_GROUND_TRUTH_0_NOT_CERTIFIED')

if __name__=='__main__':
    run()
