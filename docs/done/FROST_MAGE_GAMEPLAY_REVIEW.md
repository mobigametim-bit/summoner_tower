# Frost Mage — gameplay integration и ручная приёмка

07.10.2026. **Frost Mage полностью принят пользователем**, включая rigid cutout animations, gameplay integration и ледяное свечение. Дополнительная правка походки Goblin также принята. Animated Frost Mage включён по умолчанию; legacy art сохранён. Push не разрешён.

[Тестовый бой Frost Mage](http://127.0.0.1:4175/preview/frost-mage-gameplay/), [просмотр анимаций](http://127.0.0.1:4175/preview/frost-mage-animation/), [обновлённая походка Goblin](http://127.0.0.1:4175/preview/goblin-animation/).

## Результат

`scenes/frost_mage.tscn` сохраняет CombatUnit, исходный Sprite2D, Muzzle=(32,−8), существующие frost_bolt и характеристики. Добавлена `scenes/visuals/FrostMageVisual.tscn`: восемь Bone2D, восемь SVG textures, AnimationPlayer и отдельный SpawnPlayer. Скрипт `scripts/visuals/frost_mage_visual.gd` использует тот же визуальный контракт, что принятые Archer и Mage. CombatUnit выбирает соответствующий visual, сохраняя ответственность за цель, cooldown и создание снаряда.

После финальной приёмки в production `animated_visual_enabled=true`. В development-only `scenes/debug/FrostMageGameplayReview.tscn` доступно переключение static/animated. Первые два призыва при seed=4 дают Frost Mage через настоящий SummonPool, без изменения весов.

Короткое ледяное свечение — три cyan/white Polygon2D у Staff/ReleasePoint, opacity/scale управляются cast. Новых VFX textures, частиц и postprocessing нет. Локальный ShaderMaterial использует `art/source/mage/cloth_palette.gdshader`: уровни меняют только ткань капюшона, мантии и рукавов. Белые полосы, кожа, волосы, ботинки, дерево и лёд сохраняют цвета. Drag preview использует master.svg с той же палитрой.

## Проверки

- Через Godot MCP выполнены запуск, inspection и проверка runtime errors. После исправления config в наследуемой review scene последние запуски чистые (новых ошибок после seq=113 нет).
- Static/animated Frost Mage сравнивались на 240 шагах 60 Hz: выстрелы на кадрах 0/48/96/144/192 при interval=0.8 s. С двумя Rapid Fire: 0/37/74/111/148/185/222, interval≈0.604915 s. Кадры, snapshots снарядов и результат попаданий совпали. Damage=6, slow=0.3, speed=700; первая атака не задерживается spawn animation.
- Пять уровней просмотрены в Godot; материал каждого экземпляра независим. Cyan кристалл/свечение и белая отделка не перекрашиваются вместе с тканью.
- Целевой сохранённый сценарий `feature_7_unit_contracts`: PASS, восемь шагов, runtime_errors=[]. Устаревшее ожидание drag preview обновлено с исходной static texture на фактический `drag_texture()`; после исправления повторён только этот сценарий.
- Один целевой Web pass в Edge: два Frost Mage, static/animated, merge, перенос мышью и touch, снаряд и замедление, свечение, возврат 22 маны для объединённого юнита стоимостью 45, pause/resume, restart. После restart: mana=100, слоты пусты, merges=0, projectiles=0, wave=1. Console/page/resource errors=[].
- Просмотрены размеры 450×800, 390×844 и 1280×720. В коротком desktop Web прогоне получено 62 FPS. Физический телефон и длительная массовая нагрузка не измерялись.
- Web export через MCP: Compatibility, single-thread. Main scene и export filters восстановлены; `project.godot` и `export_presets.cfg` без diff. Полный набор сценариев не повторялся: изменены visuals и выбор visual, баланс и правила боя сохранены.

## Дополнительная правка Goblin

В walk_loop прежние ±1° головы компенсировали наклон Body, поэтому голова почти не двигалась относительно экрана. Изменены только три вращательных трека: Head локально ±8° (в мире ±7°), FrontArm ±18°, Dagger ±5° (кинжал в мире ±24°). Длительность цикла 0.64 s, движение entity, скорость, HP, attack/hit/death и остальные треки сохранены.

Две крайние позы просмотрены в Godot: явных щелей не обнаружено. В Web движение областей головы и руки с кинжалом подтверждено сравнением кадров; pause останавливает изображение, browser errors=[]. Пользователь принял правку; отдельный commit `59a45ce`.

## Что проверить вручную

1. В тестовом бою призвать двух Frost Mage: idle, spawn, подготовка cast, ледяной flash, вылет снаряда и замедление врага.
2. Объединить их: одежда становится оранжевой, белая отделка и лёд сохраняются. Перенести юнита, вернуть на башню, проверить pause и restart.
3. В Goblin preview выбрать walk_loop на 1× и игровой размер: принять заметность качания головы и руки с кинжалом.

Финальная приёмка получена. Animated Frost Mage включён по умолчанию через Godot MCP; запуск обычной game scene подтвердил animated=true, FrostMageVisual.visible=true, Visual.visible=false, Muzzle=(32,−8) и прежний frost_bolt. Новых runtime errors после seq=115 нет; одно ошибочное обращение к API inspection исправлено использованием scene.current. Обычный Web export обновлён, короткий запуск Edge из меню в бой прошёл без console/page/resource errors; screenshot просмотрен. Планы и отчёты перенесены в docs/done. Отдельный asset commit, push только по отдельному разрешению. Следующий объект — Orc: сначала обсуждение и подтверждение плана.
