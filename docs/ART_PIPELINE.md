# SUMMONER TOWER — art и animation pipeline

Стандарт зафиксирован после финальной приёмки Archer 07.10.2026. Решение пользователя: **KEEP RIGID CUTOUT**. [Отчёт пилота](done/ARCHER_GAMEPLAY_REVIEW.md).

## Порядок работы

Один asset: обсуждение и план → явное подтверждение → SVG art → ручная приёмка art → rig/animations → ручная приёмка animation → настоящий gameplay → финальная приёмка → отдельный commit. Перед следующим asset снова обсуждаем план. Push только по отдельному разрешению пользователя.

Порядок: Archer (принят), Goblin (принят), Mage (принят), Frost Mage (принят), Orc (принят 08.10.2026), Golem, Boss, Summoner Tower. Новые сущности, skins, equipment и изменения баланса не входят в art pass. Image generators, Krita, готовые чужие sprites запрещены; production art пишется вручную как SVG-код. [Итог Goblin](done/GOBLIN_GAMEPLAY_REVIEW.md), [итог Frost Mage](done/FROST_MAGE_GAMEPLAY_REVIEW.md), [итог Orc](done/ORC_GAMEPLAY_REVIEW.md).

## Стиль

- Chunky squat силуэт, крупная голова/корпус, короткие конечности, простые округлые формы. Приоритет: силуэт → читаемость → анимация → детали.
- Cartoon fantasy, flat fills, максимум 1–2 простых уровня света/тени. Без текстур, мелких узоров, ремешков и декоративного мусора.
- Главный style reference — `art/references/archer_STYLE_MASTER.png`; для следующего asset отдельно рассматривается его исходный reference.
- Outline Archer: #29180f, 7 px на холсте 256×256, round linecap/linejoin. Для следующих персонажей сохраняется визуальная толщина; внутренние границы, оружие и лицо могут использовать более узкие strokes.
- Проверяем 100/140/180 px и фактический gameplay scale. На текущем телефоне холст союзника может занимать всего 37–52 физических px: детализация должна выдерживать это уменьшение.

## SVG и имена

```text
art/source/<entity>/
  master.svg
  parts/<part_name>.svg
  rig_manifest.json
  README.md
scenes/visuals/<Entity>Visual.tscn
scripts/visuals/<entity>_visual.gd
```

`master.svg` — review-сборка тех же частей в том же порядке, не замена cutout rig. В Archer он также используется для drag preview. `.import` и необходимые `.uid` сохраняются в git; `.godot/` и экспортированные сборки исключены.

Применяем простые path, ellipse, circle, polygon и группы, flat fills/strokes. Без raster embedding, фильтров, сотен микроскопических paths и зависимостей от шрифтов. Parts добавляем только ради реально нужного движения. Кисти, лицо, уши, ботинки и украшения не отделяем автоматически.

## Pivot и overlap

Все parts персонажа сохраняют один полный прозрачный холст; случайный trimming запрещён. Пилот Archer: 256×256, actor_origin=(128,128), baseline ступней примерно y=239. Эти значения для другого asset сначала проверяются на его силуэте.

Manifest хранит canvas, actor_origin, pivot каждой части, parent_bone, имя bone, sprite_offset и z_index. Координаты — исходный SVG canvas.

- Root.position = −actor_origin.
- Sprite2D.centered=false; sprite.position = −pivot своей кости.
- Bone.position = pivot части −pivot родительской кости. Для Body под Root pivot родителя равен (0,0).
- Rest задаётся явно по исходному transform; нулевой rest запрещён. Автоподбор длины отключён, длина кости задана явно.
- Часть без отдельной кости использует pivot родителя: Quiver под Body получает offset −Body.pivot.
- Pivot руки — плечо/локоть, ноги — бедро, головы — основание головы/шея, оружия — хват. Не использовать центр bounding box вместо сустава.
- Скрытые участки плеч, локтей, ног и головы дорисовываются округлыми формами. Части перекрываются, не сходятся стык в стык. Проверяем крайние позы и зеркалирование.

