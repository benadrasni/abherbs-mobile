# Data model

Source of truth is **Firebase Realtime Database** `abherbs-backend`. Photos are **public objects** in GCS bucket `abherbs-resources`.

Most catalog trees are world-readable (the website fetches them with unauthenticated REST). Live rules are snapshotted in `firebase/database.rules.json`. Storage rules live in `firebase/storage.abherbs-resources.rules` and `firebase/storage.default.rules`. The next tightening is `firebase/database.rules.target.json` (needs a publish/credits backend). Do not deploy rule changes without an explicit ask.

### Access (live)

| Path | Unauthenticated | Signed-in client |
|---|---|---|
| Catalog (`plants_v2`, `lists_4_v2`, `counts_4_v2`, `search_v3`, `search_photo`, `translations`, `translations_taxonomy`, `web`, …) | read | read |
| Staging indexes (`*_new`) | read | read |
| `users/{uid}` | denied | owner read. Client may write `token`, `favorites`, `purchases`, `credits` (0–10000). Owner may delete the whole node. Not `old version` or `entitlements` except via that delete. |
| `users_photo_search/{lang}/{uid}` | denied | owner read/write |
| `credits/{uid}` | denied | owner read/write (string log, 64 chars) |
| `observations/by users/{uid}` | denied | owner read/write |
| `observations/public` | read | create/update own id (`{uid}_…`) only while `status == review`. Owner may delete own id in any status. `stats` is Admin-only. |
| `observations/logs/{uid}` | denied | owner read/write |
| `photo_quota/{uid}` | denied | owner read (written by the photo Cloud Functions) |
| `purchase_proofs`, `store_accounts` | denied | denied. Cloud Functions only |

Admin SDK bypasses these rules (ingest, observation reviewer, Cloud Functions). The photo lock-down of `credits` and `purchases` is staged in `firebase/database.rules.photo.json`; see `PHOTO_NAMES.md`.

Signed-out photo-search logs under `anonymous` fail. The app does not write translations.

## Root nodes

| Path | Role |
|---|---|
| `plants_v2/{latinName}` | Full species record |
| `plants_headers/{id}` | Compact card used by lists |
| `lists_4_v2/{filterKey}` | Plant ids matching a filter combination |
| `counts_4_v2/{filterKey}` | Integer count for that combination |
| `search_v3/{lang}` | Name search index (`la` = Latin) |
| `search_photo/{normalizedName}` | Maps Plant.id scientific name → in-catalog path |
| `APG IV_v3` | Taxonomy tree for browse/search |
| `translations/{lang}/{latinName}` | Plant text in that language. Missing body falls back to English in the client. `label` and `names` are that language's vernaculars only. |
| `translations_taxonomy/{lang}/{taxon}` | Localized taxon names |
| `synonyms/{latinName}` | IPNI synonym list |
| `lists_custom` | Editorial lists ("new", "by language", dated drops). Language lists: `list/{plantId}` is `1` (presence), a designation year 1900–2100, or a state name. A genus-only designation is the sibling `genera`. The store app reads only numeric `list` keys. Each language reads only its own `by language/{lang}` node. A missing node shows no language lists. |
| `plants_to_update` | `{count, list[]}` of Latin names in the live catalog |
| `catalog_changes` | Append-only offline update log. `{count, list/{n}}`. Each entry is `id`, `kind` (`added` or `pictures`), and `stamp` (photos, unsuffixed plate, range map: `u` path, `b` bytes, `h` md5). `plants_to_update` does not record a new plate on an older plant. |
| `families_to_update` | Same idea for family illustration packs |
| `versions` | Store version codes + `db_update` |
| `settings` | `ai_engine`, generic Plant.id labels to ignore |
| `promotions` | Time-boxed free unlocks |
| `users/{uid}` | Profile flags, favorites, credits, token |
| `users_photo_search/{lang}/{uid}/{ts}` | Logged Plant.id results |
| `observations/by users/{uid}` | Private observations |
| `observations/public` | Shared observations (subscription) |
| `observations/logs` | Review / publish log |
| `credits` | Credit spend/earn log |
| `photo_quota/{uid}` | Photo-name allowance counters (`identifyPlant`) |
| `purchase_proofs/{id}` | Checked receipt. Apple key `app_store_{originalTransactionId}`, Play key `play_` plus a hash of the token. No client access |
| `store_accounts/{token}` | Firebase uid for a store account token. No client access |
| `ad_rewards/{transactionId}` | Rewarded-ad callbacks already credited (`admobReward`) |
| `anonymous_daily/{day}` | Plant.id calls by guest accounts that day |
| `web/{lang}` | Legacy About/Help and old-site chrome. The current website does not read this; chrome lives in `web/src/locales.json`. |
| `web/catalog/{id}` | Slim website plant row (`id`, `name`, `family`, `url`, `illustrationUrl`). Written with each incremental add. |
| `web/labels/{lang}/{id}` | Sourced vernacular for that plant, or omitted. Not inverted from `search_v3`. |

