#!/usr/bin/env python3
from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text(encoding='utf-8')
assert 'R672PixelHPFillReader.inspect(' not in s,'R672_DUPLICATE'
def insert(anchor,extra,before=False):
 global s
 assert s.count(anchor)==1,('R672_SOURCE_ANCHOR_MISSING',anchor[:60],s.count(anchor))
 s=s.replace(anchor,extra+anchor if before else anchor+extra)
insert('                        var glyphPixelSamples=[[String:Any]]()',
       '\n                        var hpFillSamples=[[String:Any]]()')
insert('''                            var glyphs=R670HUDPixelGlyphs.unavailable(
                                epoch:sample.epoch,frame:sample.frame,
                                ms:sample.observed,sha256:digest)''',
       '''
                            var hpFill=R672PixelHPFillReader.unavailable(
                                epoch:sample.epoch,frame:sample.frame,
                                ms:sample.observed,sha256:digest)''')
insert('''                                    glyphs=R670HUDPixelGlyphs.inspect(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        ms:sample.observed,sha256:digest)''',
       '''
                                    hpFill=R672PixelHPFillReader.inspect(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        ms:sample.observed,sha256:digest)''')
insert('                            glyphPixelSamples.append(glyphs)',
       '                            hpFillSamples.append(hpFill)\n',True)
insert('''                            "r671_reviewed_reference_matches":iconMatches,''',
       '''
                            "r672_pixel_hp_fill_tracks":hpFillSamples,''')
assert s.count('R672PixelHPFillReader.inspect(')==1
assert s.count('hpFillSamples.append(')==1
p.write_text(s,encoding='utf-8')
print('R672_PIXEL_FILL_ONE_TAP_INTEGRATED')
