# Habitats v3

Eight habitats for the redesigned key (`REDESIGN.md`). They come with three generated nodes: `plants_headers_v3`, `counts_4_v3`, and `lists_4_v3`. The shipped app keeps reading `plants_headers`, `counts_4_v2`, and `lists_4_v2`, which stay as they are until v2 is retired.

## Vocabulary

| Code | Habitat | Covers | Goes elsewhere |
|---|---|---|---|
| 4 | Forest | woods, forest edges, clearings, coppice, shady hedgerows, wooded stream banks | open scrub, maquis → 7; parks and street trees → not a habitat |
| 1 | Meadow | mesic grassland, pastures, hay meadows, lawns, tallgrass prairie, lowland and montane meadows | dry or steppe grassland → 7; wet meadows → 3; alpine meadows above the tree line → 5 |
| 7 | Dry and sunny | dry and semi-dry grassland, steppe, sandy open ground, garrigue, maquis, chaparral, semi-desert, sunny dry slopes | rock is the main ground → 5; saline coast → 10 |
| 8 | Fields and roadsides | arable fields, fallows, field margins, roadsides, railways, waste ground, rubble, urban and garden weeds | old walls → 5; grassy road verges that are really meadow → 1 |
| 3 | Water and wetland | in water, banks and shores of fresh water, marshes, fens, swamps, wet meadows, ditches, wet woods (with 4) | acid peat bog → 9; salt marsh → 10 |
| 9 | Heath and bog | heath, moorland, raised and blanket bogs, acid nutrient-poor sand or peat | base-rich fens → 3 |
| 5 | Rocks and mountains | cliffs, crevices, scree, rock outcrops, old walls, alpine and subalpine zone above the tree line | sea cliffs → 10 |
| 10 | Coast | dunes, beaches, shingle, salt marshes, sea cliffs, coastal grassland and scrub within reach of salt spray | inland saline steppe → 7 |

Codes 2 (garden) and 6 (tree) are retired. They are never reused, so a code keeps one meaning in every node and every app version.

## Choosing a plant’s habitats

The question is: **where would a person most likely be standing when they see this plant in flower, growing on its own?** The places a plant *can* grow don’t count.

1. **Read the English `habitat` text.** It is already sourced from `botanical_sources.json`. When the text is too thin to decide, open a reliable flora for that region. Never tag a habitat that no source names. If the text is wrong or missing, fix it with `/update-plant` first.
2. **Pick the primary habitat.** It is usually the first place named in the text's first sentence. Every plant has exactly one primary habitat.
3. **Add at most two more**, and only places the sources describe as regular: named in the lead sentence, or marked *often*, *usually*, *commonly*, *typically*, *mainly*.
4. **Skip qualified mentions.** Places marked *also*, *sometimes*, *occasionally*, *rarely*, *locally*, *escaped to*, *casual*, or *persisting after cultivation* are not tagged, unless that place is where most people in the catalog's regions actually meet the plant.
5. **Include the naturalized range when it is large.** A plant widely naturalized in a catalog region is tagged for where it grows there as well. Example: *Erigeron annuus* is a prairie plant at home and a roadside plant in Europe, so it gets 1 and 8. The region chip already handles geography, so habitats don't need to be split by region.
6. **Tag trees and shrubs by where they grow**, usually 4, 7 or 5. The old code 6 does not come back. Whether a plant is a tree is a growth-form question, which can become its own filter later.
7. **Tag garden weeds by where they grow.** *Galinsoga* and other weeds of beds and arable ground get 8. Garden weeds do not count as garden plants.
8. **Choose the more specific habitat when two overlap.** Dry grassland gets 7, not 1. Acid bog gets 9, not 3. Alpine meadows get 5, not 1. Salt marsh gets 10, not 3.

### Limits