Live sizes (public REST, 2026-09-28):

- `plants_headers`: 1,421 (ids 0–1420, no gaps)
- `plants_v2`: 1,421
- `plants_to_update/count`: 1,421

Index sizes below were last counted on 2026-03-26:

- `lists_4_v2`: 9,731 keys
- `counts_4_v2`: 11,130 keys
- `search_photo`: 8,529 name mappings

## Species record (`plants_v2`)

Keyed by Latin binomial, e.g. `plants_v2/Acer campestre`.

```json
{
  "id": 0,
  "name": "Acer campestre",
  "author": "L.",
  "floweringFrom": 5,
  "floweringTo": 6,
  "heightFrom": 300,
  "heightTo": 2000,
  "toxicityClass": 0,
  "inflorescenceType": ["raceme"],
  "illustrationUrl": "Sapindales/Sapindaceae/Acer_campestre/Acer_campestre.webp",
  "photoUrls": ["Sapindales/Sapindaceae/Acer_campestre/ac1.webp", "..."],
  "videoUrls": [],
  "sourceUrls": ["..."],
  "ipniId": "781250-1",
  "gbifId": 3189863,
  "usdaId": "ACCA5",
  "freebaseId": "/m/028j7f",
  "wikiName": "Acer campestre",
  "habitats": [4, 7, 8],
  "wikilinks": {
    "data": "https://www.wikidata.org/wiki/Q157810",
    "commons": "...",
    "species": "..."
  },
  "APGIV": {
    "00_Genus": "Acer",
    "02_Familia": "Sapindaceae",
    "03_Ordo": "Sapindales",
    "11_Superregnum": "Eukaryota"
  }
}
```

`habitats` is the redesign key: 1–3 codes from 1 meadow, 3 water and wetland, 4 forest, 5 rocks and mountains, 7 dry and sunny, 8 fields and roadsides, 9 heath and bog, 10 coast. Primary code first. An empty array is allowed only with `cultivated: true`. Realtime Database drops an empty array, so those plants have no `habitats` key and no `filterHabitat` on the v3 header. `cultivated` is omitted when the plant is wild. Rules and the generated nodes are in `HABITATS.md`.

`inflorescenceType` is an array of the 17 legend keys (`raceme`, `spike`, `spadix`, `corymb`, `umbel`, `compound_umbel`, `capitulum`, `head`, `panicle`, `compound_spike`, `cyme`, `helicoid`, `rhipidium`, `scorpioid`, `scorpioid_thyrse`, `dichasial_thyrse`, `double_scorpioid_thyrse`). Primary type is first. Empty means none of those diagrams apply (solitary flower, catkin, unnamed cluster). Filled from the English `inflorescence` paragraph; the app and website highlight those cells in the inflorescence legend. Language-independent — not a translations field.

`lib/data/plant.dart` also mentions `synonyms` and `videoUrls` on the client object; synonyms in production live mainly under `synonyms/{name}/ipni`.

**Identity problem:** the primary key is the display name. `rename_plant.py` must copy `plants_v2`, `synonyms`, and every `translations/{lang}` child.

## Header (`plants_headers/{id}`)

```json
{
  "name": "Acer campestre",
  "family": "Sapindaceae",
  "url": "Sapindales/Sapindaceae/Acer_campestre/ac1.webp",
  "filterColor": [5, 2],
  "filterHabitat": [6],
  "filterPetal": [2],
  "filterDistribution": [10, 11, 12, 13, 14, 33, 34, 20, 72, 75, 76]
}
```

A plant can belong to **multiple** values of one filter (green *and* yellow). Ingest writes the union; list generation fans the plant into every combination.

The Flutter app keeps reading this node, including the filter arrays. The public website does **not** use those filters. It reads `web/catalog` (explicit `id` + `illustrationUrl`) and `web/labels/{lang}` once the catalog covers `plants_to_update/count`. Until a full rebuild has been published, the site falls back to `plants_headers` plus per-card `translations` / `plants_v2` fetches.

