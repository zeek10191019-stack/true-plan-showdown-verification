from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
mods=[
('var hpFillSamples=[[String:Any]]()',
 '\n                        var typeColorSamples=[[String:Any]]()'),
('var r673Sprite=R673OrientedSpriteReader.unavailable(',
 '''var typeColor=R679TypeColorProbe.unavailable(
                                epoch:sample.epoch,frame:sample.frame,sha:digest)
                            '''),
('if produced {\n                                    visualScene=',
 '''\n                                    typeColor=R679TypeColorProbe.inspect(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        observedMs:sample.observed,sha:digest,
                                        document:bundle)'''),
('hpFillSamples.append(hpFill)',
 '\n                            typeColorSamples.append(typeColor)'),
('"r675_ocr_pixel_hp_agreement":hpCrossmodal,',
 '\n                            "r679_move_type_color_pixel_samples":typeColorSamples,')]
assert 'R679TypeColorProbe.inspect(' not in s
for a,b in mods:
 assert s.count(a)==1,(a,s.count(a))
 if a.startswith('var r673Sprite'):
  s=s.replace(a,b+a)
 elif a.startswith('if produced'):
  s=s.replace(a,a.replace('visualScene=',b+'\n                                    visualScene='))
 else:s=s.replace(a,a+b)
p.write_text(s)
print('R679_REAL_RGBA_MOVE_TYPE_PIXEL_SAMPLER_INTEGRATED')