- **At least 1 and at most 3 habitats.** Validation rejects 4+, and rejects 0 unless the plant is `cultivated` (see below).
- **Two is the norm.** Three is only for real generalists (for example *Achillea millefolium*: meadow, fields and roadsides, dry and sunny). The target is an average of 2.0 or less across the catalog. If more than 25% of plants carry three, the review report flags it and the batch is re-read before anything is written.
- **Every code cites a phrase** from the English habitat text or a named flora page. A code without evidence is dropped.
- **The v2 codes are a hint, not the answer.** Old 1 becomes 1 or 7. Old 3 becomes 3 or 9. Old 4 stays 4. Old 5 becomes 5 or 7. Old 2 and 6 give no v3 habitat and are re-read from the text.

### Garden plants: `cultivated`

`cultivated: true` marks a plant that most people see planted rather than growing wild in the catalog's regions. Examples: dahlia, carnation, gerbera, China aster, peony, camellia, zinnia, rhubarb, crops and ornamentals. It is not an index axis. Plants without the flag count as wild.

- The **Wild and garden / Wild only** chip filters only the key's result list. The app remembers the choice, the same way it remembers the region.
- Search and Book always show every plant. Cultivated plants carry a **Garden plant** tag there instead of being hidden.

- Set it when the habitat text leads with cultivation (*Grown in gardens…*, *Cultivated…*), when the plant is known only in cultivation, or when it is native elsewhere and in the catalog's regions is mainly planted, not naturalized.
- A cultivated plant follows the same rules as a wild one. It gets 1–3 habitats from where the sources say it grows on its own: its wild range, or where it escapes, self-sows, or naturalizes (usually 8).
- A parent species' or wild relative's habitat is never used as a stand-in.
- When no source names any place the plant grows outside cultivation, first run it through `/update-plant`. Several such plants turn out to be gaps in the text, for example *Moricandia arvensis* and *Styphnolobium japonicum*, which both have wild ranges. If the sources still name no place, the plant gets **no habitat**. That is allowed only with `cultivated: true`. It is still found through the skip link (the empty habitat slot, `1__3_`), Search, and Book.
- The skip link on the habitat step reads **In a garden, or not sure? Show all … plants**. Someone standing in a garden keys by color and petals (`1__3_`).
- The skip link on the petal step reads **Not sure? Show all … plants**. It lists every plant in the color and place already chosen, with the petal slot empty (`1_1__`, or `1___` when the place was skipped).

## Data

### Where the facts live

The new facts go in `plants_v2/{Latin name}`, the per-plant master record. It already holds `floweringFrom`, `floweringTo` and the life form, and `/add-plant`, `/update-plant` and `/rename-plant` already write it.

| Field | Type | Rule |
|---|---|---|
| `habitats` | array of 1–3 codes from `{1,3,4,5,7,8,9,10}` | primary first; an empty array only with `cultivated: true`. Realtime Database drops an empty array, so the key is absent and readers treat that, with `cultivated: true`, as no habitat |
| `cultivated` | `true`, or absent | absent means wild |

These fields are the only place habitats and `cultivated` are edited. Everything below is generated from them.

### `plants_headers_v3` (generated)

`plants_headers_v3/{id}` is the one node the new key and result list need. It is keyed by the same numeric id as `plants_headers`.

```json
{
  "name": "Leucanthemum vulgare",
  "family": "Asteraceae",
  "url": "Asterales/Asteraceae/Leucanthemum_vulgare/lv2.webp",
  "filterColor": [1],
  "filterHabitat": [1, 8],
  "filterPetal": [3],
  "filterDistribution": [10, 11, 12, 13, 14],
  "floweringFrom": 5,
  "floweringTo": 10
}
```

| Field | From |
|---|---|
| `name`, `family`, `url`, `filterColor`, `filterPetal`, `filterDistribution` | `plants_headers/{id}` |
| `filterHabitat` | `plants_v2/{name}/habitats` (v3 codes) |
| `floweringFrom`, `floweringTo` | `plants_v2/{name}` (the result list sorts plants in flower this month first) |
| `cultivated` | `plants_v2/{name}/cultivated`, written only when `true` |

