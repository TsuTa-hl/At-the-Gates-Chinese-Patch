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

## Tags and Placeholders

Preserve these exactly unless the surrounding system explicitly requires a
translated display term:

- `[TAG]`, `[Tag|KEY]`, `[HOTKEY:*]`, `[COLOR:*]`, `[NEWLINE]`,
  `[BLANK-LINE]`
- Runtime variables, IDs, enum-like keys, file paths, URLs, version numbers,
  World IDs, and generated names
- Punctuation required by the token or tag format

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
- Some faction names and labels treated as logic-sensitive

Do not force these into Chinese solely for stylistic consistency.