Archer: 9 частей и 9 костей вместе с Root. Quiver следует Body без отдельной кости. Z-order: Quiver 0, LeftLeg 1, RightLeg 2, DrawUpperArm 3, BowArm 4, Body 5, Head 6, Bow 7, DrawForearm 8. Рука с луком за телом, лук перед рукой. NockedArrow — вспомогательный Sprite2D из существующей arrow.svg, без кости.

Goblin: 7 частей и 8 костей вместе с Root; руки цельные с кистями, ноги с ботинками, лицо/уши/клык внутри Head. Z-order: BackArm 0, LeftLeg 1, RightLeg 2, Body 3, FrontArm 4, Head 5, Dagger 6. Кинжал отдельным Sprite2D следует Dagger под FrontArm, голова закрывает скрытое плечо. Canvas 256×256, origin=(128,128), baseline y=239. По правке пользователя от 07.10.2026 visual уменьшен на 20%: gameplay visual.scale=86.4/256 (0.3375) вместо 108/256; тот же коэффициент применяется после mirror. Static fallback, HealthBar и SlowIndicator уменьшены на 20%; entity position, движение и баланс сохранены.

## Godot и ответственность

Orc: 7 SVG parts, 8 bones вместе с Root, canvas 256×256, origin=(128,128), baseline=239, visual.scale=120/256. Z-order: BackArm, LeftLeg, RightLeg, Body, Axe, FrontArm, Head; Axe следует FrontArm, располагается перед Body и за кистью. Локальная equipment mask меняет только ботинки, напульсники и повязку. Clips: walk_loop 0.8 s, attack 0.4 s / impact 0.18 s, hit 0.16 s, death 0.32 s. Gameplay сохраняет кадр контакта, visual tails не являются целями. Animated default включён после финальной приёмки; прежний static сохранён.

```text
GameplayEntity
  Visual                 # сохранённый static Sprite2D
  Muzzle / collision     # существующие gameplay anchors
  <Entity>Visual
    Skeleton2D
      Root : Bone2D
        Body : Bone2D
          ... минимальные Bone2D + Sprite2D
    AnimationPlayer
    SpawnPlayer          # только если нужен независимый spawn overlay
```

ArcherVisual — сосед прежнего Visual; static сохраняется для rollback. Gameplay выбирает цель, ведёт cooldown, создаёт projectile и выполняет damage/награды. Visual выдаёт события и меняет только позу/цвет. Он не управляет gameplay и не содержит root motion.

Кости/узлы — PascalCase, части/скрипты — snake_case, клипы — snake_case. Риг около 6–12 bones максимум; сокращаем там, где дополнительная кость не даёт видимого результата. Skeleton2D/Bone2D с отдельными жёсткими Sprite2D; без weights, Polygon2D deformation, complex IK или constraints.

Редактор, сцены, узлы, анимации, inspection, запуск и export — через Godot MCP. Код и SVG — через apply_patch. Перед preload нового SVG ждём завершения импорта. Перед сохранением/экспортом проверяем несохранённые сцены. Сложные .tscn не правим вручную.

## Анимации и события

| Entity | Реальные клипы |
|---|---|
| Archer | idle_loop, attack, spawn |
| Mage / Frost Mage | idle_loop, cast, spawn |
| Goblin / Orc / Golem | walk_loop, attack, hit, death |
| Boss | walk_loop, attack, hit, death, spawn_or_intro |
| Tower | crystal_pulse либо idle_loop, hit, destroyed; без humanoid skeleton |

Союзники не получают hit/death. Idle слабый: дыхание, небольшое движение головы/оружия. RESET восстанавливает изменяемые свойства, завершившийся клип возвращается в подходящее состояние. Spawn/merge VFX не разрастаются в отдельную систему без согласования.

