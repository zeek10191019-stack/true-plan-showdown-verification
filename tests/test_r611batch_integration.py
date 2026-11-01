import unittest,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'app/ios/ChampionsOnDevice'
class ProductionContract(unittest.TestCase):
  def test_archive_chain_is_forward_only_and_single_writer(self):
    s=(SOURCE/'CaptureCoordinator.swift').read_text()
    chain=[
      'let r609Entries = R609VisionTextSpatialEvidence.beforeZip(r608Entries)',
      'let r610Entries = R610CrossEvidenceCandidate.beforeZip(r609Entries)',
      'let r611Entries = R611TemporalHUDReview.beforeZip(r610Entries)',
      'let r612Entries = R612ArchiveEvidenceClosure.beforeZip(r611Entries)',
      ]
    positions=[]
    for item in chain:
      self.assertEqual(s.count(item),1,item)
      positions.append(s.index(item))
    self.assertEqual(positions,sorted(positions))
    self.assertEqual(s.count('R548ResearchArchive.write('),1)
  def test_uncertified_contract_kept(self):
    a=(SOURCE/'R611TemporalHUDReview.swift').read_text()
    b=(SOURCE/'R612ArchiveEvidenceClosure.swift').read_text()
    self.assertIn('HOLD_OWNER_HP_AND_ORIENTATION_UNVERIFIED',a)
    self.assertIn('location_consistent_with_previous_candidate',a)
    self.assertIn('testDigest(png.bytes)==sha',a)
    self.assertIn('HOLD_COMPLETE_UNCERTIFIED_RESEARCH_RECEIPTS',b)
    for code in [a,b]:
      self.assertIn('"certified_for_battle":false',code)
      self.assertNotIn('"owner_verified":true',code)
      self.assertNotIn('"roi_verified":true',code)
if __name__=='__main__':unittest.main()
