# TreeLua

Минималистичный 3D-движок для LÖVE 11.5 — вся обвязка, которую three.js
добавляет поверх рендерера, но без самого рендерера, ведь у LÖVE он уже есть.

Публичный API следует [three.js](https://threejs.org/docs/), поэтому его
документацию можно использовать как справочник. Два намеренных отличия
разобраны в разделе [Отличия от three.js](#отличия-от-threejs).

## Быстрый старт

```lua
local TL = require "TreeEngine"

local scene, camera, renderer, mixer

function love.load()
    local w, h = love.graphics.getDimensions()

    scene  = TL.Scene:new()
    scene:setBackground(0x171a21)

    camera = TL.PerspectiveCamera:new(60, w / h, 0.1, 1000)
    camera.position:set(0, 1.2, 3.5)

    renderer = TL.WebGLRenderer:new()

    local sun = TL.DirectionalLight:new(0xfff7eb, 1)
    sun.position:set(0.4, 1.0, 0.6)
    scene:add(sun)
    scene:add(TL.AmbientLight:new(0x474d5c, 1))

    local gltf = TL.GLTFLoader:new():load("assets/model/model3dtest.glb")
    scene:add(gltf.scene)

    mixer = TL.AnimationMixer:new(gltf.scene)
    mixer:clipAction(gltf.animations[1]):play()
end

function love.update(dt) mixer:update(dt) end
function love.draw()     renderer:render(scene, camera) end
```

Подключение библиотеки не создаёт глобальных переменных и не вешает хуков.

## API

### Математика
`Vector3` `Vector4` `Matrix4` `Quaternion` `Euler` `Color` `Box3` `Sphere`
`Plane` `Ray` `Frustum` `MathUtils`

### Ядро
`Object3D` `Group` `BufferGeometry` `Scene` `Raycaster`

Выбор объектов (picking) работает как в three.js, с одним дополнением.
`setFromCamera` принимает нормализованные координаты экрана (NDC), как и
там; `setFromScreen` — это фасад над ним для обычных пикселей, которые даёт
`love.mousepressed`:

```lua
function love.mousepressed(x, y)
    local caster = TL.Raycaster:new():setFromScreen(x, y, camera)
    local hit = caster:intersectObjects(scene.children, true)[1]
    if hit then print(hit.object.name, hit.distance) end
end
```

`Vector3:project(camera)` / `:unproject(camera)` переводят точку между
мировым пространством и NDC через view-projection камеры, как в three.js.
`Camera` добавляет фасад поверх реальных пикселей LÖVE, потому что перевод
NDC ↔ экран руками — частый источник ошибок (особенно flip по Y):

```lua
local sx, sy, visible = camera:worldToScreen(enemy.position)
local worldPoint = camera:screenToWorld(mx, my)
```

### Геометрии
`BoxGeometry` `SphereGeometry` `PlaneGeometry` `CylinderGeometry` `ConeGeometry`
`TorusGeometry`

Генерируемые примитивы, чтобы собирать сцену без загрузки файла:

```lua
local mesh = TL.Mesh:new(
    TL.BoxGeometry:new(1, 1, 1),
    TL.MeshStandardMaterial:new{ color = 0xff8800 })
```

`PlaneGeometry` лежит в плоскости XY и смотрит в сторону +Z, как в
three.js — для пола нужно `mesh:rotateX(-math.pi / 2)`.

### Объекты
`Mesh` `SkinnedMesh` `Skeleton` `InstancedMesh` `LOD`

Для `LOD` не нужна поддержка в рендерере — он только переключает видимость
дочерних объектов, а обход сцены рендерером это уже учитывает. Вызывайте
`lod:update(camera)` сами, рядом с `controls:update`, так как рендерер сам
их не ищет:

```lua
local lod = TL.LOD:new()
lod:addLevel(highDetail, 0)
lod:addLevel(lowDetail, 25)
```

`InstancedMesh` сохраняет интерфейс three.js, но **не** является одним draw
call — см. [Ограничения](#ограничения). Индексация — с 1, как и везде здесь.

### Model
`Model` — ассет, загружаемый один раз и инстанцируемый любое число раз. Не
класс three.js: он существует потому, что glTF-файл и живой игровой объект —
разные вещи, и загружать файл на каждый спавн расточительно.

```lua
local model = TL.Model:fromLoaderResult(TL.GLTFLoader:new():load(MODEL_PATH))

local enemy = model:createInstance()   -- дёшево: без чтения файла и повторного парсинга
scene:add(enemy.scene)
enemy.mixer:clipAction(enemy.animations[1]):play()
enemy.scene.position:set(x, 0, z)
```

`Model:fromLoaderResult(result)` оборачивает результат загрузчика
`{ scene, animations }`. `model:createInstance()` возвращает
`{ scene, animations, mixer }`: свежий `Object3D`-шелл на каждый примитив
(со своим transform/`matrixWorld`), склонированный `Skeleton`, хранящий
только текущую позу (joints/inverse-bind остаются общими с моделью), и свой
`AnimationMixer`. Геометрия, материалы и исходные объекты `love.Mesh`
никогда не клонируются — каждый инстанс читает их по ссылке, как three.js
делит `BufferGeometry` между копиями. Именно это разделение делает N
анимированных инстансов одной модели дешёвыми: файл парсится ровно один раз.

### Материалы
`Material` `MeshStandardMaterial`

Затенение — metallic-roughness PBR: Кук-Торренс с распределением GGX,
геометрией Смита и Френелем Шлика, так что `metalness`, `roughness`,
`emissive`, `normalMap`, `aoMap` и упакованная metallic-roughness карта из
glTF доходят до шейдера:

```lua
local m = TL.MeshStandardMaterial:new{ color = 0xc84a3a, metalness = 0, roughness = 0.35 }
m.emissive:set(0x220800)
```

Модель без карты metallic-roughness — матовый диэлектрик: `metalness` 0,
`roughness` 1. Факторы, прописанные без карты, игнорируются, потому что
экспортёры пишут их независимо от того, авторизовал ли кто-то PBR — Mixamo
ставит 0.5/0.5 на каждый материал, к которому прикасается, из-за чего кожа
иначе была бы наполовину металлической. Оба поля обычные, так что
загруженный материал всё равно можно поправить руками.

Картам нормалей не нужен атрибут тангента: касательный базис вычисляется
для каждого фрагмента из экранных производных, так что формат вершин
остаётся как есть.

Два намеренных отступления от строгого PBR, оба настраиваемые:

- **Нет карты окружения.** Её роль играет ambient-свет: металлы отражают
  его с оттенком своего цвета, диэлектрики рассеивают. Без этого металл под
  одним источником света рендерится почти чёрным — физически верно, но
  бесполезно.
- **Wrapped diffuse.** `renderer.diffuseWrap` (по умолчанию `0.25`) смягчает
  терминатор, чтобы неосвещённые грани оставались читаемыми. Поставьте `0`
  для строгого спада.

### Камеры
`Camera` `PerspectiveCamera` `OrthographicCamera`

### Источники света
`Light` `AmbientLight` `DirectionalLight` `PointLight` `SpotLight`

`PointLight` и `SpotLight` находятся в графе сцены и несут свои поля из
three.js, но встроенный шейдер берёт один направленный источник плюс
ambient, так что они пока не сэмплируются — они нужны, чтобы код сцены,
написанный под three.js, загружался без ошибок.

### Рендерер
`WebGLRenderer` — `render(scene, camera)`, `setClearColor`, `setSize`,
`info.render`

Отрисовка группируется в два пакета по варианту шейдера за один обход
сцены: сначала статические меши, затем анимированные, так что каждая
программа привязывается один раз за кадр. Внутри пакета отрисовки
упорядочены по `renderOrder`, затем непрозрачные перед прозрачными, затем по
дистанции — от ближних к дальним для непрозрачных (чтобы тест глубины рано
отбрасывал перекрытые фрагменты) и от дальних к ближним для прозрачных, как
того требует блендинг.

Frustum culling происходит в том же обходе, по ограничивающей сфере каждой
геометрии. Анимированные меши исключены: их границы описывают bind pose, а
анимация регулярно выводит конечности за её пределы. Отключается через
`renderer.frustumCulling = false`; `info.render.culled` показывает, что было
отброшено.

### Загрузчики
`GLTFLoader` `ColladaLoader` `TextureLoader` — `load(url, onLoad, onProgress,
onError)`. Загрузчики моделей возвращают `{ scene, animations }`. LÖVE
читает с диска синхронно, так что колбэк срабатывает немедленно; возвращаемое
значение работает точно так же.

### Анимация
`AnimationClip` `AnimationAction` `AnimationMixer`

Каждый активный экшен смешивается по весу, так что `crossFadeTo` — это
настоящий переход:

```lua
walk:play()
run:play()
walk:crossFadeTo(run, 0.4)
```

Установите `mixer.blending = false` для более дешёвого пути, где позу
записывает только экшен с наибольшим весом.

### Controls
`FlyControls` — движение WASD/QE, обзор мышью, колесо меняет скорость.

`OrbitControls` — левое перетаскивание вращает камеру, правое — панорамирует,
колесо — зумирует. В отличие от three.js здесь нет DOM-элемента для
привязки, поэтому приложение само прокидывает колбэки LÖVE:

```lua
function love.update(dt)             controls:update(dt) end
function love.mousemoved(x,y,dx,dy)  controls:mousemoved(x, y, dx, dy) end
function love.wheelmoved(x,y)        controls:wheelmoved(y) end
```

Контроллер сам управляет позицией камеры, пересчитывая её из `target` плюс
сферическое смещение на каждом обновлении — двигайте `target`, а не
`camera.position`.

## Отличия от three.js

**Методы вызываются через `:`.** Каждый метод принимает объект первым
аргументом, поэтому статики three.js здесь тоже методы:
`clip:findByName(clips, name)`.

**Мутирующие методы, конфликтующие со старыми именами, получили суффикс.**
`Vector3:add` движка появился раньше фасада и возвращает новый вектор;
`add` в three.js мутирует. Там, где оба должны были сосуществовать,
three.js-версия получила суффикс:

| three.js | здесь |
|---|---|
| `Vector3.add` / `.sub` | `addSelf` / `subSelf` |
| `Vector3.normalize` | `normalizeSelf` |
| `Vector3.lerp` | `lerpSelf` |
| `Vector3.min` / `.max` | `minSelf` / `maxSelf` |
| `Vector3.clamp` | `clampSelf` |
| `Vector3.floor` / `.ceil` / `.round` | `floorSelf` / `ceilSelf` / `roundSelf` |
| `Matrix4.transpose` | `transposeSelf` |

Всё остальное — `set`, `copy`, `multiplyScalar`, `applyQuaternion`,
`addScaledVector`, `crossVectors` и прочее — сохраняет написание three.js и
его мутирующее поведение.

## Ограничения

- Встроенный шейдер берёт **один** направленный источник света плюс ambient.
  Сцена с бóльшим числом источников получает самый яркий направленный и
  сумму ambient-составляющих, и явно предупреждает об этом один раз, а не
  молча отбрасывает остальные. `PointLight` и `SpotLight` пока вообще не
  сэмплируются.
- `InstancedMesh` — это не один draw call. Шейдер принимает единственный
  `u_model`, так что рендерер проходит по инстансам и делает по одной
  отрисовке на каждый — экономия в общей геометрии, материале и границах.
  API — three.js-совместимый, так что это может измениться под капотом без
  правок вызывающего кода.
- Нет карты окружения или IBL-пробы, поэтому отражениям нечего отражать —
  см. замену через ambient в разделе «Материалы».
- Вычисляемый касательный базис точен там, где UV локально аффинны — то
  есть почти везде, кроме намеренно искажённой развёртки.
- `Raycaster` проверяет анимированные меши по их **bind pose**: вершинные
  данные, которые он читает — то, что деформирует GPU, а не результат.
  Движущегося персонажа он выбирает приблизительно.
- Генераторы примитивов считают форму выпуклой относительно начала
  координат: треугольники разворачиваются наружу сравнением каждого со
  своим центроидом, в одном месте, а не вручную по каждой грани.
  `TorusGeometry` — исключение, будучи единственным примитивом с настоящей
  внутренней стенкой. Неполные развёртки (`thetaLength` меньше полного
  оборота) выходят за рамки этого допущения и могут получиться вывернутыми
  наизнанку; дайте им `side = "double"`, если это заметно.
- Нет класса `Texture` — `Image` в LÖVE уже несёт состояние фильтрации и
  wrap, которое three.js хранит отдельным объектом.
- Скелеты ограничены 128 костями — столько же, сколько `MAX_BONES` в
  шейдере.

## Структура

| Путь | |
|---|---|
| `init.lua` | публичный API; всё ниже достижимо через него |
| `three/` | фасад: core, objects, materials, cameras, lights, renderers, loaders, animation, controls |
| `math/` | vec3, vec4, mat4, quat, euler, color, box3, sphere, plane, ray, frustum |
| `shader/init.lua` | собирает варианты шейдера из частей |
| `shader/parts/` | один файл на фичу: skinning, normalmap, pbr |
| `importer/gltf/` | glTF 2.0 / GLB: геометрия, материалы, скелет, анимация |
| `importer/dae/` | Collada: та же форма результата, так что оба формата идут по одному пути |
| `importer/common.lua` | трансформы, палитра скиннинга, интерполяция |
| `three/objects/Model.lua` | один загруженный ассет, дёшево инстанцируемый любое число раз |
| `class/` | legacy, заменено фасадом — см. заметку в шапке каждого файла |
| `lib/util/` | только для демо-обвязки; устанавливает глобальные переменные, в самой библиотеке не используется |
| `game_test/` | небольшая игра, построенная на движке как на обычной библиотеке — не часть движка, используется для сквозной проверки |

## Шейдеры

LÖVE собирает шейдер из строки, поэтому вариант — это просто другая
конкатенация. Каждая часть в `shader/parts/` даёт GLSL, сгруппированный по
слоту, который она заполняет, а `shader/init.lua` хранит единственную копию
общей формы.

Части разделены по **фиче**, а не по стадии: скиннинг живёт целиком в одном
файле, включая и вершинные юниформы, и вершинную математику. Разделение по
стадиям вместо этого разбросало бы каждую фичу по нескольким файлам и
превратило бы любую правку в охоту.

Есть два скомпилированных варианта, `static` и `skinned`. Разделение не
косметическое — массив на 128 костей занимает 2048 вершинных юниформ-
компонентов, при гарантированном минимуме в 1024, так что статичный меш не
должен его объявлять.

## Тесты

    lovec . --tests

256 проверок покрывают математику, граф объектов, генераторы, чистоту
библиотеки, а также загрузчики/анимацию/рендерер против реального
графического контекста.

## Запуск тестовой игры

    love .

`main.lua` целиком делегирует в `game_test/` — небольшой top-down шутер,
построенный на TreeEngine строго как на библиотеке: ни один файл движка не
меняется, чтобы это работало, так что игра заодно служит интеграционной
проверкой. Она не часть движка и не место для примеров API сверх того, что
уже приведено выше; смотрите `game_test/init.lua`, если хотите увидеть
полную сборку сцены.
