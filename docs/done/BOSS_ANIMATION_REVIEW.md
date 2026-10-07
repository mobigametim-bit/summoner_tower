# Boss — rigid cutout animation review

08.10.2026. Boss полностью принят пользователем; animated default включён, отчёты архивированы. Ниже сохранены результаты принятого rig/animation gate. [Итог gameplay](BOSS_GAMEPLAY_REVIEW.md). Push без отдельного разрешения не выполнять.

[Открыть анимации в браузере](http://127.0.0.1:4175/preview/boss-animation/), [SVG art](http://127.0.0.1:4175/preview/boss-art/), [план](BOSS_ART_PLAN.md), [проверки SVG](BOSS_ART_REVIEW.md).

## Создано

- `scenes/visuals/BossVisual.tscn` и `scripts/visuals/boss_visual.gd`: 9 Bone2D, 8 Sprite2D с принятыми SVG parts, один AnimationPlayer. Scene / nodes / Animation resources / persistent signals созданы через Godot MCP, без ручной правки .tscn.
- `scenes/debug/BossAnimationTest.tscn` — настоящая inherited scene общего ArtAnimationTest, initial_asset_index=6. В общей сцене добавлены четыре экземпляра Boss: главный просмотр и дорожные примеры 6/7/8 столбцов. Только главный экземпляр передаёт impact/finished в UI; образцы не увеличивают счётчик события и не запускают повторные таймеры.
- Общий selector содержит 7 готовых к просмотру assets. Boss имеет отдельный список из пяти анимаций; остальные списки сохранены.
- Canvas 256×256, actor_origin=(128,128), visual.scale=166/256. Все Bone.rest явно равны исходным transforms, автоматический подбор длины выключен, длина=18. Sprite.centered=false, offset=−pivot, абсолютный z-order. Координаты сохранены в rig_manifest.json.

```text
BossVisual : CanvasGroup (наследник Node2D)
  Skeleton2D
    Root
      Body
        BackUpperArm
          BackForearm
        LeftLeg
        RightLeg
        FrontUpperArm
          FrontForearm
        Head
  AnimationPlayer
```

Это rigid cutout: отдельные жёсткие textures следуют костям; без mesh, weights, IK, root motion и деформирования частей. Корона и клыки следуют Head, кулаки — предплечьям, наплечники — плечам.

## Clips

| Clip | Длина | Поведение |
|---|---:|---|
| walk_loop | 1.20 s | Тяжёлый короткий шаг, заметное покачивание головы и кулаков, небольшое движение корпуса. Entity не перемещает. |
| attack | 0.55 s | Оба предплечья поднимаются / сгибаются, короткая подготовка, удар двумя кулаками вниз с лёгким оседанием корпуса. Visual impact ровно на 0.22 s. |
| hit | 0.16 s | Короткий recoil и flash, затем ходьба. |
| death | 0.45 s | Оседание, наклон и единый fade; исчезнувшая поза удерживается до Replay. |
| spawn_or_intro | 0.35 s | Alpha 0→1, небольшой scale pulse 0.88→1.04→0.99→1; затем ходьба. |

RESET восстанавливает позиции, вращение, масштабы и цвета, включая прозрачность после death/intro. Impact защищён от повторной отправки и от события старой прерванной атаки. Это пока visual event в review, а не урон башне.

При первом Web-просмотре обнаружено просвечивание скрытых суставов во время fade: понижение alpha на каждой texture делало overlap видимым. Исправлено штатным CanvasGroup.self_modulate: сначала части собираются в один рисунок, затем применяется общая прозрачность / flash. Fit margin=0, clear margin=2, mipmaps=false; custom shader не нужен. Переход не меняет количество bones или подход cutout.

## Проверки

- Godot MCP: нужный проект, Godot 4.7.2 / Compatibility. Rig inspect подтвердил 9 ненулевых корректных rest transforms, отключённый auto length. Запущена BossAnimationTest; runtime errors отсутствуют.
- На 0.5× / 1× / 2× impact отсутствует до 0.22 s, появляется один раз после пересечения этого времени, повторный emit не увеличивает счётчик. Завершившаяся attack возвращается в walk_loop.
- Прерывание attack на 0.10 s → hit: позднего impact нет, после hit включается walk_loop.
- Death заканчивается alpha=0; Replay восстанавливает alpha=1 и Root.position=(−128,−128), scale=(1,1). Intro начинается alpha=0 / scale=0.88 и заканчивается alpha=1 / scale=1 / walk_loop.
- Все семь selectors выбирают правильные animations и четыре preview экземпляра. Main / sample event connections не дублируют счётчик.
- Визуально просмотрены windup, impact, fade, Replay и дорожные примеры при реальном размере. Голова и кулаки движутся при walk; в просмотренных крайних позах отверстий в плечах/локтях/шее не обнаружено. Ручная художественная приёмка остаётся за пользователем.
- Edge Web, один совмещённый прогон: все пять clips, Replay / Pause / Mirror, скорости 0.5×/1×/2×, touch mirror, все selectors, реальные размеры, 450×800 / 390×844 / 1280×720. Pause останавливает все четыре видимых экземпляра. Console/page/resource errors отсутствуют.
- После изменения fade повторно экспортирован только debug preview и выполнена целевая Web-проверка flash / death / Replay / intro / Pause; overlap перестал просвечивать. Полный прогон selectors и размеров повторять не потребовалось. Финальный native check подтвердил CanvasGroup, alpha death=0, alpha после Replay/intro=1, impact count=1; runtime errors отсутствуют.

Экспорт выполнен через MCP, single-thread / без extensions. Временный preset удалён, project.godot и export_presets.cfg восстановлены в точности; main scene остаётся main_menu. Native игра остановлена. Нормальная Web игра не пересобиралась и игровой Boss по-прежнему использует прежний static visual.

## Ограничения и следующий gate

Это preview анимаций, не игровой тест Boss. Существующие `scenes/boss.tscn`, баланс, wave logic, targeting и outcomes не менялись. Synchronization с tower contact, slow/hit interruption в бою, rewards/upgrades, очистка tails и restart проверяются после отдельной приёмки анимаций на gameplay gate.

Восемь общих 256×256 textures ≈2 MiB RGBA8 без mipmaps, девять костей / один AnimationPlayer. CanvasGroup использует backbuffer, поэтому его GPU cost учитывается при будущей gameplay-проверке; он добавлен только Boss. Производительность больших боевых волн и физический телефон на этом gate не проверены.

## Ручная приёмка

1. Проверить walk_loop на 1×: заметны тяжёлый шаг, голова и кулаки, силуэт остаётся читаемым.
2. Проверить attack на 0.5× и 1×: два кулака участвуют в ударе, impact показывает один event на 0.22 s; плечи и локти не раскрываются.
3. Просмотреть hit / death / spawn_or_intro. После death нажать Replay; после intro персонаж возвращается к ходьбе без остаточной прозрачности или увеличения.
4. Проверить Mirror, Pause и real gameplay scale / примеры 6–8 столбцов. Принять анимации перед интеграцией в бой.

Анимации и Boss gameplay приняты; static fallback сохранён, animated default включён. Этот отчёт перенесён в docs/done. Boss фиксируется отдельным локальным commit; Tower начинается с нового PLAN gate.
