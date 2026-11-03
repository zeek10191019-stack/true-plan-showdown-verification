from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
assert 'R670HUDPixelGlyphs.inspect(' not in s

def add(anchor, extra, before=False):
 global s
 assert s.count(anchor)==1, anchor[:50]
 s=s.replace(anchor,extra+anchor if before else anchor+extra)

add('                        var actorAppearanceSamples=[[String:Any]]()',
    '\n                        var glyphPixelSamples=[[String:Any]]()')
add('                            if w>=128,h>=128',
'''                            var glyphs=R670HUDPixelGlyphs.unavailable(
                                epoch:sample.epoch,frame:sample.frame,
                                ms:sample.observed,sha256:digest)
''',True)
add('''                                    colorHUD=R590ColorHUDCorroboration.inspect(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        observedMs:sample.observed,imageSHA:digest)''',
'''
                                    glyphs=R670HUDPixelGlyphs.inspect(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        ms:sample.observed,sha256:digest)''')
add('                            visualSceneSamples.append(visualScene)',
    '                            glyphPixelSamples.append(glyphs)\n',True)
add('                        manifest["r589_owner_hp_or_mega_certified"]=false',
'''
                        let glyphArchive:[String:Any]=[
                            "schema":"trueplan.r670.historical-hud-rgba-bundle.v1",
                            "frame_count":glyphPixelSamples.count,
                            "frames":glyphPixelSamples,
                            "owner_certified":false,
                            "status_icon_class_certified":false,
                            "current_state_eligible":false]
                        let glyphBytes=try JSONSerialization.data(
                            withJSONObject:glyphArchive,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(
                            name:"historical_hud_rgba_glyphs.json",
                            bytes:glyphBytes))
                        manifest["r670_rgba_glyphs_file"] =
                            "historical_hud_rgba_glyphs.json"
                        manifest["r670_status_icon_class_certified"] = false''')
assert s.count('R670HUDPixelGlyphs.inspect(')==1
p.write_text(s)
print('R670_RGBA_GLYPH_ONE_TAP_INTEGRATED')
