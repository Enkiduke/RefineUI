# Adventure Guide achievement and collection progress

The native expansion dungeon/raid cards show compact counters across **all difficulties**,
with unique rewards counted once and a thin combined progress bar. Hover for category
details and counting scope. The existing cards, expansion selector and navigation remain native.

The native dungeon/raid boss list displays earned/available counters for achievements,
appearances, pet species, mounts, and toys. Hover an icon for its counting rules.
The header above the list shows an earned/available count for each available category
(hover one for its missing rewards) and a combined percentage with a progress bar.

## Counting scope

- Expansion cards union all supported journal difficulties. Instance/boss details use
  the selected Adventure Guide difficulty, across all classes and slots.
- Appearances are unique visual appearances, using difficulty-specific item links.
  Owning another source of the same appearance counts as collected.
- Pets are unique species, mounts are mount IDs, and toys are toy item IDs.
- Shared loot counts for every associated boss but only once in the instance total.
- Achievements span difficulties. Boss attribution uses the existing name/description/path
  text matching, which is heuristic. Unmatched and instance-wide achievements remain in
  the instance total. Boss totals therefore need not sum to the instance total.
- Supported token rewards contribute their unique appearance IDs, including alternate classes.
- Only journal-listed appearances, pets, mounts, and toys are supported. Hidden drops,
  recipes, unsupported tokens, ensembles, illusions, housing decor, and other unlocks are
  not included. The percentage is completion of the tracked categories, not an exhaustive
  measure of every reward obtainable from an instance.
- `...` means data is incomplete; `earned+/available` means some ownership states are
  unknown. The combined percentage is withheld until all tracked data is known.
- Expansion cards retry unavailable journal/item data a few times (about 15 seconds),
  then show the counts they have without a percentage. Revisiting the card retries.

## Performance and lifecycle

Loot catalogs and account ownership use the shared Core services described in
[Collections.md](../../docs/Collections.md). Batches are cached across the Guide and
tracker. Ownership updates reuse discovery data. Expansion cards request summaries
only while visible, using one bounded worker; offscreen cards do not start scans.
Journal selection, difficulty, tier and loot filters are restored after every batch.

Resolved catalogs and completion snapshots also survive reloads through the
account-wide [journal cache](../../../docs/JournalCache.md). Collection events
refresh ownership from compact instance manifests while retaining discovery.
Interface/locale changes, ownership revisions, and bounded expiry protect against
stale saved data. Blizzard's broad collection initialization events do not erase
the account cache during login or `/reload`.

The native ScrollBox stays virtualized. Rows retain their native height and allocate compact badges
once per recycled frame. Existing boss clicks and lockout overlays remain available.
Zero-total categories are hidden and the remaining badges pack into one line.
The parchment-toned bordered summary reserves 76 pixels of the list area: 24 pixels
below the original list top for the instance portrait, a 40-pixel header, and a
12-pixel gutter above the first boss artwork.

## Validation

From the addon root, using Lua 5.1:

```text
lua Tests/Instances.lua
lua Tests/EncounterCompletion.lua
lua Tests/InstanceCompletion.lua
```

The suites mock game APIs and cover scan budgets, warm-cache reuse, shared drops,
appearance deduplication, pet species IDs, unknown/missing data, filter restoration on
errors, difficulty changes, cancellation, and recycled native row initialization.
They do not replace in-game validation.

In game, reload and inspect a raid with shared loot, switch difficulty and boss selection,
scroll through the entire boss list, hover the badges/header, and verify that native loot
filters remain unchanged. Check the custom achievement tab and collection updates too.
