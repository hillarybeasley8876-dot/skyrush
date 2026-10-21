# SKYRUSH: NEON SHANGHAI (飞驰申城) — GAMEPLAY + FEEL DOSSIER

Research date 2026-10-19. Audience: the implementer (MiniMax M3.1) building in Godot 4.7.2 + Jolt.
Rule for you, implementer: **copy the numbers, do not invent new ones.** If a number feels wrong in
play, change it only in the tuning file (§8.6) and write down why.

Legend: **(src)** = taken from a cited source. **(meas.)** = measured by me from footage.
**(est.)** = my engineering estimate. **(unverified)** = plausible but I could not confirm.
**(clone)** = from a third-party QQ飞车 web clone (not Tencent data; numbers that are known to play OK).
**(ours)** = a design decision for SKYRUSH, not a copy of any game.

Raw downloads (untrusted data, text extracts only) live in `ref/gameplay/dl/b01..b14/`.
Scratch contact sheets live in `ref/gameplay/scratch/`.

Units everywhere: metres, kilograms, seconds, m/s (km/h only for HUD/speed tables; 1 m/s = 3.6 km/h).
Axes (Godot): +Y up. Vehicle nose = +Z local (Godot `Vector3.MODEL_FRONT`; a Blender model whose nose
faces Blender −Y ends up facing +Z after glTF export). If `ref/tech` states another convention, tech wins.

---------------------------------------------------------------------------------------------------
## 0. TL;DR — the 25 numbers that define the feel

| # | What | Value | Basis |
|---|------|-------|-------|
| 1 | Physics tick | 120 Hz, physics interpolation ON | Rocket League GDC 2018 (src) |
| 2 | Car mass | 1,900 kg (brief); real target 1,700 kg | MotorTrend (src) |
| 3 | Base top speed | 250 km/h (69.4 m/s) | (ours); QQ PC top car 225 km/h (src) |
| 4 | N₂ boost top speed | 300 km/h (83.3 m/s), +12 m/s², 3.0 s | QQ nitro 3.08–3.35 s (src) |
| 5 | 小喷 mini-boost | +22 km/h cap, +10 m/s², 0.68 s | QQ 小喷时间 0.68 s (src) |
| 6 | Hard speed cap | 330 km/h (91.7 m/s) | (ours) |
| 7 | 0–100 km/h | ≈ 2.4 s normal; ≈ 0.9 s with 完美起步 thruster launch | real Thrust 0–60 mph 0.85 s (src) |
| 8 | Drift min speed | 54 km/h (15 m/s) | (est.) |
| 9 | Drift slip angle | 26–52° (emerges from yaw 0.9–1.8 rad/s with λ 2.0 /s) | NWH "30–45° balanced" (src) |
| 10 | Drift speed loss | (1.5 + 8·sin β) m/s² | clone used 2.5+11·sin β (clone) |
| 11 | Gauge fill per tick (in slots) | max(0.015 × km/h lost this tick, 0.10 × dt) | QQ designer formula shape (src), constants (ours) |
| 12 | 3 s drift ≈ one full slot | 1 slot = 100 N₂ units, 2 slots max | QQ official article (src) |
| 13 | 小喷 window | opens on clean drift exit, 0.50 s long | clone 0.5 s (clone) |
| 14 | CWW W–W spacing | 0.55–0.85 s for full effect | QQ designer Q&A (src) |
| 15 | C–W spacing | ≤ 0.25 s for full effect | QQ designer Q&A (src) |
| 16 | Hop | Δv_y 11 m/s → apex 3.1 m, 1.1 s air, 25 N₂ | (ours) |
| 17 | Big Hop | Δv_y 17.5 m/s → apex 7.8 m, 1.8 s air, 50 N₂ | real car: 27 ft = 8.2 m (src) |
| 18 | Air gravity | 2.0 g (19.6 m/s²) while airborne | arcade practice; clone uses 30 m/s² |
| 19 | Barrel roll | 360° in 0.70 s, 20 N₂, 3.5 m side-dodge | (ours) |
| 20 | Camera vFOV | 62° base → 84° max | RaceRoom chase 62° (src); clone 66° (clone) |
| 21 | Camera position follow | λ = 14 /s; yaw follow λ = 7 (grip) / 4.5 (drift) | (clone) |
| 22 | Takedown cam | 2.7 s cut-away; 0.3× slow-mo for the first 1.2 s | 2.7 s = Burnout Paradise (meas.); slow-mo values (ours) |
| 23 | Takedown streak window | 10 s | Burnout wiki (src) |
| 24 | Heat 1→5 cooldown | 20 / 35 / 50 / 70 / 90 s | NFS MW05 20/45/75/90/120 s (src), shortened (ours) |
| 25 | Traffic | 50–70 active cars, spawn ring 180–350 m, despawn > 420 m | (est.) |

---------------------------------------------------------------------------------------------------
## 1. QQ飞车 (QQ Speed) mechanics — what we are copying

### 1.1 PC control scheme (端游) (src)

| Key | Function |
|-----|----------|
| ↑ | throttle; **release and re-press right after a drift = 小喷 (drift-exit mini-boost)** |
| ↓ | brake / reverse |
| ← → | steer |
| Shift | drift (hold with a direction; "Shift一定要点的很轻" — light taps for fine control) |
| Ctrl | use nitro (氮气) / use item; in item mode hold Ctrl to aim, release to fire |
| Alt | swap the 2 held items |
| W | dedicated 小喷 key used by experts instead of re-pressing ↑ ("用W键代替↑", W喷) |
| R | reset car onto track |
| Tab | change camera view |

