# 场景化交接说明（`codex/battle-scene`）

> 分支从 `hao/battle-v1.2` 的 **`813bca7`**（"Support 4 choice slots; hand composition repair"）分出，共 **7 个提交**，`behind 0`（截至 2026-10-17）。可直接 `git merge --ff-only`。

## 一、改了哪些文件

| 文件 | 改了什么 |
|---|---|
| `scenes/run/run_battle.tscn` | 13 行空壳 → **真节点树**：79 个节点、8 条 `[connection]`、主题（`Theme` + `SystemFont` + 11 个 StyleBox）作为**子资源**内嵌 |
| `scripts/run/run_battle.gd` | 965 → 约 580 行。删掉建 UI 的 5 个 `_build*` 与 4 个 helper；27 个写入点改成 `@onready` **`$` 绝对路径**取节点。**逻辑与写读数的代码一字未动** |
| `scenes/run/run_shell.tscn` | 新增 `Battle` 节点（`run_battle.tscn` 的**场景实例**） |
| `scripts/run/run_shell.gd` | 删掉自己 `load` / `instantiate` / `add_child` 战斗屏的四行，改 `@onready var _battle: RunBattle = $Battle`；修 z 序 |

## 二、三条行为变化（需要知道）

1. **程序不再接管布局。** 删掉了 `_fit_board()`（它每次 `_ready` / 窗口 `resized` / 重新显示都会覆盖 `Board` 的 `scale` / `size` / `position`）、`DESIGN` 常量、以及根节点上的 `set_anchors_and_offsets_preset` 调用。
   ⇒ 编辑器里摆的就是运行时的样子；**窗口尺寸变化不再自动缩放**，换分辨率要靠锚点。
   ⇒ 唯一还由程序写的位置是血条 `Track/Fill` 的 `anchor_right`（按生命比例，数据驱动）。
2. **战斗屏是 `run_shell` 的场景实例**，跟跑图壳**同时进树**、默认隐藏；战斗内/外的切换方式**没变**，仍是 `_set_battle_visible()` 改 `visible`。z 序改成显式：`move_child(backdrop, 0)` + `move_child(_battle, -1)`（原代码只是"碰巧"对的）。
3. **4 处 null guard 收紧成 `assert`**（`_board` / `_enemy_name` / 两个连击点 / `_hand_box`）：节点找不到时当场报错，不再静默停在默认文字。

## 三、新增的判据

| 文件 | 作用 |
|---|---|
| `tests/run_battle_view_dump.gd` | **gold 生成器**（不是判据）：固定 seed 开一局，跑固定序列（组一式 → 提交 → 烧牌 → 结束回合），在 5 个检查点 dump 27 个读数 + 79 个节点属性 + 连接表 |
| `tests/gold/run_battle_view_gold.json` | 迁移**前**的屏幕快照，随分支提交一起入库 |
| `tests/run_battle_view_test.gd` | 与 gold **逐项对拍**：27 读数 / 79 节点属性 / 连接表 |
| `tests/run_battle_scene_shape_test.gd` | 结构判据：连接数 7、隐藏时停 `_process`、跨局无残留、无 session 不崩、挂载关系与 z 序 |

跑法与全项目一致：

```
godot --headless --path . --script tests/<name>.gd
```

判据 = stdout **无** `SCRIPT ERROR|Parse Error|Compile Error` **且出现** `PASS:`。**退出码不可信**（Godot 报错后仍会 exit=0 且打完 `PASS:`）。当前 **13 份全绿**。

## 四、我们没碰的东西

- 逻辑层一律没动：`CombatSession` / `RunContext` / `CardBattle` / `MonsterRules` / `CardService` / `DrawService` / `EquationService`。
- `run_shell` **自己的 UI** 仍是代码建的（`_header` / `_status` / `_body` 那一套），这次没场景化。

## 五、已知遗留（不是这次引入的）

| 项 | 说明 |
|---|---|
| 样式源有四处 | `run_battle.tscn` 的局部 `Theme`、`run_shell.gd` 自建的 `Theme`、`card_view.gd` 自建的 `StyleBoxFlat`、`main_menu` 的贴图按钮 ⇒ 换一套美术要改四处 |
| 字体是 `SystemFont` | 依赖本机"微软雅黑"，导出到别的机器字形会变 |

## 六、需要确认的一件事

我们这次**接管了这四个文件**：`scenes/run/run_battle.tscn`、`scripts/run/run_battle.gd`、`scenes/run/run_shell.tscn`、`scripts/run/run_shell.gd`（后两个只改挂载方式）。如果你们还要动这四个，请先说一声，避免双写。
