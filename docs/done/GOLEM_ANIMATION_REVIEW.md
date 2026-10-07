# Golem — rigid cutout rig и анимации для приёмки

08.10.2026. [План](GOLEM_ART_PLAN.md), [SVG art](GOLEM_ART_REVIEW.md) и **animation gate приняты пользователем, включая поправку на удар двумя руками.** Последующая [gameplay integration](GOLEM_GAMEPLAY_REVIEW.md) также принята. Ниже сохранены результаты animation gate.

[Открыть анимации Golem](http://127.0.0.1:4175/preview/golem-animation/) — настоящий Godot Web export. Доступны Replay, Pause, 0.5×/1×/2×, Repeat, Mirror, переключение анимаций и большой/игровой масштаб. Три дополнительных Golem показаны одновременно на дороге в размерах сеток 6/7/8. Asset selector включает только созданных Archer, Goblin, Mage, Frost Mage, Orc и Golem.

## Риг

Через Godot MCP создана `scenes/visuals/GolemVisual.tscn`: Node2D, Skeleton2D, девять Bone2D вместе с Root, восемь Sprite2D, один AnimationPlayer. `scripts/visuals/golem_visual.gd` управляет только проигрыванием clips и однократным событием attack_impact; не двигает enemy, не наносит damage и не выдаёт rewards. `scenes/debug/GolemAnimationTest.tscn` — наследник ArtAnimationTest с initial_asset_index=5.

Pivots/позиции и z-order точно соответствуют [manifest](../../art/source/golem/rig_manifest.json). Root=(−128,−128), Body=(128,170); Head под Body=(5,−23). Руки состоят из двух костей: BackUpperArm=(−43,−44), BackForearm=(−28,21), FrontUpperArm=(43,−40), FrontForearm=(39,27). Ноги под Body=(−28,26)/(23,26). Sprite.centered=false, position=−pivot, абсолютный z-index 0–7. Кулаки входят в forearms, глаза — в Head. Rest явно совпадает с исходным transform, auto length выключен. Visual.scale=140/256=0.546875.

Принятые SVG shapes, pivots и порядок слоёв не изменялись. Mesh, weights, IK, root motion, дополнительные states и VFX не добавлены. Исходный зелёный мох сохранён; runtime palette/mask будут подключены на gameplay gate.

| Клип | Длительность | Поведение |
|---|---:|---|
| walk_loop | 1.2 s | короткий тяжёлый шаг, лёгкий наклон корпуса, заметное движение головы и кулаков |
| attack | 0.5 s | одновременный подъём обоих кулаков, короткое удержание, удар двумя руками на 0.20 s, recovery |
| hit | 0.16 s | короткий recoil и тёплый flash, возврат в walk_loop |
| death | 0.35 s | оседание, наклон и fade; финальная поза удерживается до Replay |

В walk локальное движение Head ±5°, плеч ±6°/±7°, предплечий ±4°, ног ±6°; Body ±1.3° и подъём 1.5 source px. RESET восстанавливает position/rotation/scale/modulate всех bones. После attack/hit происходит возврат в walk_loop. Method track выдаёт attack_impact на 0.20 s; в этой сцене событие только отображается, damage не подключён.

## Выполненные проверки

- Godot MCP подтвердил проект C:/Gamedis/summoner-tower, Godot 4.7.2 и Compatibility. До правок unsaved=[]. Постоянные nodes, animations и connections созданы/сохранены через редактор MCP.
- Native запуск: четыре видимых Golem, девять bones у каждого, rest корректны. Просмотрены крайняя ходьба 0.3 s, windup 0.17 s, impact 0.20 s и death 0.22 s. Явных щелей в соединениях/перекрытия обоих глаз кулаком не обнаружено.
- Скорости 0.5×/1×/2×: перед 0.20 s событий=0, после=1, повторный emit остаётся=1; clip возвращается в walk_loop. Прерывание attack на 0.1 s с переходом в walk_loop не выдаёт запоздалое событие.
- Death заканчивается alpha=0, finished=true. Replay восстанавливает alpha=1, Root.position=(−128,−128), scale=(1,1), rotation=0.
- Native selectors: все шесть assets доступны, четыре видимых экземпляра каждого. Golem использует дорогу и полный canvas 100/84/72 логических px для сеток 6/7/8.
- Web export выполнен через MCP: single-thread, без extensions. Временные main scene/export preset удалены; project.godot/export_presets.cfg восстановлены точно, diff отсутствует.
- Один полный целевой Edge pass: четыре clips, Replay/reset, Pause/Resume, 0.5×/1×/2×, touch Mirror, все шесть asset selectors, выбор игрового масштаба мышью. Области головы/кулака меняются при walk; два кадра Pause идентичны. Console/page/resource errors=[]. Просмотрены 450×800, 390×844 и широкое окно 1280×720; выбран `6 columns · 100 px`.
- После полного pass исправлены connections миниатюр: счётчик Impact и Repeat получают события только от основного Golem. Также тестовая сцена сохранена настоящим наследником, чтобы правки ArtAnimationTest применялись к ней. Повторно экспортирован только debug preview; проверен один attack и счётчик `0.20 s · 1 event`. Полный Web pass не повторялся.
- При создании bones до отключения autocalculate появились временные предупреждения длины; итоговые flags=false и rest корректны. Во время импорта редактор выдал два сообщения progress_dialog об уже существующей задаче. Последующие native запуски и Web проверки не дали ошибок scripts/runtime.

Сохранены `.uid` и SVG import settings. Исходные `scenes/golem.tscn`, `assets/golem.svg`, характеристики и общий ApproachingEnemy не менялись на этом gate. Полный gameplay suite не запускался: новая visual ещё не подключена к бою. Contact/rewards/slow/tails/restart, runtime moss shader и массовая Web performance проверяются после приёмки animations на integration gate. Физический телефон не использовался. Восемь общих textures 256×256 ≈2 MiB RGBA8, mask добавит ≈0.25 MiB; texture набор не создаётся для каждого уровня.

## Ручная приёмка

1. Walk на 1× в большом и игровом размере: принять тяжесть шага, движение головы/кулаков, проверить суставы и Mirror.
2. Attack на 0.5×/1×: принять одновременный подъём и удар обоими кулаками, impact и recovery; лицо должно оставаться читаемым.
3. Hit/death и Replay: принять recoil, оседание и исчезновение; проверить восстановление фигуры и остановку всех четырёх Golem на Pause.

Animation и gameplay gates приняты. Animated default включён, отчёты перенесены в docs/done для отдельного commit. Push требует отдельного разрешения; Boss/Tower art не начаты.

## Поправка: атака двумя руками

По решению пользователя Golem одновременно замахивается и бьёт обоими кулаками. Задняя рука повторяет движение передней зеркально: upper arm 0 → +40° → −16° → 0; forearm 0 → +25° → −9° → 0. Сохранены исходные времена ключей и единственный method event на 0.20 s, общая длительность 0.5 s. Корпус оседает по центру, без бокового смещения. SVG, pivots, слои и другие clips не менялись.

Через MCP просмотрены windup 0.17 s и impact 0.20 s, включая миниатюры игрового размера. Лицо открыто, явных разрывов суставов нет. Перед impact событий=0, после=1, повторный emit остаётся=1; recovery возвращает walk_loop. Runtime errors отсутствуют. Debug Web preview обновлён; повторная браузерная проверка ограничена изменённым attack и счётчиком события, полный pass не повторялся.
