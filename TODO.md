# TODO для движка (TreeEngine)

Не связано с game_test — баг/пробел в самом движке, найден при разработке тестовой игры.

## Отсутствуют `Vector3:project` / `Vector3:unproject`

В three.js у `Vector3` есть методы `project(camera)` и `unproject(camera)` —
проекция мировой точки в NDC через камеру и обратно. В TreeEngine их нет
(проверено в `math/vec3.lua` и `three/cameras/Camera.lua`), хотя все нужные
для реализации кирпичики уже есть: `camera.projectionMatrix`,
`camera.matrixWorldInverse`, `camera.projectionMatrixInverse`,
`camera:viewProjectionMatrix()`, `Vector3:applyMatrix4`.

Из-за этого пришлось писать world→screen проекцию вручную в игровом проекте
(`game_test/hpbar.lua`), хотя по духу "следуем API three.js, если не можем —
пишем фасад" это должно быть частью движка.

Предлагаемая реализация (по аналогии с three.js):

```lua
-- Vector3:project(camera) -- мировые координаты -> NDC [-1,1]
function Vector3:project(camera)
    return self:applyMatrix4(camera:viewProjectionMatrix())
end

-- Vector3:unproject(camera) -- NDC [-1,1] -> мировые координаты
function Vector3:unproject(camera)
    local inverse = Matrix4:new()
        :multiplyMatrices(camera.matrixWorld, camera.projectionMatrixInverse)
    return self:applyMatrix4(inverse)
end
```

Было бы неплохо также добавить фасад над пикселями экрана, как это уже
сделано для `Raycaster:setFromScreen` — что-то вроде
`Camera:worldToScreen(vec3, width, height)` /
`Camera:screenToWorld(x, y, camera, width, height)`, потому что перевод
NDC <-> пиксели LÖVE каждый раз руками — источник ошибок (flip по Y и т.п.).

## Идея: автогенерация LOD-уровней

Сейчас `LOD` (`three/objects/LOD.lua`) — это только контейнер: он переключает
видимость между уровнями по дистанции до камеры, но сами геометрии для каждого
уровня разработчик обязан подготовить и передать руками через
`lod:addLevel(mesh, distance)`. Автоматического упрощения геометрии
(decimation/симплификация меша) в движке нет.

В game_test это привело к тому, что low-detail уровень босса пришлось
собирать вручную (примитивом), а не получить автоматически из исходного
glTF-меша.

Стоит попробовать добавить опциональный автогенератор low-poly уровня(ей) из
существующей `BufferGeometry` — например, простая decimation по вершинам/
edge-collapse, либо хотя бы генерация упрощённого bounding-примитива
(box/sphere/capsule) по `boundingSphere`/`boundingBox` геометрии как дешёвый
fallback-LOD. Не факт что это оправдано (сложность реализации vs польза для
маленького движка), но стоит оценить хотя бы прототипом.

## Клонирование skinned-модели не даёт независимый скелет

Нужно было заспавнить несколько врагов с одной и той же анимированной glTF-
моделью (`assets/model/model3dtest.glb`). Ожидаемый путь — загрузить один раз
через `GLTFLoader`, потом `gltf.scene:clone(true)` на каждого врага, как
обычно делается в three.js.

Это не работает в TreeEngine: `SkinnedMesh:copy()` переносит `skeleton` **по
ссылке** (см. `docs/page/SkinnedMesh.html`, "carries over skeleton... by
reference"), а `Skeleton` сам по себе оборачивает не собственные данные, а
общий плоский список узлов импортёра (`docs/page/Skeleton.html`: "wraps the
importer's flat node list... animation writes to nodes"). Значит несколько
клонов одной `SkinnedMesh`/сцены в итоге делят один и тот же `Skeleton` и один
и тот же набор узлов — если на каждом клоне повесить свой `AnimationMixer` и
играть разные (или даже одинаковые, но не синхронизированные по времени)
клипы, миксеры конкурентно пишут в общие узлы, и результат — визуальное
"дёрганье"/скачки позы у всех клонов разом, а не независимая анимация каждого.

Обошли в `game_test/enemies.lua` тем, что каждый враг грузит **свою** копию
модели через отдельный `GLTFLoader:new():load(...)` (полный повторный парсинг
glTF на инстанс) — это работает, но дорого по памяти/времени загрузки при
большом числе врагов и явно не то, что ожидаешь от clone() в three.js-подобном
API.

Правильный фикс — глубокое клонирование `Skeleton` (собственная копия
`nodes`/`skin`) при `SkinnedMesh:clone(true)`, а не перенос по ссылке, так,
чтобы каждый клон был независимо анимируемым, как в three.js
(`SkeletonUtils.clone` там решает ровно эту проблему).

Более точно: корень проблемы в том, что `Skeleton`/`nodes` сейчас смешивает
в одном объекте **данные модели** (структура joints, `inverseBind`-матрицы —
то, что честно можно шарить между инстансами по ссылке, как геометрию и
материалы) и **состояние конкретного инстанса** (текущие локальные/мировые
матрицы узлов на этот кадр — то, во что пишет `AnimationMixer`, и что
обязано быть своим у каждого инстанса). Раз это не разделено, расшарить
модель между несколькими анимируемыми объектами невозможно в принципе, не
дублируя всю структуру.

Нужное API-разделение (по образцу three.js, где `Skeleton` держит ссылки на
`Bone`-объекты — сами по себе клонируемые независимо от geometry/material):
- **shared/static**: geometry, material, joints-иерархия, inverseBind — грузится
  через `GLTFLoader` один раз.
- **per-instance**: набор текущих матриц узлов + `AnimationMixer` — создаётся
  дёшево на каждый инстанс без повторного парсинга файла, например через
  `Skeleton:clone()`, копирующий только "живую" часть (узлы), но берущий
  `skin.inverseBind`/geometry по ссылке из исходного.

Это позволило бы делать `N` дешёвых анимируемых инстансов одной модели без
`N` повторных загрузок с диска — практический кейс из game_test (толпа
одинаковых врагов).
