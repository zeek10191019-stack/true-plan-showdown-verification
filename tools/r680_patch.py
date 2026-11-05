from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
anchor=('visualChanges["r594_actor_appearance"] =\n'
        '                            R594ActorAppearance.timeline(actorAppearanceSamples)')
assert s.count(anchor)==1, 'R594 archive anchor missing or repeated'
assert 'R680MegaReferenceSeeds.make(' not in s, 'Already applied'
block=('\n                        // R680: PNG-bound unlabeled reference drafts; NOT Mega proof.\n'
       '                        visualChanges["r680_real_png_reference_drafts"] =\n'
       '                            R680MegaReferenceSeeds.make(\n'
       '                                frames:actorAppearanceSamples,\n'
       '                                snapshots:snapshots)')
s=s.replace(anchor,anchor+block)
p.write_text(s)
print('R680_PNG_BOUND_REFERENCE_DRAFTS_IN_ONE_TAP')
