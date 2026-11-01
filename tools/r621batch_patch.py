"""R621-R624 atomic, hash-pinned patch of R620 production writer and old terminal tests."""
from pathlib import Path
import hashlib,re
TARGET=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
MODULE=Path('app/ios/ChampionsOnDevice/R617R620RotationReadout.swift')
TEST=Path('tests/test_r617batch_source.py')
MODULE_SHA='d5c1081d0a1458fe9f6f451f57e403db15cd04f154786db6246b6e8db5d961ac'
TEST_SHA='5bc22743d31bc59fcecabe4723865eb37dbe3d75f4ac3c93af28af3632d0015b'
ANCHOR='''        let statusMap:[String:String] = ['''
MEGA_INSERT='''        // Mega evolution dialogue is a scene cue, never actor/form proof.
        let megaText = text.uppercased().replacingOccurrences(of:" ",with:"")
        if text.contains("メガシンカ") || text.contains("メガ進化") ||
           megaText.contains("MEGAEVOLUTION") {
            return ["kind":"MEGA_SCENE_TEXT_CUE_UNASSIGNED",
                    "source":"OCR_SCENE_WORD_NOT_ACTOR_OR_FORM"]
        }
        let statusMap:[String:String] = ['''
WRITER=re.compile(
 r'(?m)^(?P<i>[ \t]*)_ = try R548ResearchArchive\.write\(\n'
 r'(?P=i)    r617Entries, to: zipURL, work: exportWork\n'
 r'(?P=i)\)')
OLD="self.assertIn('r617Entries, to: zipURL, work: exportWork',s)"
NEW="self.assertIn('let r617Entries = R617R620RotationReadout.beforeZip(r613Entries)',s)"

def patch(root):
 root=Path(root)
 c=root/TARGET;m=root/MODULE;t=root/TEST
 src=c.read_text();mod=m.read_bytes();test=t.read_bytes()
 if hashlib.sha256(mod).hexdigest()!=MODULE_SHA:
  raise ValueError('R620_MODULE_PIN_DRIFT')
 if hashlib.sha256(test).hexdigest()!=TEST_SHA:
  raise ValueError('R620_TEST_PIN_DRIFT')
 if mod.decode().count(ANCHOR)!=1 or test.decode().count(OLD)!=1:
  raise ValueError('REQUIRED_INSERT_ANCHOR_NOT_UNIQUE')
 mm=list(WRITER.finditer(src))
 if len(mm)!=1 or src.count('R621R624VisualCandidates.beforeZip(')!=0:
  raise ValueError('R620_WRITER_NOT_UNIQUE_OR_ALREADY_PATCHED')
 mt=mm[0];i=mt.group('i')
 new=src[:mt.start()]+(
  i+'let r621Entries = R621R624VisualCandidates.beforeZip(r617Entries)\n'
  +i+'guard r621Entries.count == r617Entries.count &&\n'
  +i+'      R621R624VisualCandidates.containsReport(r621Entries) else {\n'
  +i+'    throw NSError(domain:"R624_VISUAL_EMBEDDED_REPORT_MISSING",code:624)\n'
  +i+'}\n'
  +i+'_ = try R548ResearchArchive.write(\n'
  +i+'    r621Entries, to: zipURL, work: exportWork\n'
  +i+')')+src[mt.end():]
 newmod=mod.decode().replace(ANCHOR,MEGA_INSERT).encode()
 newtest=test.decode().replace(OLD,NEW).encode()
 if new.count('R548ResearchArchive.write(')!=1 or new.count('R621R624VisualCandidates.beforeZip(')!=1:
  raise ValueError('WRITER_CONTRACT_BROKEN')
 # No disk mutation before all validations finish.
 c.write_text(new);m.write_bytes(newmod);t.write_bytes(newtest)
 return c
