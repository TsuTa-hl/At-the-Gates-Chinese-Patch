# known-texts 5.5 预筛选文案（供试验汉化参考）

来源：`docs/review/known-texts.csv` 中 `Status=Skipped` 的文本筛选，作为 5.5 试验参考，不直接用于 IL patch 精准替换。

优先级标注约定：
- `P0`：高优先，建议直接进入 5.5 Trial
- `P1`：中高优先，建议一并验证
- `P2`：低优先，需上下文确认
- `P3`：暂不建议进入 5.5，建议先观察/保留英文

可复用已汉化文本基准：
- `Please show this to Jon!` → `请把这段给 Jon！`
- `Click to delete all saved game files... WARNING: This cannot be undone.` → 已译 `警告：此操作无法撤销。`
- `SHORTAGE WARNING` → 已译 `短缺警告`
- `Please Enter a Name for the Save File` → 已译 `请输入存档名称`
- `AtG save files can be found in this folder on your computer:` → 已译 `AtG 存档文件位于此文件夹：`

## A. 强烈建议进入 5.5 Trial（用户可见/高价值）

1. **AT THE GATES HAS CRASHED !**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P0**  
   - 判断：崩溃主标题级别文本，玩家会直接读到。  
   - 判断依据：已有 `ERROR/WARNING` 译例，符合现有界面术语口径；不译会显著降低中文体验一致性。  
   - 建议动作：试验并重点截图确认位置。  

2. **WARNING: MAJOR ERROR. Unable to find any valid portrait for new Clan ... The game will now crash. Please send a screenshot of this message along with your most recent save file to Jon Shafer.**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P0**  
   - 判断：崩溃类完整错误说明，含反馈动作。  
   - 判断依据：已有 `请把这段给 Jon！`、`请上传存档`相关译例，可复用语气并降低上报歧义。  
   - 建议动作：高优先入 Trial。  

3. **A map object is being killed during the load process! If AtG DIDN'T just update to a new version please post a bug report about this. If the game did just update, well, bad things might happen soon. Sorry!**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P0**  
   - 判断：加载异常与玩家可能遭遇的死路场景，用户价值明确。  
   - 判断依据：与“错误原因 + 玩家反馈”样式一致，已在项目中有对应错误块翻译。  
   - 建议动作：高优先，建议联动 `AT THE GATES HAS CRASHED !` 一并验证。  

4. **! ...PLEASE send your last 3 autosaves and a screenshot of this error message to Jon.**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P0**  
   - 判断：故障反馈流程文本，玩家理解成本高于英文。  
   - 判断依据：已有“发送存档/截图”中文范式可复用。  
   - 建议动作：先纳入 P0 试验。  

5. **Please show Jon this message and provide a save file right before it happened!**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P0**  
   - 判断：崩溃追踪前置动作，直接面向用户。  
   - 判断依据：同类反馈句型已汉化，且用户行为明确（“提供存档”）。  
   - 建议动作：与 4 一并纳入同批次。  

6. **Please show this to Jon! Intro Map mode enabled but invalid map index ( ... )**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P1**  
   - 判断：错误上下文明确，出现概率较低但属于地图初始化异常。  
   - 判断依据：已有“Please show this to Jon!” 统一译式，适合补齐。  
   - 建议动作：P1 试验。  

7. **Please help us fix this by providing all of the following :**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P1**  
   - 判断：错误指引文本，界面可见性尚可。  
   - 判断依据：有现成“反馈链路”翻译模板；但内容较短，需搭配上文。  
   - 建议动作：P1，绑定完整错误块处理。  

8. **Please show this to Jon.**  
   - Source: `source\AtTheGatesUI.original.dll`  
   - 优先级：**P1**  
   - 判断：UI 常见短句，重复出现时非常有价值。  
   - 判断依据：已有完全一致条目译文可直接复用。  
   - 建议动作：P1，优先用于回归模板。  

9. **' does not exist. Defaulting to portrait index 01. Please tell Jon about this error message ...**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P1**  
   - 判断：资源加载异常提示，属于面向玩家的故障诊断。  
   - 判断依据：已有“肖像/文件/资源加载”相关处理语义。  
   - 建议动作：P1，保持占位与参数片段结构。  

10. **. Please take a screenshot of this error box.**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P2**  
   - 判断：短句指令，常作为多行错误体的一部分。  
   - 判断依据：有完整错误文本可译性，但单行独立时易出歧义。  
   - 建议动作：待与前句绑定后入 Trial。  

11. **- Showing Save File Count Warning**  
   - Source: `source\AtTheGatesUI.original.dll`  
   - 优先级：**P1**  
   - 判断：与现有存档管理告警链路强相关。  
   - 判断依据：已有 `SHORTAGE WARNING` 与“存档告警”译例，语义衔接好。  
   - 建议动作：P1。  

