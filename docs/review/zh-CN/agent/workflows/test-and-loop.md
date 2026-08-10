# 工作流：测试与循环

## 目的

运行选定的黑盒覆盖，形成文本优先的结论，更新归属知识，然后完成或返回修复。

## 首先读取

- `docs/agent/knowledge-index.md`
- `docs/agent/black-box-tests.md`
- `docs/agent/black-box/interfaces.md` 的选定章节
- `docs/agent/operations/game-automation.md`

## 匹配失败后读取

| 失败 | 还要读取 |
| --- | --- |
| 原始键、英文、乱码、未知来源 | `text-sources.md`，再读取 catalog 操作专题 |
| 动态顺序、损坏链接/高亮、递归悬浮 | 按 `EntryPointId` 或来源定位器直接查询组合规则 JSON |
| 翻译质量 | `translation-style.md` |
| 启动/XML/设置/宗教/ClanCard 崩溃 | `crash-risks.md`，再读取 `crash-risks/startup-and-content.md` |
| 字体、图集、图标、缺字形、重载/OOM | `crash-risks.md`，再读取 `crash-risks/runtime-and-assets.md` |
| 托管重写、概念链接、逻辑敏感显示 | `crash-risks.md`，再读取 `crash-risks/managed-rewrites.md` |
| XML/DLL 补丁路径 | `text-sources/managed-patching.md` |

## 会话步骤

1. 确认当前成功的打包/安装/烟测交接；否则先运行打包/安装。
2. 选择 Active Focus 与仅受变更影响的界面场景。完整回归仍需选择加入。用户批准指定
   固定存档回放时，只执行该选定场景。
3. 每个受影响场景只构建并静态验证一次，然后运行已获授权的固定存档回放。绝不为了
   发现无关界面是否错误而创建新的随机世界；重复随机世界创建仍需用户明确确认和手动
   流程确认。
4. 未授权回放时，将准备好的场景交给用户手动执行；否则从获准固定存档点收集带光标
   标记的截图和文本跟踪证据。
5. 用户后来提供手动崩溃结果时，使用崩溃流程：将截图和新的 `Crash.AtGLog` 块记录为
   主要证据。
6. 只有未授权回放时才能给出 `Stopped`（等待用户运行）结论；否则报告测得的回放结果。
7. **每个结论后、做其他事情前都运行 `update-knowledge.md`。** 使用其中的知识维护
   步骤，将通过覆盖、失败、限制和文本证据纳入其归属文件。
8. 若结论为 `Failed`，除非满足停止条件，否则使用已更新知识返回评估/修复。对于用户
   提供的手动结果，不得自主重试游戏。
9. 知识更新后报告停止/等待手动结果。

## 用户确认的探索边界

默认禁用创建随机世界的工作流。用户明确重新授权时，只执行其请求的流程，不能自主
调整坐标、增加覆盖、修改停止条件或迭代。

## 停止条件

- 只剩没有隔离覆盖的逻辑敏感编辑。
- 三次修复/测试循环都没有新证据。
- 结果需要不可获得的人工视觉判断。
- 时间或任务预算结束。
