# Нежить кладбища: воспроизводимая подготовка частей

Общий animation-pass разрешён пользователем 17.10.2026. Принятые концепты
из `art/concepts/graveyard/` не перезаписываются. Генераторов изображений,
чужих sprites и mesh deformation нет.

`prepare_art.py` берёт собственные исходные SVG shapes принятого concept-pass,
группирует по шарнирам и нормализует относительные subpaths при разделении ног
и парных накладок. У некроманта добавлен рукав под рукой посоха для overlap.
Кости, кожа и металл не перекрашиваются; используются готовые принятые облики Lv1–5.

```powershell
python art/source/graveyard_animation/prepare_art.py
```

Результат: `art/source/{skeleton,zombie,ghoul,necromancer,flesh_golem,lich}/`,
master/parts/rig_manifest для 27 обликов и десять собственных масок частиц
в `assets/vfx/undead/` плюс тень. У голема только варианты от Некроманта Lv4/Lv5.

Каждая часть сохраняет canvas 256×256. Manifest фиксирует source pivots,
родительские кости, local positions, sprite offsets, уровни и порядок слоёв.
Runtime SVG import — 128×128, Sprite2D scale=2 при прежних source pivots.
Задние аксессуары не получают отдельных костей. 7–8 bones вместе с Root.
Шлемы, щиты, оружие и броня меняются текстурами на тех же костях.

`rig_spec.json` — вход для editor builder, не runtime data/framework.
Сцены, bones, rest, animations, VFX и постоянный UI создаёт
`scripts/debug/graveyard_animation_builder.gd` внутри Godot через MCP:

1. Импортировать новые SVG, установить svg/scale=0.5 для parts через Godot ConfigFile
   и EditorFileSystem.reimport_files, сохранить `.import`/UID.
2. Вызвать `build_visuals()`, затем `build_effects_and_bind()`, затем `build_preview()`.
3. Проверить сцены, clips и runtime errors. Не править сгенерированные `.tscn` вручную.

Полная повторная генерация rig требует повторно сверить импорты и NodePaths.
Для правки одного VFX достаточно `_build_effect(key)` без пересоздания ригов.
Обновлённые VFX собирает `scripts/debug/graveyard_vfx_builder.gd`: он использует
существующий SummonRays и шесть масок Kenney CC0 (лицензия/источники рядом с PNG).
Builder загружает PackedScene с CACHE_MODE_IGNORE, чтобы не заменять ресурсы
у уже открытых сцен редактора. Существующий art/rig первого биома не меняется.
