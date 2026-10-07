# Goblin — SVG art и rigid cutout animation review

07.10.2026. **Goblin полностью принят пользователем**, включая gameplay integration, окраску только одежды и дополнительное заметное качание головы/руки с кинжалом при ходьбе. Animated visual включён по умолчанию, static fallback сохранён.

Референс: `art/references/goblin.png`. SVG написаны вручную, без image generators, Krita, растровых вставок или сторонних assets. Старый `assets/enemy.svg` и gameplay не изменены.

## Просмотр

[Goblin art preview](http://127.0.0.1:4175/preview/goblin-art/) — сравнение с reference, 100/140/180 px, текущий enemy scale, примерка на телефоне, сравнение с принятым Archer, переключение частей и pivot overlay.

[Goblin animation preview](http://127.0.0.1:4175/preview/goblin-animation/) — настоящий Godot Web export: walk_loop, attack, hit, death, 0.5×/1×/2×, Replay, Pause, Mirror, gameplay scale и переключение на Archer. Сцены: `scenes/debug/ArtAnimationTest.tscn`, её наследник `scenes/debug/GoblinAnimationTest.tscn` с Goblin по умолчанию.

[Goblin gameplay preview](http://127.0.0.1:4175/preview/goblin-gameplay/) — реальный бой на текущей процедурной арене, Goblin ANIMATED / STATIC и Pause. Первые три призыва с seed=23: Archer, Mage, Frost Mage; характеристики и веса пула прежние. [Результаты игрового этапа](../../../docs/done/GOBLIN_GAMEPLAY_REVIEW.md).

`master.svg` — сборка тех же 7 частей; `parts/` — самостоятельные прозрачные SVG 256×256. `rig_manifest.json` сохраняет pivots, слои, масштаб и длительности. Rig: `scenes/visuals/GoblinVisual.tscn`, поведение visual: `scripts/visuals/goblin_visual.gd`. [Результаты проверки анимаций](../../../docs/done/GOBLIN_ANIMATION_REVIEW.md).

## Формы и палитра

Крупная округлая голова с широкими ушами, сердитые глаза, короткий нос и один крупный клык. Маленький корпус, короткие ноги и руки, коричневая одежда и кинжал. Голова вместе с ушами/лицом — одна часть, руки вместе с кистями, ноги вместе с ботинками. Нет отдельных мелких суставов или декоративных элементов.

Outline #29180f, 7 px на общем canvas, round linecap/linejoin; более тонкие внутренние линии и оружие. Кожа #98bf45, тень #728f32, свет #afd15b. Внутри ушей #ce8e62 / #a86342, одежда #9c642d / #754229, свет #aa7540 / #b77e42, клинок и клык #ead5a2, тень клинка #c6ab7f. Плоские заливки, без текстур и градиентов.

По последней правке пользователя сложность меняет только ботинки, напульсники и набедренную повязку через equipment_palette.gdshader и общую equipment_mask.svg 256×256. Материал назначен пяти частям; Head и Dagger без него. Кожа всегда сохраняет принятую зелёную palette. Плечевой ремень, наплечник, внутренние уши, глаза и клык также сохраняют цвета. Все пять цветов одежды и пороги HP берутся из EnemyStats; цвет определяется max HP при spawn, не уменьшается после попаданий. Материал локален для экземпляра, маска общая для всех.

## Parts и pivots

| Part | Pivot canvas | Parent bone | Z |
|---|---|---|---:|
| arm_back | 83,159 | Body | 0 |
| leg_left | 101,203 | Body | 1 |
| leg_right | 146,203 | Body | 2 |
| body | 126,179 | Root | 3 |
| arm_front | 164,161 | Body | 4 |
| head | 133,145 | Body | 5 |
| dagger | 205,190 | FrontArm | 6 |

Голова поставлена перед передней рукой: скрытое плечо не перекрывает нижнюю часть лица. Кинжал перед кистью. Для плеч, бёдер и шеи дорисованы округлые скрытые участки. Крайние позы замаха/удара и mirror проверены в preview; принятые SVG shapes не потребовали изменений.

Origin (128,128), baseline ступней около y=239. Sprite2D centered=false, position=−pivot; Bone.position=pivot−parent_pivot. Все parts сохраняют полный canvas, trimming отсутствует. В rig 8 bones вместе с Root, явные rest transforms с determinant=1, без mesh/IK/root motion.

По правке пользователя от 07.10.2026 Goblin уменьшен на 20%: полный canvas 86.4 логических единиц вместо 108, visual.scale=0.3375. При 6/7/8 столбцах и существующем коэффициенте min((cell_size−12)/140,1) получаются примерно 62/52/44 логических px, а на экране шириной 390 px — 33/28/24 физических px. Static fallback, полоска HP и индикатор slow уменьшены тем же коэффициентом. Mirror сохраняет новый размер; движение, HP, урон и награды не менялись.

## Выполненные проверки

- Master и 7 parts импортированы Godot MCP как Texture2D 256×256; просмотр master выполнен через MCP. Новых editor/runtime errors при импорте нет.
- SVG XML и manifest корректны, pivots/offsets согласованы. Сборка содержит 44 path и 2 ellipse, без embedded bitmap. Все 7 групп master соответствуют отдельным parts.
- Browser canvas сравнение сборки частей с master: максимальная разница каналов 0/255. Прозрачные поля сохранены, границы силуэта (19,26)–(246,241) не обрезаны холстом.
- Preview проверен в Edge при ширине 1000 и 390 px: reference, размеры 100/140/180, enemy scale, phone scale, сравнение с Archer, выбор части, pivots и mirror. Ошибок console/загрузки ресурсов и горизонтального overflow на телефоне нет.
- Gameplay сцены/скрипты, старый enemy.svg и принятый Archer не менялись; игровых regression tests и Web game export для этого art gate не потребовалось.

## Animation gate и ручная проверка

1. Walk: короткий шаг, лёгкое движение корпуса, читаемость на трёх игровых размерах.
2. Attack: замах и короткий удар кинжалом на 0.5× и 1×, устойчивый хват, нет дыр в суставах.
3. Hit и death: короткая реакция, плавное исчезновение; Replay после смерти восстанавливает вид.
4. Mirror, Pause/Resume, скорости и переключение Archer/Goblin работают без перескоков поз.

Все gates приняты. Native/Web проверки и 40 одновременно движущихся Goblin пройдены; результаты и ограничения в gameplay отчёте. Normal default animated, старые assets сохранены. Объект фиксируется отдельным commit; push требует отдельного разрешения.
