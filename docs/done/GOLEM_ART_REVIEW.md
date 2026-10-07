# Golem — SVG art для приёмки

08.10.2026. [План](GOLEM_ART_PLAN.md) принят, включая цвет сложности только на мхе. **Восемь SVG parts и статический preview приняты пользователем.** Последующие [animations](GOLEM_ANIMATION_REVIEW.md) также приняты; [gameplay integration](GOLEM_GAMEPLAY_REVIEW.md) также принята.

[Открыть preview](http://127.0.0.1:4175/preview/golem-art/) · [master.svg](../../art/source/golem/master.svg) · [reference](../../art/references/golem.png) · [source README](../../art/source/golem/README.md).

## Результат

Созданы `art/source/golem/master.svg`, восемь файлов `parts/`, `moss_mask.svg`, `rig_manifest.json`, README.md и review.html. Все source parts на полном прозрачном canvas 256×256 без trimming; 50 простых paths в master, основной outline #29180f / 7 px. Production art отрисован вручную кодом SVG; image generators, Krita, raster embedding, filters/fonts, готовые сторонние sprites не использовались.

Каменный персонаж сохраняет широкие плечи, тяжёлые кулаки, небольшие жёлтые глаза и короткие ноги reference. Мелкие грани сведены к большим светлым/тёмным плоскостям; мох состоит из крупных пятен. Пять уровней меняют только мох на голове, руках, ногах и небольшом участке корпуса; камень, тёмные стыки и глаза сохраняют цвета. HP-пороги 120/240/480/960/1920 взяты из существующего EnemyStats.

Восемь parts: body, head, две upper arms, два forearms с цельными кулаками, две ноги. Точные pivots и bone positions/offsets/z-order описаны в [manifest](../../art/source/golem/rig_manifest.json). Плечи/локти/бёдра/шея имеют округлые скрытые окончания и overlap. В ходе внутренней проверки оси помещены глубже в перекрытие; это правка координат pivots, а не изменение рисунка. На art gate Skeleton2D/Bone2D/AnimationPlayer не создавались; последующий rig описан в [animation review](GOLEM_ANIMATION_REVIEW.md).

Preview показывает reference рядом с новым рисунком, 100/140/180 px, фактические клетки 6/7/8 столбцов, телефонный масштаб, сравнение с Goblin/Orc, пять цветов мха, выбор отдельной части, pivots и Mirror. Golem canvas_size=140, Orc=120, Goblin=86.4; их gameplay размеры не изменены. При сетках 6/7/8 Golem имеет canvas 100/84/72 логических px, при ширине экрана 390 — 54/46/39 физических px.

## Проверки

- Godot MCP подтвердил нужный проект, Godot 4.7.2, Compatibility и unsaved=[] перед работой. Новые SVG импортированы и прочитаны через редактор: master, mask и восемь parts имеют textures 256×256, svg/scale=1, mipmaps=false. Master просмотрен через Godot MCP.
- Проверено структурное совпадение каждой части с группой master, включая paths, fills, outline и pivots: восемь совпадений. Различия XML-форматирования/whitespace не относятся к рисунку. В master восемь moss regions, нет embedded images.
- По импортированным texture images проверены точки соединений: pivot находится в непрозрачных участках child и parent, alpha=1. Это статическая проверка overlap; крайние вращения и динамические joints будут проверяться на rig gate.
- Edge: все изображения и данные preview загрузились, восемь parts и пять цветовых вариантов отображаются; selector одного forearm показывает одну часть и один pivot, Mirror отражает сборку. Просмотрены reference, малые размеры, дорога и пять цветов. Console/page/resource errors=[].
- При размере окна 390×844 content width=390: горизонтального overflow нет. Снимки reference/scale/comparison/levels/phone просмотрены; глаза, кулаки и мох различимы на малом размере. Физический телефон не использовался.
- Короткий запуск MainMenu после импорта через Godot MCP прошёл без новых runtime errors после seq=132. SVG ещё не подключены к gameplay; бой, скорость, HP, урон, projectiles, spawn/waves и исходные `scenes/golem.tscn`/`assets/golem.svg`/golem_stats не изменялись. Игровые regression tests и повторный Web export не требовались для статической art страницы.

Preview и снимки размещены в игнорируемом build/, диагностические helpers — в .tools/. Исходные SVG, manifest и настройки .import сохранены в проекте. Проверки rig/clips выполнены позднее и описаны отдельно. Runtime material, реальные contact/death события и HTML5 массовый бой относятся к gameplay gate.

## Ручная приёмка art

1. Принять силуэт и упрощение reference: массивность относительно Orc/Goblin, плечи, кулаки, каменная голова/глаза, короткие ноги.
2. Посмотреть 100 px и телефонный масштаб: фигура читается, камень отличается от дороги, мох достаточно заметен.
3. Принять пять цветов только мха; камень и глаза остаются прежними. Проверить отдельные части, layers и прозрачный фон master.

Golem полностью принят. Animated default включён; static сохранён. Отчёты перенесены в docs/done для отдельного commit. Push требует отдельного разрешения; Boss и Tower art не начаты.
