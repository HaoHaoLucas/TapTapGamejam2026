# 卡牌美术

`faces/` 为卡底、卡背和房间图，`glyphs/` 为裁去透明留白的数字与运算符，`marks/` 为强化与槽位图标。游戏使用 `scripts/cards/card_art.gd` 统一组合这些图片，数值和底板取强化后的实际值。

`source/` 保留压缩包内使用的原始 PNG（以 `.gdignore` 排除游戏导入）；`manifest.json` 记录压缩包原路径、SHA256、加工方式和重复印记对应关系。6–9、零的配色变体及九种缺失强化图标均为本地加工，无生图 API。

安装 Pillow、numpy 后，在仓库根目录重新生成：

```powershell
py tools/prepare_card_art.py '完整路径/卡牌.zip'
```

回归验证与实际渲染截图（去掉 `--headless` 才可截图）：

```powershell
& $godot --headless --path . --script tests/card_art_test.gd
& $godot --path . --script tests/card_art_test.gd -- --capture
& $godot --path . --script tests/run_choice_layout_test.gd -- --capture
```

截图输出到 `build/card-art-qa/` 和 `build/layout-qa/`。
