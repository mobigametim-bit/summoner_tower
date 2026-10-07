# Mage — rig и animation review

07.10.2026. **Mage полностью принят пользователем**, включая idle Mage и Archer 1.2 s. Этот отчёт сохраняет результаты animation gate; последующая [gameplay integration со свечением посоха](MAGE_GAMEPLAY_REVIEW.md) также принята. Animated Mage включён по умолчанию. Push только по отдельному разрешению.

## Просмотр и результат

[Mage animation preview](http://127.0.0.1:4175/preview/mage-animation/) — настоящий отдельный Godot Web export. Верхние стрелки переключают Archer/Goblin/Mage и animation. Есть Replay/Pause, 0.5×/1×/2×, Repeat, Mirror и выбор большого/игрового масштаба. Внизу одновременно показаны Mage на постаментах сеток 6/7/8 столбцов.

`scenes/visuals/MageVisual.tscn`: Node2D → Skeleton2D → Root → Body → Head/Hat, BackArm, FrontArm/Staff, LeftLeg, RightLeg. Восемь Bone2D и восемь Sprite2D; Hat следует Head без своей кости. Позиции, pivots и слои совпадают с manifest; rest явно задан, determinant=1 у всех костей. Без mesh/weights/IK/root motion. Принятые SVG shapes не изменялись.

`scripts/visuals/mage_visual.gd` управляет позой и выдаёт visual release; не выбирает цели, не создаёт projectiles и не наносит damage. AnimationPlayer — physics mode, method callbacks immediate. Отдельный SpawnPlayer с root-only tracks подготовлен для будущего spawn overlay, сейчас в preview не запускается параллельно основному player.

| Animation | Длительность | Поведение |
|---|---:|---|
| idle_loop | 1.2 s, loop | Дыхание и движение головы/посоха, без прыжков; вдвое быстрее первоначального варианта, амплитуда прежняя |
| cast | 0.42 s | Короткое движение посоха/свободной руки, anticipation, release 0.18 s, recovery → idle |
| spawn | 0.4 s | Небольшой scale/fade с опорой ног на исходной высоте, затем idle |

RESET восстанавливает все изменяемые свойства. Hit/death союзнику не созданы. ReleasePoint под Staff имеет local=(6.92,−67.48); на release frame после visual scale=(100/256) он соответствует (32,−8), прежнему Muzzle Mage. В review release показывается счётчиком события; существующий fireball будет подключён на следующем gameplay gate.

`scenes/debug/ArtAnimationTest.tscn` расширена только Mage: четыре экземпляра нового visual, selector трёх созданных assets. Скрытые visuals стоят на паузе. `scenes/debug/MageAnimationTest.tscn` — настоящий наследник ArtAnimationTest с initial_asset_index=2. Исходные gameplay scene Mage, CombatUnit, fireball, баланс и legacy visuals не менялись.

## Выполненные проверки

- Godot MCP: нужный проект, Godot 4.7.2-stable official, Compatibility; сцены, bones, sprites, AnimationPlayer/tracks и inherited test scene созданы через MCP. Несохранённых сцен нет.
- Lint: 39 scenes, 57 scripts, errors=0, warnings=0. Native запуск MageAnimationTest и runtime inspection без новых ошибок.
- Крайний windup 0.14 s и release 0.18 s просмотрены в Godot; хват/плечи/голова не показывают явных дыр или обрезания, шляпа следует голове. Малые samples сохраняют опору на постаменте.
- Native release: при 0.5×/1×/2× до 0.18 s event=0, после event=1, повторный `_emit_release()` не увеличивает счётчик. Cast возвращается в idle_loop. Прерывание до release не выдаёт запоздалое событие.
- Native reset: после spawn alpha≈0.351 на 0.04 s; смена на cast восстанавливает alpha=1, Root.scale=(1,1), position=(−128,−128). Pause фиксирует время AnimationPlayer, Resume продолжает; все 8 rest determinant=1, Sprite2D count=8.
- Native selector: Archer/Goblin/Mage, четыре активных visual каждого выбранного asset, все скрытые players paused. Реальные события Archer/Goblin остались доступны в общем review.
- Godot Web export через MCP: debug, Compatibility, single-thread, без native extensions. Main scene и exclude filter временно менялись для preview и восстановлены; diff project.godot/export_presets.cfg пуст. Обычная game build не заменялась.
- Edge: idle/cast/spawn, label release 0.18 s · 1 event, Replay/reset, 0.5×/1×/2×, Pause/Resume, touch Mirror, Archer/Goblin selector. Две screenshots во время паузы идентичны. Просмотрены 450×800, 390×844, 1280×720; console/page/resource errors=[].
- Выбор масштаба проверен отдельным коротким UI проходом: первоначальное keyboard действие оставило Large preview, поэтому нужный пункт выбран мышью. Screenshot подтвердил 6 columns · 96 px и уменьшение центрального visual; дополнительно просмотрены phone/wide при этом масштабе. Это исправление проверки, без изменения gameplay/animation и повторного полного набора.

Полный gameplay regression suite не запускался: изменения ограничены новым visual и development review. Синхронизация настоящего fireball, уровни/drag/merge/refund и реальный бой проверяются только на integration gate после приёмки анимаций.

## Правка idle от 07.10.2026

По запросу пользователя idle Mage и Archer ускорены вдвое: длина цикла и времена всех ключей уменьшены вдвое (2.4 → 1.2 s) через Godot MCP. Значения ключей и transitions сохранены. Сравнение снимков AnimationPlayer до/после подтвердило, что RESET, cast/attack и spawn не изменились. Native review подтвердил цикл 1.2 s, возврат из атаки в idle и ровно одно release после прежнего момента: Mage 0.18 s, Archer 0.24 s. Ошибки отступов в двух временных inspection snippets исправлены; последующие runtime проверки без ошибок. Обновлены Mage/Archer animation preview и обычный Web export для нового idle Archer.

Короткая проверка обновлённых сборок в Edge: idle Mage и Archer движется, Pause фиксирует кадр, обычная игра запускается; console/page/resource errors=[]. Новых runtime/editor errors после исправления inspection snippets нет. Main scene и export preset восстановлены, их diff пуст. Полный набор проверок не повторялся: изменены только времена ключей idle.

Свечение посоха предложено для gameplay integration: короткое усиление перед release и вспышка при выпуске существующего fireball. После подтверждения «принимаю, дальше» реализовано вместе с integration; результаты и дополнительные проверки — в MAGE_GAMEPLAY_REVIEW.md. Принятые SVG shapes и кости не изменились.

## HTML5 и ограничения

8 общих textures 256×256 ≈2 MiB RGBA8 без служебных копий, 8 bones, 8 Sprite2D и два AnimationPlayer (SpawnPlayer пока неактивен). Четыре Mage в review проверены; память/FPS массовой gameplay нагрузки не измерялись. Физический телефон не проверялся; малый размер смотрели в desktop browser viewport. Новые материалы/mesh/IK/particles не добавлены.

## Ручная приёмка

1. Посмотреть idle на 1×: движение спокойное, ноги стоят на постаменте, шляпа/посох читаются.
2. Cast на 0.5× и 1×: принять anticipation/release/recovery, хват и overlap; проверить Mirror и малые samples.
3. Spawn/Replay/Pause: нет скачков позы, потерянной прозрачности или застревания после смены animation.
4. Посмотреть большой и реальный игровой масштаб, принять читаемость движения.

Анимации и gameplay integration с существующим fireball и прежним timing приняты. Следующий asset — Frost Mage, перед созданием art требуется отдельное согласование плана. Push только по отдельному разрешению.