Sources: 17173 2008 guide https://speed.17173.com/content/2008-03-10/20080310172701503.shtml ;
official modes page https://speed.qq.com/web202204/game.shtml ; official 2009 skills page
http://speed.qq.com/webplat/info/news_version3/147/14551/14572/14577/m15538/200907/5630.shtml ;
Tab view: https://m.ourplay.net/find/detail/164896 . Mobile has 2 arrows, 漂移 button, 喷 button,
2 item buttons (src: https://speedm.qq.com/webplat/info/news_version3/28528/28529/31655/m19806/201708/627219.shtml).

### 1.2 Drift entry and exit (src unless marked)
1. Enter: hold steer + tap/hold Shift. Start the drift ~**1.5 s before** the corner, ~45° entry angle
   (official mobile guides: https://speedm.qq.com/webplat/info/news_version3/28528/33593/33805/m19692/201709/631747.shtml ,
   https://fcsy.qq.com/webplat/info/news_version3/28528/33593/33805/m19692/201803/704423.shtml).
2. Hold: the car slides on an arc; Shift pressure/time sets the arc ("力气大了会漂过头、小了会弯度不够").
3. Exit = **拉车头 (pull the nose back)**: release Shift, press the opposite direction until the car
   is straight. Hitting the outer wall during the drift **cancels the 小喷 and the gauge gain**.
4. 小喷: when the nose is straight, release ↑ and press it again ("滑痕刚消失的一瞬间" = the moment the
   skid marks stop). Mobile shows this as the 喷 button lighting up (小喷键亮起).
   (17173 2008: http://news.17173.com/content/2008-03-17/20080317142458659.shtml)
5. A nitro or 小喷 fired after a drift also **cancels the tail wag** (车尾摆动) → cleaner straight.
6. Car stat "漂移能力" = drift yaw rate + how early 小喷 lights; higher = 小喷 lights earlier (src: designer Q&A
   https://speedm.qq.com/web201712/strategy-detail.shtml?newsid=9388344).

### 1.3 How drifting fills the nitro gauge (集气) (src)
Official designer formula (QQ飞车手游 策划面对面, 2020-01-15, https://fcsy.qq.com/gicp/news/595/9388344.html):
```
gauge gained per unit time while drifting = max( speed_lost × K_decel , dt × K_floor )
```
- Gauge comes mainly from **speed lost while drifting**; K_decel is the car's "减速集气系数".
- K_floor ("保底集气") gives a minimum trickle when the drift no longer loses speed (late drift, shallow
  "小刮" drifts). Most cars share the same K_floor.
- Rule of thumb from an official guide: **a 3-second drift or a 180° drift ≈ one full nitro**
  (https://speedm.qq.com/webplat/info/news_version3/28528/33593/33805/m19692/201709/631747.shtml).
- Enter drift points at **~240 km/h** to be sure to fill a nitro (official player guide
  https://fcsy.qq.com/webplat/info/news_version3/28528/33593/33805/m19692/201803/704452.shtml).
- Drifting while a nitro is burning and without collision gives extra gauge (same 2017 article).
- Gauge turns into one 氮气 item **only when the drift ends cleanly** with gauge ≥ 100%
  (moegirl: "集气达到100%并成功结束漂移状态时，获得一个氮气道具", https://zh.moegirl.org.cn/QQ飞车手游).
- Collisions reduce speed **and** gauge (official newbie page https://speedm.qq.com/web201712/greenhand.shtml).
- Car stat "集气效率" e.g. 90 % (爆天雷诺, 黑曼巴 PC), 95–96 % (mobile A cars) (src: official car pages).
- Slots: 2 nitro items can be held (PC HUD shows 2 square item slots top-left; 超级喷 merges "两个集气槽")
  (https://baike.baidu.com/item/qq飞车超级喷/3862160) (exact nitro cap = 2: unverified, but consistent).

### 1.4 Nitro (C / 氮气) and mini-boost (W / 小喷) numbers
Official PC stat cards (爆天雷诺 https://speed.qq.com/cp/a20200115btln/index.html ; 黑曼巴 Baidu):

| Stat | 爆天雷诺 (A/S) | 黑曼巴 (S) | mobile A cars |
|------|-----------|-----------|-----------|
| 直线最高速度 base top speed | 225 km/h | — | — |
| 氮气时间 nitro duration | 3.35 s | 3.35 s | 3.08–3.09 s |
| 小喷时间 mini-boost duration | 0.68 s | 0.68 s | 0.68 s |
| 氮气动力 nitro accel (game hp) | 789.76 | 802.1 | — |
| 小喷动力 mini-boost accel (game hp) | 814.44 | 819.38 | — |
| 集气效率 gauge efficiency | 90 % | 90 % | 95–96 % |
| 车重 mass | 1,325 kg | 1,470 kg | — |
| 转弯最小半径 / 高速转弯半径 | 3.88 m / 7.94 m | 3.71 m / 7.77 m | — |
| 转向失控 speed where steering goes loose | 195 km/h | — | — |
| 组队氮气 team nitro | 4.3 s | — | — |

Take-aways: 小喷 accel ≈ nitro accel (×1.03) but lasts 0.68 s vs 3.35 s; C-class car nitro 3.0 s
(Baidu 积木). Accel model: "基础动力" decays from 1.0× to **0.2×** as speed approaches base top speed;
nitro and 小喷 add a **constant** extra accel on top (designer Q&A).

**Speed-cap stacking rule (designer Q&A, exact):**
```
cap_base          = base_top
cap_nitro_only    = base_top + E_n           (E_n = nitro top − base top)
cap_mini_only     = base_top + E_w           (E_w = 小喷 top − base top)
cap_CW   = base_top + E_n + 0.3·E_w    (nitro then 小喷)
cap_WCW  = base_top + E_n + 0.4·E_w    (小喷, nitro, 小喷)
cap_CWW  = base_top + E_n + 0.8·E_w    (nitro, 小喷, 小喷)
cap_WCWW = base_top + E_n + 0.9·E_w
```
Extra 小喷 beyond these patterns add nothing (WWCWW = WCWW, CWWW = CWW). Without nitro, 小喷 do not
stack (they overwrite). Timing: C→W gap **≤ 0.25 s** for full effect; the two W in CWW must be
**0.55–0.85 s apart**; earlier or later = weaker. Measured by a player (A car 黑夜传说, full mods):
WCW reaches 283.4 km/h in 1.52 s and lasts 3.72 s; CWW reaches 303.2 km/h in 1.22 s, lasts 2.99 s;
bad W–W rhythm costs ~10 km/h (https://fcsy.qq.com/webplat/info/news_version3/28528/33593/33805/m19809/201803/704411.shtml).

### 1.5 Named techniques (what each one *is*, so we can design equivalents)

| Name | What happens | SKYRUSH equivalent (ours) |
|------|--------------|---------------------------|
| 小喷 (drift-exit boost) | re-press ↑/W right after a clean drift exit | same; 0.50 s window |
| 双喷 (double boost) | drift → tiny second drift ("点漂") → two 小喷 in a row; needs a drift that is not too tight (Baidu 双喷技巧) | "Chain": tap drift again ≤0.4 s after the first 小喷 to earn a 2nd 小喷 window |
| 断位 / 断位漂移 | during a drift, release and re-tap Shift: nose snaps straight faster, 小喷 lights earlier (in-game tutorial card: "通过断位迅速将车头拉正，也叫断位拉车头") | "Drift Cut": re-tap drift mid-drift = fast straighten + early 小喷 window |
| 段位 / 段位漂移 | optimal drift hugging the inside edge without touching it ("贴边而不撞边") (https://baike.baidu.com/item/QQ飞车段位技巧/15778959); 段位起步 = drift-tap start for 双喷 at race start | no special code; good racing line + Drift Cut |
| CW / WCW / CWW | stacking orders of nitro (C) and 小喷 (W), see caps above | same formula |
| 空喷 (air boost) | tap ↑/W while airborne → short boost in the air | Hop/ramp air: tap 小喷 key = air 小喷 (once per jump) |
| 落地喷 (landing boost) | after airtime, 小喷 lights on touchdown; "空喷晚点按，落地喷立马按" | Landing 小喷 window 0.45 s after ≥0.3 s airtime |
| 卡气 (gauge trick) | short extra drift between two 小喷 to top up the gauge | falls out of the gauge formula; no code |
| 撞墙点喷 | after a wall bounce, quick drift tap + 小喷 to recover | allow 小喷 window after a wall bounce if a drift was started ≤0.3 s after impact |
| 超级起步 / 完美起步 | press throttle as "1" vanishes / "GO" appears → "完美" text; too late = normal start (https://speedm.qq.com/gicp/news/603/138035.html) | 完美起步 = thruster launch (§8) |
| 双刹断氮 | double-tap brake cancels a burning nitro early | not needed (est.) |

Sources for techniques: http://fcsy.qq.com/gicp/news/603/7699215.html , https://www.cnblogs.com/Chqbelief/articles/17441226.html ,
http://speed.17173.com/moregame123/qfczmdwlct_2.shtml , in-game tutorial screenshot (dl/b11_qq_pc_imgs/bili.jpg).

### 1.6 Collision rules in QQ飞车 (src + est.)
- Any collision costs speed **and** gauge; a wall hit during a drift cancels that drift's 小喷 + gauge.
- Car-to-car contact pushes both cars; cars have a "碰撞重量" (collision weight, e.g. 400/450 on mobile
  cards) and some cars have "受撞车影响减弱40%" (40 % less affected by bumps) (moegirl; 17173 car card).
- Getting hit mid-drift: recommended to end the drift early (快速出弯) to avoid "锁胎" and a wall hit
  (https://news.17173.com/z/qqfcsy/content/03312018/100021447.shtml).
- No damage, no wrecks: QQ collisions only cost time. (SKYRUSH adds damage + wrecks, §7.)
- Working arcade wall rule (clone, plays well): reflect the normal velocity ×1.25 (restitution 0.25),
  keep tangential speed × (1 − 0.45·impact) where impact = |v·n|/|v|; impact > 0.3 during a drift ends
  the drift with no 小喷 (https://learn.zhoujunhui.com/blog/learn-qq-speed-sourcecode-with-ai).

### 1.7 Item mode (道具赛) basics (src)
Pick up random items from 道具箱 boxes on the track; hold 2 items; Ctrl uses, Alt swaps. Last place gets
better odds. Items (PC + mobile lists):

| Item | Effect |
|------|--------|
| 导弹 missile | hold Ctrl to aim (reticle green→red), release; homing, passes walls, target flips in the air |
| 磁铁 magnet | aim + release; pulls you forward to the target, slows it |
| 酷比 bubble | auto-hits the racer directly ahead; traps it in a floating bubble |
| 乌龟 turtle | hits 1st place; heavy slowdown (two turtles ≈ stop) |
| 恶魔 devil | reverses all opponents' steering |
| 龙卷风 tornado | placed on track; cars that touch it are lifted for seconds |
| 香蕉皮 banana | dropped behind; 360° spin and speed halved |
| 云雾 / 墨汁 cloud / ink | blinds racers behind / ahead |
| 闪电 lightning | hits everyone ahead |
| 加速 / 氮气 boost | speed burst |
| 天使 / 护盾 angel / shield | blocks attacks for a time (not magnet/cloud on mobile) |

Sources: https://speed.17173.com/content/2009-09-02/20090902102703842.shtml ,
https://speedm.qq.com/webplat/info/news_version3/28528/28529/31655/m19806/201708/627219.shtml ,
https://speed.qq.com/web202204/game.shtml . SKYRUSH does **not** need an item mode for v1; police
pursuit equipment (§3) plays that role. Keep the 2-slot HUD idea.

### 1.8 Reference feel numbers from a working QQ-like clone (clone)
A web clone of QQ飞车 ("做一个QQ飞车3D网页版") was dissected line by line here:
https://learn.zhoujunhui.com/blog/learn-qq-speed-sourcecode-with-ai (repo linked there). Not Tencent data,
but a concrete, playable baseline. Its tuning: fixed physics step **1/120 s**; vmax 55 m/s (198 km/h);
nitro vmax 76 m/s (274 km/h); global cap 86 m/s (310 km/h); accel 24 m/s²; nitro accel 40 m/s²;
brake 45 m/s²; coast 2.2 m/s²; max turn rate 1.9 rad/s, steer weakens ×(1 − 0.55·v/vmax);
drift yaw 1.5 rad/s (+0.85 when steering into the drift); velocity-follows-heading rate λ = 12 /s grip,
2.0 /s drifting, 5.2 /s at drift release; max drift angle 66°; drift speed loss (2.5 + 11·sin β) m/s²;
drift shorter than 0.22 s gives no 小喷; 小喷 window 0.50 s, "perfect" if pressed < 0.20 s;
小喷 +8 m/s top speed for 0.75 s; nitro 2.8 s, stacking cap 4.5 s; gauge rate = dt·(0.3 + 1.7·intensity)
·speedFactor; max 2 nitro; landing window 0.45 s after > 0.3 s airtime; start boost if throttle held in
the last 0.28 s of countdown; gravity 30 m/s² ("2–3× gravity makes jumps snappy").

---------------------------------------------------------------------------------------------------
## 2. QQ飞车 HUD, camera and the sense of speed

### 2.1 HUD layout seen in QQ飞车 screenshots (meas. from official/press screenshots, dl/b06, dl/b11)
PC (端游; a 2008 and a 2023 screenshot share the same layout):
- **Top-left**: race position — big italic rank ("1ST", or an orange circle with "2"), under it a list of
  racer names/avatars; 2 square item/nitro slots (≈ 64 px each at 1080p, est.) at the very top-left.
- **Top-right**: 时间 00'27"74 / 最佳 00'00"00 / 个人记录 01'48"85 stacked, right-aligned, white with
  dark outline; under them a large italic lap counter **"1/2 圈数"**.
- **Right-middle**: minimap = track outline in a dark translucent box; dots for racers.
- **Bottom-right**: round speedometer dial (needle arc, green→red), big digital number inside (e.g. 279),
  km/h.
- **Bottom-left**: long thin **N2O** gauge bar (cyan/blue fill) = 集气条.
- **Bottom-centre** (some modes): score/combo "009524 ×3" with a star.
Mobile: rank top-left, time + lap top-right, minimap under it, speed "280 公里/时" bottom-centre-left,
←/→ buttons bottom-left, big orange 漂移 button + 喷 button bottom-right.
Pop-up texts confirmed: "完美" on perfect start; countdown 3-2-1-GO in screen centre.
"完美漂移" as an in-race pop-up: (unverified) — it is the name of guides/marketing, not a confirmed popup.

### 2.2 Camera behaviour (QQ + general practice)
- Third-person chase camera, low and close; Tab changes the view (src: ourplay); the clone offers near /
  far / bumper presets.
- QQ marketing describes speed feel as "高速而产生的画面线条，再加上氮气释放时产生的蓝色火焰" — speed
  lines plus blue nitro flames (official modes article, 2017). Nitro flame colour by type on PC:
  normal = yellow, team = blue, super = deep purple (Baidu 超级喷) (mobile uses blue).
- Clone camera (clone): 3 presets {dist 8.2, h 3.0, look-ahead 5, look-height 1.3}, {12.5, 4.6, 6, 1.5},
  bumper {5.2, 1.9, 8, 1.1} m; camera yaw target = velocity_dir + 0.35·(heading − velocity_dir);
  yaw follow λ = 7 /s grip, 4.5 /s drifting; position follow λ = 14 /s (position tight, rotation lazy —
  "反了就会晕"); FOV = 66° + 0.12°·|v in m/s| + 9° nitro + 4° 小喷; hit shake decays ×1.8/s;
  bloom 0.55 → 1.05 during nitro; speed lines at high speed.

### 2.3 What creates the sense of speed — toolkit with numbers
Principles (Criterion "Vehicle Feel Masterclass", GDC 2018, slides OCR'd from
https://media.gdcvault.com/gdc2018/presentations/Harris_Matthew_VehicleFeelMasterclass.pdf):
"Camera = Handling"; use a **vehicle-led sprung camera** with 3 parameters: *convergence* (pull to
target), *momentum* (camera keeps moving), *damping* (camera speed limit); camera looks ahead along the
**velocity**, not the nose; the car's screen position should show the turning radius; sell heavy
landings with **shake + momentum with low damping**; assists should fade in/out, never switch binary.

| Cue | SKYRUSH value | Notes |
|-----|---------------|-------|
| vertical FOV | 62° at 0 km/h → +0.10°/(m/s) → +8° N₂ → +4° 小喷; clamp 84° | Godot `Camera3D.fov` is vertical (keep_aspect = KEEP_HEIGHT). RaceRoom chase cam 62° vFOV (https://forum.kw-studios.com/index.php?threads/is-there-a-way-to-change-chase-hood-and-bumper-camera-fov.21162/) |
| FOV smoothing | λ = 4 /s toward target | never jump FOV |
| camera distance | 6.0 m behind, 1.9 m up at rest; +1.2 m further back at V_TOP (linear with speed); on N₂ ignition fall back an extra 1.0 m over 0.25 s (the car surges away), return over 1.0 s after N₂ ends | (est.) |
| look-at point | car origin + 1.2 m up + velocity_dir × 4 m | (est.) |
| camera lag | position λ 14 /s, yaw λ 7 /s grip, 4.5 /s drift, yaw target 35 % toward nose | (clone) |
| speed lines | start 160 km/h, full opacity 280 km/h | §8.5 for implementation |
| radial blur | 0 below 200 km/h → strength 0.35 at 300 km/h; off in menus; user toggle | motion blur adds little at 60 fps+ (Disney Research: https://la.disneyresearch.com/wp-content/uploads/Presence-of-Motion-Blur-Effect-Does-Not-Improve-Gaming-Experience-Paper.pdf) — keep it subtle |
| shake | landing 0.10 m × (v_y/10), 0.30 s; wall hit 0.15 m, 0.25 s; N₂ ignition 0.04 m, 0.2 s | low-frequency (8–12 Hz) noise, not white noise |
| bloom/glow | glow intensity 0.6 → 1.0 in N₂ | Godot WorldEnvironment glow |
| chromatic aberration | 0 → 1.5 px at screen edge during N₂ | optional |
| audio | wind noise ∝ v², tyre squeal ∝ slip, thruster "whoomp" | sound sells speed as much as FOV |
| world | lane dashes every 6 m + 9 m gap (China standard, unverified), lamp posts every 30–40 m, overhead gantries — dense near-field detail = speed | coordinate with ref/shanghai |

Do NOT tilt the horizon with the car body roll; do NOT exceed 90° vFOV (nausea).

---------------------------------------------------------------------------------------------------
## 3. Police pursuit (NFS) and takedowns (Burnout)

### 3.1 NFS Most Wanted (2005) heat table (src: nfs.fandom.com/wiki/Pursuit via API; wikibooks)

| Heat | Max engaged units | Vehicles | Backup timer | Cooldown timer | Tactics added |
|------|------|----------|------|------|---------------|
| 1 | 5 | city cruiser | 180 s | 20 s | Follow, rolling roadblock |
| 2 | 10 | undercover cruiser | 120 s | 45 s | Box, all roadblock types |
| 3 | 15 | state cruiser + light SUV | 120 s | 75 s | Herd, PIT, head-on SUV ram |
| 4 | 20 | undercover state + heavy SUV + helicopter | 120 s | 90 s | Spike strips, air support |
| 5 | 25 | federal (Corvette) + heavy SUV + heli + boss | 90 s | 120 s | All tactics |

(The table's timer unit is assumed to be seconds — unverified.) Wikibooks (https://en.wikibooks.org/wiki/Need_for_Speed:_Most_Wanted/Pursuit_system):
H2 roadblocks, H3 light Rhino SUVs, H4 heavy SUVs + spike strips + helicopter, H5 everything.
Tactic definitions (https://nfs.fandom.com/wiki/Police_Tactics): **Follow** (stay close, demand stop);
**Rolling roadblock / Box** (units on every side, up to 8 cars at high heat); **Herd** (2–3 cars squeeze
you into narrow space); **PIT** (hit your rear quarter to spin you, ideally into a wall/block);
**Head-on ram** (2 SUVs drive at you; if they miss they turn and ram); **Stationary roadblock** (cars
across the road, SUVs + spikes at high heat); **Spike strip** (punctures tyres). The player is briefly
immune to collisions right after passing a roadblock or triggering a pursuit breaker. Cop cars are not
affected by spikes; rear of a cop car is lighter than the front (ram the rear).

### 3.2 Escape, cooldown, busted (src)
- MW05: break line of sight of every unit → evade bar fills → **Cooldown**: survive the cooldown timer
  unseen; being seen restarts the pursuit; **hiding spots** (marked on map) fill cooldown faster;
  helicopters at heat 4+ keep you in view, lost only in large tunnels.
- MW2012 (https://nfs.fandom.com/wiki/Fairhaven_City_Police_Department/Pursuit): police "visibility
  circle" on the minimap; cooldown = the heat meter draining to 0; turning off the engine/hiding speeds
  it; staying near a wrecked cop stops cooldown; re-engaged if a unit sees you.
- Busted: a meter fills while you are slow/stopped with cops around; MW05 pursuit bar at the bottom of
  the screen swings left (red = busted) / right (green = evading) and shows units, backup timer.
- Pursuit Breakers (https://nfs.fandom.com/wiki/Pursuit_Breaker): gas stations, water towers, signs,
  scaffolds… hit the supports → collapse on following cops; plays a short camera sequence (player car
  AI-driven meanwhile); icons are triangles on the minimap; they reset only after you leave the area.
  Hitting one too slowly can trap you in the debris.
- Hot Pursuit 2010 police "equipment" (https://nfs.fandom.com/wiki/Equipment): roadblock called ahead;
  helicopter keeps contact and drops spikes ahead; EMP (lock-on, forces a slide + damage); spike strip
  from the rear (spin-out, small damage, tyres re-inflate). Racers counter with Jammer and Turbo.

### 3.3 Burnout takedowns — rules and presentation
Rules (src: https://burnout.fandom.com/wiki/Takedown , https://en.wikipedia.org/wiki/Burnout_3:_Takedown):
- Takedown = you force an opponent to crash: into a wall, out of bounds, into traffic/another car.
  Types: Wall, Traffic, Traffic Check (shove a traffic car into a rival), **Grinding** (pin against a wall
  over distance), T-Bone, **Vertical (land on top of a rival after a jump)**, Psyche-Out (rival crashes
  from your erratic driving without contact), Revenge, Aftertouch, Signature (special place).
- **Streak**: takedowns within **10 s** of each other chain ("2-in-a-row"… "Rampage"; max 5 in B3,
  10 in Paradise).
- Boost economy (B3): boost bar has 4 segments; each takedown fills the bar **and** adds a segment;
  being crashed removes a segment. Paradise: drive through a gas station = boost refilled; through a
  repair shop = car repaired (https://burnout.fandom.com/wiki/Burnout_Paradise).
- Wreck in Paradise: if the car keeps 4 wheels you drive on; losing a wheel or "critical damage" = wreck.
- Crashes run in **Impact Time** (slow-mo) where Aftertouch steers the wreck (B3).
- Dev notes (Wikipedia): the team doubted cutting the camera to the victim during play, but it worked;
  crash sequences ran at **30 fps with many more particles** while racing stayed at 60 fps.
Presentation, **measured** from Burnout Paradise footage (dl/b13, 8 takedowns, scene-cut detection):
- Gameplay cuts to a **side-on / low angle shot of the victim**; slow motion; the cut-away lasts
  **2.63–2.80 s (mean 2.7 s)**, then hard-cuts back to the chase camera with the race continuing.
- A yellow brush-stroke banner, top-left: **"TAKEDOWN!"** / **"GRINDING TAKEDOWN!"**, sub-line
  "2-in-a-row" / "RAMPAGE"; on the first frames it pops large mid-screen, then shrinks to the corner.
- Sparks, glass and body parts are oversized; the victim tumbles/rolls; the camera holds still or pans
  slowly — the *victim* moves, not the camera.

### 3.4 SKYRUSH police design (ours, derived from 3.1–3.3)
Police vehicles (stylised, no real logos): **巡逻车 Patrol EV sedan** (HP 60, 1,800 kg, top 230 km/h),
**拦截车 Interceptor** (HP 70, 1,900 kg, top 290 km/h), **重型SUV Heavy SUV** (HP 140, 2,600 kg, top
210 km/h, rams), **无人机 Police drone** (air unit replacing the helicopter; follows at 30–40 m altitude,
spotlight cone 25°, keeps line of sight, can enter Sky Lanes, drops a spike strip 120 m ahead every 25 s).

| Heat | Units max | Backup | Cooldown | Adds |
|------|-----------|--------|----------|------|
| 1 | 3 | 60 s | 20 s | Patrol follow, ram from behind |
| 2 | 5 | 50 s | 35 s | Rolling box (3 cars), 2-car roadblocks |
| 3 | 7 | 45 s | 50 s | Interceptors, PIT, 3-car roadblocks with a 3 m gap |
| 4 | 9 | 40 s | 70 s | Heavy SUV head-on rams, spike strips, 1 drone |
| 5 | 12 | 35 s | 90 s | 2 drones, toll-plaza full closures, EMP drone pulse |

Heat rises when: pursuit time passes 60/120/200/300 s, OR damage dealt to police passes 2/5/9/14
cars disabled (whichever first). Infractions that START a pursuit at heat 1: hitting a police car,
> 160 km/h in sight of a patrol, hitting traffic in sight, flying through a toll plaza without paying.
Line of sight: raycast from each unit's roof (1.6 m) to player roof every 0.2 s; max 220 m (ground),
350 m (drone). Ground units lose sight when you enter a Sky Lane (they must re-route); drones do not.
Evade: when **no unit** has had sight for 4.0 s → Cooldown starts. Cooldown bar fills over the heat's
cooldown time; under an elevated road deck, in a tunnel or parking garage ("hiding spot") it fills ×2;
any sighting during cooldown → pursuit resumes at the same heat.
Busted: meter fills at 1/3 per s while speed < 15 km/h AND ≥1 unit within 12 m; drains at 1/s otherwise;
full = BUSTED screen (lose chase rewards). Never busts while airborne or in a Sky Lane.
Pursuit breakers: gas-station canopy, scaffolding, billboard on poles, construction crane load, toll
booth canopy. Hit 1–2 marked supports at ≥ 60 km/h → 1.2 s collapse; police inside a 25 m × 12 m box
behind the breaker are wrecked; 1.5 s player immunity; icon: amber triangle on minimap; re-arms after
the player is > 1 km away for 120 s.
Charging stations (闪充站): drive through the glowing bay at ≥ 60 km/h → N₂ to 200, +20 HP, 0.6 s "闪充！"
effect; each station 30 s cooldown; during a pursuit the police lose sight for 1.0 s (EMP-ish flash).

### 3.5 SKYRUSH takedown rules and takedown cam (ours)
What counts as a takedown (credit to the player):
1. A rival/police car becomes **wrecked** (§7.4) within **2.0 s** after the player's last contact with it
   (contact = any collision with relative speed ≥ 3 m/s), OR
2. **Vertical takedown**: player lands on a car's roof from a hop (relative vertical speed ≥ 5 m/s) → that
   car is wrecked immediately (signature move of a hopping Roadster), OR
3. **Psyche-out**: a rival/police car wrecks while the player is within 8 m and no contact happened.
4. **Breaker takedown**: police wrecked by a pursuit breaker the player triggered.
Rewards: +50 N₂ per takedown, +25 more per streak step; streak window 10 s (Burnout).
Takedown cam timeline (t = 0 at the wreck event):

| t (s) | Action |
|-------|--------|
| 0.00 | hit-stop: Engine.time_scale = 0.05 for 0.06 s real time; white flash 1 frame (alpha 0.35) |
| 0.06 | cut to TakedownCam: placed 9 m from the victim, perpendicular to its velocity, on the side away from walls, 1.0 m above road; vFOV 50°; look at victim; Engine.time_scale = 0.30 |
| 0.06–1.30 | victim tumbles in slow-mo; camera slowly dollies 1.5 m toward victim; debris & sparks ×2 count |
| 0.10 | banner pops in centre at 160 % scale, shrinks to top-left anchor in 0.25 s |
| 1.30–2.40 | time_scale eases 0.30 → 1.0 (ease-in-out) |
| 2.70 | hard cut back to the chase camera; autopilot hands control back with a 0.3 s input blend |

The race keeps running during the cam (as in Burnout Paradise), but the player's car is driven by a
lane-keeping autopilot and is immune to traffic hits (NFS pursuit-breaker cams also hand the car to AI).
Skip with any face button after 0.5 s. Disable takedown cam for traffic-only wrecks and when another cam played < 4 s ago (show banner
only). Cap: 1 slow-mo per 4 s. All cam times above are **real time**: drive them with
`get_tree().create_timer(sec, true, false, true)` (last arg = ignore_time_scale) or
`create_tween().set_ignore_time_scale(true)`, otherwise Engine.time_scale stretches them.
Banner text (zh / en): 撞毁！TAKEDOWN! · 碾压！VERTICAL TAKEDOWN! · 心理战！PSYCHE OUT! · 连击 ×2 · 狂暴 RAMPAGE (×5).
Banner style: amber #FFB300 skewed parallelogram (skew −12°), black #0A0A0A text, CJK font weight Black,
64 px (1080p); sub-line 36 px white #FFFFFF with 3 px black outline.

---------------------------------------------------------------------------------------------------
## 4. Arcade vehicle physics recipe — Godot 4.7.2 + Jolt

### 4.1 Why custom, not VehicleBody3D
Godot's own docs: VehicleBody3D "has known issues and isn't designed to provide realistic 3D vehicle
physics… write your own physics integration using CharacterBody3D or RigidBody3D"
(https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html). Rocket League (Psyonix,
GDC 2018, https://media.gdcvault.com/gdc2018/presentations/Cone_Jared_It_Is_Rocket.pdf) uses the same
recipe we want: fixed 120 Hz, raycast suspension, no transmission (force/accel **curve** instead),
constant mass, no longitudinal tyre friction, a **simple lateral friction curve**, "stay upright"
forces, forces applied at **CoM height**, physics presets separate from visuals.

### 4.2 Project settings (exact)
```
physics/3d/physics_engine = "Jolt Physics"        # set explicitly; DEFAULT may mean GodotPhysics3D
physics/common/physics_ticks_per_second = 120
physics/common/max_physics_steps_per_frame = 8
physics/common/physics_interpolation = true       # then move game logic to _physics_process
physics/jolt_physics_3d/simulation/velocity_steps = 10   # default, keep ≥ 2 (friction needs it)
physics/jolt_physics_3d/simulation/position_steps = 2    # default
physics/jolt_physics_3d/simulation/continuous_cd_movement_threshold = 0.75  # default
physics/jolt_physics_3d/simulation/continuous_cd_max_penetration = 0.25     # default
```
Settings names verified in the Godot 4.7 class reference (ProjectSettings). Call
`reset_physics_interpolation()` after every teleport/respawn. Keep the playable map within ±4 km of the
origin (float precision; Godot "Physics simulation is unreliable when far away from the world origin").
At 92 m/s the car moves 0.77 m per 120 Hz tick: enable `continuous_cd = true` on player, rivals and
police; make static wall colliders ≥ 0.5 m thick; never use single-sided planes for walls.

### 4.3 Body setup for the 1.9 t Roadster (est. unless noted)

| Property | Value |
|----------|-------|
| RigidBody3D.mass | 1900 |
| collision shape | BoxShape3D 1.95 × 0.80 × 4.40 m, centred 0.70 m above ground (body only, no wheels) |
| center_of_mass_mode | CUSTOM, center_of_mass = (0, 0.42, 0.05) relative to body origin at road level → CoM 0.42 m high, 5 cm forward |
| inertia (local x=pitch, y=yaw, z=roll) | Vector3(3400, 3200, 900) kg·m² (box formula gives 3397 / 3807 / 793; yaw reduced 16 % for agility, roll raised for calm) |
| linear_damp / angular_damp | 0.0 / 0.5 (mode REPLACE) |
| gravity_scale | 1.0 grounded; 2.0 when no wheel touches for > 0.10 s; 0.0 in Sky Lane |
| continuous_cd | true |
| contact_monitor / max_contacts_reported | true / 8 (for impacts and damage) |
| wheels | 4 ShapeCast3D, anchor (±0.82, 0.70, +1.38) front, (±0.84, 0.70, −1.32) rear → wheelbase 2.70 m, track 1.64/1.68 m |
| wheel radius | 0.36 m (visual and cast sphere, §4.4) |

### 4.4 Suspension (per wheel; shapecast) (est.)
Geometry: ShapeCast3D at the anchor, `shape = SphereShape3D(radius 0.36)` (= wheel radius, so sphere
centre = wheel centre), `target_position = (0, -0.46, 0)` local, `exclude_parent = true`,
`collision_mask = world | traffic | cars`. Each tick: `force_shapecast_update()`; if colliding:
`d = get_closest_collision_safe_fraction() * 0.46` (anchor→wheel-centre distance), else wheel at droop.

| Parameter | Value | Why |
|-----------|-------|-----|
| rest length L0 (anchor→wheel centre, unloaded) | 0.41 m | static sag 0.067 m at 1.9 t |
| compression x | L0 − d (0 if negative) | |
| travel (max compression) | 0.20 m; beyond: bump-stop k_bs = 300,000 N/m | no bottoming-through |
| spring k | 70,000 N/m per wheel | corner mass 475 kg → 1.93 Hz ride frequency (sports car 1.5–2.5 Hz) |
| critical damping c_crit = 2√(k·m_corner) | 11,530 N·s/m | |
| damper c (compression / rebound) | 4,600 (ζ 0.40) / 6,300 (ζ 0.55) N·s/m | calm but not floaty |
| landing damper | ×2.0 for 0.25 s after touchdown | kills the bounce |
| force | F = k·x + c·(dx/dt), clamp to [0, 60,000] N, applied along the **ground normal** at the wheel contact point (the height of the point does not matter for this near-vertical force) | standard raycast car |
| grounded wheel | x > 0.005 m | |
| anti-roll bars | F_arb = k_arb·(x_left − x_right): +F on the more compressed side, −F on the other; k_arb front 28,000, rear 20,000 N/m | flat cornering, slight understeer |

Visual wheel: place at anchor − d along body −Y; spin = v_long / 0.36 rad/s; steer yaw = steer angle.
Never parent the CollisionShape to the visual wheel.

### 4.5 Tyre model (lateral grip curve, slip, drive, brake)
Per grounded wheel, every tick (in `_integrate_forces(state)`):
```
offset   = contact_point_global - state.transform.origin          # Godot wants global offset
up       = state.transform.basis.y
offset_at_com_height = offset - up * up.dot(offset - state.center_of_mass)  # RL: tyre forces at CoM height
v_pt     = state.get_velocity_at_local_position(offset)
fwd      = wheel_forward_global (body +Z rotated by steer for front wheels)
right    = wheel_right_global
v_long   = v_pt.dot(fwd);  v_lat = v_pt.dot(right)
slip_deg = rad_to_deg(atan2(abs(v_lat), max(abs(v_long), 1.0)))
mu       = MU_PEAK * grip_curve(slip_deg) * drift_mult(wheel) * surface_mult
F_need   = -v_lat * (MASS / 4.0) / state.step                     # force that cancels lateral slide in 1 tick
                                                                  # (below 0.5 m/s use the park rule in §4.7)
F_lat    = clamp(F_need, -mu * F_z, mu * F_z)                     # F_z = this wheel's suspension force
state.apply_force(right * F_lat, offset_at_com_height)
```
`grip_curve(slip)` (piecewise linear, normalised; shape after Pacejka plots in the Criterion slides):

| slip ° | 0 | 4 | 8 | 12 | 20 | 35 | 90 |
|--------|---|---|---|----|----|----|----|
| factor | 1.00 | 1.00 | 1.00 | 0.92 | 0.80 | 0.70 | 0.65 |

(Using F_need clamped by μ·F_z means the curve acts as a *cap*; at small slip the tyre simply cancels
lateral velocity → crisp, stable, Rocket-League-like. RL: `Friction = SlideFriction(ratio) × GroundFriction(normal.y)`,
`ratio = SideSpeed/(SideSpeed+ForwardSpeed)`.)
- MU_PEAK = 1.45 front, 1.40 rear (arcade, above real 1.1); surface_mult: asphalt 1.0, painted line 0.95,
  wet/neon puddle 0.85, grass 0.55.
- Drive (RWD, rear wheels only): `F_drive_total = MASS × a_drive(v) × throttle`, split 50/50 rear,
  applied along `fwd` at CoM height. `a_drive(v) = A0 × max(0.2, 1 − 0.8·v/V_TOP)` with A0 = 14 m/s²
  (QQ: base accel decays to 0.2× near top speed). Above V_TOP: no drive force, extra drag
  `−4 m/s² × (v − V_TOP)/10` pulls speed back softly (clone used 1.1 m/s per s).
- Brake: 16 m/s² total, split 60/40 front/rear; reverse top speed 40 km/h, reverse accel 6 m/s².
- Coast drag (throttle 0): 1.5 m/s² + 0.0004·v² m/s².
- Steering: max wheel angle `lerp(32°, 7°, clamp(v / 69.4, 0, 1))`; keyboard steer input ramps at
  4.0 /s toward ±1 and returns at 6.0 /s; gamepad stick uses response curve `s·|s|` (squared) with 0.12
  dead-zone.
- Ackermann: inner front wheel +10 % angle (cosmetic; optional).

### 4.6 Drift state (QQ-style, assisted) (ours; numbers est.)
States: `GRIP → DRIFT → RECOVER → GRIP`. All in the car controller, evaluated every physics tick.

| Rule | Value |
|------|-------|
| Enter DRIFT | drift button held AND abs(steer) ≥ 0.3 AND forward speed ≥ 15 m/s AND ≥ 3 wheels grounded |
| On enter | drift_dir = sign(steer); yaw-rate kick: apply_torque_impulse(up × I_yaw × 1.1 × drift_dir); rear μ multiplier → 0.45 over 0.08 s |
| Yaw control | k = (steer × drift_dir + 1) / 2 (0 = counter-steer, 1 = full into drift); ω_target = drift_dir × lerp(0.9, 1.8, k) rad/s (52–103 °/s, independent of speed); torque_y = I_yaw × 6.0 × (ω_target − ω_y) |
| Velocity steering | velocity direction chases the nose at λ_drift = 2.0 /s (clone): lateral accel a = v × 2.0 × β (β in rad), applied at CoM toward the nose side, capped at 50 m/s²; this makes drifts carve instead of spin |
| Resulting slip β | steady state β ≈ ω_target / λ_drift = 0.45–0.90 rad = **26°–52°** (no separate slip controller needed); path radius at 200 km/h ≈ 31–62 m |
| Slip clamp | abs(β) > 66° → yaw damping torque = −I_yaw × 10 × (abs(β) − 66°)(rad) toward the velocity |
| Spin-out guard | abs(ω_y) > 2.4 rad/s (137 °/s) → damping torque −I_yaw × 8 × (abs(ω_y) − 2.4) |
| Speed loss | (1.5 + 8·sin β) m/s² while grounded (≈ 6 m/s² at 35°) |
| Maintain-speed assist | while 20° ≤ β ≤ 55°, cancel 60 % of that loss; fade to 0 % at 10° and at 66° (Criterion "maintain speed force" idea) |
| Gauge gain | per tick: max(0.015 × (km/h removed by the Speed-loss row this tick, measured **before** the maintain-speed assist), 0.10 × dt) slots — at β ≈ 35° that is 0.33 slot/s, so a 3 s drift ≈ 1 slot |
| Exit to RECOVER | drift button released AND (β < 12° OR steer × drift_dir < −0.3) |
| Drift Cut (断位) | release + re-press drift within 0.25 s during DRIFT → λ_drift = 5.2 /s for 0.20 s and ω_target = 0 → instant RECOVER with early 小喷 window (needs drift ≥ 0.40 s) |
| RECOVER | rear μ multiplier 0.45 → 1.0 over 0.30 s; λ = 5.2 /s, then GRIP (tyre model only) |
| Clean exit | drift lasted ≥ 0.40 s AND no impact > 0.30 during it → open 小喷 window 0.50 s; commit this drift's pending gauge into N₂ (1.0 gauge = 100 N₂ units; shown striped in the filling slot until committed) |
| Dirty exit | wall impact > 0.30 during the drift → no 小喷, gauge gained in this drift × 0.5 |
| Visual counter-steer | front wheel visual angle = −β × 0.8 (cosmetic; the player never has to counter-steer by hand) |

Air or low speed (< 10 m/s) cancels the drift with no reward. β = signed angle between the car's
forward axis and its horizontal velocity; all comparisons above use abs(β).

### 4.7 Downforce, anti-roll, stability, high speed
- Downforce at CoM: `F = −up × 2.3 × v²` N → 0.6 g extra at 250 km/h (11,100 N). (Real car's fan system
  claims far more; we keep it modest for jumps.)
- Aero drag is NOT used to set top speed (speed caps do); keep 0.30·v² N only for coasting feel.
- Stay-upright (grounded, ≥ 2 wheels): torque = I × (8.0 × (body_up × ground_normal) − 2.5 × ω_pitch/roll).
- Lateral force application height: at CoM height (prevents roll-over and pitching).
- Rollover guard: if abs(roll) > 55° while grounded → extra upright torque ×3; if upside down for 1.5 s →
  auto-respawn (no wreck).
- High-speed stability: steering limit (7° at top speed), yaw damping torque −I_yaw × 0.8 × ω_y always
  on in GRIP, CCD on, 120 Hz.
- Low-speed jitter fix: below 0.5 m/s with throttle 0 → set lateral and longitudinal velocity to 0
  (park) to avoid creeping.

### 4.8 Air control and landing
- Airborne = 0 grounded wheels for > 0.10 s → gravity_scale 2.0.
- Auto-level (Battlefront 2 "auto-roll to horizon": subtle near level, strong when far):
  torque_pitch/roll = I × (6.0 × angle_error − 2.5 × ω), target = level with the road below; disabled
  during barrel roll; never fights the player's input (scale 0.3 while the player is giving air input).
- Air yaw: steer input → ω_y target 1.8 rad/s; air pitch: throttle/brake → ±1.5 rad/s (RL max angular
  speed 5.5 rad/s; we stay well below).
- Landing: if (pitch and roll within 30° of the ground normal) → snap-align over 0.12 s, landing damper
  ×2 for 0.25 s, keep 100 % horizontal speed, white "puff" (§5.5), open 落地喷 window if airtime ≥ 0.3 s.
  If misaligned 30–70° → keep 85 % speed, wobble, no window. If > 70° (roof/side first) → crash check
  (§7). Landing vertical speed > 14 m/s → 10 HP damage, heavier shake.
- Weighty but forgiving checklist: big camera lag + heavy landing shake + 0.08 s hit-stop on big hits (0.06 s for takedowns)
  (weight); auto-level, wall-glance assist (§7.2), velocity steering in drift, no wreck from traffic
  glances < 30° (forgiving).

### 4.9 Code layout and tick order (sketch; one file = one job)
```
scripts/vehicle/car_tuning.gd      # const-only tuning table (§8.6); no logic
scripts/vehicle/car_input.gd       # reads InputMap → steer/throttle/brake/drift/boost/hop/roll (+ edge flags)
scripts/vehicle/wheel_probe.gd     # one ShapeCast3D wrapper: compression, contact point/normal, F_z
scripts/vehicle/car_body.gd        # RigidBody3D; _integrate_forces calls the modules below in order
scripts/vehicle/drift_state.gd     # GRIP/DRIFT/RECOVER + gauge + 小喷 window (pure logic, testable)
scripts/vehicle/boost_state.gd     # N₂ slots, nitro/小喷 timers, CW/WCW/CWW cap formula
scripts/vehicle/thruster_state.gd  # hop, big hop, hover, barrel roll, landing window
scripts/vehicle/damage_state.gd    # HP, dents, part detach, smoke/fire tier
```
`car_body._integrate_forces(state)` order each 1/120 s tick:
1. read input snapshot (sampled in `_physics_process`, never in `_process`);
2. update 4 wheel probes → compression, F_z, grounded count;
3. suspension + anti-roll forces; 4. tyre lateral forces (μ from drift state);
5. drive / brake / coast; 6. drift assists (yaw torque, velocity steering, speed loss);
7. boost forces (N₂, 小喷, thrusters) and **speed cap**: if `v_forward > cap` apply −4 m/s²·(excess/10);
8. downforce, upright torque, yaw damping; 9. air control (if airborne);
10. emit events (`drift_started`, `mini_boost`, `landed`, `impact(strength, normal)`) for HUD/audio/FX.
Unit tests (GUT or a headless script): drift_state gives 0.95–1.05 slot for a scripted 3.0 s drift at
β = 35° from 200 km/h; CWW cap equals base + E_n + 0.8·E_w; a 25 m/s head-on wall hit yields 60 HP damage (§7.3 formula).

---------------------------------------------------------------------------------------------------
## 5. Thruster hop + Sky Lane (flight) mechanics

### 5.1 Facts from the 2026-10-15 reveal (src)
- Event at SpaceX McGregor, Texas, 15 Oct 2026. Trims: **Performance** (fan "multi-mode suction" + active
  aero, 0–60 mph < 1.6 s), **Thrust** (+ rear cold-gas thrusters, 200 L tank, 4 rear nozzles, 0–60 mph
  0.85 s, top speed 230 mph), **Rocket** (one seat, +400 L tank = 600 L, **10 nozzles**: 4 rear
  propulsion, 1 downward behind each wheel = 4 lift, 2 at the nose pointing sideways for yaw; can hover,
  flip, barrel-roll) (Top Gear https://www.topgear.com/car-news/electric/tesla-roadster-has-finally-landed-thrusters-0-60mph-059s-and-flight ;
  MotorTrend https://www.motortrend.com/news/first-look-2028-tesla-roadster-performance-thrust-rocket ;
  Electrek https://electrek.co/2026/10/15/an-updated-technical-look-at-teslas-kick-flipping-0-60-in-1s-next-gen-roadster/).
- Gas: pressurised **nitrogen** (MotorTrend) in carbon COPVs at **10,000 psi** (~690 bar) (Electrek);
  thrust "over 80 kilonewtons" (Car and Driver https://www.caranddriver.com/news/a74145531/tesla-roadster-revealed/).
  80 kN on 1.9 t ≈ 42 m/s² ≈ 4.3 g — consistent with 0–60 mph in ~0.8 s.
- Demo: drove up a curved ramp held by suction, launched off inverted, barrel-rolled, landed "gently…
  in a cloud of white smoke"; then **hopped over five parked Teslas** (Cybercab, Cybertruck, Semi,
  Model Y, Model 3) while rolling; Tesla says it jumped **27 ft (8.2 m)** (NBC
  https://www.nbcnews.com/tech/tech-news/elon-musk-shows-flying-tesla-roadster-years-delays-rcna603905 ;
  TechCrunch https://techcrunch.com/2026/10/15/tesla-reveals-spacex-powered-roadster-that-flies-and-falls-with-style/).
- Live 0–60 mph run: 0.81 s claimed (NBC). Thrusters spool up before the car moves (Electrek frame study).
- Endurance: the Thrust tank empties in ~5–6 s; refill takes 2–6 h today (target < 30 min); Musk:
  "self-refilling", "going to puff itself up" (InsideEVs https://insideevs.com/news/812205/tesla-roadster-replenishes-air-tanks/ ; TechCrunch).
- Target mass 1,700 kg (MotorTrend); critics call it "4,000+ lb" (TechCrunch quoting MKBHD). Brief
  says 1.9 t for our Rocket-spec car — keep 1,900 kg.
- Real physics check: apex 8.2 m needs v_y = √(2·9.81·8.2) = 12.7 m/s and 2.6 s of air at 1 g.
  The five parked cars ≈ 25–30 m long in total (est.); tallest = Semi ≈ 4 m (est.).

### 5.2 One resource: N₂ (氮气) — QQ's nitro *is* the Roadster's nitrogen (ours)
QQ calls nitro 氮气 = nitrogen, and the real Roadster thrusters run on nitrogen. So SKYRUSH uses a
single resource, **N₂**, shown as **2 COPV slots** (QQ's 2 nitro slots). 1 slot = 100 units, max 200.

| Gain | Amount |
|------|--------|
| Drift (集气) | QQ formula (§4.6): 3 s drift ≈ 100 |
| Self-refill compressor | +3 /s while grounded and not thrusting, only up to 100 (slot 1) |
| Takedown | +50 (+25 per streak step) |
| Near miss (traffic passes within 1.2 m at ≥ 60 km/h relative) | +5 |
| Clean landing after Big Hop / barrel roll | +15 |
| 闪充站 charging bay | refill to 200 |
| Sky Lane N₂ ring | +40 |

| Spend | Cost |
|-------|------|
| **N₂ Boost** (QQ 氮气, written "C" in QQ combos; keys Left Ctrl / J / gamepad X) | needs one FULL slot (100) → 3.0 s burn |
| Hop (tap) | 25 |
| Big Hop (hold ≥ 0.25 s, fire on release) | 50 |
| Hover (hold hop key in the air after apex) | 12 /s |
| Barrel roll | 20 |
| Sky Lane flight | 10 /s |

小喷 (W) is free (drift reward), exactly like QQ. Charging stations are the Burnout gas-station idea.

### 5.3 Hop, Big Hop, Hover (ours)

| Move | Input | Physics | Result |
|------|-------|---------|--------|
| Hop | tap hop (< 0.25 s) while ≥ 2 wheels grounded | thruster spool 0.08 s (4 white jets under the car), then `apply_central_impulse(Vector3.UP * MASS * (11.0 - min(v_y, 0.0)))` (world up; cancels any downward speed first); air gravity 2 g | apex 3.1 m, airtime 1.12 s, clears one car/traffic jam; at 150 km/h covers 47 m |
| Big Hop | hold hop ≥ 0.25 s, release to fire (charge ring on HUD) | spool 0.15 s, same impulse formula with 17.5 m/s | apex 7.8 m (≈ the reveal's 8.2 m), airtime 1.78 s; clears 5 parked cars, a bus, a police roadblock incl. SUVs; with Hover also a gas-station or toll-plaza canopy (§5.7) |
| Hover | hold hop in the air after apex | upward force = 0.85 × m × g_air → net descent accel 2.9 m/s²; max 3.0 s per jump | stretch a jump over a breaker or onto an elevated deck |
| Air 小喷 (空喷) | tap 小喷 once per jump while airborne | +6 m/s forward impulse, 0.5 s | QQ 空喷 |
| Landing 小喷 (落地喷) | tap 小喷 within 0.45 s after touchdown, airtime ≥ 0.3 s | normal 小喷 | QQ 落地喷 |

Rules: set gravity_scale = 2.0 at the moment of the hop impulse (do not wait the 0.10 s airborne
delay); no hop under a low ceiling (raycast up 3 m → hop disabled, HUD icon grey); hop cooldown 0.6 s;
hop keeps all horizontal speed (no forward thrust). Thruster plumes are **cold gas: white/pale, never
orange fire** (§5.5).

### 5.4 Barrel roll (ours)
- Input: roll-left / roll-right key while airborne (keyboard Q/E; gamepad LB/RB), or double-tap steer
  within 0.25 s in the air (Star-Fox style).
- 360° about the car's forward axis in **0.70 s** (ease: 0.12 s spin-up, peak ≈ 12 rad/s, 0.12 s
  spin-down; drive it kinematically as a visual+body roll with `angular_velocity` override, then
  restore exact pre-roll orientation at the end to avoid drift).
- Side-dodge 3.5 m toward the roll direction during the roll; 0.50 s immune to EMP, spikes dropped by
  drones, and police rams < 15 m/s relative.
- Costs 20 N₂; max 2 rolls per airtime; a roll that ends ≥ 0.15 s before touchdown → clean landing
  bonus +15 N₂ and "特技 TRICK!" pop-up; landing mid-roll = misaligned landing (§4.8).

### 5.5 Landing "puff" and thruster VFX (ours; matches the reveal footage)
Reveal: the car "brought itself to a soft landing in a cloud of condensation" (NBC); keyframes in
`ref/video/keyframes/t140.jpg` and `t150.jpg` show a low white cloud around the car.
- Puff on every hop landing, on Sky Lane exit, and on any touchdown with v_y > 4 m/s:
  GPUParticles3D, one-shot, 48 particles, lifetime 0.9 s, emission ring radius 1.2 m at wheel height,
  initial radial speed 6 m/s + upward 0.8 m/s, damping 8, scale 0.6 → 2.2 m (curve), colour
  #F2F6FA alpha 0.85 → 0, unshaded billboard soft particles; plus a 0.25 s ground ring decal (alpha 0.4).
- Thruster jets: 4 under-body (hop/hover), 4 rear (N₂ boost): cone mesh 0.12 m → 0.45 m radius,
  length 1.2 m (hop) / 2.5 m (boost), additive, core #FFFFFF, edge #9FD8FF, faint shock diamonds
  (3 brighter rings scrolling at 8 Hz); a short-lived white vapour trail (#E8F2FA, alpha 0.3, 0.4 s).
- Audio: short "pssh-WHOOMP" (hop), sustained hiss + roar (boost). No fire, no smoke-black.

### 5.6 Sky Lanes (飞行航道) — flight sections (ours)
Concept: designated air corridors between elevated roads / across the Huangpu, entered from a launch
ramp. Easy on keyboard: the car flies **on rails along a spline**; the player only moves inside a tube.

| Parameter | Value |
|-----------|-------|
| Entry condition | drive over the LAUNCH PAD (glowing ramp) at ≥ 120 km/h with ≥ 25 N₂; else the car just jumps |
| Transition | 0.4 s: lift jets fire, gravity → 0, car aligns to lane tangent |
| Forward speed | max(entry speed, 200 km/h), N₂ Boost raises it to 300 km/h |
| Tube cross-section | 14 m wide × 8 m tall (offset x ∈ [−7, 7], y ∈ [−3, 5] around the spline) |
| Player control | steer → lateral offset speed up to 9 m/s; throttle/brake → up/down 6 m/s (option: invert); response λ = 6 /s |
| Bank / pitch visuals | bank = −lateral speed × 3.5° per m/s (max 35°); pitch = vertical speed × 2.5° per m/s |
| Edge | soft spring back into the tube (accel 30 m/s² per m outside); no wall crashes in the tube |
| Cost | 10 N₂/s; N₂ rings every ~250 m (+40 each; net ≈ −1 N₂/s at 200 km/h if all are collected); at N₂ = 0 → glide: gravity 0.35 g, keep speed, exit tube |
| Obstacles | drones, neon billboards, crane arms; hit = 15 HP + 30 % speed loss, no wreck |
| Exit | lane end over a road: auto-descend 3 m/s to the deck, puff, 落地喷 window |
| Length | 400–1,500 m per lane (5–20 s of flight) |

Signposting (must be impossible to miss): 300 m before — overhead gantry "飞行航道 SKY LANE ▲ 300 m"
(cyan #00E5FF text on #0A1A2A panel); 150 m before — road arrows painted cyan; the LAUNCH PAD is a 30 m
ramp with animated chevrons (#00E5FF / #FF2BD6); in the air — hologram ring gates every 40 m,
diameter 14 m, cyan with magenta chevrons, rotating 20°/s; minimap — Sky Lanes as dashed cyan lines.
Police: ground units lose sight; drones (heat ≥ 4) follow into lanes.

### 5.7 Flying over gas stations, toll plazas, roadblocks (ours; heights est.)

| Obstacle | Height to clear | Depth | Move |
|----------|-----------------|-------|------|
| Traffic car / police sedan | 1.5 m | 4.8 m | Hop |
| Police SUV / van | 2.0 m | 5.2 m | Hop |
| Bus / truck | 3.2–4.2 m | 12 m | Big Hop |
| 3-car roadblock | 2.0 m | 5 m deep, spans road | Hop (timed) or Big Hop |
| Gas-station canopy (pursuit breaker) | 6.0 m | 20 m | Big Hop + 0.5 s Hover |
| Toll plaza canopy (收费站) | 7.0 m | 18 m | Big Hop + Hover; or drive the ETC lane (green) |

Big Hop at 150 km/h spends 0.57 s (24 m) above 7 m; with Hover after apex it spends ~1.1 s (45 m).
HUD helper: 150 m before a roadblock/toll plaza flash "跳！HOP ▲" (amber) if the player has ≥ 50 N₂.
Flying through a toll plaza without paying (driving a red lane or jumping over) = infraction → heat +1.

---------------------------------------------------------------------------------------------------
## 6. AI: traffic, rival racers, police

### 6.1 Traffic (lane graph + IDM; kinematic until hit)
- Data: one `Path3D` per lane, authored per road piece; each lane stores `speed_limit`, `next_lanes[]`,
  `left_lane`, `right_lane`. Lane width 3.75 m expressway / 3.5 m urban (China norms, unverified).
- Movement: each traffic car is one RigidBody3D (box collider; 1,500 kg sedan, 2,400 kg van, 12,000 kg
  bus) with 3 modes. FAR (> 60 m from every player/rival/police car): `freeze = true`,
  `freeze_mode = FREEZE_MODE_KINEMATIC`, moved by setting its transform at `distance along lane` (cheap).
  NEAR (≤ 60 m): `freeze = false`, `axis_lock_angular_x = true`, `axis_lock_angular_z = true`, and in
  `_integrate_forces` steer `state.linear_velocity` toward the lane velocity (IDM speed along the lane
  tangent, lateral error corrected at 2 /s); when switching FAR→NEAR set the velocity first (no jolt).
  This way the player hits a real 1.5 t mass, not an infinite-mass kinematic wall. WRECK: on a contact
  with relative speed ≥ 6 m/s → unlock the axes, stop controlling, let it tumble; despawn 8 s later
  when not visible.
- Longitudinal model = IDM (Treiber): `a = a_max·[1 − (v/v0)^4 − (s*/s)^2]`,
  `s* = s0 + v·T + v·Δv / (2√(a_max·b))`. Wikipedia's calibrated values (v0 30 m/s, T 1.5 s,
  a 0.73 m/s², b 1.67 m/s², s0 2 m — https://en.wikipedia.org/wiki/Intelligent_driver_model) are
  realistic but sluggish; SKYRUSH game values: v0 = lane limit × U(0.9, 1.1) (expressway 22 m/s ≈ 80 km/h),
  T = 1.2 s, a_max = 2.0 m/s², b = 3.0 m/s², s0 = 2.5 m, emergency brake cap 8 m/s².
  Integrate at the physics tick; clamp v ≥ 0; never let a car pass through its leader
  (https://www.denis-iakimenko.com/blog/ai-traffic-simulation-idm-mobil).
- Lane changes: MOBIL-lite every 2–4 s per car (staggered): change if the gain in IDM accel > 0.3 m/s²
  and the new follower's braking would be < 3 m/s²; politeness p = 0.3; lane-change duration 2.5 s
  (lateral S-curve). Indicators blink 1.0 s before.
- Reaction to the player: if the player approaches from behind with closing speed > 15 m/s within 40 m,
  20 % of cars change lane away, 10 % brake 2 m/s² (creates near-miss gaps); horn 0.6 s if passed
  within 1.5 m. Traffic never deliberately blocks the player.
- Spawn ring: spawn points on lanes 180–350 m from the player, outside the camera frustum, 70 % ahead /
  30 % behind; never within 120 m in view; despawn when > 420 m away AND not visible for 2 s.
- Density targets: expressway 1 car per 45 m per lane (night), surface roads 1 per 60 m; 50–70 active
  cars typical, hard cap 90; during races/pursuits scale density by 0.7 on the player's route.
- Variety: 6 models × 8 colours; 8 % vans, 4 % buses/trucks, 5 % taxis (Shanghai turquoise/maroon
  liveries — coordinate with ref/shanghai).

### 6.2 Rival racers (racing line + rubber band)
- Track data: racing-line spline + per-node max curvature (Game AI Pro ch. 39, Tomlinson:
  https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter39_Representing_and_Driving_a_Race_Track_for_AI_Controlled_Vehicles.pdf).
  Steer toward a look-ahead point ("runner/rabbit") that moves along the line; look-ahead distance grows
  with speed: `L = 18 + 1.25·v` m (clone). Brake by predicting speed vs the max viable speed at future
  nodes (Game AI Pro).
- Corner speed: `v_corner = √(A / κ)` with κ = max curvature in the look-ahead window and A = "grip
  skill": easy 32, normal 45, hard 57 m/s² (clone values).
- Steering controller: PD on heading error (Kp 2.2, Kd 0.25) (est.; Game AI Pro ch. 40 PID chapter).
- Rubber band (clone formula): multiply rival top speed by
  `ahead: max(r_min, 1 − 0.00045 × gap_m)`, `behind: min(r_max, 1 + 0.0004 × gap_m)`;
  easy r = [0.88, 1.03], normal [0.93, 1.06], hard [0.97, 1.10]. Never apply in the last 10 % of a race.
- Abilities: rivals drift (visual + same gauge rules simplified), use N₂ on straights > 250 m, hop over
  traffic only on hard.
- Mistakes: easy every 25–40 s, normal every 45–70 s, hard every 90–120 s: brake 0.4 s late (→ wall
  scrape) or 0.6 s drift too wide. Rivals can be taken down (§3.5).
- Avoidance: if traffic within 25 m ahead in the same lane → shift lateral target ±3.5 m (pick the side
  with more clearance) — keep it on the racing-line frame, not raw steering.

### 6.3 Police AI steering (ours; numbers est.)
Police use the **same car physics** as the player (RigidBody3D + wheel probes) with an AI input source,
so rams and PITs are real collisions. A per-unit state machine; the Dispatcher (one node) assigns roles.

| State | Steering target | Speed target | Exit |
|-------|-----------------|--------------|------|
| PATROL | lane path (like traffic) | lane limit | sees infraction → PURSUE |
| PURSUE | player position + player velocity × t_lead, t_lead = clamp(dist / closing_speed, 0, 1.5 s) | player speed + 8 m/s (cap = unit top speed) | dist < 12 m behind → RAM / alongside → PIT |
| RAM | player rear bumper, lateral offset ±0.6 m | player speed + 6 m/s for 1.0 s | after contact or 2.5 s → PURSUE (cooldown 3 s) |
| PIT | point 1.0 m outside the player's rear quarter | match speed (Δv < 4 m/s) | when lateral overlap 0.6–1.6 m: steer 25° into the player for 0.45 s; then PURSUE (cooldown 6 s) |
| BOX (3 units) | front unit: 9 m ahead in the player's lane; side units: ±2.6 m lateral, 0–2 m behind the player | front: player speed − 3 m/s; sides: match player speed | player speed < 40 km/h for 2 s → busted meter fills ×2; else break after 8 s |
| HEAD-ON (SUV) | spawn 400 m ahead on the opposite direction, drive into player lane, offset 0 | 25 m/s | miss → U-turn and PURSUE |
| ROADBLOCK | static: 2–3 cars across the road 350–450 m ahead on the predicted route, out of view; 1 gap of 3.0 m (heat ≤ 3) / no gap + spikes (heat ≥ 4) | — | despawn 20 s after passed |
| SPIKES | strip 7 m × 0.6 m across 2 lanes; placed by roadblock or by a unit 80 m ahead | — | hit → tyres punctured: μ × 0.55, top speed × 0.65 for 8 s, sparks from rims; charging bay repairs |
| DRONE | hover 30–40 m above, 20 m behind; spotlight cone 25° on the player; drops spikes every 25 s; EMP (heat 5) lock 2.0 s then pulse: −30 % speed, no N₂ for 3 s | — | cannot be rammed; disabled only by a pursuit breaker (crane load, billboard) or when the pursuit ends |

- Catch-up (fairness, not cheating): units > 150 m behind get top speed × 1.08; units < 20 m behind get
  × 0.98; never spawn police in the player's view; never more than 3 units within 30 m.
- Line of sight and backup per §3.4. Units disabled = HP 0, flipped, or stuck > 4 s.
- Radio chatter text (zh): "嫌疑车辆，立即靠边停车！" / "请求支援！" / "部署路障！" / "目标飞走了！" (Sky Lane).

---------------------------------------------------------------------------------------------------
## 7. Crash and damage model

### 7.1 What reads best on screen (research summary)
- Burnout: crash = spectacle; cut-away slow-mo 2.7 s (meas.), oversized sparks/glass/parts, crash
  frames at 30 fps with **more particles** (Wikipedia B3 dev notes); Paradise: lose a wheel or reach
  critical damage = wreck, else drive on.
- Real-time car damage study (Smekens 2019, DAE graduation work,
  https://static1.squarespace.com/static/5aa06b5d45776efa78eb5d26/t/5c1bfc71032be4feca50056c/1545337983238/paper.pdf):
  morph targets = cheap and good-looking; **skeletal meshes = don't** (uncontrollable, heavy);
  procedural/vertex deformation = best if you have time, split the mesh into sections; material
  vertex displacement = additive, cheap on GPU. Wreckfest computes the deformation per hit (no full
  soft-body).
- At chase-camera distance (6 m), dents smaller than ~8 cm are invisible; exaggerate (×1.5).
- Readability order (most to least): sparks + camera shake + sound → flying parts (bumper, wing) →
  smoke/fire tier → dents → scratches/decals.

### 7.2 Impact classification (every contact event, player + AI cars)
```
n       = contact normal (pointing out of the other body)
v_rel   = my_velocity − other_velocity
v_n     = max(0, −v_rel.dot(n))                 # closing speed along the normal, m/s
impact  = v_n / max(v_rel.length(), 0.1)         # 0 = scrape, 1 = head-on
```

| Case | Rule |
|------|------|
| Scrape (impact < 0.35, static wall) | wall-glance assist: remove the normal velocity, keep 95 % tangential speed, yaw the car 50 % toward the wall tangent over 0.15 s; sparks; 2 HP/s while grinding |
| Hit (0.35 ≤ impact < 0.70) | keep tangential × (1 − 0.45·impact) (clone rule), normal bounce 0.25; damage formula |
| Head-on (impact ≥ 0.70) | damage formula; if v_n ≥ 30 m/s (108 km/h) → wreck regardless of HP |
| Traffic glance (impact < 0.3, other = traffic) | traffic car is shoved (switches to WRECK mode, §6.1), player keeps 90 % speed, 1 HP |

### 7.3 Health and damage numbers (ours)
`damage_HP = 0.15 × max(0, v_n − 5)² × k_mass`, k_mass = 1.0 vs static/world; vs a car
`k_mass = 2 × m_other / (m_self + m_other)` (equal masses → 1.0; a 2.6 t SUV hitting a 1.9 t car → 1.16).
Examples (player, k = 1): v_n 10 m/s → 4 HP; 20 → 34; 25 → 60; 28 (100 km/h) → 79; 30 → wreck rule.

| Vehicle | HP | Mass | Notes |
|---------|----|------|-------|
| Player Roadster | 100 | 1,900 kg | regen +2 HP/s after 6 s without damage, up to 60 HP; charging bay +20 |
| Rival racer | 100 | 1,600–2,000 kg | same formula |
| Patrol sedan | 60 | 1,800 kg | |
| Interceptor | 70 | 1,900 kg | |
| Heavy SUV | 140 | 2,600 kg | |
| Traffic sedan / van / bus | 40 / 60 / 300 | 1,500 / 2,400 / 12,000 kg | bus never wrecks from player hits |

Ramming bonus: the car that hits with its **front** (my forward · −n > 0.7) takes ×0.5 damage — rewards
aggression, Burnout-style. Landing on a roof (vertical takedown): victim takes 999.

### 7.4 Damage tiers and wreck states (visual spec)

| HP % | State | Visual |
|------|-------|--------|
| 100–61 | clean | dents only |
| 60–31 | light | grey smoke from the front (GPUParticles3D 24 particles, #8A8F96 alpha 0.5, rise 1.5 m/s), one headlight flickers 3 Hz |
| 30–1 | heavy | dark smoke (#2B2D31 alpha 0.7, 40 particles), sparks under the car every 0.5 s, bumper hangs (hinge 25°), screen edge red pulse for player |
| 0 | wrecked | fire at engine bay (orange #FF7A1A → #FFD27A core, 60 particles, 6 s), one small explosion (0.4 s flash, 6 m radius light #FFB04A energy 8), wheel detaches if impact ≥ 0.7; AI cars: stay 6 s then sink/fade; player: crash cam then respawn |

Note: the Roadster is an EV — use **white-blue electrical arcs + white smoke** for the player car's
heavy state instead of black oil smoke (est. stylistic choice; keeps the cold-gas look). Police/ICE
traffic may use dark smoke.

### 7.5 Deformation implementation (Godot 4.7) — choose A, add B only if time
**A. Vertex-shader dents (recommended: cheap, no mesh rebuild, works with any car mesh)**
- Body mesh needs enough vertices where dents happen: Blender side — panels subdivided so edge length
  ≤ 12 cm on bumpers, hood, doors, rear deck (≈ 8–15 k vertices for the body; ask the art dossier).
- Keep up to **8 dents** per car in a ring buffer (oldest replaced). Each dent = local impact point
  (car local space), radius r = clamp(0.25 + v_n × 0.025, 0.25, 0.9) m, depth = clamp(v_n × 0.012, 0.03,
  0.25) m, direction = −n in car local space.
```glsl
shader_type spatial;
uniform vec4 dent_pos[8];   // xyz = local point, w = radius (0 = unused)
uniform vec4 dent_dir[8];   // xyz = local push direction (unit), w = depth (m)
void vertex() {
    vec3 p = VERTEX;
    for (int i = 0; i < 8; i++) {
        float r = dent_pos[i].w;
        if (r <= 0.0) { continue; }
        float f = 1.0 - smoothstep(0.0, r, distance(VERTEX, dent_pos[i].xyz));
        p += dent_dir[i].xyz * dent_dir[i].w * f * f;
        NORMAL = normalize(mix(NORMAL, -dent_dir[i].xyz, f * 0.35)); // fake shading of the dent
    }
    VERTEX = p;
}
```
  Dent points must be in the **MeshInstance3D's local space** (`body_mesh.to_local(global_contact_point)`;
  directions via `body_mesh.global_transform.basis.inverse() * dir`). Set the uniforms with
  `material.set_shader_parameter("dent_pos", PackedVector4Array or Array of Vector4)` only when a dent
  is added (not every frame). Collision shapes do NOT deform.
- Paint scrape: same impact data writes into a 512×512 damage mask texture (Image.set_pixel splat,
  ≤ 1 update per 0.1 s) that the fragment shader uses to blend carbon/primer over paint.
**B. CPU vertex deformation (optional, Wreckfest-like)** — on impact, move vertices within r by the same
falloff in a cached PackedVector3Array, then rebuild with `ArrayMesh.clear_surfaces()` +
`add_surface_from_arrays()` (simple) at most once per 0.1 s per car; budget ≤ 1.5 ms per rebuild for
≤ 15 k vertices (est.). Recompute normals for affected vertices only. Faster path:
`RenderingServer.mesh_surface_update_vertex_region()` — but the vertex stride depends on the mesh format
(check `mesh_surface_get_format_vertex_stride()`), so use it only after the simple path works.

### 7.6 Detachable parts (RigidBody3D debris)

| Part (separate MeshInstance3D in the car scene) | Detach when | Debris body |
|------|-------------|-------------|
| Front bumper/splitter | cumulative front damage ≥ 45 HP or one front hit with v_n ≥ 22 m/s | BoxShape3D 1.9×0.25×0.3 m, 14 kg |
| Rear active wing (the Roadster's pop-up wing) | rear hit v_n ≥ 18 m/s or roof landing | Box 1.4×0.08×0.35 m, 8 kg |
| Camera "winglets" (mirrors) ×2 | side scrape ≥ 1.5 s or side hit ≥ 12 m/s | Box 0.25×0.1×0.15 m, 2 kg |
| Frunk lid | front hit ≥ 26 m/s | Box 1.2×0.05×0.9 m, 10 kg |
| Wheel | wreck with impact ≥ 0.7 (AI cars and player wreck only) | CylinderShape3D r 0.36 h 0.28, 22 kg |

On detach: hide the part mesh on the car, spawn a pooled RigidBody3D with the same global transform,
linear velocity = car velocity × 0.8 + random(±3, 2..6, ±3) m/s, angular velocity random ±8 rad/s,
collision layer `debris` (collides with world only, NOT cars — avoids jitter and unfair hits),
continuous_cd off, sleep allowed, lifetime 8 s then fade 0.5 s and return to pool. Global pool 32
bodies (oldest recycled). Police/rival cars: same parts list, simplified (bumper + wheel).

### 7.7 Performance budget (target: 60 fps on a mid PC, 1080p; est.)

| System | Budget per frame |
|--------|------------------|
| Physics (Jolt, 120 Hz → 2 ticks/frame): player + 5 rivals or 12 police (full sim) + 32 debris + world | ≤ 3.0 ms |
| Car controllers (GDScript, 18 cars × 4 shapecasts × 2 ticks) | ≤ 1.5 ms |
| Traffic (70 cars, most frozen-kinematic, ≤ 15 near-dynamic; IDM + lane change) | ≤ 1.0 ms |
| Particles: ≤ 8 active smoke/fire emitters, ≤ 64 particles each; sparks 1 emitter per scraping car | GPU |
| Damage: dent uniforms on change only; mask texture ≤ 10 updates/s total | ≤ 0.3 ms |

If over budget: AI cars > 150 m from the camera drop to 60 Hz updates and 2 wheel probes (front/rear axle
centre); traffic beyond 200 m updates every 2nd tick.

### 7.8 Wreck → respawn flow (player)
1. Wreck trigger (HP 0, head-on rule, or upside-down 1.5 s on the ground).
2. Crash cam 2.2 s: camera detaches, orbits 30° around the wreck at 7 m, time_scale 0.35 → 1.0;
   banner "撞车 WRECKED" (red #FF3B3B). Input disabled.
3. Respawn on the nearest valid lane point 30 m behind the wreck position (never inside a Sky Lane,
   never facing traffic), at 70 % of pre-crash speed (min 60 km/h), HP 60, N₂ unchanged, 2.0 s ghost
   (no collisions with cars, 50 % alpha flicker). Call `reset_physics_interpolation()`.
4. In a pursuit: heat does not change; each wreck adds 1/3 to the busted meter.

---------------------------------------------------------------------------------------------------
## 8. Recommended design for SKYRUSH — feel table, controls, HUD, tuning file

### 8.1 Feel table (target numbers; all (ours) unless marked)

| Quantity | Value |
|----------|-------|
| Physics tick | 120 Hz (RL, clone) |
| Mass / CoM height / inertia | 1,900 kg / 0.42 m / (3400, 3200, 900) kg·m² |
| Base top speed V_TOP | 250 km/h = 69.4 m/s |
| Base accel A0 (decays to 0.2× at V_TOP) | 14 m/s² → 0–100 km/h ≈ 2.4 s, 0–250 km/h ≈ 10 s |
| Brake / reverse | 16 m/s² / 40 km/h max |
| Steering max wheel angle | 32° at 0 → 7° at V_TOP |
| Grip μ front / rear | 1.45 / 1.40; drift rear × 0.45 |
| Downforce | 2.3·v² N (0.6 g at 250 km/h) |
| Drift entry | ≥ 54 km/h, abs(steer) ≥ 0.3; yaw 0.9–1.8 rad/s; slip 26–52°; loss (1.5 + 8 sin β) m/s² |
| Gauge | per tick (in slots): max(0.015 × km/h of drift loss this tick (before assist), 0.10·dt); 3 s drift at 35° ≈ 1 slot; 2 slots |
| 小喷 | window 0.50 s; +22 km/h cap (E_w = 6.1 m/s); +10 m/s²; 0.68 s (QQ 0.68 s src); 完美小喷 (< 0.20 s): +4 m/s instant kick (ours) |
| N₂ Boost | 1 full slot; 3.0 s; +50 km/h cap (E_n = 13.9 m/s); +12 m/s² (QQ 3.08–3.35 s src) |
| Stack caps | 小喷 only 272; N₂ only 300; CW 306.6; WCW 308.8; CWW 317.6; WCWW 319.8 km/h (QQ coefficients 0.3/0.4/0.8/0.9 src); hard cap 330 km/h |
| Stack timing | C→W ≤ 0.25 s; W→W 0.55–0.85 s (src) |
| 完美起步 (thruster launch) | throttle pressed in the last 0.25 s before GO → extra +20 m/s² for the first 1.0 s → 0–100 km/h ≈ 0.9 s; white rear plume; "完美起步！" (costs no N₂) |
| Early throttle (before the window) | no launch, 0.3 s wheelspin (normal start) |
| N₂ resource | 2 slots × 100; self-refill +3/s to 100; drift, takedown +50, near miss +5, trick +15, charging bay full |
| Hop / Big Hop | 25 N₂, v_y 11 m/s, apex 3.1 m, 1.12 s / 50 N₂, v_y 17.5 m/s, apex 7.8 m, 1.78 s |
| Air gravity / Hover | 2.0 g / net 2.9 m/s² down, 12 N₂/s, ≤ 3 s |
| Barrel roll | 0.70 s, 20 N₂, 3.5 m dodge, 0.5 s immunity, ≤ 2 per airtime |
| Landing 小喷 window | 0.45 s after ≥ 0.3 s airtime |
| Sky Lane | ≥ 120 km/h + 25 N₂ to enter; 200–300 km/h; tube 14 × 8 m; 10 N₂/s; rings +40 every 250 m |
| Camera | 6.0 m back, 1.9 m up; vFOV 62° → 84°; pos λ 14, yaw λ 7/4.5 |
| Wall scrape / hit | keep 95 % / × (1 − 0.45·impact); damage 0.15·(v_n − 5)² |
| Wreck | HP 0 or v_n ≥ 30 m/s head-on; respawn 30 m back at 70 % speed |
| Takedown | 2.0 s contact credit; cam 2.7 s; streak 10 s; +50 N₂ |
| Police | heat 1–5: units 3/5/7/9/12, cooldown 20/35/50/70/90 s, evade after 4 s unseen |
| Traffic | 50–70 cars, spawn 180–350 m, despawn > 420 m, IDM T 1.2 s, s0 2.5 m |

### 8.2 Controls (default bindings; all rebindable via InputMap)

| Action (InputMap name) | Keyboard A — QQ PC layout (default) | Keyboard B — WASD | Gamepad (Xbox / PlayStation) |
|------------------------|------------------------|-------------------|------------------------------|
| `throttle` | ↑ | W | RT / R2 (analog) |
| `brake_reverse` | ↓ | S | LT / L2 (analog) |
| `steer_left` / `steer_right` | ← / → | A / D | Left stick X (dead-zone 0.12, curve s·abs(s)) |
| `drift` (hold) | Left Shift | Left Shift | RB / R1 (on ground) |
| `mini_boost` 小喷 (tap) | W (or release + re-press ↑) | K (or release + re-press W) | B / Circle (or release + re-press RT) |
| `n2_boost` 氮气 | Left Ctrl | J | X / Square |
| `hop` (tap = Hop, hold ≥ 0.25 s = Big Hop; hold in air = Hover) | Space | Space | A / Cross |
| `roll_left` / `roll_right` (air) | Q / E | Q / E | LB / RB (in air) = L1 / R1 |
| Sky Lane up / down | ↑ / ↓ (throttle/brake keys) | W / S | Left stick Y (option invert) |
| `look_back` | C | C | R3 |
| `camera_cycle` (near / far / bumper) | Tab | Tab | Y / Triangle |
| `reset_car` | R | R | View / Share (hold 1 s) |
| `pause` | Esc | Esc | Menu / Options |

Notes: on gamepad, RB is drift on the ground and roll-right in the air — the car state decides
(airborne ≥ 0.10 s ⇒ roll). Show both key prompts in the tutorial. Hold-to-charge Big Hop shows a
radial ring around the hop icon (0.25 s to full).

### 8.3 HUD spec (reference canvas 1920 × 1080, anchors in brackets; colours hex)
Palette (coordinate with ref/art; these are defaults): cyan #00E5FF (N₂, speed lines, Sky Lanes),
magenta #FF2BD6 (accents, chevrons), amber #FFB300 (takedown banner, warnings, HOP prompt),
white #FFFFFF text with 3 px #0A0A0A outline, police red #FF3B3B / blue #2F6BFF (flash 2 Hz),
panel background #0A1A2A at 70 % alpha. Fonts (suggestion, OFL licensed): numbers "Rajdhani Bold
Italic", CJK "Noto Sans SC Black".

| Element | Anchor / position | Size | Content and behaviour |
|---------|-------------------|------|-----------------------|
| Speedometer | bottom-right, centre (1730, 900) | dial radius 120 px | arc 240° from 7 o'clock; cyan fill ∝ speed/330; number 72 px italic; "km/h" 22 px; turns magenta while N₂ burns |
| N₂ slots | left of dial, centres (1505, 900) and (1550, 900) | each 34 × 110 px capsule | fill bottom→top cyan; full = glow pulse 1 Hz; filling slot shows the 集气 gauge live |
| 集气 bar (QQ N2O bar) | bottom-right, (1460, 1040) → (1860, 1052) | 400 × 12 px | thin bar under dial + slots mirroring the current slot fill; label "N₂" 20 px at its left end |
| Position | top-left (60, 50) | rank 96 px italic ("2", with "/6" 40 px) | QQ style; list of racers below (max 6 rows × 28 px, ends at y ≈ 320); races only |
| Lap / time | top-right (1860, 50) right-aligned | 30 px | 时间 00'27"74 / 最佳 / 圈 1/2 (lap 64 px) |
| Minimap | bottom-left circle centre (190, 860) | diameter 280 px | heading-up; route = cyan line; rivals orange #FF8A00 dots; police red/blue chevrons; Sky Lanes dashed cyan; charging bays ⚡; breakers amber △ |
| Pursuit bar | bottom-centre (960, 1010) | 600 × 18 px | NFS MW05 style: left red (busted) ← → right green (evade); heat 1–5 as 5 chevrons above; units count; cooldown replaces it with a blue bar |
| Pop-up text | centre (960, 380) | 64 px | stack max 2; scale-in 0.12 s to 110 % → 100 %, hold 0.8 s, fade 0.25 s |
| Takedown banner | top-left (60, 340) after the centre pop | 64 px | §3.5 |
| Hop prompt | above the car on screen (960, 620) | 48 px | "跳！HOP ▲" amber when a roadblock/toll plaza is 150 m ahead and N₂ ≥ 50 |

### 8.4 Pop-up texts (trigger → text → colour)

| Trigger | Text (zh / en) | Colour |
|---------|----------------|--------|
| Countdown | 3 · 2 · 1 · GO! (160 px, centre) | white; GO cyan |
| Launch in window | 完美起步！ PERFECT START | cyan glow |
| Clean drift ≥ 1.5 s | 漂移 DRIFT +N | white |
| 小喷 within 0.20 s | 完美小喷！ PERFECT BOOST | cyan |
| 2nd 小喷 (chain) | 双喷！ DOUBLE BOOST | cyan |
| CWW achieved | CWW! | magenta |
| Landing boost | 落地喷！ LANDING BOOST | cyan |
| N₂ slot filled | 氮气 +1 | cyan icon flash on the slot (no centre text) |
| Near miss | 擦身而过 NEAR MISS +5 | white, small (40 px) |
| Trick (roll + clean landing) | 特技！ TRICK +15 | magenta |
| Charging bay | 闪充！ FLASH CHARGE | cyan + white flash |
| Takedown types | §3.5 banner | amber |
| Pursuit start | 警方追捕！ PURSUIT (heat chevrons slide in) | red/blue flash |
| Heat up | 通缉等级 ↑ HEAT 3 | red |
| Cooldown started | 甩开警察 EVADING… | blue #2F6BFF |
| Escaped | 成功逃脱！ ESCAPED | green #39FF88 |
| Busted | 被捕 BUSTED (full-screen dim 60 %) | red |
| Wreck | 撞车 WRECKED | red |

"完美漂移" is not used as a pop-up because it is not a confirmed QQ pop-up (§2.1); use 漂移 + 完美小喷.

### 8.5 Speed-feel effects — implementation notes (Godot 4.7)
- Speed lines: GPUParticles3D child of the Camera3D with `local_coords = true`; emission shape = ring
  (inner radius 4 m, outer 9 m) centred at camera-local (0, 0, −30) facing the camera; process material
  direction (0, 0, 1) (toward the camera), spread 0°, initial velocity = current car speed (update the
  material's `initial_velocity_min/max` each frame), lifetime 0.40 s, 120 particles, gravity 0;
  draw pass = thin quad stretched along velocity (length 2.5–6 m); colour white alpha 0.25 (cyan
  #00E5FF alpha 0.45 during N₂); `amount_ratio` = smoothstep(160, 280, km/h).
- Radial blur: full-screen ColorRect (CanvasLayer layer −1, below the HUD) with a shader sampling
  `hint_screen_texture` 6 taps toward the screen centre; strength 0 at 200 km/h → 0.35 at 300 km/h;
  centre 15 % of the screen untouched. Settings toggle "运动模糊 Motion blur" (default ON-low).
- FOV, camera shake and glow per §2.3. Camera shake uses `FastNoiseLite` 10 Hz, never `randf()` per frame.
- Wind/whoosh audio: AudioStreamPlayer pitch 0.8 → 1.3 and volume −20 → −4 dB with speed.
- Lamp posts/gantries passing close to the camera are the strongest speed cue → keep roadside props
  dense (every 30–40 m) along race routes (coordinate with ref/shanghai).

### 8.6 Tuning file — copy into `scripts/vehicle/car_tuning.gd` (all SI units)
```gdscript
class_name CarTuning
extends RefCounted
const MASS := 1900.0
const COM := Vector3(0.0, 0.42, 0.05)
const INERTIA := Vector3(3400.0, 3200.0, 900.0)
const V_TOP := 69.4            # 250 km/h
const V_CAP := 91.7            # 330 km/h hard cap
const A0 := 14.0               # base accel, decays to 0.2x at V_TOP
const BRAKE := 16.0
const SPRING_K := 70000.0
const DAMP_BUMP := 4600.0
const DAMP_REBOUND := 6300.0
const REST_LEN := 0.41
const TRAVEL := 0.20
const WHEEL_R := 0.36
const ARB_FRONT := 28000.0
const ARB_REAR := 20000.0
const MU_FRONT := 1.45
const MU_REAR := 1.40
const DRIFT_REAR_MU := 0.45
const DOWNFORCE_K := 2.3
const STEER_MAX_DEG := 32.0
const STEER_MIN_DEG := 7.0
const DRIFT_MIN_SPEED := 15.0
const DRIFT_YAW_MIN := 0.9
const DRIFT_YAW_MAX := 1.8
const DRIFT_VEL_LAMBDA := 2.0
const DRIFT_LOSS_BASE := 1.5
const DRIFT_LOSS_SIN := 8.0
const GAUGE_PER_KMH_LOST := 0.015
const GAUGE_FLOOR_PER_S := 0.10
const MINI_WINDOW := 0.50
const MINI_PERFECT := 0.20
const MINI_TIME := 0.68
const MINI_EXTRA_V := 6.11     # +22 km/h
const MINI_ACCEL := 10.0
const N2_TIME := 3.0
const N2_EXTRA_V := 13.89      # +50 km/h
const N2_ACCEL := 12.0
const STACK := {"CW": 0.3, "WCW": 0.4, "CWW": 0.8, "WCWW": 0.9}
const CW_GAP_MAX := 0.25
const WW_GAP_MIN := 0.55
const WW_GAP_MAX := 0.85
const N2_SLOT := 100.0
const N2_MAX := 200.0
const HOP_VY := 11.0
const BIG_HOP_VY := 17.5
const AIR_GRAVITY_SCALE := 2.0
const COST := {"hop": 25.0, "big_hop": 50.0, "roll": 20.0, "hover_per_s": 12.0, "lane_per_s": 10.0}
const ROLL_TIME := 0.70
const LAND_WINDOW := 0.45
const CAM_DIST := 6.0
const CAM_HEIGHT := 1.9
const FOV_BASE := 62.0
const FOV_MAX := 84.0
const FOV_PER_MS := 0.10       # degrees per m/s of speed
const FOV_N2 := 8.0
const FOV_MINI := 4.0
const CAM_POS_LAMBDA := 14.0
const CAM_YAW_LAMBDA_GRIP := 7.0
const CAM_YAW_LAMBDA_DRIFT := 4.5
const HOVER_LIFT := 0.85       # fraction of air gravity cancelled while hovering
const SELF_REFILL_PER_S := 3.0 # N2 units/s, only up to N2_SLOT
const LAND_MIN_AIRTIME := 0.30
const START_WINDOW := 0.25     # throttle in the last 0.25 s before GO = perfect launch
```

---------------------------------------------------------------------------------------------------
## 9. Do / Don't for the implementer
DO
- Run all vehicle logic in `_integrate_forces` / `_physics_process` at 120 Hz; read input there too.
- Keep every number in `car_tuning.gd` (§8.6); log changes with a reason.
- Apply tyre/drive forces at CoM height; pass `position` to `apply_force` as a **global offset from the
  body origin** (Godot API), not a local position.
- Make the drift reward loop obvious: gauge fills visibly, slot icon flashes, 小喷 window shown as a
  shrinking cyan ring around the speedometer (0.50 s).
- Make thrusters white cold gas (puff clouds, pale jets). Make N₂ boost read as "white jets + cyan glow".
- Give every hit feedback in this order: sound → sparks → shake → (if big) hit-stop 0.06–0.08 s.
- Keep far traffic frozen-kinematic, near traffic dynamic with axis locks (§6.1); pool everything.
- Test with numbers (§10) before tuning by feel.
DON'T
- Don't use VehicleBody3D (Godot docs warn against it for this).
- Don't put physics in `_process`; don't scale forces by frame delta twice (forces are already per second).
- Don't make thrusters orange fire or leave black smoke; don't put real police/Tesla logos on cars.
- Don't let the camera copy the car's roll/pitch 1:1 (nausea); don't exceed 84° vFOV.
- Don't deform collision shapes; don't rebuild meshes every frame.
- Don't spawn traffic or police inside the camera view or < 120 m away.
- Don't stack 小喷 without N₂ (QQ rule: they overwrite); don't let speed exceed V_CAP.
- Don't wreck the player for glancing traffic hits (< 0.3 impact) — forgiving first.

---------------------------------------------------------------------------------------------------
## 10. Build order and numeric acceptance tests

| Step | Build | Accept when (log it in a debug overlay) |
|------|-------|----------------------------------------|
| 1 | Car body + 4 wheel probes + suspension | car settles at 0.067 m sag ± 0.01 in < 1.0 s; no jitter at rest |
| 2 | Drive/brake/steer | 0–100 km/h 2.3–2.5 s; top speed 250 ± 2 km/h (reached in ≈ 10 s); 100–0 in 1.6–1.9 s |
| 3 | Drift state | 3.0 s drift held at β ≈ 35° from 200 km/h → gauge 0.95–1.05 slot; slip 26–52°; no spin with full input |
| 4 | 小喷 / N₂ / stacking | caps: 272 / 300 / 306.6 / 308.8 / 317.6 / 319.8 km/h within ±1 km/h |
| 5 | Hop / Big Hop / roll | apex 3.1 ± 0.2 m / 7.8 ± 0.3 m; roll 0.70 s, ends level ± 2° |
| 6 | Camera + HUD + speed FX | vFOV 62.0° at rest; 79.2° at 330 km/h with N₂; 83.2° with N₂ + 小喷; never > 84°; pop-ups per §8.4 |
| 7 | Traffic | 60 cars at 60 fps; zero spawns in view (count in overlay) |
| 8 | Police | heat 1→5 reachable in 5 min; cooldown times per §3.4 ± 1 s |
| 9 | Damage + takedowns | 25 m/s head-on wall = 60 HP; takedown cam 2.7 s; streak resets after 10 s |
| 10 | Sky Lanes | entry at ≥ 120 km/h + 25 N₂ only; never leave the tube except at the end or at N₂ = 0 |

---------------------------------------------------------------------------------------------------
## 11. Open questions (need a decision from the lead / other dossiers)
1. Single N₂ resource (recommended, §5.2) vs separate "air tank" for hop/flight — playtest both?
2. Speed display: true km/h, or scaled ×1.2 for drama? (Some arcade games inflate; unverified.)
3. Exact dimensions of the 2026 Roadster (length, wheelbase, track) — I used est. 4.40 × 1.95 m and a
   2.70 m wheelbase; replace with ref/roadster measurements.
4. Coordinate axis convention (+Z nose) — confirm with ref/tech.
5. Do Shanghai elevated roads in the game have toll plazas? Real urban elevated roads are toll-free;
   toll plazas fit the outer expressways (unverified) — ask ref/shanghai.
6. Police livery/vehicle look: stylised "SPD"-like generic, no real 公安 marks (legal safety) — art lead.
7. Is an item mode (道具赛) wanted at all? Not needed for v1 (§1.7).
8. QQ facts still unverified: max held nitro = 2 on PC; whether "完美漂移" ever appears as a pop-up.

---------------------------------------------------------------------------------------------------
## 12. Sources (all accessed 2026-10-19; text extracts in ref/gameplay/dl/)
- QQ飞车 designer Q&A (stacking caps, timing, gauge formula): https://fcsy.qq.com/gicp/news/595/9388344.html
- QQ WCW vs CWW measurements: https://fcsy.qq.com/webplat/info/news_version3/28528/33593/33805/m19809/201803/704411.shtml
- QQ gauge efficiency guide: https://fcsy.qq.com/webplat/info/news_version3/28528/33593/33805/m19692/201803/704452.shtml
- QQ nitro collection (3 s / 180°): https://speedm.qq.com/webplat/info/news_version3/28528/33593/33805/m19692/201709/631747.shtml
- QQ PC car card 爆天雷诺: https://speed.qq.com/cp/a20200115btln/index.html ; 黑曼巴: https://baike.baidu.com/item/黑曼巴/61894270
- QQ PC keys/drift (2008): https://speed.17173.com/content/2008-03-10/20080310172701503.shtml ; http://news.17173.com/content/2008-03-17/20080317142458659.shtml
- QQ skills (2009 official): http://speed.qq.com/webplat/info/news_version3/147/14551/14572/14577/m15538/200907/5630.shtml
- QQ technique list: http://fcsy.qq.com/gicp/news/603/7699215.html ; https://www.cnblogs.com/Chqbelief/articles/17441226.html
- QQ perfect start: https://speedm.qq.com/gicp/news/603/138035.html ; items: https://speed.17173.com/content/2009-09-02/20090902102703842.shtml
- QQ-like clone analysis: https://learn.zhoujunhui.com/blog/learn-qq-speed-sourcecode-with-ai
- NFS pursuit: https://nfs.fandom.com/wiki/Pursuit , /Police_Tactics , /Pursuit_Breaker , /Equipment , /Fairhaven_City_Police_Department/Pursuit ; https://en.wikibooks.org/wiki/Need_for_Speed:_Most_Wanted/Pursuit_system
- Burnout: https://burnout.fandom.com/wiki/Takedown , /Boost , /Aftertouch , /Burnout_Paradise ; https://en.wikipedia.org/wiki/Burnout_3:_Takedown ; takedown-cam timing measured from https://www.youtube.com/watch?v=cTZf3TqjNxQ (60–240 s)
- Rocket League GDC 2018: https://media.gdcvault.com/gdc2018/presentations/Cone_Jared_It_Is_Rocket.pdf ; RLBot values: https://wiki.rlbot.org/v4/botmaking/useful-game-values/
- Criterion Vehicle Feel Masterclass GDC 2018: https://media.gdcvault.com/gdc2018/presentations/Harris_Matthew_VehicleFeelMasterclass.pdf
- NWH arcade assists: https://nwhcoding.com/VehiclePhysics/api/NWH.VehiclePhysics2.Modules.ArcadeModule.ArcadeModule.html
- Godot 4.7 docs: Jolt https://docs.godotengine.org/en/latest/tutorials/physics/using_jolt_physics.html ; RigidBody3D, ShapeCast3D, ProjectSettings, VehicleBody3D, PhysicsDirectBodyState3D class pages; troubleshooting physics.
- AI: Game AI Pro ch. 39/40 (gameaipro.com); IDM https://en.wikipedia.org/wiki/Intelligent_driver_model ; https://www.denis-iakimenko.com/blog/ai-traffic-simulation-idm-mobil
- Damage: Smekens 2019 real-time car damage (link in §7.1).
- Roadster reveal: Car and Driver, Electrek, Top Gear, MotorTrend, NBC, TechCrunch, InsideEVs (links in §5.1); Mexico Business News https://mexicobusiness.news/automotive/news/teslas-rocket-thruster-roadster-takes-flight-stunt-unveiling
