# Summoner Tower — SVG art

Этап: Tower полностью принят пользователем 08.10.2026, animated default включён. Рисунок написан вручную в SVG по `art/references/tower.png`, без генераторов изображений и сторонних ассетов. Это упрощённый образ референса: крупный голубой кристалл, широкое каменное основание, золотая оправа и два синих знамени.

`master.svg` — общий просмотр, не будущая runtime texture. `parts/` содержит три жёсткие полноразмерные части. `review.html` — локальный просмотр рисунка, масштаба и независимой цены призыва. PNG-референс остаётся только референсом.

Все SVG имеют прозрачный canvas 256×256; trimming отсутствует. Outline #29180f, 7 px, округлые стыки. Цветовая палитра фиксированная. Цена не нарисована внутри SVG.

| Часть | Pivot в canvas | Pivot относительно origin | Sprite offset | Слой |
| --- | --- | --- | --- | --- |
| base | 128, 128 | 0, 0 | −128, −128 | 0 |
| crystal | 128, 95 | 0, −33 | −128, −95 | 1 |
| body | 128, 159.9 | 0, 31.9 | −128, −159.9 | 2 |

Origin (128,128), нижняя линия основания y=250.1. После замечания пользователя силуэт увеличен на 15% по ширине и 10% по высоте внутри прежнего canvas. Во всех трёх группах одинаковый SVG transform; pivots уже указаны в итоговых координатах canvas, дополнительный transform в Godot не нужен. Base останется неподвижным. BodyPivot — у основания верхней конструкции; CrystalPivot — у нижней части кристалла. Будущие Sprite2D centered=false. Родительский pivot располагается на `pivot−origin`, Sprite внутри на `−pivot`. Положение частей в rest совпадает с master. Координаты записаны в `rig_manifest.json`.

Base продолжается под верхнюю каменную часть. Crystal уходит до y=126.9 под золотую оправу body. Широкие скрытые пересечения дают запас для небольших смещений, наклонов и scale. Подвижные стыки просмотрены в крайних позах tap / refund / hit / destroyed.

Башне не нужны Skeleton2D/Bone2D: в `scenes/visuals/TowerVisual.tscn` один AnimationPlayer и три Sprite2D. Clips: crystal_pulse1.6s loop / tap0.16s / refund0.26s / hit0.18s / destroyed0.45s. RESET восстанавливает transforms и цвета. Destroyed удерживает финальную позу; части остаются непрозрачными. Runtime master.svg не загружается.

Контроллер `scripts/visuals/tower_visual.gd` отвечает только за отображение. `play_animation` используется в review и для полного reset; TowerHealth вызывает show_tap / show_refund / show_hit / show_destroyed по существующим игровым событиям. Destroyed отменяет реакции; hit приоритетнее refund и tap; хранится максимум одна ожидающая реакция. Старый `assets/tower.svg` сохранён; animated default включён после финальной приёмки. В `TowerGameplayReview.tscn` доступен переключатель STATIC / ANIMATED.

В ArtAnimationTest добавлен Tower: 108/92/80 логических px при сетке6/7/8, без постамента, на дорожной клетке. `scenes/debug/TowerAnimationTest.tscn` наследует общий просмотр и сразу выбирает Tower. [Браузерные анимации](http://127.0.0.1:4175/preview/tower-animation/).

Уточнение пользователя при приёмке ART реализовано: нижняя обводка цифр призыва совпадает с краем основания (canvas y=254). Независимый CostLabel z=10 компенсирует descent шрифта и outline, не качается с Body и не темнеет вместе с crystal. Проверены реальные размеры 108/92/80 при6/7/8 columns. HTML art review показывает предыдущую примерку цены; актуальное положение видно в [бою](http://127.0.0.1:4175/preview/tower-gameplay/).

См. [план](../../../docs/done/TOWER_ART_PLAN.md), [проверку рисунка](../../../docs/done/TOWER_ART_REVIEW.md), [проверку анимаций](../../../docs/done/TOWER_ANIMATION_REVIEW.md), [проверку gameplay](../../../docs/done/TOWER_GAMEPLAY_REVIEW.md).