Nothing edits this node by hand. `catalog.refresh` rebuilds it, and the rebuild fails if `plants_headers/{id}/name` and `plants_v2` disagree about a plant. `plants_headers` is 336 KB today; the v3 copy should come out around 370 KB.

### `counts_4_v3` and `lists_4_v3` (generated)

These are built from `plants_headers_v3`. The key shape is unchanged: `color_habitat_petal_distribution`, with an empty slot for "not selected". Habitat ids for v3 are `None, 1, 3, 4, 5, 7, 8, 9, 10`.

| | v2 | v3 |
|---|---|---|
| Header node | `plants_headers` | `plants_headers_v3` |
| Keys (6 × habitats × 5 × 53 regions) | 11,130 | 14,310 |
| Index nodes | `counts_4_v2`, `lists_4_v2` | `counts_4_v3`, `lists_4_v3` |

Values have the same shape as v2: `counts_4_v3/{key}` is an integer, including zeros. `lists_4_v3/{key}` is `{plantId: 1}`, and empty lists are omitted. Plants carry fewer habitats than today (average 2.78 now, about 2 in v3), so `lists_4_v3` should come out no bigger than the 3.6 MB `lists_4_v2`.

## Plan

### 1. Code (`ingest`)

- `catalog/catalog_indexes.py`:
  - add `HABITAT_IDS_V3`
  - make key generation, `header_values`, `matching_keys` and `build_counts_and_lists` take the habitat id set, so one function builds v2 or v3
  - add `build_headers_v3(plant_names, headers, plants_v2)`, which returns the headers, the name mismatches, and the plants with missing `habitats`
- `catalog/refresh.py`: add a `v3` stage that writes `plants_headers_v3.json`, `counts_4_v3.json` and `lists_4_v3.json`. It still never writes to Firebase.
- `catalog/incremental_indexes.py`, `catalog/publish.py`, `catalog/promote.py`: for one plant, write its `plants_headers_v3/{id}` and patch the v3 counts and lists next to the v2 ones.
- `scripts/apply_accuracy_patches.py`, `scripts/repair_filter_lists.py`: the same remove-old/add-new diff and cleanup for v3.
- `plant/validate.py`:
  - `habitats` must have 1–3 codes from `{1,3,4,5,7,8,9,10}`
  - an empty array is allowed only when `cultivated` is `true`
  - `cultivated` must be absent or `true`
- `plant/infer_traits.py`: add `HABITAT_WORDS_V3` so drafts for new plants propose v3 codes with evidence phrases, following the rules above.
- `scripts/backup_catalog.py`: back up the three v3 nodes.
- Tests in `tests/test_catalog_indexes.py`:
  - the v3 header copies every shared field exactly and takes `filterHabitat` and flowering months from `plants_v2`
  - a name mismatch fails the build
  - key count is 14,310
  - retired codes 2 and 6 are ignored
  - `counts["___"]` equals the number of plants
  - every count equals its list length
  - a plant with 1, 2 or 3 habitats lands in exactly the right keys

### 2. Rules (`app/firebase`)

Add `plants_headers_v3`, `counts_4_v3` and `lists_4_v3` as `".read": true, ".write": false` to `database.rules.json` and `database.rules.target.json`. Deploy the rules before the nodes exist.

### 3. Tag the catalog

Tag in `plants/_jobs/_habitat_v3/`, in batches of 100 by catalog index (0–99 … 1400–1420), the same way as the language passes.