Rebuild locally with `python -m catalog.refresh --only web` (`web_catalog_new.json`, `web_labels_new/`). That does not write Firebase.

## Website catalog (`web/catalog/{id}`)

```json
{
  "id": 0,
  "name": "Acer campestre",
  "family": "Sapindaceae",
  "url": "Sapindales/Sapindaceae/Acer_campestre/ac1.webp",
  "illustrationUrl": "Sapindales/Sapindaceae/Acer_campestre/Acer_campestre.webp"
}
```

`id` is the `plants_to_update` list index (same as `plants_headers/{id}` and search). `illustrationUrl` is copied from `plants_v2`. Do not invent it from `url` at publish time except as a fallback when `plants_v2` has none. Labels live next door:

```json
"web/labels/en/0": "common maple"
```

Empty / missing means show the Latin name. Later-language publishes (`publish_new_plant_translations.py` and the same helper) must write `web/labels/{lang}/{id}` when they set a sourced `label`.

## Editorial lists (`lists_custom/by language/{lang}/{name}`)

```json
{
  "icon": "Orchidaceae",
  "sourceUrl": "https://www.orchideen-deutschlands.de/orchidee-des-jahres/",
  "list": { "157": 2020, "424": 2025 }
}
```

`list` keys are `plants_headers` ids. Values are `1` (membership only), a year `1900–2100` for campaigns such as Blume / Baum / Orchidee des Jahres, or a state name for a state-flower list. One species that is the flower of more than one state stores a map whose keys are those state names. When a state also designates a wildflower, that row is labeled `{State} (wildflower)`. The list is ordered by state. Optional `sourceUrl` is the campaign’s official page. Optional `parameter` is a short classifier such as a country epithet or a US state name. Production reads every key of `list` with `int.parse`. A genus name in `list` throws, and that list never opens. A genus-only designation is the sibling `genera`, which those builds ignore:

```json
{
  "icon": "Asteraceae",
  "sourceUrl": "https://en.wikipedia.org/wiki/List_of_U.S._state_and_territory_flowers",
  "list": { "1105": "Alabama" },
  "genera": {
    "Viola": { "Illinois": 1, "Rhode Island": 1 },
    "Malus": "Arkansas"
  }
}
```

`genera` uses the same values as `list`: one state name, a map of state names to `1`, a year `1900–2100`, or membership `1`. The field guide and the website draw one row per designation, genus rows in the same order as the species. The row shows the state or the year and the genus in italic. The picture is one species from that genus: its plate on the website, and that species’ photo or plate in the app. A tap opens the genus. A genus the book does not list still shows its Latin name, with no picture and no tap. In the app, New in the book is the first item in the same list as the other custom lists. A language shows only its own lists. On the website, Recently added stays its own section above the language lists. Language lists with a `sourceUrl` come next, then lists with a year value or a `parameter`. In that group a list with a `parameter` is ordered by the parameter, so two country lists follow it alphabetically, and the other lists in the group stay in title order. The remaining titles follow alphabetically. Year-lists sort newest first inside the list, show the year, and link `sourceUrl` on the list screen. A plant named in two years appears once, with the later year.

## Filter vocabulary

Order in a key is always `color_habitat_petal_distribution`. Empty slot = not selected. Example: `1_1_1_` = white + meadow + 4 or less + any region.

| Attribute | Codes |
|---|---|
| Color | 1 white, 2 yellow, 3 red, 4 blue, 5 green |
| Habitat (v2, shipped filter) | 1 meadow, 2 garden, 3 wetland, 4 forest, 5 rock, 6 tree |
| Habitat (v3, redesign key) | 1 meadow, 3 water and wetland, 4 forest, 5 rocks and mountains, 7 dry and sunny, 8 fields and roadsides, 9 heath and bog, 10 coast |
| Petal | 1 four or less, 2 five, 3 many, 4 zygomorphic |

`filterPetal` is never empty for a flowering plant. Three petals and apetalous flowers use **1**. A gymnosperm order leaves `filterColor` and `filterPetal` empty and is omitted from `lists_4_*` and `counts_4_*`. It carries `filterLeaf` (1 bundle, 2 single, 3 tufts, 4 scales, 5 fans) and `filterCone` (1 long woody, 2 small round, 3 berry or cup) on `plants_headers` and `plants_headers_v3`. The app and the website filter those two fields in memory. *Ginkgo biloba* (id 1570) is a conifer in that key, not in the flower lists.
| Distribution | TDWG level-2 numeric codes (10 Northern Europe … 91 Antarctic). Mapped from POWO distribution text via `abherbs-auto/tdwg.csv`. |

