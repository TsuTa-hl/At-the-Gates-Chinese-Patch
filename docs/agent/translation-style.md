# Translation Style

Use this guide when translating newly discovered safe text or reviewing existing
Chinese strings.

## Setting

- The game is a 4X strategy game about late antiquity, the Roman frontier,
  migrating peoples, tribal survival, and so-called barbarian factions.
- In Chinese terms, treat it as a `古罗马晚期` / `蛮族部族` historical strategy
  setting about migration, survival, and frontier politics.
- Chinese text should fit a historical strategy UI, not a modern casual app.

## Voice

- Prefer concise, steady, historically grounded Chinese.
- Avoid internet slang, modern jokes, over-literal machine translation, and
  excessive literary/classical wording.
- Use direct strategy-game language for commands, costs, requirements, and
  warnings.
- Keep character dialogue natural and readable, with light period flavor only
  when the English supports it.

## UI and Layout

- Button labels should be short and action-oriented.
- Tooltips may use fuller sentences, but should stay compact enough to fit the
  panel.
- Do not add artificial spaces between Chinese characters.
- Preserve readable spacing around icons, numbers, variables, and inline tags.
- If a long English sentence must fit a narrow UI surface, compress the Chinese
  while preserving gameplay meaning.
- Rich-text concept links may render with extra visual spacing around the
  linked Chinese term. Do not add padding characters to compensate, and do not
  remove useful concept tags solely for cosmetic spacing unless the specific UI
  has been proven safe without the tag.
- For dynamic property lines where a concept label precedes a scope qualifier,
  keep the concept link in place and render the qualifier parenthetically (for
  example, `资源产出（由自己建造的建筑）降低-10%`) rather than concatenating
  nouns into an ambiguous order.

## Tags and Placeholders

Preserve these exactly unless the surrounding system explicitly requires a
translated display term:

- `[TAG]`, `[Tag|KEY]`, `[HOTKEY:*]`, `[COLOR:*]`, `[NEWLINE]`,
  `[BLANK-LINE]`
- Runtime variables, IDs, enum-like keys, file paths, URLs, version numbers,
  World IDs, and generated names
- Punctuation required by the token or tag format

For composed or rich-text templates,
`translations/composite-text-rules.json` owns argument ordering, structural
preservation, and reusable rule selection. Generate a temporary `Composite` CSV
only when filtering or sorting its navigation context is useful. Keep the term and voice decisions
here, but do not introduce a word-level patch when the composition catalog
identifies a full display template.

## Core Terms

- Clan: `氏族`
- Tribe: `部族`
- Faction: `派系`
- Profession: `职业`
- Discipline: `纪律`
- Settlement: `定居点`
- Turn: `回合`
- Knowledge screen / Study: `知识界面` / `研究`
- Learn / Learned: `学会` / `已学会`
- Tech: `技术`
- Upgrade: `升级`
- Structure: `建筑`
- Builder: `建造者`
- Deposit: `资源点`
- Stockpile: `库存`
- Supply: `补给`
- Supply Reserve: `补给储备`
- Support Limit: `支持上限`
- Fame: `声望`
- Cloth: `布料`
- Treasure: resource label `财宝`; `财富` is acceptable in prose when it reads
  more naturally
- Caravan: `商队`
- Cargo Space / Cargo: `货舱` / `货物`
- Ennoble / Ennobled: `册封` / `已册封`
- Approach: `态度`
- Relationship Level: `关系等级`
- Influence: `影响力`
- Reputation: `声誉`
- Leverage: `筹码`
- Leader: `领袖`
- Emissary: `使者`
- Mercenary / Mercenaries: `佣兵`
- Alliance: `同盟`
- Magister Militum: `军务长官`
- Luminary / Minister: `贤才` / `大臣`
- River / Rivers: `河流`
- Hill / Hills: `丘陵`
- Road: `道路`
- Marsh: `沼泽`
- Border / Borders: `边界`
- Control / Controlled: `控制区` / `受控`
- Religion: `宗教`
- Naval: `水上`
- Active: `主动`
- Warrior / Warriors: `战士`
- Civilian / Civilians: `平民`
- Apprentice / Apprentices: `学徒`
- Resident: `驻留者`
- Family / Families: `家庭`
- Damage: `伤害`
- Mood: `心情`
- Morale: `士气`
- Retreat: `撤退`
- Combat XP: `战斗经验`
- Noble: `贵族`
- Crime / Crimes: `罪行`
- Desire / Desires: `愿望`
- Feud / Feuds: `纷争`
- Siege / Besiege: `围攻`
- Encamp: `扎营`
- Dig In: `固守`
- Pack Up / Packed Up / Unpack: `打包` / `已打包` / `展开`
- Pillage / Pillaged / Pillaging: `劫掠` / `已劫掠` / `劫掠中`
- Spoilage: `腐坏`
- Degrade / Degraded: `枯竭` / `已枯竭`
- Offline: `停工`

Update this list when a new recurring term is introduced.

For profession production rows, translate the repeated `increased by` fragment
as `提高` at each method offset and render the source ` ... OR ...` connector as
`；或`; do not leave an ellipsis placeholder that obscures the relation between
the two alternatives. Keep `Supply Level`, `Traits`, and `Crimes` as linked
concepts rather than translating their identifiers.

For numeric modifiers, all positive `increased by` forms use an Arabic-number
percentage (`提高75%`, `提高50%`, `提高33%`, `提高25%`, `提高20%`). The dynamic
`increased by 4x` branch retains the source integer and therefore displays as
`提高400%`; its scoped managed rewrite is recorded as
`HumanReadableModDynamicPercent`. The separate multiplier words use Arabic
digits in the `变为4倍` / `变为3倍` / `变为2倍` form.

For clan placement clauses, a standalone runtime ` of a ` is not the possessive
`的`; map it to `，驻留在` so phrases such as `居民 of a 建筑` become
`居民，驻留在建筑` without leaking the English connector.

For the forage tooltip, keep the sentence connectors compact: ` will ` is
Chinese “将”, `This ` is Chinese “该”, and the rich trait phrase
`become obsessed with the idea of` is Chinese “会痴迷于”. These are
scoped display decisions, not global word replacements.

For Relationship Level tooltips, translate the delta-reason connectors and
reason phrases as one scoped display family (`from`, `borders being too close
(within 6 tiles)`, `shared religious beliefs`, and `suffering differing
religious beliefs`). For diplomacy-operation tooltips, map `at`, `DENOUNCE`,
`AND...`, `OR...`, and `You` at their method-scoped operands. Preserve all
concept-link markup and apply plain fragments only outside bracketed tags.

For the UBL-TVF residual group, direct `Bandit`/`Pillage`, `This`, `next`, and
`As` operands are also method-scoped. Movement/status/combat-XP labels use the
same scoped connector rules, and every training title of the form `as
<profession>` is rendered with the unified Chinese connector `为`.

## Acceptable Remaining English

The following may remain English unless a safe display-only source is identified:

- Generated character or clan names
- Generated notification prefixes such as `Clan <Name>` until a safe
  display-only source is isolated
- World IDs
- Version numbers
- URLs and file paths
- Hotkey labels and technical markers
- The product title `At the Gates` when it appears as a title/name rather than
  ordinary prose
- Non-tribal faction names and labels whose logic-sensitive source has not been
  separately mapped

Do not force these into Chinese solely for stylistic consistency.
