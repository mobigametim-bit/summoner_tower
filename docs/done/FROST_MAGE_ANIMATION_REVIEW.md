# Frost Mage — rig и анимации для ручной приёмки

07.10.2026. **Frost Mage полностью принят пользователем**, включая gameplay integration: [отчёт gameplay gate](FROST_MAGE_GAMEPLAY_REVIEW.md). [Согласованный план](FROST_MAGE_ART_PLAN.md), [принятый art](FROST_MAGE_ART_REVIEW.md). Ниже сохранены результаты animation gate до интеграции.

[Открыть анимации](http://127.0.0.1:4175/preview/frost-mage-animation/) — настоящий Godot Web export. Верхние стрелки переключают asset и animation. Replay/Pause, 0.5×/1×/2×, Repeat, Mirror, большой/игровой масштаб; внизу три дополнительных экземпляра на постаментах 6/7/8 столбцов. Доступны принятые Archer/Goblin/Mage и текущий Frost Mage.

## Структура и клипы

`scenes/visuals/FrostMageVisual.tscn` создана через Godot MCP: Node2D → Skeleton2D → Root → Body → Head/Hood, BackArm, FrontArm/Staff, LeftLeg, RightLeg. Восемь Bone2D, восемь Sprite2D, AnimationPlayer и root-only SpawnPlayer для будущего независимого spawn overlay. В preview SpawnPlayer не запускается параллельно основному player. Все rest явно заданы, determinant=1. Hood следует Head без своей кости; слои и pivots совпадают с manifest. Только rigid cutout, без mesh, IK, weights и root motion.

Принятые SVG shapes не менялись. Базовые motion tracks адаптированы из принятого Mage rig с совпадающими pivots; VFX tracks исключены. Свечение Frost Mage относится к следующему согласованному gameplay gate.

| Animation | Длительность | Поведение |
|---|---:|---|
| idle_loop | 1.2 s, loop | Лёгкое дыхание, движение головы и посоха, скорость как у принятых Archer/Mage |
| cast | 0.42 s | Подготовка посоха и свободной руки, release на 0.18 s, recovery → idle |
| spawn | 0.4 s | Короткий scale/fade с опорой ног на исходной высоте, затем idle |

`scripts/visuals/frost_mage_visual.gd` управляет позой и выдаёт однократное visual release. Нет target selection, projectile creation или damage. RESET восстанавливает изменяемые properties, смена animation отменяет незавершённый cast. AnimationPlayer работает в physics mode с immediate method callbacks. ReleasePoint под Staff=(6.92,−67.48); в release pose после visual scale=100/256 соответствует прежнему gameplay Muzzle=(32,−8).

`scenes/debug/ArtAnimationTest.tscn` расширена четырьмя экземплярами FrostMageVisual. Только центральный экземпляр подключён к счётчику release и таймеру Repeat. `scenes/debug/FrostMageAnimationTest.tscn` — настоящий наследник общей сцены с initial_asset_index=3.

## Выполненные проверки

- Godot MCP: нужный проект, Godot 4.7.2-stable, Compatibility, сохранённых пользовательских изменений не перезаписывали; несохранённых сцен нет.
- Native inspection: восемь bones с rest determinant=1, восемь Sprite2D с текстурами 256×256 и согласованными слоями; четыре активных экземпляра. Windup 0.14 s и release 0.18 s просмотрены в Godot: явных щелей, обрезания капюшона или нарушения хвата не обнаружено.
- При 0.5×/1×/2×: до release event=0, после event=1, повторный `_emit_release()` не увеличивает счётчик; cast возвращается в idle_loop. ReleasePoint в точной pose 0.18 s=(32,−8). Прерывание cast на 0.1 s с переходом в idle не выдаёт запоздалое событие.
- Spawn на 0.04 s: alpha≈0.351. Смена на cast восстанавливает alpha=1, Root.scale=(1,1), Root.position=(−128,−128).
- Native selector Archer/Goblin/Mage/FrostMage: четыре активных экземпляра каждого выбранного asset, все скрытые AnimationPlayer остановлены на паузе.
- Исправлена persistence связей animation_finished/release. Первоначальная вспомогательная сцена оказалась самостоятельной копией; заменена настоящим наследником ArtAnimationTest через Godot Editor. Ошибки временного inspection snippet и смены вкладки редактора устранены; после повторного открытия и свежего запуска новых editor/runtime errors после seq=101 нет.
- Godot Web export через MCP: Compatibility, single-thread, без extensions. Main scene/exclude filter временно изменялись для review и восстановлены; diff project.godot/export_presets.cfg пуст.
- Edge: idle/cast/spawn, Replay/reset, 0.5×/1×/2×, Pause/Resume, touch Mirror, selectors и игровой scale. Две screenshots во время паузы идентичны. Release label после cast: 0.18 s · 1 event. Просмотрены 450×800, 390×844 и 1280×720; console/page/resource errors=[]. Игровой масштаб 6 columns · 96 px подтверждён screenshot, также показаны samples 7/8 столбцов.

Полный gameplay suite не запускался: Frost Mage ещё не подключён к gameplay. Его настоящие projectile timing, slow, уровни, drag/merge/refund и бой проверяются после приёмки анимаций. Для четырёх экземпляров просмотр и управление проверены; производительность массового боя и физического телефона пока не измерялась. Части — восемь общих textures 256×256, около 2 MiB RGBA8 без служебных копий; без новых runtime textures на каждый level.

## Правка огненного Mage по запросу пользователя

Кристалл посоха в `art/source/mage/parts/staff.svg` и той же группе master.svg перекрашен в красный: #ed5158 / #9f293f / #ffb0a0 / #fff0ce. Форма, pivots, outline, деревянный посох и маленькие украшения одежды не менялись. Цвета существующих Halo/Aura/Core через Godot MCP изменены на тёплые красно-оранжевые, opacity/scale tracks и timing прежние. Баланс, fireball, cooldown и cloth level palette сохранены.

Обновлены статический art preview Mage/Frost Mage, Mage animation/gameplay previews и обычный Web export. Красный кристалл и свечение просмотрены в Godot; короткая Edge проверка MageGameplayReview подтвердила призыв animated Mage с красным кристаллом и console/page errors=[]. [Посмотреть Mage в бою](http://127.0.0.1:4175/preview/mage-gameplay/).

## Ручная приёмка

1. Idle на 1×: принять спокойное движение головы/капюшона/посоха, проверить опору ног.
2. Cast на 0.5× и 1×: принять подготовку, release и recovery; проверить плечи, хват, Mirror и малые постаменты.
3. Spawn, Replay и Pause: нет щелей, скачков позы или застрявшей прозрачности.
4. Переключиться на Mage: принять красный кристалл и тёплое свечение, отличающие огонь от льда.

Анимации и gameplay приняты; Frost Mage подключён к существующей CombatUnit/projectile logic, добавлен согласованный короткий ледяной flash. Animated visual включён по умолчанию. Документы перенесены в docs/done; отдельный commit после финальной приёмки, push только по отдельному разрешению.
