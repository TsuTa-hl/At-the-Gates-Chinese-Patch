# 崩溃风险与回滚索引

仅用此索引对崩溃或高风险编辑分类。修改受影响子系统前读取一个链接专题；默认不要
加载全部三个。

| 症状或变更 | 下一步读取 |
| --- | --- |
| 启动失败、XML、工作目录、设置、宗教、ClanCard 别名 | [startup-and-content.md](crash-risks/startup-and-content.md) |
| CJK 缺字形、图标损坏、字体内存、设备重置、游戏内重载/OOM | [runtime-and-assets.md](crash-risks/runtime-and-assets.md) |
| Common/UI/Game/ElfTools 重写、概念链接、派系/日期/通知术语 | [managed-rewrites.md](crash-risks/managed-rewrites.md) |

## 隔离前始终不安全

- 不得宽泛替换 Common 概念标识符、派系名、日期术语或 `Clan <Name>` 通知前缀。
- 补丁保持小且可逆。新的风险变更只有在构建、安装、烟测和目标 UI 回归完成后才可
  保留。
- 游戏崩溃时，先保留文本崩溃摘要，再恢复最后已知良好产物；不要叠加更多推测编辑。

## 必需回滚事实

- `DynamicCjk` 是默认渲染器。`MergedFonts` 仅用于回滚，绝不能替换原始图标字形。
- ClanCard 中文别名资产是生成的构建输出；安装翻译后的纪律标签时必须仍可用。
- 补丁输出可能短暂处于内存映射状态。使用有界复制助手，不能直接原始替换复制。
