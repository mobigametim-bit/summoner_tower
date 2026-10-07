# Frost Mage — SVG art review

07.10.2026. **Frost Mage полностью принят пользователем.** Animated visual включён по умолчанию; static fallback сохранён. Source art и восемь частей сохранены без изменения принятых shapes. [Тестовый бой](http://127.0.0.1:4175/preview/frost-mage-gameplay/), [отчёт](../../../docs/done/FROST_MAGE_GAMEPLAY_REVIEW.md). Push только по отдельному разрешению.

Reference: `art/references/frost_mage.png`. Новый art отрисован вручную SVG-кодом: простые paths/circles/ellipses, flat fills, outline #29180f толщиной 7 px и простое shading. Фон, тень и парящие декоративные кристаллы reference исключены.

[Просмотр в браузере](http://127.0.0.1:4175/preview/frost-mage-art/) — reference рядом с новой сборкой; размеры 100/140/180 px; постаменты сеток 6/7/8 столбцов и телефонный масштаб; сравнение с принятыми Archer/Mage; пять цветов ткани; отдельные части, pivots и зеркало.

`master.svg` — сборка тех же восьми групп, что сохранены в `parts/`. Все SVG — полный прозрачный canvas 256×256 без trimming. Master предназначен для review и будущего drag preview, runtime visual использует части. `review.html` — статический просмотр, не игровая сцена. `rig_manifest.json` фиксирует pivots, слои и длительности clips.

[Просмотр анимаций](http://127.0.0.1:4175/preview/frost-mage-animation/) — Godot Web: idle_loop 1.2 s, cast 0.42 s с release 0.18 s, spawn 0.4 s. Четыре одновременно анимируемых экземпляра, большой и игровой масштаб, 0.5×/1×/2×, pause/replay, repeat/mirror и переключение на принятых Archer/Goblin/Mage. [Отчёт animation gate](../../../docs/done/FROST_MAGE_ANIMATION_REVIEW.md).

## Части и слои

Сзади вперёд: arm_back, leg_left, leg_right, body, staff, arm_front, head, hood. Посох перед корпусом и за удерживающей кистью. Капюшон обрамляет лицо и в будущем следует Head без отдельной кости.

Руки цельные вместе с кистями; волосы входят в голову, ботинки в ноги. Окантовка, ремни, брошь и два задних выступа входят в body. Ледяной кристалл входит в staff. Скрытые окончания плеч, ног и шеи дорисованы под соседние части; отсутствие щелей при движении проверяется на следующем gate.

## Палитра и pivots

Ткань source: #3568b6 / #254b85 / #5488d0. Белая отделка #f3f2ec, волосы #f3f2ec / #d4d0df, кожа #ffc18c / #de9668, кожа/дерево #895334 / #613821 / #a46b42, лёд #56d9ed / #2999c0 / #b5f4f4 / #e8ffff. В браузерной примерке уровней меняются только три цвета ткани; отделка, кожа, волосы, ремни, ботинки и лёд сохраняются. В Godot используется локальный ShaderMaterial с общим `art/source/mage/cloth_palette.gdshader`; drag preview получает ту же палитру. Ледяное свечение — три Polygon2D у посоха, без дополнительных textures.

Canvas coordinates: actor_origin=(128,128), feet_baseline_y=239. Плечи BackArm=(94,158), FrontArm=(163,159), корпус Body=(127,175), шея Head/Hood=(128,144), хват Staff=(203,175), бёдра LeftLeg=(102,211), RightLeg=(148,211). Rig: Root.position=−actor_origin, Bone.position=pivot−parent_pivot, Sprite2D centered=false, position=−pivot. Hood использует Head pivot. Восемь bones включая Root; rest задан явно. ReleasePoint под Staff=(6.92,−67.48), на release соответствует прежнему Muzzle=(32,−8). Visual выдаёт только событие, не создаёт снаряды.

[Согласованный план](../../../docs/done/FROST_MAGE_ART_PLAN.md), [результаты проверки art](../../../docs/done/FROST_MAGE_ART_REVIEW.md). Документы принятого Frost Mage находятся в docs/done.
