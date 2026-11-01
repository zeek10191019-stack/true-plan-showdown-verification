"""Expand the official M-A/M-B/M-C whitelist into image source metadata.
No image binaries are fetched or stored. URLs are human-verified only.
"""
import json
from pathlib import Path

OFFICIAL = {
    "M-A": "https://champions-news.pokemon-home.com/ja/page/751.html",
    "M-B": "https://champions-news.pokemon-home.com/ja/page/776.html",
    "M-C": "https://news.pokemon-home.com/ja/page/816.html",
}
# A URL appears only after independently checking its page contents.
VERIFIED = {
    "charizard-mega-x": "https://zukan.pokemon.co.jp/detail/0006-1",
    "charizard-mega-y": "https://zukan.pokemon.co.jp/detail/0006-2",
    "garchomp-mega-z": "https://zukan.pokemon.co.jp/detail/0445-2",
    "lucario-mega-z": "https://zukan.pokemon.co.jp/detail/0448-2/",
    "golisopod-mega": "https://zukan.pokemon.co.jp/detail/0768-1",
    "salamence-mega": "https://zukan.pokemon.co.jp/detail/0373-1",
    "raichu-mega-x":
      "https://www.pokemon.co.jp/ex/legends_z-a_dlc/ja/pokemon/250912_01/",
    "raichu-mega-y":
      "https://www.pokemon.co.jp/ex/legends_z-a_dlc/ja/pokemon/250912_01/",
}


def main():
    root = Path(__file__).resolve().parents[1]
    p = root / "research/mega_m_c_81_registry.json"
    source = json.loads(p.read_text("utf-8"))
    rows = source["forms"]
    assert len(rows) == 81
    assert len({r["id"] for r in rows}) == 81
    assert [sum(r["phase"] == q for r in rows)
            for q in ("M-A", "M-B", "M-C")] == [59,16,6]
    entries = []
    for r in rows:
        entries.append({**r,
          "regulation_evidence_url": OFFICIAL[r["phase"]],
          "official_image_info_page": VERIFIED.get(r["id"]),
          "form_image_binary_acquired": False,
          "champions_3d_labeled_reference_acquired": False,
          "official_art_3d_domain_gap": "UNRESOLVED",
          "image_reuse_license": "NOT_ESTABLISHED_FOR_MODEL_DATASET",
          "needs_manual_label": True})
    payload = {
      "schema": "trueplan.r650.mega-image-source-index.v1",
      "reviewed_date": "2026-11-01",
      "regulation": "M-C", "count": 81,
      "unique_base_species": len({r["species"] for r in rows}),
      "forms": entries,
      "primary_official_urls": {
         **OFFICIAL,
         "champions_mega":
           "https://www.pokemonchampions.jp/ja/megaevolution/",
         "champions_reuse_guidelines":
           "https://www.pokemonchampions.jp/ja/streaming_guideline/",
         "pokemon_zukan_index":"https://zukan.pokemon.co.jp/",
         "official_use":"https://www.pokemon.co.jp/rules/"},
      "intended_use":
         "PUBLIC_METADATA_ONLY_NEVER_PUBLIC_COPYRIGHT_IMAGE_BUNDLING",
      "evidence_capabilities": {
         "public_urls_verified_per_form": len(VERIFIED),
         "real_champions_game_frame_reference_count": 0,
         "real_game_visual_accuracy_measured": False},
      "limitations": [
        "Official art is not Champions 3D gameplay rendered image.",
        "Info-page URLs do not convey binary redistribution rights.",
        "Missing per-form image URLs are deliberately null.",
        "No form or owner promotion without gameplay proof."]}
    dst = root / "research/mega_m_c_81_image_source_index.json"
    dst.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+"\n",
                   encoding="utf-8")
    print("R650_OFFICIAL_SOURCE_METADATA_81_PASS",len(VERIFIED))

if __name__ == "__main__":
    main()