The shipped app reads v2 (`counts_4_v2`, `lists_4_v2`, `plants_headers`). The redesign key reads `plants_headers_v3`, `counts_4_v3` and `lists_4_v3`, built from `plants_v2.habitats`. Those three nodes are world-readable and not client-writable. v3 has 14,310 count keys. Codes 2 and 6 are not reused. The all-empty key is `___`.

Client: `lib/key/filter_utils.dart` (v2). v3 paths: `firebasePlantHeadersV3`, `firebaseCountsV3`, `firebaseListsV3` in `lib/data/utils.dart`.

## Translations

`translations/{lang}/{latinName}`:

| Field | Meaning |
|---|---|
| `label` | Common name from a source in that language (Wikidata label/alias, that Wikipedia title, EPPO Global Database, GBIF vernacular names, or a flora). Never a translation of the English name. If no source, omit; the app shows the Latin name. |
| `names` | Extra sourced common names |
| `wikipedia` | Language Wikipedia URL |
| `description`, `flower`, `inflorescence`, `fruit`, `leaf`, `stem`, `habitat` | Required for "fully translated" |
| `toxicity` | Optional poison notes (contact rash, ingestion). Distinct from `plants_v2.toxicityClass`. |
| `herbalism` | Optional culinary and traditional-use paragraph. UI heading is **Uses**, with a “not medical advice” disclaimer. `/add-plant` and `/update-plant` fill it from a sourced use. |
| `trivia` | Optional. UI heading is **Notes**. Cultural history, etymology, folklore. Written only when a page that covers this species has a real hook. |
| `sourceUrls` | Localized sources |

Wikidata ingest creates a huge set of language codes (Wikipedia sitelinks). The app requests the device language. When the seven body fields are missing, the app and website show English for the empty body fields and keep the language's own `label` and `names`.

`isTranslated()` in `plant_translation.dart` requires the seven body fields above. Do not recreate `translations/{lang}-GT`. Plan: [TRANSLATIONS.md](TRANSLATIONS.md).

Live `translations` is read-only for clients. The app and website no longer collect volunteer translation edits.

## Observations

```
observations/
  by users/{uid}/
    by date/list/{key}     Observation
    by plant/{plant}/...
  public/
    by date/list/{key}
    by plant/...
    stats                  aggregates
  logs/
```

Observation fields (`lib/seen/observation.dart`): `id`, `plant`, `date` (legacy Java-style map + `time` millis), `latitude`, `longitude`, `note`, `photoPaths`, `status` (`private` / `public`), `order` (negative timestamp for newest-first), `indoors`. Guide rows also use `confirmed`, `source` (`camera`, `manual`, `import`), and `candidates`. A private row can carry `photoCloud: true` after its photos are in `private/{uid}/`. That flag is not part of `toJson`, so a Share payload and a full rewrite omit it.

`id` is `{uid}_{millis}`. Private rows are owner-only. Publish writes the same payload to `observations/public` with `status: review`; the reviewer (`review_observations.py`) sets `public` or `rejected` via Admin SDK.

Upload statuses used when publishing: `private`, `review`, `public`, `success`, `rejected`, `failure`.

`abherbs-auto/review_observations.py` is a Tkinter reviewer: download photos from the bucket, accept / reject / skip.

Public stats recounted 2026-09-28 from `observations/public/by date/list`: 1,778 outdoor observations with status `public`, 56 observers, 630 species. The same list also holds 260 indoor observations and 2 outdoor rows still in `review`; those are not in the 1,778. Heaviest countries on the stored stats remain SK / SI / GB / CH. The latest public observation is *Dahlia pinnata*, 18 September 2026. Private: 2,654 records in 172 accounts (1,958 uploaded and published, 609 with photos only on the phone, 87 rejected).

## Users

Read by the app after sign-in (`lib/person/authentication.dart`). Client-writable fields are only `token`, `favorites/{plantId}`, `purchases`, and `credits` (number 0–10000).