12. **( 2 ) The [ Crash.AtGLog ] file in your install folder.**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P2**  
   - 判断：上下文通常为错误列表项，用户理解需整段。  
   - 判断依据：崩溃日志路径类已有可参考术语。  
   - 建议动作：P2（建议与上文完整列表一起处理）。  

13. **Unable to load assembly:**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P2**  
   - 判断：核心错误开头短语，通用性高。  
   - 判断依据：已存在 `ERROR` 与通用错误文本译法，可形成统一“错误入口”。  
   - 建议动作：P2。  

14. **Unable to overwrite existing save:**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P2**  
   - 判断：存档写入失败，用户可感知。  
   - 判断依据：同类型 `save` 文本已存在既有译法，连贯性可控。  
   - 建议动作：P2，与下一条同组处理。  

## B. 条件进入（片段化/需上下文）

1. **( 1 ) A text copy or screenshot of this message.**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P2**  
   - 判断：片段文本，依赖列表前后文。  
   - 判断依据：缺前缀/编号上下文时，单独翻译会导致句法不完整。  
   - 建议动作：暂缓入包，待抓到完整块后统一处理。  

2. **Invalid map size: [**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P3**  
   - 判断：参数化片段，缺失关键数值字段。  
   - 判断依据：可能是技术断言，且当前文本不完整。  
   - 建议动作：不直接入 5.5，先补全上下文。  

3. **is upgrading or downgrading into a [null] config. This is bad! Please send ...**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P3**  
   - 判断：内核状态兼容性提示，偏诊断。  
   - 判断依据：有反馈意图但可能与调试链耦合。  
   - 建议动作：观察，不做核心优先级。  

4. **( was not assigned a Zone! Please show Jon this.**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P3**  
   - 判断：偏内部逻辑报表。  
   - 判断依据：缺少用户决策上下文。  
   - 建议动作：先不入 5.5。  

5. **Unable to overwrite existing Faction Data file:**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P3**  
   - 判断：偏底层数据文件错误，触发路径低频。  
   - 判断依据：非纯 UI 提示，容易产生误翻译和维护成本。  
   - 建议动作：不建议。  

6. **( x _ x ) HE'S DEAD, JIM**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P3**  
   - 判断：明显调侃/彩蛋或内部日志语气。  
   - 判断依据：与用户可用性关系弱。  
   - 建议动作：不建议。  

7. **\***\*\* PAUSED \*\***\nNOTE: [**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P3**  
   - 判断：战斗日志类框架标记。  
   - 判断依据：与 `*** Battle ***` 同类型，通常不面向用户翻译。  
   - 建议动作：不建议。  

8. **[ 1 ] A text copy or screenshot of this message.** 与 **[ 2 ] The [ Crash.AtGLog ] file ...**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P2**  
   - 判断：列表项组合块，需完整拼接。  
   - 判断依据：单独翻译会破坏列表语义。  
   - 建议动作：保留为同块一次性试验。  

## C. 建议不进 5.5（非用户文案/低收益）

1. **Assigning/Adding/Removing/Calculating/...（Internal 状态变更类）**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P3**  
   - 判断：多为内部逻辑一致性校验文本。  
   - 判断依据：用户价值低，且属技术噪声。  
   - 建议动作：维持英文。  

2. **MovableObject / Pillaging / Structure is being exhausted / AdjacentZones...（内部运行日志类）**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P3**  
   - 判断：日志/调试语境，非玩家交互。  
   - 判断依据：当前文本多为动作级断言。  
   - 建议动作：不入 5.5。  

3. **Trying to change a [CannotAttack]/[CannotDigIn]/[CannotEncamp] Property...**  
   - Source: `source\AtTheGatesUI.original.dll`  
   - 优先级：**P3**  
   - 判断：属性枚举类内部保护提示。  
   - 判断依据：与程序行为紧耦合，且翻译风险高。  
   - 建议动作：不建议。  

4. **Negative caravan / Already has... / Unit already has a Desire... / Giving Control to Human / Structure ...**  
   - Source: `source\AtTheGatesGame.original.exe`  
   - 优先级：**P3**  
   - 判断：明显技术短语堆栈。  
   - 判断依据：缺少用户可见价值，且收益低。  
   - 建议动作：不建议。  

## 小结

给 5.5 的优先进入顺序建议：  
1) A1~A5（P0）  
2) A6~A11（P1）  
3) A12~A14（P2）  
4) B 与 C 仅在上下文确认后有选择性尝试，不建议大批量直接上包。

