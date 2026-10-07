# Orc — rigid cutout rig и анимации для приёмки

08.10.2026. **Orc полностью принят пользователем.** Этот отчёт сохраняет результаты animation gate от 07.10.2026; последующая [интеграция в бой](ORC_GAMEPLAY_REVIEW.md) также принята. [План](ORC_ART_PLAN.md), [принятый art](ORC_ART_REVIEW.md).

[Открыть анимации Orc](http://127.0.0.1:4175/preview/orc-animation/) — настоящий Godot Web export. Стрелки asset/animation, Replay, Pause, 0.5×/1×/2×, Repeat, Mirror и большой/игровой масштаб. Три дополнительных Orc одновременно показаны на дороге в размерах сеток 6/7/8; также можно выбрать принятых Archer/Goblin/Mage/Frost Mage.

## Что создано

Через Godot MCP создана `scenes/visuals/OrcVisual.tscn`: Node2D, Skeleton2D, восемь Bone2D вместе с Root, семь Sprite2D, один AnimationPlayer. `scripts/visuals/orc_visual.gd` содержит только управление просмотром и однократное событие attack_impact; он не создаёт enemies, не наносит урон и не двигает gameplay entity. `scenes/debug/OrcAnimationTest.tscn` — настоящий наследник ArtAnimationTest с initial_asset_index=4.

Риг соответствует manifest: Root.position=(−128,−128), Body=(126,176), Head локально (2,−34), BackArm=(−51,−28), FrontArm=(45,−26), Axe под FrontArm=(32,34), LeftLeg=(−24,31), RightLeg=(21,31). Rest явно совпадает с исходным transform; auto length выключен. Sprite2D.centered=false, position=−pivot, абсолютные z-index 0–6. Canvas каждой части 256×256, visual.scale=120/256.

Порядок слоёв сохранён: BackArm, LeftLeg, RightLeg, Body, Axe, FrontArm, Head. Топор перед корпусом и за кистью; наплечники/кисти остаются внутри цельных рук. Принятые SVG shapes не изменялись. Mesh, weights, IK, root motion и дополнительные bones не использовались.

| Клип | Длительность | Поведение |
|---|---:|---|
| walk_loop | 0.8 s | короткие шаги, небольшое движение корпуса, заметные голова и рука с топором |
| attack | 0.4 s | подготовка, удержание перед ударом, impact 0.18 s, восстановление |
| hit | 0.16 s | короткий recoil и тёплый flash, возврат в walk_loop |
| death | 0.32 s | наклон/оседание и fade, удержание финальной позы до Replay |

RESET восстанавливает Root.position/rotation/scale/modulate и все свойства частей, затронутые clips. В ходьбе голова в мировых координатах качается ±7°, топор ±16.5°; это visual motion, не движение enemy entity. Событие удара в текущей сцене отображается счётчиком, урон башне не подключён.

## Проверки

- Godot MCP подтвердил правильный проект и Godot 4.7.2, Compatibility. Перед редакторскими изменениями unsaved=[]. Создание/сохранение обеих сцен и постоянные connections выполнены в редакторе через MCP.
- Запуск OrcAnimationTest: четыре видимых Orc, восемь bones/семь sprites у каждого, все rest корректны. Посмотрены windup 0.14 s, impact 0.18 s, крайняя ходьба, hit 0.04 s и death 0.2 s: явных щелей в плечах, отрыва хвата или перекрытия топором лица не обнаружено.
- Для speed=0.5/1/2 до 0.18 s событий=0, после=1, повторный вызов emit оставляет=1; attack возвращается в walk_loop. Прерывание attack на 0.1 s с переходом в walk_loop не выдаёт запоздалый impact.
- После death alpha=0 и finished=true. Replay в walk_loop восстановил alpha=1, Root.scale=(1,1), position=(−128,−128), rotation=0.
- Native selectors всех пяти assets: четыре видимых экземпляра выбранного asset, скрытые AnimationPlayer остановлены. Orc использует road вместо pedestal, масштаб 6 columns: host=0.71428573, полный canvas≈86 px; 7/8≈72/62 px.
- Web export через MCP: Compatibility, single-thread, без extensions. Main scene и export filters временно изменены для debug preview и точно восстановлены; project.godot/export_presets.cfg без diff.
- Один целевой Edge pass: walk/attack/hit/death, death replay/reset, 0.5×/1×/2×, Pause/Resume, Repeat, touch Mirror и переключение всех assets. Два кадра во время паузы идентичны; области головы и руки с топором меняются при ходьбе. Console/page/resource errors=[].
- Просмотрены 450×800, 390×844 и 1280×720. Отдельная короткая проверка выбора масштаба мышью исправила пробел в проверке управления: первая попытка клавиатурой оставила Large preview. После выбора показан `6 columns · 86 px` в основном окне; screenshot просмотрен. Полный Web pass ради этого не повторялся.
- После свежего native запуска новых editor/runtime errors после seq=119 нет. SVG/import resources сохранены, исходные gameplay scenes/scripts и баланс Orc не менялись.

Полный gameplay suite не запускался: OrcVisual ещё не подключён к ApproachingEnemy. Поведение контакта с башней, rewards/waves, slow, tails/restart и маска сложности будут проверяться на integration gate. Сейчас mask не назначена; коричневая одежда в animation preview соответствует принятому source art. Производительность массового боя и физического телефона не измерялась. Семь общих textures 256×256 ≈1.75 MiB RGBA8; mask добавит ≈0.25 MiB при интеграции, без texture набора на каждый уровень.

## Ручная приёмка

1. Walk на 1×: принять движение головы/топора и короткий шаг; проверить большой и игровой размер, Mirror и плечи.
2. Attack на 0.5×/1×: принять подготовку, impact и recovery; проверить хват и читаемость удара. Сейчас impact только preview event.
3. Hit/death и Replay: принять короткий recoil, исчезновение и корректный сброс. Pause должна остановить все четыре видимых Orc.

Animation и gameplay gates приняты. Подключение к прежней ApproachingEnemy logic и окраска только одежды описаны в [gameplay review](ORC_GAMEPLAY_REVIEW.md). Animated default включён; документы перенесены в docs/done для отдельного commit. Push только по отдельному разрешению.
