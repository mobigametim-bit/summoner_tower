# Orc — SVG art для ручной приёмки

08.10.2026. **Orc полностью принят пользователем**, включая art, rigid cutout animations и gameplay. Animated default включён. [Art preview](http://127.0.0.1:4175/preview/orc-art/), [animation preview](http://127.0.0.1:4175/preview/orc-animation/), [бой](http://127.0.0.1:4175/preview/orc-gameplay/), [план](../../../docs/done/ORC_ART_PLAN.md), [art gate](../../../docs/done/ORC_ART_REVIEW.md), [animation gate](../../../docs/done/ORC_ANIMATION_REVIEW.md), [gameplay gate](../../../docs/done/ORC_GAMEPLAY_REVIEW.md).

Reference: `art/references/orc.png`. Art отрисован вручную SVG-кодом, без image generators, Krita, raster embedding или чужих игровых assets. Прозрачный полный canvas 256×256 без trimming; outline #29180f, 7 px, round joins/caps; flat colors и простые оттенки.

`master.svg` — сборка тех же семи групп, что находятся в `parts/`. `scenes/visuals/OrcVisual.tscn` использует эти части на восьми Bone2D; master нужен для общего просмотра. `rig_manifest.json` фиксирует pivots, слои и клипы созданного rig. `review.html` — отдельная статическая страница для art review. `equipment_mask.svg` — маска ботинок, напульсников и видимой повязки; верх повязки скрыт под нейтральным поясом и не включает его в маску. Локальный material назначен пяти частям; GPU-сравнение пяти цветов подтвердило неизменность кожи, нейтральных областей, головы и топора.

Силуэт массивнее Goblin: широкие плечи, два крупных клыка, короткие конечности и большой топор. Наплечники и кисти входят в руки, ботинки в ноги, лицо/уши/клыки в голову, пояс/повязка и диагональный ремень в body. Мелкие детали, фон и тень reference исключены. Клыки находятся ниже глаз, нос между глазами.

| Part | Pivot canvas | Parent / bone | Bone local position | Z |
|---|---|---|---|---:|
| arm_back | (75,148) | Body / BackArm | (−51,−28) | 0 |
| leg_left | (102,207) | Body / LeftLeg | (−24,31) | 1 |
| leg_right | (147,207) | Body / RightLeg | (21,31) | 2 |
| body | (126,176) | Root / Body | (126,176) | 3 |
| axe | (203,184) | FrontArm / Axe | (32,34) | 4 |
| arm_front | (171,150) | Body / FrontArm | (45,−26) | 5 |
| head | (128,142) | Body / Head | (2,−34) | 6 |

Root.position=(−128,−128); Sprite2D.centered=false, offset=−pivot; rest=initial transform. Ноги заканчиваются около y=239 с контуром до y=242. Скрытые основания шеи, плеч и бедер дорисованы с overlap. Windup/impact, крайняя ходьба, hit/death просмотрены в Godot; явных щелей и нарушения хвата не обнаружено.

Палитра кожи #7fa443 / #5f8134 / #a0bf60; ремни/дерево #895334 / #613821 / #a46b42; металл #8d8981 / #625e59 / #c5c0b6; клыки/шипы #f3e7ce / #d9c39e. Source одежда #9c642d / #b77e42. Только группы `data-equipment` меняют эти два fills в SVG-примерке пяти уровней. Кожа, наплечники, ремни, металл, клыки и топор не перекрашиваются.

Preview использует visual.scale=120/256 и фактический follow_route scale=min((cell_size−12)/140,1). На клетках сеток 6/7/8 полный canvas получается около 86/72/62 логических px, на экране шириной 390 — 46/39/33 физических px. Используется существующая мощёная дорога. По правке пользователя Goblin уменьшен на 20%; сравнение учитывает его canvas size=86.4, размер Orc сохранён. С Archer показана общая стилизация. HealthBar поднята над головой; движение, animations и настоящий бой проверены через MCP и Web, результаты в gameplay review.

Clips: walk_loop=0.8 s, attack=0.4 s с impact=0.18 s, hit=0.16 s, death=0.32 s. RESET восстанавливает изменяемые transforms/modulate. Gameplay выбирает прежний кадр контакта с башней и ставит позу impact; animation не является отдельным источником урона. Development animation scene — настоящий наследник `ArtAnimationTest`, четыре видимых Orc, реальные масштабы и playback controls. OrcGameplayReview использует настоящий бой с wave 3, STATIC/ANIMATED и Pause.

`assets/orc.svg` сохранён для rollback; animated default в `scenes/orc.tscn` включён после полной приёмки. Отчёты находятся в docs/done; отдельный commit фиксирует Orc и согласованное уменьшение Goblin. Push только по отдельному разрешению.
