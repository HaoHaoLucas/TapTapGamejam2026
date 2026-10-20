"""Import the first art archive only. Requires Pillow; never touches assets/cards.

Usage: py tools/import_battle_assets.py FIRST.zip --exclude CARDS.zip
GIF frames are disposal-aware RGBA composites. Each clip uses ONE transform,
referenced to its final entrance / initial death pose, never per-frame recropping.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/battle/imported"


def usage(name):
    stem = Path(name).stem
    if "主菜单" in name:
        if stem == "menu":
            return "主菜单背景（保留原接入）"
        if stem == "setting_bg":
            return "设置弹窗底板（保留原接入）"
        if stem.startswith("newgame"):
            return "新游戏确认弹窗底板／确认取消按钮状态（保留原接入）"
        return "主菜单开始／新游戏／设置／退出按钮常态或悬停（保留原接入）"
    if stem.startswith(("map_bg_", "battle_bg")):
        return ("地图" if stem.startswith("map") else "战斗") + {"1": " 1–3 层背景", "2": " 4–6 层背景", "3": " 7 层及以上背景"}[stem[-1]]
    if stem.endswith("_enter"):
        if stem in ("MON_INK_enter", "MON_PARITY2_enter", "MON_PRIEST_enter"):
            return "备用入场动画：已注册；正常开战为另一形态，机制切换直接换静态图"
        return "开战 0.4 秒后单次入场" + ("；最后可见合成帧同时作为待机图" if stem == "MON_RUST_enter" else "")
    if stem.endswith("_die"):
        return "击杀时对应形态的单次死亡动画（包含在 2 秒胜利展示内）"
    if stem.startswith("MON_"):
        return {"MON_INK": "偶数回合乘法税 × 静态形态", "MON_INK2": "奇数回合减半税 ÷ 静态形态", "MON_PARITY": "要求奇数的一眼形态", "MON_PARITY2": "要求偶数的两眼形态", "MON_PRIEST": "治疗取消后的闭嘴形态", "MON_PRIEST2": "准备治疗的张嘴形态"}[stem]
    return {
        "battle_human_": "玩家正常立绘，合成脚下阴影",
        "battle_human_die": "HP 归零第 1 秒跪倒，合成脚下阴影",
        "battle_human_die2": "HP 归零第 2 秒倒地，合成脚下阴影",
        "battle_": "裁切为顶部 HUD 边框与底部手牌边框",
        "battle_hud2_": "算式区域纸张底板",
        "battle_hud_": "牌堆、准备／胜利浮层、暂停弹窗及战斗背包纸张底板",
        "battle_hud_monster_": "怪物红色血条填充",
        "battle_hud_monster_bottom": "怪物血条底图",
        "battle_hud_player_": "玩家黄色血条填充",
        "battle_hud_player_bottom": "玩家血条底图",
        "battle_hud_timer_": "准备／回合／追击计时条填充",
        "battle_hud_timer_bottom": "计时条底图",
        "battle_log_1": "发射按钮",
        "battle_log_2": "结束回合按钮",
        "battle_log_continue": "暂停入口：实际图片为暂停双竖线",
        "battle_log_pause": "继续游戏：实际图片为播放三角",
        "battle_log_exit": "暂停菜单退出游戏图标",
        "battle_log_restart": "暂停菜单重开本场战斗图标",
        "battle_shadow": "怪物脚下阴影；同时合成进三个玩家姿态",
    }.get(stem, "开战立即播放裂隙（比怪物早 0.4 秒）")


def entries(path):
    result = {}
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            if not entry.flag_bits & 0x800:
                try:
                    name = name.encode("cp437").decode("gbk")
                except UnicodeError:
                    pass
            if name.lower().endswith((".png", ".jpg", ".gif")):
                result[name] = archive.read(entry)
    return result


def union(boxes):
    boxes = [b for b in boxes if b]
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


def normalize(image, bounds, reference, height=400, anchor=320):
    scale = height / (reference[3] - reference[1])
    crop = image.crop(bounds)
    crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.LANCZOS)
    x = round(anchor + (bounds[0] - (reference[0] + reference[2]) / 2) * scale)
    y = round(480 + (bounds[1] - reference[3]) * scale)
    canvas = Image.new("RGBA", (720, 600))
    canvas.paste(crop, (x, y))
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    parser.add_argument("--exclude", required=True)
    args = parser.parse_args()
    source = entries(args.archive)
    excluded = {hashlib.sha256(b).hexdigest() for b in entries(args.exclude).values()}
    OUT.mkdir(parents=True, exist_ok=True)
    inventory = []
    clips = {}
    for name, blob in source.items():
        digest = hashlib.sha256(blob).hexdigest()
        row = {"source": name, "sha256": digest, "outputs": []}
        inventory.append(row)
        if digest in excluded:
            row["usage"] = "excluded: duplicate in card archive"
            continue
        if "主菜单" in name:
            stem = Path(name).stem
            menu = {"menu": "bg_menu.jpg", "newgame_": "dlg_newgame.png", "setting_bg": "bg_settings.png"}
            for prefix, action in [("menu_btn_01", "start"), ("menu_btn_02", "new"), ("menu_btn_03", "options"), ("menu_btn_04", "quit"), ("newgame_btn_01", "confirm"), ("newgame_btn_02", "cancel")]:
                if stem.startswith(prefix):
                    menu[stem] = f"btn_{action}_{'hover' if '悬停' in stem else 'normal'}.png"
            path = ROOT / "assets/ui/menu" / menu[stem]
            assert path.exists(), path
            row.update(usage="existing main menu", outputs=[path.relative_to(ROOT).as_posix()])
            continue
        image = Image.open(io.BytesIO(blob))
        stem = Path(name).stem
        if name.lower().endswith(".gif"):
            key = stem if stem.startswith("MON_") else "rift"
            frames, durations = [], []
            for i in range(image.n_frames):
                image.seek(i)
                frames.append(image.convert("RGBA").copy())
                durations.append(image.info.get("duration", 200) / 1000)
            bounds = union([f.getchannel("A").getbbox() for f in frames])
            visible = [f for f in frames if f.getchannel("A").getbbox()]
            reference = (visible[-1] if key.endswith("enter") else visible[0]).getchannel("A").getbbox()
            if key == "rift":
                reference = bounds
            height = 320 if "PRIEST" in key else 400
            if key == "rift":
                height = 440
            clip_dir = OUT / key
            clip_dir.mkdir(exist_ok=True)
            paths = []
            for i, frame in enumerate(frames):
                path = clip_dir / f"{i:02}.png"
                normalize(frame, bounds, reference, height, 360).save(path)
                paths.append("res://" + path.relative_to(ROOT).as_posix())
            clips[key] = {"frames": paths, "durations": durations, "loop": False}
            row["outputs"] = [p.removeprefix("res://") for p in paths]
            row["usage"] = "opening rift" if key == "rift" else "entrance (opening state only; other variants registered as reserve)" if key.endswith("enter") else "death of current form"
            if key == "MON_RUST_enter":
                path = OUT / "MON_RUST.png"
                normalize(visible[-1], bounds, reference, height, 360).save(path)
                row["outputs"].append(path.relative_to(ROOT).as_posix())
            continue
        rgba = image.convert("RGBA")
        if stem.startswith("MON_"):
            pair = stem.rstrip("2")
            refs = [Image.open(io.BytesIO(source[f"战斗/怪物/{s}.PNG"])).convert("RGBA").getchannel("A").getbbox() for s in (pair, pair + "2")]
            reference = union(refs)
            rgba = normalize(rgba, reference, reference, 320 if "PRIEST" in stem else 400, 360)
            row["usage"] = "mechanics-derived monster form"
        elif stem.startswith("battle_human"):
            ref = Image.open(io.BytesIO(source["战斗/battle_human_.PNG"])).convert("RGBA").getchannel("A").getbbox()
            rgba = normalize(rgba, union([ref, rgba.getchannel("A").getbbox()]), ref, 400, 270)
            shadow = Image.open(io.BytesIO(source["战斗/ui/battle_shadow.PNG"])).convert("RGBA")
            shadow = shadow.crop(shadow.getchannel("A").getbbox()).resize((200, 48), Image.Resampling.LANCZOS)
            ground = Image.new("RGBA", rgba.size)
            ground.alpha_composite(shadow, (170, 444))
            ground.alpha_composite(rgba)
            rgba = ground
            row["usage"] = "player normal / kneeling / lying down"
        elif stem == "battle_":
            for part, box in [("top", (0, 0, 2560, 425)), ("bottom", (0, 1100, 2560, 1440))]:
                path = OUT / f"battle_frame_{part}.png"
                rgba.crop(box).save(path)
                row["outputs"].append(path.relative_to(ROOT).as_posix())
            row["usage"] = "top HUD and bottom hand frame"
            continue
        elif "/ui/" in name:
            rgba = rgba.crop(rgba.getchannel("A").getbbox())
            row["usage"] = "battle HUD, paper panels, menu controls, or character shadow"
        else:
            row["usage"] = "depth tier background (1-3 / 4-6 / 7+)"
        path = OUT / (stem + ".png")
        rgba.save(path)
        row["outputs"].append(path.relative_to(ROOT).as_posix())
    for row in inventory:
        if not row["usage"].startswith("excluded:"):
            row["usage"] = usage(row["source"])
    (OUT / "animations.json").write_text(json.dumps(clips, indent=2), encoding="utf-8")
    (OUT / "inventory.json").write_text(json.dumps(inventory, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# 第一份素材包逐项清单", "", "来源：`1(2).zip`。`卡牌.zip` 仅用于重复检查，未导入或改写卡牌素材。", "",
             f"共 {len(inventory)} 项；与卡牌包 SHA-256 相同的项目 {sum(row['usage'].startswith('excluded:') for row in inventory)} 项；注册 {len(clips)} 个单次动画。",
             "", "输出路径及原文件 SHA-256 见同目录 `inventory.json`，帧时长见 `animations.json`。", "", "| 原始文件 | 使用位置／备用说明 |", "| --- | --- |"]
    lines += [f"| `{row['source']}` | {row['usage']} |" for row in inventory]
    (OUT / "INVENTORY.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Inventoried {len(inventory)} source assets; registered {len(clips)} nonlooping animations.")


if __name__ == "__main__":
    main()
