from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
assert 'R673OrientedSpriteReader.inspect(' not in s

def add(a,b):
 global s
 assert s.count(a)==1,(a,s.count(a))
 s=s.replace(a,a+b)

add('var hpFillSamples=[[String:Any]]()','''
                        var r673SpriteSamples=[[String:Any]]()
                        let r673RefURL=FileManager.default.urls(
                            for:.applicationSupportDirectory,
                            in:.userDomainMask).first?.appendingPathComponent(
                                "R595FormReferenceCatalog.json")
                        let r673References=R595FormReferenceMatcher.loadLocalCatalog(
                            at:r673RefURL)
                        var r673Expected=[String:Set<String>]()
                        for item in R649MegaRegistryAudit.entries {
                            let token=item.species.uppercased()
                            let form=item.variant == "N" ? "MEGA" :
                                "MEGA_" + item.variant
                            r673Expected[token,default:["BASE"]].insert(form)
                        }''')
add('''                            var hpFill=R672PixelHPFillReader.unavailable(
                                epoch:sample.epoch,frame:sample.frame,
                                ms:sample.observed,sha256:digest)''','''
                            var r673Sprite=R673OrientedSpriteReader.unavailable(
                                epoch:sample.epoch,frame:sample.frame,
                                sha:digest)''')
add('''                                    hpFill=R672PixelHPFillReader.inspect(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        ms:sample.observed,sha256:digest)''','''
                                    r673Sprite=R673OrientedSpriteReader.inspect(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        sha:digest,references:r673References,
                                        expected:r673Expected)''')
add('hpFillSamples.append(hpFill)','''
                            r673SpriteSamples.append(r673Sprite)''')
add('''visualChanges["r594_actor_appearance"] =
                            R594ActorAppearance.timeline(actorAppearanceSamples)''','''
                        visualChanges["r673_oriented_sprite_candidates"] =
                            r673SpriteSamples''')
assert s.count('R673OrientedSpriteReader.inspect(')==1
assert s.count('r673SpriteSamples.append(')==1
p.write_text(s)
print('R673_ORIENTED_SPRITE_ONE_TAP_INTEGRATED')
