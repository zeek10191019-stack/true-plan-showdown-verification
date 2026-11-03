from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/R673OrientedSpriteReader.swift')
s=p.read_text()
a='("LEFT_ACTOR_POSITION_ONLY",0.06,0.30,0.60,0.80)'
b='("LEFT_ACTOR_POSITION_ONLY",0.06,0.60,0.30,0.80)'
assert s.count(a)==1 and b not in s
p.write_text(s.replace(a,b))
p=Path('tests/R673SpriteSmoke.swift')
s=p.read_text()
for a,b in [('Double(x)/Double(w)>0.30','Double(x)/Double(w)>0.60'),
            ('Double(y)/Double(h)<0.60','Double(y)/Double(h)<0.30'),
            ('(0.06+0.24*','(0.06+0.54*'),
            ('(0.60+0.20*','(0.30+0.50*')]:
 assert s.count(a)==1,(a,s.count(a))
 s=s.replace(a,b)
p.write_text(s)
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
a='''                        visualChanges["r673_oriented_sprite_candidates"] =
                            r673SpriteSamples'''
b='''
                        // R674: same-frame position link; NOT owned game state.
                        visualChanges["r674_actor_hud_links"] =
                            zip(r673SpriteSamples,hpFillSamples).map {
                                R674ActorHUDLink.link(sprite:$0.0,hp:$0.1)
                            }'''
assert s.count(a)==1 and 'R674ActorHUDLink.link(' not in s
p.write_text(s.replace(a,a+b))
print('R674_CORRECTED_R594_REFERENCE_ROI_AND_LINKED_HUD')
