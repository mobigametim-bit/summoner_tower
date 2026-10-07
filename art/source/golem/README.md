# Golem — SVG-art для ручной приёмки

08.10.2026. План, art и animations приняты пользователем, включая удар двумя руками. **Golem полностью принят; animated default включён, static сохранён.** [Открыть art](http://127.0.0.1:4175/preview/golem-art/), [анимации](http://127.0.0.1:4175/preview/golem-animation/), [бой](http://127.0.0.1:4175/preview/golem-gameplay/), [план](../../../docs/done/GOLEM_ART_PLAN.md), [art review](../../../docs/done/GOLEM_ART_REVIEW.md), [animation review](../../../docs/done/GOLEM_ANIMATION_REVIEW.md), [gameplay review](../../../docs/done/GOLEM_GAMEPLAY_REVIEW.md).

Reference — `art/references/golem.png`, PNG 1254×1254. Production art написан вручную SVG-кодом, без image generators, Krita, растровых вставок, чужих assets, fonts или filters. Полный прозрачный canvas 256×256 без trimming; основной outline #29180f, 7 px, round joins/caps. Крупные плоскости камня с одним тёмным и одним светлым оттенком; мох из крупных пятен с одной тенью. Всего 50 paths в master, восемь parts.

Силуэт: широкие плечи, крупная каменная голова между ними, маленькие жёлтые глаза, короткий корпус, большие кулаки и короткие ноги. Мелкие грани/трещины reference исключены. Кулаки входят в предплечья, плечевые блоки — в upper arms, глаза и мох головы — в Head; отдельных пальцев, кистей, коленей, оружия и костей мха не будет.

`master.svg` собирает те же восемь групп в том же порядке, что `parts/`. GolemVisual использует отдельные parts; master нужен для просмотра. `rig_manifest.json` содержит точные pivots, позиции костей, offsets и z-order; `rig_created=true`. `moss_mask.svg` выделяет восемь исходных областей мха. `moss_palette.gdshader` перекрашивает только зелёные fills внутри mask. Один local-to-scene материал общий для восьми частей экземпляра, независимый от других Golem; камень, глаза и outline сохраняются.

| Part | Pivot canvas | Parent / bone | Bone local position | Z |
|---|---|---|---|---:|
| arm_back_upper | (85,126) | Body / BackUpperArm | (−43,−44) | 0 |
| arm_back_forearm | (57,147) | BackUpperArm / BackForearm | (−28,21) | 1 |
| leg_left | (100,196) | Body / LeftLeg | (−28,26) | 2 |
| leg_right | (151,196) | Body / RightLeg | (23,26) | 3 |
| body | (128,170) | Root / Body | (128,170) | 4 |
| arm_front_upper | (171,130) | Body / FrontUpperArm | (43,−40) | 5 |
| arm_front_forearm | (210,157) | FrontUpperArm / FrontForearm | (39,27) | 6 |
| head | (133,147) | Body / Head | (5,−23) | 7 |

Ориентир Root.position=(−128,−128), baseline ступней y=239; Sprite2D.centered=false и position=−pivot, Bone rest явно равен исходному transform. Pivots плеч, локтей, бёдер и головы находятся внутри непрозрачного overlap обеих соединяемых частей: проверено по импортированным Godot textures, alpha=1. Динамические gaps/clipping проверяются после ручной приёмки art при создании rig.

Камень #bba58b / #887562 / #dfcbae; щели #49392c; глаза #ffd16c. Мох #88b96b / #668b50 (тень ×0.75). Только группы `data-moss` меняют fills в пяти цветовых примерках. Камень, контур, щели и глаза сохраняются. Пороги исходного EnemyStats — 120/240/480/960/1920 HP, без изменения баланса.

Примерка использует canvas_size=140 и будущий visual.scale=140/256=0.546875 с существующим follow_route scale=min((cell_size−12)/140,1). На сетках 6/7/8 полный canvas получается 100/84/72 логических px; при экранной ширине 390 — 54/46/39 физических px. Для сравнения используются Orc 120 и принятый уменьшенный Goblin 86.4 на таких же клетках. Эта страница не заменяет будущую проверку в бою с HealthBar.

Godot 4.7.2 импортировал master, восемь parts и mask как textures 256×256, svg/scale=1, без mipmaps. В Edge просмотрены reference, большой и малый рисунок, дорога и пять цветов; selector parts, pivot overlay и mirror работают. Phone width=390, content width=390, console/page/resource errors=[].

Создан `scenes/visuals/GolemVisual.tscn`: 9 bones вместе с Root, 8 sprites, один AnimationPlayer; walk_loop 1.2 s, attack двумя руками 0.5 s с impact 0.20 s, hit 0.16 s, death 0.35 s. RESET возвращает все изменяемые свойства. Риг и clips созданы через Godot MCP; принятые SVG shapes не менялись. Gameplay integration принята после native/Web проверок; animated default включён, отчёты перенесены в docs/done. Push требует отдельного разрешения. Static `assets/golem.svg` сохранён.
