# 飞驰申城 SKYRUSH: NEON SHANGHAI

赛博朋克夜上海街机竞速游戏。主角车是一台黑白双色的 Roadster 概念跑车，靠冷气推进器跳跃、悬停、飞行车道和空中翻滚。玩法参考 QQ飞车（漂移、小喷、氮气），加上警察追捕和碰撞物理。地图按比例压缩还原上海：外滩、陆家嘴、延安高架龙柱立交、南浦大桥螺旋引桥、收费站、加油站和充电站。

A cyberpunk night-Shanghai arcade racer starring a black-and-white concept Roadster (cold-gas thrusters: hops, hover, sky lanes, barrel rolls), with QQ Speed–style drifting, police pursuits and crash physics.

> 这是公开版快照，对应 M3.1 最后一轮评审时的状态，全部脚本都能通过检查，游戏可以完整运行。之后未完成的修复，以及 `ref/` 里的第三方参考图片，不在公开版里。
>
> Public snapshot of the state after the last worker review round: every script passes the project check and the game runs end to end. Later work-in-progress fixes and the third-party reference photos in `ref/` are not included.

- 引擎：Godot 4.7.2（Forward+、Metal、Jolt 物理 120 Hz）
- 建模：Blender 5.2，用 Python 程序化生成（城市、地标、道具）；主角车、交通车和警车是转换后的第三方模型（见下）
- 开发方式：21 个模块由 MiniMax M3.1 工人按任务书实现，Claude Opus 负责规划、评审和美术指导

## 运行

```sh
godot --path game                         # Godot 4.7.2；第一次打开会导入全部资源，需要一段时间
tools/godot.sh check                      # 检查全部脚本、场景和着色器（工具脚本默认仓库位于 ~/m/skyrush）
tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu --shots=3,9
tools/blender.sh run blender/npc_cars/web/convert.py   # 重新转换交通车和警车（build.py 只剩警用无人机）
```

操作：W/S 油门刹车，A/D 转向，Shift 漂移，Ctrl/J 氮气，空格 跳跃（长按大跳或悬停），Q/E 空中翻滚，F 离开飞行车道，Esc 暂停。完整键位见 `SPEC.md` §4。

## 目录

- `SPEC.md`、`ART.md`、`CONTRACTS.md`：游戏设计、美术规范，以及模块分工、坐标系和代码约定
- `briefs/`、`status/`、`reviews/`：每个模块的任务书、进度检查点和评审记录（`*-lead.md` 是美术总监的强制要求）
- `game/`：Godot 工程。`core/` 是核心契约与自动加载，其余目录按模块划分
- `blender/`：程序化建模脚本。`lib/` 是公共库，包括车身放样和导出
- `data/city/`：上海地图数据（道路、立交、街区、兴趣点、赛道）
- `ref/`：调研资料汇编（车辆、上海、玩法、技术、美术）。参考图片已移除，来源清单见各目录的 `INDEX.md` 和 `_meta.jsonl`
- `tools/`：Godot/Blender 包装脚本、M3.1 工人调度（`tools/m31/`）和贴图下载

## 状态

每个模块最多跑了 4 轮"实现 → Opus 评审 → 修改"，最终评审得分 3–7/10，记录在 `reviews/<unit>-r*.md`。游戏能完整跑起来，但离成品还有距离。项目于 2026-10-20 暂停。

## 第三方素材

- 主角车模：Khronos glTF Sample Assets 的 Car Concept（Eric Chadwick，CC BY 4.0，原型是 Unity Fan 的 CC0 模型），改成黑白双色并按本项目的车辆契约重新拆分，转换脚本在 `blender/car/concept/`，署名全文见 `CREDITS.md`
- 交通车和警车：Rgsdev 的 Free Low Poly Vehicles Pack（CC0），按车辆契约拆分材质和部件，转换脚本在 `blender/npc_cars/web/convert.py`，原始 FBX 和许可证在 `blender/npc_cars/web/source/`
- 贴图：Poly Haven、ambientCG（CC0），用 `tools/textures/fetch.py` 下载
- 字体：得意黑 Smiley Sans、Noto Sans SC（SIL OFL，许可证见 `game/assets/fonts/`）
