from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
anchor=('visualChanges["r680_real_png_reference_drafts"] =\n'
        '                            R680MegaReferenceSeeds.make(\n'
        '                                frames:actorAppearanceSamples,\n'
        '                                snapshots:snapshots)')
assert s.count(anchor)==1,'R680 seed anchor missing or duplicated'
assert 'R681MegaSeedOCRHints.make(' not in s,'R681 already applied'
block=('\n                        // R681: same-PNG HUD species OCR hints; never form proof.\n'
       '                        visualChanges["r681_species_ocr_seed_hints"] =\n'
       '                            R681MegaSeedOCRHints.make(\n'
       '                                draftReport:visualChanges[\n'
       '                                    "r680_real_png_reference_drafts"] as?\n'
       '                                    [String:Any] ?? [:],\n'
       '                                spatial:spatial,\n'
       '                                registry:R649MegaRegistryAudit.entries.map {\n'
       '                                    (species:$0.species.uppercased(),jp:$0.jp)\n'
       '                                })')
s=s.replace(anchor,anchor+block)
p.write_text(s)
print('R681_SAME_PNG_SPECIES_HINTS_ONE_TAP_INTEGRATED')
