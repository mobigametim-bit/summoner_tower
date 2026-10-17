# Башня-склеп

Выбранный пользователем вариант 01 из `art/concepts/graveyard_towers/crypt.svg`.
Собственная ручная SVG-отрисовка, три жёсткие части, общий canvas 256×256.
`prepare_parts.py` воспроизводимо создаёт master и parts, без внешних изображений.

Все части сохраняют одинаковый canvas и сдвиг Y +7: нижняя граница обводки
основания совпадает с существующим anchor Y=254 для цены призыва.
Перекрытие корпуса и основания сохраняется при scale punch.

Godot: `scenes/visuals/GraveyardTowerVisual.tscn`; используется прежний TowerVisual
controller и существующие crystal_pulse / tap / refund / hit / destroyed.
Поворот кристалла выполняется вокруг его нового центра (128,63.5) в source canvas.
Ресурсы лесной башни не изменяются.