- `old version` — former plus-app entitlement (Admin / existing value only)
- `lifetime subscription` — leftover. The app and `identifyPlant` ignore it.
- `credits` — rewarded-ad balance (client can still set its own number)
- `token` — FCM
- `purchases` — product id list the phone still writes from its own store. It does not unlock another phone, and `identifyPlant` does not read it.
- `entitlements/products/{productId}` — `{ active, expiresAt, store, originalId, updatedAt }`. `store` is `app_store` or `play`. Cloud Functions write it after Apple or Google confirms the receipt. The owner can read it. Both phones unlock from `active`. `identifyPlant` treats an active `search_by_photo`, `store_photos_monthly`, `store_photos_yearly`, `field_guide_monthly`, or `field_guide_yearly` as unlimited names.
- `favorites/{plantId}`

## Photo storage layout

```
gs://abherbs-resources/
  photos/{Order}/{Family}/{Genus_species}/
    ac1.webp                square 1024 (add-plant; files already stored may be 512)
    Acer_campestre@1600.webp  illustration 1600×2400 (legacy: Acer_campestre.webp)
    Acer_campestre@400.webp   illustration 400×600
  families/
  observations/{uid}/{Plant_name}/{file}.jpg
  private/{uid}/{Plant_name}/{file}.jpg
  misc/                     terms, privacy
```

Firebase Storage: `photos/`, `families/`, `offline/`, `misc/` are public-read, client-write denied. `observations/{uid}/**` is public-read and owner-write (image, 10 MB); shared Sightings use it. `private/{uid}/**` is owner-read and owner-write (image, 10 MB). Field Guide and the Observations purchase copy a Seen photo there, including a name outside the book. The object key mirrors the `observations/` path. The rule file `firebase/storage.abherbs-resources.rules` was released to `abherbs-resources` on 2026-10-03 (`firebase.storage/abherbs-resources`). A signed-in owner can read and write `private/`. The default bucket `abherbs-backend.appspot.com` is deny-all. `firebase.json` has no Storage target, so a database or functions deploy does not publish these rules. Public **listing** of the GCS bucket is IAM, not these rules.

Local staging on this machine (from `abherbs-auto/constants.py`):

- Source plants: `~/whatsthatflower/plants/{Family}/{Name}/`
- Prepared photos: `~/whatsthatflower/storage/photos/{Order}/{Family}/{Genus_species}/`
- Observation review: `~/whatsthatflower/observations/`
- WCVP cache: `~/whatsthatflower/wcvp/`

Photo file names are `{first letter of genus}{first letter of species}{n}.webp` (`ac1.webp` for *Acer campestre*).

## Search by photo

1. The app sends the image to `identifyPlant`, which posts it to Plant.id v3.
2. Each suggestion's scientific name is looked up in `search_photo/{lowercase name without dots}`.
3. A hit contains `count` + `path` into the catalog (species or higher taxon).
4. Results are logged under `users_photo_search/{lang}/{uid}/{ts}` when the user is signed in. Anonymous logs are denied.

`settings/generic_entities` / `generic_labels` list Plant.id labels that are too generic to treat as a species (`plant`, `flower`, `leaf`, …).

## How lists and counts are rebuilt

The 4-axis indexes are not maintained by the Flutter app. After plants or headers change, `abherbs-auto` `python -m catalog.refresh` rebuilds them locally:

1. Generates every combination of color × habitat × petal × TDWG region (including empty “not selected”).
2. For each plant header, increments `counts_new/{key}` and adds the numeric plant id to `lists_new/{key}` when all selected slots match (a plant with several colors matches every one of those color slots).
3. Rebuilds `search_new/{lang}` from `translations/{lang}` labels and extra names, plus Latin + synonyms under `la`.
4. Rebuilds `search_photo_new` from APG IV taxa, Latin names, Freebase ids, and synonyms.

Those `*_new` trees are staging and client-write denied (Admin SDK only). The app reads `counts_4_v2`, `lists_4_v2`, `search_v3`, `search_photo`. Promote by copying staging → live, then set `versions/db_update`. See [BACKEND_MIGRATION.md](BACKEND_MIGRATION.md). The script currently writes JSON on disk only; it does not write Firebase.

## Why this model will need to change

Filter lists are **precomputed Cartesian products**. That is fast on a phone for 1.4k plants and four tiny enums. It is the wrong index for:

- 10⁵–10⁶ taxa
- plants that do not have petals or a flower color
- queries like "trees of Slovakia" or "Fabaceae in Mexico"

Any encyclopedia work should add a stable taxon id and a query model that is not `lists_4_v2`, without deleting the current indexes until the identifier UI is replaced.