Archer: idle_loop 1,2 s, attack 0,52 s, release 0,24 s, spawn 0,4 s. По правке пользователя от 07.10.2026 idle Archer и Mage ускорены вдвое: 2,4 → 1,2 s при прежней амплитуде. Уменьшены только времена ключей idle; attack/cast/spawn и gameplay timing не изменены. В review AnimationPlayer обновляется в physics mode с immediate method callbacks. В бою — manual mode, обновляемый CombatUnit:

1. Подготовка проходит во время прежнего cooldown. Seek задаёт pose и не исполняет method events заранее.
2. В прежний кадр готовности gameplay переводит visual на release, visual выдаёт событие один раз, CombatUnit вызывает прежний `_fire()`.
3. Первый выстрел и новая доступная цель после истёкшего cooldown не ждут полного windup.
4. Скорость клипа max(1, 0,52 / effective_interval), характеристики остаются прежними.
5. Исчезновение цели/перенос отменяет подготовку. Stop останавливает animation players; повторные release не создают новые снаряды.

SpawnPlayer отдельно анимирует Root теми же spawn-треками. RESET атаки сохраняет transform/modulate Root, поэтому spawn не задерживает первый выстрел. Пауза SceneTree останавливает обе анимации.

Настоящий projectile использует существующие scene/script/Muzzle; ReleasePoint внутри visual — ориентир позы. Для Archer gameplay Muzzle=(32,−8), зеркалируется как прежде. Скорость, damage snapshot, размер стрелы, target validation, reassign при merge и cancel при refund сохранены.

Для врагов movement остаётся в ApproachingEnemy; walk только сопровождает движение. Их атака башни/смерть должны сохранить прежний момент damage, разрешение волны и награды. Перед реализацией обсуждаем, как показать recovery/death после мгновенного удаления gameplay entity.

Принятый Goblin: walk_loop 0,64 s, attack 0,34 s с impact 0,16 s, hit 0,16 s, death 0,32 s. В gameplay manual AnimationPlayer получает оставшееся время до контакта с учётом slow; preparation использует seek без событий. В прежний contact frame pose устанавливается на impact, затем выполняется однократный gameplay outcome. Entity сразу перестаёт быть целью и учитываться в волне; только visual переносится в World, заканчивает death/recovery и удаляется. Group enemy_visual_tails очищается при остановке боя. Движение, HP, damage и награды не ждут окончания animation.

Принятый Mage: idle_loop 1,2 s, cast 0,42 s, release 0,18 s, spawn 0,4 s; синхронизация с gameplay аналогична Archer. Свечение посоха — три небольших Polygon2D с opacity/scale tracks внутри cast, без postprocessing или новых textures. По правке пользователя от 07.10.2026 кристалл посоха красный, свечение тёплое красно-оранжевое; форма и timing прежние. [Итог Mage](done/MAGE_GAMEPLAY_REVIEW.md).

## Палитра уровней и текстуры

Один rig на все уровни. Archer: Lv1 зелёный, Lv2 оранжевый, Lv3 красный, Lv4 синий, Lv5 фиолетовый. Перекрашивается только ткань четырёх частей простым canvas_item shader; кожа/волосы/кожаные детали/лук/колчан сохраняют цвета. Материал локален для экземпляра и общий для его частей. Другие персонажи получают отдельно согласованный принцип; нельзя автоматически перекрашивать всё тело через modulate.

Goblin: только ботинки, напульсники и набедренная повязка получают пять цветов из EnemyStats по max HP при spawn. Кожа всегда зелёная, плечевой ремень/наплечник/уши/глаза/клык/кинжал сохраняют цвета. equipment_palette.gdshader выделяет исходные brown fills внутри общей equipment_mask.svg; один локальный материал назначен Body, обеим рукам и ногам, Head/Dagger без него. Общий mask canvas совпадает с полным canvas частей, поэтому pivots не нарушают UV.

