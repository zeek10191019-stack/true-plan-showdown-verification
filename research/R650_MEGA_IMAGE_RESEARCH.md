# R650 | Mega image recognition research (2026-11-01)

Scope: Pokémon Champions Regulation M-C singles. Official
M-A, M-B and M-C lists total 59 + 16 + 6 = 81 Mega forms;
76 distinct base species. Older or otherwise known Mega forms
are not automatically legal within current Regulation M-C.

Primary regulation notices:
- https://champions-news.pokemon-home.com/ja/page/751.html
- https://champions-news.pokemon-home.com/ja/page/776.html
- https://news.pokemon-home.com/ja/page/816.html

Direct form comparison sources manually checked:
- Mega Charizard X: https://zukan.pokemon.co.jp/detail/0006-1
- Mega Charizard Y: https://zukan.pokemon.co.jp/detail/0006-2
- Mega Garchomp Z: https://zukan.pokemon.co.jp/detail/0445-2
- Mega Lucario Z: https://zukan.pokemon.co.jp/detail/0448-2/
- Mega Golisopod: https://zukan.pokemon.co.jp/detail/0768-1
- Mega Salamence: https://zukan.pokemon.co.jp/detail/0373-1
- Mega Raichu X and Y:
  https://www.pokemon.co.jp/ex/legends_z-a_dlc/ja/pokemon/250912_01/

Published Champions in-game 3D reference imagery:
https://www.pokemonchampions.jp/ja/megaevolution/
The page contains selected rendered examples, not all 81
verified independent game-angle references.

Rights conditions:
https://www.pokemonchampions.jp/ja/streaming_guideline/
https://www.pokemon.co.jp/rules/
The Champions guideline concerns permitted publishing of
captured play footage, not a blanket license to redistribute
isolated character assets or package them into an app.
This repository saves only metadata, URLs and original code.

Domain shift: official Pokédex art is not equivalent to a
rendered Champions battle frame. No uncalibrated images can
be used to certify a species, Mega state or actor ownership.

Data capture contract:
- Users supply their own Champions gameplay PNGs locally.
- Require consent, privacy review and human form label.
- Record session, epoch, frame, source hash, left/right region.
- Preserve base and Mega X/Y/Z as distinct labels.
- Reject background, camera, roster and source discontinuities.
- Do not upload raw screenshots automatically.
- Keep all game-state and battle-advice approval gates closed.

Current results:
- All 81 forms registered; no game-trained visual weights.
- Zero independently labeled Champions gameplay reference images.
- Real-game image accuracy: NOT MEASURED.
- Existing R594/R595 matcher remains historical/candidate only.

Future dataset must include: two actor sides, multiple angles,
pre- and post-Mega states, animation missed, camera shifts,
lighting and shiny variants, switch/leave/re-entry, OCR missing,
lookalike Mega variants, and independently sealed test frames.
