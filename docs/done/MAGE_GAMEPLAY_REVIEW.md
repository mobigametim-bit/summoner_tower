# Mage — gameplay integration и финальная ручная приёмка

07.10.2026. **Mage полностью принят пользователем**, включая art, rigid cutout animations, idle 1.2 s, gameplay integration и свечение посоха. После финальной приёмки animated visual включён в обычной игре; static fallback сохранён. Push только по отдельному разрешению.

## Просмотр

[Mage gameplay preview](http://127.0.0.1:4175/preview/mage-gameplay/) — отдельный Godot Web export. Нажать башню дважды: первые два призыва — Mage (seed 10, прежние веса 40/35/25). Внизу STATIC/ANIMATED, pause и restart. Arena seed 101 фиксирует поле для воспроизведения; боевые правила, цены и характеристики прежние. [Крупный просмотр анимации и свечения](http://127.0.0.1:4175/preview/mage-animation/) — выбрать cast.

В обычной игре Mage, Archer и Goblin используют принятые animated visuals по умолчанию. Legacy Mage SVG всех пяти уровней сохранены. Development review и JS snapshot не входят в production export.

## Изменения

- `scenes/mage.tscn`: сохранены Visual/Muzzle/stats/fireball; добавлен дочерний MageVisual. Сцены, узлы, материалы, animation tracks и сигналы изменены через Godot MCP.
- CombatUnit выбирает существующий ArcherVisual либо MageVisual через одинаковый небольшой контракт. Target selection, `_fire()`, cooldown, damage, range, mana, waves, merge/refund и stats resources не изменены. Frost Mage без нового визуала продолжает прежний static путь.
- MageVisual: cast preparation следует оставшемуся gameplay cooldown, seek не выполняет ранний release. На прежнем кадре атаки `release_now()` ставит pose 0.18 s и выдаёт ровно одно событие; CombatUnit создаёт прежний fireball из `Muzzle.global_position`. Recovery ускоряется при effective interval короче cast. Первый выстрел не задерживается ради windup.
- SpawnPlayer двигает только Root, поэтому spawn сохраняется при первой атаке. Потеря цели/перенос отменяет preparation и свечение; stop останавливает оба player. Idle остаётся 1.2 s.
- `cloth_palette.gdshader`: только синие fills ткани заменяются на Lv1–5 зелёный/оранжевый/красный/синий/фиолетовый с сохранением shading. Порог blue/green=1.4 исключает тёмно-cyan окантовку кристаллов (#2999c0); все три cloth fills остаются внутри маски. Материал назначен robe/hat/sleeves и локален для экземпляра. Skin/hair/beard/gold/boots/bag/staff/crystal сохраняются. Drag preview использует master и тот же материал/масштаб.
- VFX: три вложенных Polygon2D у кристалла, opacity/scale tracks в cast. Нарастание во время подготовки, вспышка на release, fade до 0.30 s; RESET очищает эффект. Нет новых textures, particles, WorldEnvironment glow или mesh. Принятые SVG shapes и восемь bones сохранены.
- `scenes/debug/MageGameplayReview.tscn` наследует реальную game scene. Static/animated switch отменяет drag; pause/restart используют текущий игровой жизненный цикл. Debug seed меняет последовательность, а не production summon pool.

## Проверки

- Godot 4.7.2-stable, Compatibility, нужный проект; несохранённых пользовательских сцен перед работой не было. Финальный lint: 40 scenes, 58 scripts, errors=0, warnings=0.
- Native сравнение STATIC/ANIMATED при 60 FPS: Mage выстрелы на кадрах 0/72/144, Archer 0/36/72/108/144, Frost Mage 0/48/96/144. Совпали кадры, damage snapshots и muzzle origin. Mage release pose=0.18 s, glow alpha=1, ReleasePoint совпал с Muzzle с погрешностью менее 0.001.
- Отдельный риск короткого cooldown: 12 существующих Rapid Fire bonuses, effective interval≈0.2243 s. Оба режима выстрелили на 0/14/28/42/56; mirrored origin совпал, повторный visual release не породил снаряд, потеря цели отменяет preparation/glow без выстрела. Балансные ресурсы не изменялись.
- Проверены отмена подготовки, сохранение spawn alpha при первой атаке, остановка обоих player и glow. Два реальных призыва Mage запускают spawn; shader materials независимы между экземплярами.
- Все пять цветов одежды просмотрены через Godot MCP в реальном поле. Head/staff без recolor material; пик cast со свечением просмотрен крупно и на малых samples.
- Существующие scenarios `feature_7_unit_contracts` и `feature_2_archer_defense` прошли без runtime errors: типы, RNG/atomic summon, merge, in-flight snapshot/reassign, Frost lifecycle, touch cancel, остановка боя, restart, прежний Archer бой/доход/следующая волна. Полный набор не повторялся: общая правка ограничена выбором visual.
- Edge Web: два Mage, STATIC/ANIMATED, mouse merge до Lv2, paid_mana=45, перенос мышью и touch, drag preview, настоящий fireball/glow, pause с идентичными кадрами, refund=22, restart (mana=100, wave=1, merges/projectiles=0, поле пустое). Просмотрены 450×800, 390×844, 1280×720; console/page/resource errors=[]. Короткий запуск обычной обновлённой Web build также без ошибок.
- Export через MCP: single-thread Compatibility; Mage gameplay/animation preview и обычная Web build обновлены. Main scene/exclude filter восстановлены, diff project.godot/export_presets.cfg пуст.
- При создании debug inheritance пришлось восстановить root config после смены скрипта: первоначальный Nil/config startup error исправлен. Один native summon check был запущен после завершения боя и повторён на свежем запуске; прошёл. Временные MCP snippets исправлены. Финальная проверка новых runtime/editor errors после seq 85: entries=[].

## HTML5 и ограничения

8 общих textures 256×256 ≈2 MiB RGBA8 плюс master для drag, 8 bones, 8 sprites, три небольших VFX polygons и два AnimationPlayer (spawn активен только при появлении). Материалы локальны для recolor; textures/shader общие. В коротком desktop Web проходе snapshot показал 62 FPS; это не массовое profiling. Физический телефон и отдельный долгий нагрузочный прогон не проверялись. Новых native extensions, потоков или mesh нет.

После приёмки уточнена цветовая маска: исключена тёмно-cyan окантовка кристалла, сохранены три оттенка ткани. Lv5 просмотрен через Godot MCP, shader импортирован без runtime errors; обычная Web build и оба Mage preview обновлены. Короткий Edge запуск с призывом animated Mage прошёл без console/page errors. Полный игровой прогон не повторялся для этой правки shader.

## Ручная приёмка

1. Призвать двух Mage: принять размер на постаментах, idle, spawn и cast; посмотреть свечение в бою и крупно в animation preview.
2. Сравнить STATIC/ANIMATED: fireball появляется у кристалла в момент вспышки, темп боя тот же; mirror не ломает хват или origin.
3. Объединить двух Mage: оранжевая только одежда; затем проверить перенос, drag preview и возврат объединённого Mage на башню (+22 mana).
4. Проверить pause/restart и удобство на своём экране.

Финальная приёмка получена. После включения default короткий native запуск обычной game scene подтвердил animated=true, MageVisual.visible=true, static Visual.visible=false, idle 1.2 s и работающий spawn; новых runtime errors нет. Ordinary Web build обновлена, короткий Edge запуск из меню в бой прошёл без console/page/resource errors. Полный игровой набор не повторялся: изменён только default visual. Планы и отчёты перенесены в docs/done. Push только с отдельным разрешением. Перед Frost Mage — отдельное обсуждение и план.

## Принятая правка огненного кристалла

07.10.2026. По запросу пользователя кристалл посоха в staff.svg и той же группе master.svg перекрашен в красный: #ed5158 / #9f293f / #ffb0a0 / #fff0ce. Цвета существующих Halo/Aura/Core изменены через Godot MCP на тёплые красно-оранжевые. Формы, pivots, outline, opacity/scale tracks, timing, fireball и баланс прежние; маленькие украшения одежды остаются cyan.

Правка показана в Godot и Mage Web gameplay preview, короткий Edge запуск с animated Mage прошёл без console/page errors. Обычная Web build и Mage previews обновлены. Пользователь принял результат вместе с анимациями Frost Mage следующей репликой «принимаю, дальше». Правка фиксируется отдельно от ещё не принятой gameplay integration Frost Mage. Push не разрешён.
