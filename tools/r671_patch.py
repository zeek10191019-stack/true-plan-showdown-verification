#!/usr/bin/env python3
from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text(encoding='utf-8')
anchor='''                        let glyphArchive:[String:Any]=[
                            "schema":"trueplan.r670.historical-hud-rgba-bundle.v1",
                            "frame_count":glyphPixelSamples.count,
                            "frames":glyphPixelSamples,
                            "owner_certified":false,'''
assert s.count(anchor)==1,'R671_PARENT_R670_ANCHOR_MISSING'
assert 'R671StatusGlyphMatcher.audit(' not in s,'R671_DUPLICATE'
repl='''                        let iconCatalog=FileManager.default.urls(
                            for:.applicationSupportDirectory,in:.userDomainMask
                        ).first?.appendingPathComponent(
                            "R671StatusGlyphReferences.json")
                        let glyphReferences=iconCatalog.map {
                            R671StatusGlyphMatcher.loadReferences(at:$0)
                        } ?? []
                        let iconMatches=R671StatusGlyphMatcher.audit(
                            frames:glyphPixelSamples,references:glyphReferences)
                        let glyphArchive:[String:Any]=[
                            "schema":"trueplan.r670.historical-hud-rgba-bundle.v1",
                            "frame_count":glyphPixelSamples.count,
                            "frames":glyphPixelSamples,
                            "r671_reviewed_reference_matches":iconMatches,
                            "owner_certified":false,'''
s=s.replace(anchor,repl)
assert s.count('R671StatusGlyphMatcher.audit(')==1
p.write_text(s,encoding='utf-8')
print('R671_GLYPH_REFERENCE_MATCHER_ONE_TAP_INTEGRATED')