Mage: общий локальный cloth_palette.gdshader на robe/hat/sleeves заменяет синие fills ткани на пять цветов уровня. Skin/hair/beard/gold/boots/bag/staff/crystal сохраняются; Head и Staff без материала. Drag preview использует master и тот же material. Восемь parts и восемь bones, без mesh.

Frost Mage: тот же cloth shader на body/hood/arms; белая отделка, кожа, волосы, ремни, ботинки, дерево и cyan лёд не перекрашиваются. Восемь parts и восемь bones, 256×256, visual.scale=100/256. Idle 1.2 s, cast 0.42 s с release 0.18 s, spawn 0.4 s. Gameplay timing следует принятому контракту Mage: подготовка в cooldown, release в прежний кадр готовности. Три cyan/white Polygon2D создают короткое свечение без дополнительных textures. Static fallback и исходный Muzzle=(32,−8) сохранены.

Runtime части Archer — 256×256 без mipmaps, общий набор Texture2D для всех экземпляров, без текстур на каждый level. Visual.scale=100/256; масштаб клетки задаёт существующий UnitHost. Drag preview использует master.svg, тот же материал и этот коэффициент. Другой масштаб enemy visual определяется по текущей entity, не изменением gameplay range/collision.

## Проверки и performance

Development-only `scenes/debug/ArtAnimationTest.tscn`: asset/animation selector, replay, pause, 0.5×/1×/2×, mirror и реальные масштабы. Производим только текущий asset; остальные пока недоступны. Debug scenes/scripts/assets/resources исключаются из обычного Web export.

На gate проверяем силуэт, gaps/clipping, pivots/overlap/z-order, reset/interruption, события и совместную работу экземпляров. В реальном бою — projectile timing, merge/move/refund/pause/restart и console. Для общих кодовых изменений выбираем затронутые существующие сценарии, не повторяем полный набор без нового риска. Приёмка/перенос отчёта/commit без gameplay правок не требуют повторного длительного прогона.

Web: Godot 4.7.2, Compatibility, соответствующие templates, single-thread, без native extensions. Не вводим большие rasterized SVG и незаметную в игре сложность.

Archer: 9 общих RGBA текстур частей ~2,25 MiB, master ~0,25 MiB без mipmaps. Native замер 10 Archer: ~145 FPS / 103 draw calls со всей ареной против ~144 FPS / 51 STATIC; это desktop evidence. Goblin: 7 textures и общая маска ~2 MiB RGBA8. До последней цветовой правки 40 Goblin в Edge показали 144 FPS при 354 draw calls ANIMATED против 153 STATIC; после добавления маски FPS повторно не измерялся. Это короткие desktop замеры с ограничением частоты экрана, не гарантия для телефона. Draw calls, прозрачный overdraw и bones растут с числом enemies; физический телефон и большие поздние волны требуют отдельной проверки при конкретном риске. Pooling и другие оптимизации только по измеренной проблеме.

## Mesh exceptions

Orc: 7 textures и mask около 2 MiB RGBA8; desktop Edge, 40 экземпляров — около 65 FPS / 325 draw calls ANIMATED против 63 FPS / 163 draw calls STATIC. Это короткий тест текущего компьютера, не гарантия для телефона. Новый набор textures на каждый цвет не нужен.

По принятому решению сохраняем rigid cutout. Сначала исправляем art shape, overlap, pivot, z-order и keys. Mesh допускается только по новому явному подтверждению и для конкретной гибкой части (длинная ткань, хвост, щупальце). Head/body/arms/legs/weapon остаются rigid. Не переводим весь персонаж на deformation и не переносим исключение автоматически на остальные assets.

Legacy art не удаляется; cleanup — отдельная задача. После финальной приёмки Archer, Goblin, Mage, Frost Mage и Orc animated visuals включены по умолчанию, STATIC доступен в review. Планы и отчёты принятых assets сразу переносятся в docs/done с обновлением ссылок; этот стандарт остаётся в docs.