1. **Draft.** For each plant, a script reads live `translations/en/{name}/habitat`, `plants_headers/{id}/filterHabitat` and the `plants_v2` life form. It writes `batch_NNNN.json` with `id`, `name`, `v2`, `habitats`, `cultivated`, and for each code its `evidence` phrase.
2. **Review.** Read every proposal against the text and the rules. Fix the codes and record the reason. Plants whose text doesn't support a decision go to `needs_update.json` for `/update-plant`, not into a guess.
3. **Check each batch automatically:**
   - 1–3 codes, all allowed (0 only for a `cultivated` plant already checked with `/update-plant`)
   - every evidence phrase appears in the English habitat text or in a named flora URL
   - share of plants with three codes, and a per-habitat total
   - plants whose habitat changed completely from v2, listed for a second look
4. **Spot-check** 30 well-known plants by hand across all eight habitats, including trees, weeds, aquatics, alpines, coastal plants and garden plants.
5. **Report.** `_BATCH_PROGRESS.md` gets a Habitat v3 line with the next index.

### 4. Write the facts

After all batches are reviewed, and only when asked, back up with `scripts/backup_catalog.py`. Then write `plants_v2/{name}/habitats`, plus `cultivated: true` where set, with the Admin SDK. `plants_headers` is not touched.

### 5. Build and write the v3 nodes

1. Run `python -m catalog.refresh --only v3` on a fresh dump.
2. Check the output:
   - `plants_headers_v3` has 1,421 entries and no name mismatches
  - a plant with no habitats is always `cultivated`, and each one is listed in the report
   - 14,310 count keys
   - `counts_4_v3["___"] == 1421`
   - each count equals its list length
   - each plant appears in exactly (colors + 1) × (habitats + 1) × (petals + 1) × (regions + 1) keys, as `matching_keys` predicts
   - no key uses 2 or 6
3. Compare the white-flower counts per habitat with the mockup estimates. They should come out lower, because the rules limit each plant to the places it's typical.
4. Only when asked, write the three nodes with `set()`. Nothing reads them yet, so they don't need a staging copy. Then set `versions/db_update`.

### 6. Keep v2 and v3 in step

Until v2 is retired, every catalog change updates both sets:

- **`/add-plant`**
  - the job packet carries `habitats` and `cultivated` in `plants_v2`
  - publish writes `plants_headers/{id}` and `plants_headers_v3/{id}`, and patches both index sets
- **`/update-plant`**
  - retune `habitats` in `plants_v2` alongside `filterHabitat` in `plants_headers`
  - rebuild that plant's `plants_headers_v3/{id}`
  - remove-old/add-new diff on both index sets
  - a change to flowering months also rewrites `plants_headers_v3/{id}`
- **`/rename-plant`**
  - `plants_v2` moves to the new name, and the ids don't change
  - rewrite `plants_headers_v3/{id}/name`
- **Docs:** update both skill copies (`.grok/skills/` and `ingest/skills/`), `ingest/ADD_PLANT.md` (traits table and habitat evidence rule), and `DATA_MODEL.md` (filter vocabulary, `plants_v2` fields, and the three v3 nodes).

### 7. App

- `lib/data/utils.dart`: add `firebasePlantHeadersV3`, `firebaseCountsV3` and `firebaseListsV3`.
- The new key screen and result list read only these three nodes. The shipped filter screens stay on v2.
- The result list sorts by `floweringFrom`–`floweringTo` and filters on `cultivated` for the Wild only chip, both from `plants_headers_v3`. The chip choice is saved in prefs next to the region.
- Search results and Book rows (families, genera, lists) show a **Garden plant** tag when `cultivated` is set. They never hide a plant.
- Habitat strings: eight labels and eight example lines in `intl_en.arb`, then every UI language. Take the wording from that language's morphology or habitat glossary, not a word-for-word rendering of the English.

### 8. Retire v2

When the installs still on the v2 filter screens drop to a level you accept:

1. Stop writing `plants_headers/{id}/filterHabitat`, `counts_4_v2` and `lists_4_v2`.
2. Keep one backup, then delete the two v2 index nodes.
3. `plants_headers` then only feeds the shared fields of `plants_headers_v3`. Moving those fields into `plants_v2` as well, and deleting `plants_headers`, is a separate decision.
