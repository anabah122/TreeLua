-- tests/suite.lua — the assertions, independent of how they are run
--
-- Split from the runner so the same file can be driven headlessly or from a
-- window: the loader and renderer tests need a real graphics context, and the
-- math ones do not care.

local T = {}

local passed, failed = 0, 0
local failures = {}

local function ok(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. (detail and ("  -- " .. detail) or "")
    end
    print((cond and "ok   " or "FAIL ") .. name)
end

local function near(a, b, eps)
    return math.abs(a - b) < (eps or 1e-5)
end

-- ── math ─────────────────────────────────────────────────────────────────────

function T.math()
    local V = require "math.vec3"
    local M = require "math.mat4"
    local Q = require "math.quat"
    local E = require "math.euler"
    local C = require "math.color"

    print("\n-- math --")

    -- the original immutable surface must survive the three.js additions
    local a, b = V:new(1, 2, 3), V:new(1, 1, 1)
    local s = a + b
    ok("vec3 immutable add leaves operand alone", s.x == 2 and a.x == 1)

    ok("vec3 multiplyScalar mutates", (function()
        local v = V:new(1, 2, 3):multiplyScalar(2)
        return v.x == 2 and v.z == 6
    end)())

    ok("vec3 length", near(V:new(3, 4, 0):length(), 5))
    ok("vec3 lengthSq", V:new(3, 4, 0):lengthSq() == 25)

    -- 90 degrees about Y sends +Z to +X
    local q = Q:new():setFromAxisAngle(V:new(0, 1, 0), math.pi / 2)
    local v = V:new(0, 0, 1):applyQuaternion(q)
    ok("vec3 applyQuaternion", near(v.x, 1) and near(v.z, 0))

    local mat = M:new():compose(V:new(5, 6, 7), q, V:new(2, 2, 2))
    local p2, q2, s2 = V:new(), Q:new(), V:new()
    mat:decompose(p2, q2, s2)
    ok("mat4 decompose position", near(p2.x, 5) and near(p2.z, 7))
    ok("mat4 decompose scale", near(s2.x, 2))
    ok("mat4 decompose rotation", near(math.abs(q2:dot(q)), 1))

    -- elements() must hand out column-major, whatever the internal layout is
    local e = M:new():makeTranslation(1, 2, 3):elements()
    ok("mat4 elements are column-major", e[13] == 1 and e[14] == 2 and e[15] == 3)

    local pv = V:new(0, 0, 0):applyMatrix4(M:new():makeTranslation(1, 2, 3))
    ok("vec3 applyMatrix4", near(pv.x, 1) and near(pv.z, 3))
    ok("vec3 setFromMatrixPosition",
        near(V:new():setFromMatrixPosition(M:new():makeTranslation(9, 8, 7)).x, 9))

    -- lookAt builds an ORIENTATION, not a view matrix: -Z must end up aimed
    -- at the target, so a camera at +Z looking at the origin keeps +Z as its
    -- third basis column
    local la = M:new():lookAt(V:new(0, 0, 5), V:new(0, 0, 0), V:new(0, 1, 0))
    local le = la:elements()
    ok("mat4 lookAt orientation", near(le[9], 0) and near(le[10], 0) and near(le[11], 1))

    local eu = E:new(0.3, 0.4, 0.5, "XYZ")
    local eu2 = E:new():setFromQuaternion(Q:new():setFromEuler(eu), "XYZ")
    ok("euler roundtrip", near(eu2.x, 0.3) and near(eu2.y, 0.4) and near(eu2.z, 0.5))

    local qa, qb = Q:new(), Q:new():setFromAxisAngle(V:new(0, 1, 0), math.pi / 2)
    ok("quat slerp endpoint", qa:clone():slerp(qb, 1):equals(qb))
    ok("quat slerp midpoint stays unit", near(qa:clone():slerp(qb, 0.5):length(), 1))

    ok("color hex", C:new(0xff8800):getHexString() == "ff8800")
    ok("color name", C:new("red").r == 1 and C:new("red").g == 0)
    local h, sat, l = C:new(0xff8800):getHSL()
    ok("color HSL roundtrip", C:new():setHSL(h, sat, l):getHexString() == "ff8800")
    ok("color toArray carries alpha", #C:new(1, 0, 0):toArray() == 4)

    ok("mat4 invert", M:new():compose(V:new(1, 2, 3), q, V:new(1, 1, 1)):invert() ~= nil)
end

-- ── scene graph ──────────────────────────────────────────────────────────────

function T.object3d()
    local O = require "three.core.Object3D"
    local V = require "math.vec3"

    print("\n-- Object3D --")

    local root, a, b = O:new(), O:new(), O:new()
    a.name, b.name = "a", "b"
    root:add(a); a:add(b)
    ok("add wires parent", a.parent == root and b.parent == a and #root.children == 1)

    -- adding elsewhere must move, not duplicate
    root:add(b)
    ok("add re-parents", b.parent == root and #a.children == 0 and #root.children == 2)
    a:add(b)

    a.position:set(1, 0, 0)
    b.position:set(0, 2, 0)
    root:updateMatrixWorld(true)
    local wp = b:getWorldPosition()
    ok("world matrix composes down the chain", near(wp.x, 1) and near(wp.y, 2))

    a.rotation:set(0, math.pi / 2, 0)
    a:updateMatrix()
    ok("euler drives quaternion", near(a.quaternion.y, math.sin(math.pi / 4)))

    root:updateMatrixWorld(true)
    local wp2 = b:getWorldPosition()
    ok("children follow a rotated parent",
        near(wp2.x, 1) and near(wp2.y, 2) and near(wp2.z, 0))

    local c = O:new()
    c:setRotationFromAxisAngle(V:new(0, 1, 0), math.pi / 2)
    c:updateMatrix()
    ok("quaternion write refreshes euler", near(c.rotation.y, math.pi / 2))

    local d = O:new()
    d:rotateY(math.pi / 4); d:rotateY(math.pi / 4)
    ok("rotateY accumulates", near(d.rotation.y, math.pi / 2))

    local e = O:new()
    e.rotation:set(0, math.pi / 2, 0); e:updateMatrix()
    e:translateZ(5)
    ok("translateZ respects orientation", near(e.position.x, 5) and near(e.position.z, 0))

    local n = 0; root:traverse(function() n = n + 1 end)
    ok("traverse visits every node", n == 3)
    ok("getObjectByName", root:getObjectByName("b") == b)

    -- attach re-parents without moving the object in world space
    local p1, p2 = O:new(), O:new()
    p1.position:set(10, 0, 0); p2.position:set(0, 5, 0)
    p1:updateMatrixWorld(true); p2:updateMatrixWorld(true)
    local ch = O:new(); ch.position:set(1, 1, 1)
    p1:add(ch); p1:updateMatrixWorld(true)
    local before = ch:getWorldPosition()
    p2:attach(ch)
    local after = ch:getWorldPosition()
    ok("attach preserves world transform",
        near(before.x, after.x) and near(before.y, after.y) and near(before.z, after.z))

    local l = O:new()
    l:lookAt(0, 0, -1)
    ok("lookAt aims -Z at the target", near(l:getWorldDirection().z, -1))

    local cl = root:clone(true)
    local m = 0; cl:traverse(function() m = m + 1 end)
    ok("clone is deep", m == 3 and cl ~= root)

    local Sub = O:extend("Thing")
    local sub = Sub:new()
    ok("extend produces a working subclass",
        sub.type == "Thing" and sub:isObject3D() and sub.position.x == 0)
    sub:add(O:new())
    ok("subclass inherits add", #sub.children == 1)
end

-- ── generated geometry ───────────────────────────────────────────────────────

function T.geometry()
    local TL   = require "init"
    local Box3 = require "math.box3"

    print("\n-- geometry --")

    -- Every generator must produce a drawable love.Mesh, an index list that is
    -- a whole number of triangles, and indices inside the vertex array. An
    -- out-of-range index is a hard crash at draw time, so it is worth asserting
    -- rather than discovering on screen.
    local function checkMesh(name, g, expectBounds)
        ok(name .. " builds a mesh", g.mesh ~= nil)
        ok(name .. " has vertices", g.vertices and #g.vertices > 0)
        ok(name .. " indices form triangles",
            g.indices and #g.indices > 0 and #g.indices % 3 == 0)

        local maxIndex, count = 0, #g.vertices
        for _, i in ipairs(g.indices) do
            if i > maxIndex then maxIndex = i end
        end
        ok(name .. " indices stay in range", maxIndex <= count,
            ("max %d of %d"):format(maxIndex, count))

        -- vertices are { x,y,z, u,v, nx,ny,nz }; a zero-length normal means the
        -- generator forgot one and the surface would light as flat black
        local badNormal = false
        for _, v in ipairs(g.vertices) do
            local n = math.sqrt(v[6]^2 + v[7]^2 + v[8]^2)
            if math.abs(n - 1) > 1e-3 then badNormal = true break end
        end
        ok(name .. " normals are unit length", not badNormal)

        if expectBounds then
            local box = g:computeBoundingBox()
            local size = box:getSize()
            ok(name .. " bounds match its size",
                near(size.x, expectBounds[1], 1e-3) and
                near(size.y, expectBounds[2], 1e-3) and
                near(size.z, expectBounds[3], 1e-3),
                tostring(size))
        end
    end

    checkMesh("BoxGeometry", TL.BoxGeometry:new(2, 3, 4), { 2, 3, 4 })
    checkMesh("SphereGeometry", TL.SphereGeometry:new(1.5, 16, 8), { 3, 3, 3 })
    checkMesh("PlaneGeometry", TL.PlaneGeometry:new(5, 7), { 5, 7, 0 })
    checkMesh("CylinderGeometry", TL.CylinderGeometry:new(1, 1, 4, 16), { 2, 4, 2 })
    checkMesh("ConeGeometry", TL.ConeGeometry:new(1, 3, 16), { 2, 3, 2 })

    -- a segmented box must subdivide, not just re-emit the same 24 corners
    local plain = TL.BoxGeometry:new(1, 1, 1)
    local split = TL.BoxGeometry:new(1, 1, 1, 3, 3, 3)
    ok("box segments subdivide", #split.vertices > #plain.vertices)

    -- box normals point outward: the +X face's vertices must carry +X normals
    local box = TL.BoxGeometry:new(2, 2, 2)
    local outward = true
    for _, v in ipairs(box.vertices) do
        -- for a box centred on the origin, a vertex on a face has its normal
        -- pointing the same way as its offset along that axis
        local dot = v[1] * v[6] + v[2] * v[7] + v[3] * v[8]
        if dot <= 0 then outward = false break end
    end
    ok("box normals point outward", outward)

    -- same check for the sphere, where position and normal must be parallel
    local sphere = TL.SphereGeometry:new(2, 12, 6)
    local radial = true
    for _, v in ipairs(sphere.vertices) do
        local len = math.sqrt(v[1]^2 + v[2]^2 + v[3]^2)
        if len > 1e-6 then
            local dot = (v[1] * v[6] + v[2] * v[7] + v[3] * v[8]) / len
            if math.abs(dot - 1) > 1e-3 then radial = false break end
        end
    end
    ok("sphere normals are radial", radial)

    -- a cone is a cylinder with a zero top radius
    ok("cone has no top cap", TL.ConeGeometry:new(1, 2, 8).parameters.radiusTop == 0)

    -- Winding, which the normal checks above cannot catch: they are stored per
    -- vertex and stay correct even when the triangle is wound the wrong way
    -- round. A backwards triangle is culled and the surface silently vanishes,
    -- which is how the cylinder shipped without a top cap.
    --
    -- For a closed convex body centred on the origin, every triangle's
    -- geometric normal (from its winding) must point away from the centre.
    local function windingOutward(g)
        local v = g.vertices
        for i = 1, #g.indices, 3 do
            local p1 = v[g.indices[i]]
            local p2 = v[g.indices[i + 1]]
            local p3 = v[g.indices[i + 2]]

            local ax, ay, az = p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3]
            local bx, by, bz = p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3]

            -- cross(a, b) is the face normal for counter-clockwise winding
            local nx = ay * bz - az * by
            local ny = az * bx - ax * bz
            local nz = ax * by - ay * bx

            -- centroid doubles as the outward direction from the origin
            local cx = (p1[1] + p2[1] + p3[1]) / 3
            local cy = (p1[2] + p2[2] + p3[2]) / 3
            local cz = (p1[3] + p2[3] + p3[3]) / 3

            local dot = nx * cx + ny * cy + nz * cz
            if dot < -1e-9 then
                return false, ("triangle %d faces inward"):format((i + 2) / 3)
            end
        end
        return true
    end

    local okBox, whyBox = windingOutward(TL.BoxGeometry:new(2, 2, 2))
    ok("box winding faces outward", okBox, whyBox)

    local okSph, whySph = windingOutward(TL.SphereGeometry:new(1, 16, 8))
    ok("sphere winding faces outward", okSph, whySph)

    local okCyl, whyCyl = windingOutward(TL.CylinderGeometry:new(1, 1, 2, 16))
    ok("cylinder winding faces outward (caps included)", okCyl, whyCyl)

    local okCone, whyCone = windingOutward(TL.ConeGeometry:new(1, 2, 16))
    ok("cone winding faces outward", okCone, whyCone)

    -- a capped cylinder must actually carry both caps: 16 segments give 16
    -- triangles each, on top of the 2*16 the wall needs
    local capped = TL.CylinderGeometry:new(1, 1, 2, 16)
    local open   = TL.CylinderGeometry:new(1, 1, 2, 16, 1, true)
    ok("caps add geometry", #capped.indices == #open.indices + 2 * 16 * 3,
        ("capped %d, open %d"):format(#capped.indices, #open.indices))

    -- An open wall still surrounds the axis, so the centroid rule holds there.
    local okOpen, whyOpen = windingOutward(open)
    ok("open cylinder wall faces outward", okOpen, whyOpen)

    -- A plane is exempt: it lies at z = 0, every centroid is coplanar with the
    -- origin, and the centroid rule says nothing. Its winding must instead
    -- agree with the +Z normal its generator declares.
    local plane = TL.PlaneGeometry:new(2, 2)
    local pv, pi = plane.vertices, plane.indices
    local p1, p2, p3 = pv[pi[1]], pv[pi[2]], pv[pi[3]]
    local ax, ay = p2[1] - p1[1], p2[2] - p1[2]
    local bx, by = p3[1] - p1[1], p3[2] - p1[2]
    ok("plane winding matches its +Z normal", (ax * by - ay * bx) > 0)

    -- Partial sweeps are NOT convex about the origin -- a quarter cylinder's
    -- cap centroids sit off to one side. Assert only that they build and draw,
    -- which is the honest guarantee; their winding is not covered by the rule.
    local wedge = TL.CylinderGeometry:new(1, 1, 2, 12, 1, false, 0, math.pi / 2)
    ok("partial sweep builds", wedge.mesh ~= nil and #wedge.indices % 3 == 0)
    local dome = TL.SphereGeometry:new(1, 12, 6, 0, math.pi * 2, 0, math.pi / 2)
    ok("partial sphere builds", dome.mesh ~= nil and #dome.indices % 3 == 0)

    -- Box3
    local b = Box3:new()
    ok("empty Box3 reports empty", b:isEmpty())
    b:expandByPoint(TL.Vector3:new(1, 2, 3))
    b:expandByPoint(TL.Vector3:new(-1, 0, 1))
    ok("Box3 expands", not b:isEmpty() and b.min.x == -1 and b.max.z == 3)
    ok("Box3 centre", near(b:getCenter().y, 1))
    ok("Box3 size", near(b:getSize().x, 2))
    ok("Box3 contains an interior point", b:containsPoint(TL.Vector3:new(0, 1, 2)))
    ok("Box3 rejects an exterior point", not b:containsPoint(TL.Vector3:new(5, 5, 5)))

    -- setFromObject must account for the object's transform
    local mesh = TL.Mesh:new(TL.BoxGeometry:new(2, 2, 2), TL.MeshStandardMaterial:new())
    mesh.position:set(10, 0, 0)
    local worldBox = Box3:new():setFromObject(mesh)
    ok("Box3 setFromObject follows the transform",
        near(worldBox:getCenter().x, 10) and near(worldBox:getSize().x, 2),
        tostring(worldBox))

    -- and a rotated box must grow, since its corners no longer align
    local spun = TL.Mesh:new(TL.BoxGeometry:new(2, 2, 2), TL.MeshStandardMaterial:new())
    spun.rotation:set(0, math.pi / 4, 0)
    spun:updateMatrix()
    local spunBox = Box3:new():setFromObject(spun)
    ok("Box3 grows for a rotated object",
        spunBox:getSize().x > 2.4, tostring(spunBox:getSize()))

    -- and the whole thing has to survive an actual draw
    local scene = TL.Scene:new()
    scene:add(TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new{ color = 0xff8800 }))
    scene:add(TL.Mesh:new(TL.SphereGeometry:new(0.5, 16, 8), TL.MeshStandardMaterial:new()))
    scene:add(TL.AmbientLight:new(0xffffff, 1))

    local cam = TL.PerspectiveCamera:new(60, 4 / 3, 0.1, 100)
    cam.position:set(0, 0, 5)
    local renderer = TL.WebGLRenderer:new()
    love.graphics.origin()
    local drew, err = pcall(function() renderer:render(scene, cam) end)
    ok("primitives render", drew, tostring(err))
    ok("primitives counted", renderer.info.render.meshes == 2)
end

-- ── the library must stay self-contained ─────────────────────────────────────

function T.hygiene()
    print("\n-- hygiene --")

    -- require must not leak globals or patch the standard library; this is what
    -- makes it usable as a library rather than a framework
    local before = {}
    for k in pairs(_G) do before[k] = true end
    local ceil = math.ceil

    package.loaded["init"] = nil
    require "init"

    local leaked = {}
    for k in pairs(_G) do if not before[k] then leaked[#leaked + 1] = k end end

    ok("require leaks no globals", #leaked == 0, table.concat(leaked, ", "))
    ok("require does not patch math.ceil", math.ceil == ceil)
    ok("require does not replace love.run", _G.mainLoop == nil)
end

-- ── loaders, animation, rendering (need a graphics context) ──────────────────

function T.integration()
    local TL = require "init"

    print("\n-- integration --")

    ok("namespace is populated",
        TL.Scene and TL.PerspectiveCamera and TL.WebGLRenderer and TL.GLTFLoader)

    local cam = TL.PerspectiveCamera:new(60, 4 / 3, 0.1, 1000)
    ok("camera takes the three.js signature",
        cam.fov == 60 and near(cam.aspect, 4 / 3) and cam.near == 0.1)
    cam.position:set(0, 1.2, 3.5)
    cam:updateMatrixWorld(true)
    ok("viewProjectionMatrix builds", cam:viewProjectionMatrix()[16] ~= nil)

    local scene = TL.Scene:new()
    scene:setBackground(0x171a21)
    ok("scene background", near(scene.background.r, 0x17 / 255))

    local sun = TL.DirectionalLight:new(0xfff5ec, 1)
    sun.position:set(0, 1, 0)
    scene:add(sun)
    ok("directional light with no target points down", near(sun:direction().y, -1))
    sun.position:set(0, 0, 1)
    ok("directional light aims at its target", near(sun:direction().z, -1))
    scene:add(TL.AmbientLight:new(0x484a5c, 1))

    local gltf = TL.GLTFLoader:new():load("assets/model/model3dtest.glb")
    ok("GLB loads", gltf and gltf.scene ~= nil)

    local meshes, skinned = 0, 0
    gltf.scene:traverse(function(o)
        if o.isMesh and o:isMesh() then meshes = meshes + 1 end
        if o.isSkinnedMesh and o:isSkinnedMesh() then skinned = skinned + 1 end
    end)
    ok("GLB yields meshes", meshes > 0)
    ok("GLB yields a skinned mesh", skinned > 0)
    ok("GLB yields animations", #gltf.animations > 0)
    ok("clip carries a duration", gltf.animations[1].duration > 0)

    local mat
    gltf.scene:traverse(function(o)
        if o.isMesh and o:isMesh() and not mat then mat = o.material end
    end)
    ok("material is a MeshStandardMaterial", mat and mat.type == "MeshStandardMaterial")
    ok("material yields a base colour array", mat and #mat:baseColorArray() == 4)
    ok("material keeps its texture", mat and mat.map ~= nil)

    local dae = TL.ColladaLoader:new():load("assets/model/model3dtest/Dancing.dae")
    ok("Collada loads", dae and dae.scene ~= nil)
    ok("Collada yields animations", #dae.animations > 0)

    local mixer = TL.AnimationMixer:new(gltf.scene)
    local action = mixer:clipAction(gltf.animations[1])
    ok("clipAction is cached", mixer:clipAction(gltf.animations[1]) == action)
    action:play()
    ok("action reports running", action:isRunning())
    mixer:update(0.1)
    ok("mixer advances the clock", near(action.time, 0.1, 1e-4))

    local sm
    gltf.scene:traverse(function(o)
        if o.isSkinnedMesh and o:isSkinnedMesh() and not sm then sm = o end
    end)
    local pal = sm and sm:palette()
    ok("skinning palette builds", pal and #pal > 0)

    action.time = gltf.animations[1].duration - 0.01
    mixer:update(0.05)
    ok("looping wraps", action.time < gltf.animations[1].duration)

    -- the drift fix that used to live in main.lua, now expressed through the API
    local a2 = TL.AnimationMixer:new(dae.scene):clipAction(dae.animations[1])
    a2:setDuration(gltf.animations[1].duration)
    ok("setDuration retimes the clip",
        near(a2.timeScale, dae.animations[1].duration / gltf.animations[1].duration))

    local fired = false
    local m3 = TL.AnimationMixer:new(gltf.scene)
    m3:addEventListener("finished", function() fired = true end)
    m3:clipAction(gltf.animations[1]):setLoop("once"):play()
    m3:update(gltf.animations[1].duration + 0.1)
    ok("a 'once' action fires finished", fired)

    -- PBR fields must survive the trip from file to material
    ok("material carries metalness", mat.metalness ~= nil)
    ok("material carries roughness", mat.roughness ~= nil)
    ok("material has an emissive colour", mat.emissive ~= nil)

    -- An omitted factor means the file never authored PBR, so it defaults to a
    -- dielectric rather than to glTF's own default of 1, which would turn every
    -- such material into a mirror.
    local bare = TL.MeshStandardMaterial:fromImporter{ baseColor = { 1, 1, 1, 1 } }
    ok("absent metalness defaults to 0", bare.metalness == 0)
    ok("absent roughness defaults to 1", bare.roughness == 1)
    -- the base Material carries the same fields, so the renderer never tests
    -- for them
    local plain = TL.Material:new()
    ok("a plain Material is a matte dielectric",
        plain.metalness == 0 and plain.roughness == 1 and plain.emissive ~= nil)

    -- Factors without a metallic-roughness map are ignored: exporters leave
    -- junk there (Mixamo writes 0.5/0.5 into everything), and a material with
    -- no map is a matte dielectric no matter what the numbers say.
    for _, value in ipairs{ 0.5, 1 } do
        local m = TL.MeshStandardMaterial:fromImporter{
            baseColor = { 1, 1, 1, 1 }, metallic = value, roughness = value,
        }
        ok(("metalness %s without a map is ignored"):format(value), m.metalness == 0)
        ok(("roughness %s without a map is ignored"):format(value), m.roughness == 1)
    end

    -- With a map present the factors multiply it, so they are kept
    local mapped = TL.MeshStandardMaterial:fromImporter{
        baseColor = { 1, 1, 1, 1 }, metallic = 0.5, roughness = 0.25,
        metallicRoughnessTexture = mat.map,
    }
    ok("factors are kept when a map is present",
        mapped.metalness == 0.5 and mapped.roughness == 0.25)

    -- the model in the demo is exactly this case
    local body
    gltf.scene:traverse(function(o)
        if o.isMesh and o:isMesh() and not body then body = o.material end
    end)
    ok("the demo model reads as matte and non-metal",
        body.metalness == 0 and body.roughness == 1,
        ("metal=%s rough=%s"):format(body.metalness, body.roughness))

    -- The defaults are ordinary fields on the material, so a caller can reach
    -- in and change them after loading -- they are a starting point, not a
    -- verdict.
    body.metalness, body.roughness = 0.8, 0.2
    ok("material values can be overridden by hand",
        body.metalness == 0.8 and body.roughness == 0.2)

    body.metalness, body.roughness = 0, 1

    -- and the importer must report absence as absence, not as a substituted 1
    local rawMat = require("importer.gltf"):load{
        path = "assets/model/model3dtest.glb", mesh = false, tex = false,
    }[1].material
    ok("importer reports the file's own factor", rawMat.metallic == 0.5,
        tostring(rawMat.metallic))

    local renderer = TL.WebGLRenderer:new()
    scene:add(gltf.scene)
    love.graphics.origin()
    local drew, err = pcall(function() renderer:render(scene, cam) end)
    ok("render runs", drew, tostring(err))
    ok("render counts meshes", renderer.info.render.meshes > 0)

    -- the renderer must cope with a material that has no PBR fields at all
    local plainScene = TL.Scene:new()
    plainScene:add(TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.Material:new()))
    plainScene:add(TL.AmbientLight:new(0xffffff, 1))
    local plainDrew, plainErr = pcall(function() renderer:render(plainScene, cam) end)
    ok("render survives a base Material", plainDrew, tostring(plainErr))

    ok("diffuseWrap is configurable", TL.WebGLRenderer:new{ diffuseWrap = 0 }.diffuseWrap == 0)

    -- Every uniform a variant declares must actually be sent. LOVE substitutes
    -- a default for one that never is, so a miss would not crash -- it would
    -- silently shade with whatever that default happens to be, which is far
    -- harder to notice than a hard error.
    --
    -- Read from the GENERATED source, so a part that declares something the
    -- renderer forgot is caught. Comment lines are stripped first: the word
    -- "uniform" appears in prose too, and matching it there yields phantom
    -- names.
    local ShaderLib = require "shader"
    local rendererSrc = love.filesystem.read("three/renderers/WebGLRenderer.lua")

    local sent = {}
    for name in rendererSrc:gmatch('send%("([%w_]+)"') do sent[name] = true end

    for _, variant in ipairs{ "static", "skinned" } do
        local src = ShaderLib:sourceFor{ skinning = variant == "skinned" }

        local missing = {}
        for line in (src .. "\n"):gmatch("([^\n]*)\n") do
            local code = line:gsub("//.*$", "")
            local name = code:match("^%s*uniform%s+[%w_]+%s+([%w_]+)")
            if name and not sent[name] then missing[#missing + 1] = name end
        end

        ok(("every uniform in the %s variant is sent"):format(variant),
            #missing == 0, table.concat(missing, ", "))
    end

    -- The point of splitting the variants: a static mesh must not pay for the
    -- bone array, which is 2048 vertex uniform components.
    local staticSrc  = ShaderLib:sourceFor{ skinning = false }
    local skinnedSrc = ShaderLib:sourceFor{ skinning = true  }
    ok("static variant declares no bone array", not staticSrc:find("u_bones", 1, true))
    ok("skinned variant declares the bone array", skinnedSrc:find("u_bones", 1, true) ~= nil)
    ok("both variants compile",
        pcall(function()
            ShaderLib:get{ skinning = false }
            ShaderLib:get{ skinning = true }
        end))

    -- and the renderer must actually pick between them
    local skinnedSeen, staticSeen = false, false
    gltf.scene:traverse(function(o)
        if o.isMesh and o:isMesh() then
            if renderer:_isSkinned(o) then skinnedSeen = true else staticSeen = true end
        end
    end)
    ok("skinned meshes are recognised", skinnedSeen)
    ok("a static mesh takes the static variant",
        not renderer:_isSkinned(TL.Mesh:new(TL.BoxGeometry:new(1,1,1), TL.Material:new())))

    -- Batching: the draw list is grouped by variant so each program is bound
    -- once -- all static meshes, then all skinned. Without it an interleaved
    -- scene would swap programs on nearly every draw.
    --
    -- Built deliberately interleaved, so a renderer that did not sort would
    -- swap on every mesh and the count would give it away.
    local mixed = TL.Scene:new()
    mixed:add(TL.AmbientLight:new(0xffffff, 1))

    local skinnedSource = {}
    gltf.scene:traverse(function(o)
        if o.isSkinnedMesh and o:isSkinnedMesh() then
            skinnedSource[#skinnedSource + 1] = o
        end
    end)

    for i = 1, 3 do
        mixed:add(TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new()))
        for _, sm in ipairs(skinnedSource) do mixed:add(sm:clone(false)) end
    end

    love.graphics.origin()
    renderer:render(mixed, cam)

    -- two variants in play means at most two binds for the whole frame
    ok("draws are batched by shader variant",
        renderer.info.render.shaderSwaps <= 2,
        ("%d swaps over %d meshes"):format(
            renderer.info.render.shaderSwaps, renderer.info.render.meshes))
    ok("the batched frame drew everything", renderer.info.render.meshes >= 6,
        tostring(renderer.info.render.meshes))

    local culling = TL.Scene:new()
    culling:add(TL.AmbientLight:new(0xffffff, 1))

    local inView = TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new())
    inView.position:set(0, 0, 0)
    culling:add(inView)

    local behind = TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new())
    behind.position:set(0, 0, 400)
    culling:add(behind)

    local farOff = TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new())
    farOff.position:set(900, 0, 0)
    culling:add(farOff)

    local cullCam = TL.PerspectiveCamera:new(50, 4 / 3, 0.1, 100)
    cullCam.position:set(0, 0, 6)
    cullCam:lookAt(0, 0, 0)

    love.graphics.origin()
    renderer:render(culling, cullCam)
    ok("offscreen meshes are culled", renderer.info.render.culled == 2,
        ("culled %d, drew %d"):format(renderer.info.render.culled,
                                      renderer.info.render.meshes))
    ok("the visible mesh survives culling", renderer.info.render.meshes == 1)

    local noCull = TL.WebGLRenderer:new{ frustumCulling = false }
    noCull:render(culling, cullCam)
    ok("culling can be turned off", noCull.info.render.meshes == 3,
        tostring(noCull.info.render.meshes))

    local exempt = TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new())
    exempt.position:set(900, 0, 0)
    exempt.frustumCulled = false
    culling:add(exempt)
    renderer:render(culling, cullCam)
    ok("frustumCulled = false is honoured", renderer.info.render.meshes == 2,
        tostring(renderer.info.render.meshes))
    culling:remove(exempt)

    -- opaque draws near-to-far so the depth test can reject early
    local ordering = TL.Scene:new()
    ordering:add(TL.AmbientLight:new(0xffffff, 1))
    local near = TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new())
    near.position:set(0, 0, 4)
    local far = TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new())
    far.position:set(0, 0, -4)
    ordering:add(far)
    ordering:add(near)
    ordering:updateMatrixWorld(true)

    renderer:render(ordering, cullCam)
    local bucket = renderer._staticList
    ok("opaque meshes sort near to far", bucket[1] == near and bucket[2] == far)

    -- transparency reverses it, since blending has to composite back to front
    near.material.transparent = true
    far.material.transparent = true
    renderer:render(ordering, cullCam)
    ok("transparent meshes sort far to near",
        renderer._staticList[1] == far and renderer._staticList[2] == near)

    -- and renderOrder overrides distance entirely
    near.material.transparent = false
    far.material.transparent = false
    near.renderOrder = 5
    renderer:render(ordering, cullCam)
    ok("renderOrder wins over distance", renderer._staticList[1] == far)

    -- FlyControls must work without the lib/util globals
    local ctl = TL.FlyControls:new(cam, { lockMouse = false })
    local moved, cerr = pcall(function()
        ctl:update(1 / 60); ctl:mousemoved(5, 2); ctl:wheelmoved(1)
    end)
    ok("FlyControls runs without lib.util globals", moved, tostring(cerr))
end

-- ── the classes added to close the three.js gap ──────────────────────────────

function T.additions()
    local TL = require "init"
    local V  = TL.Vector3

    print("\n-- additions --")

    -- Sphere
    local s = TL.Sphere:new(V:new(0, 0, 0), 2)
    ok("sphere contains an inside point", s:containsPoint(V:new(1, 0, 0)))
    ok("sphere rejects an outside point", not s:containsPoint(V:new(3, 0, 0)))
    ok("sphere distance is signed", near(s:distanceToPoint(V:new(5, 0, 0)), 3))

    -- a non-uniform scale must grow the radius by the LARGEST axis, so the
    -- result still encloses the true shape
    local scaled = TL.Sphere:new(V:new(0, 0, 0), 1)
                            :applyMatrix4(TL.Matrix4:new():makeScale(3, 1, 1))
    ok("sphere takes the largest axis scale", near(scaled.radius, 3))

    local grown = TL.Sphere:new(V:new(0, 0, 0), 1):expandByPoint(V:new(3, 0, 0))
    ok("sphere expands to swallow a point", grown:containsPoint(V:new(3, 0, 0)))
    ok("sphere does not over-expand", near(grown.radius, 2))

    -- Plane
    local ground = TL.Plane:new(V:new(0, 1, 0), 0)
    ok("plane distance is positive above", near(ground:distanceToPoint(V:new(0, 5, 0)), 5))
    ok("plane distance is negative below", near(ground:distanceToPoint(V:new(0, -2, 0)), -2))
    ok("plane projects onto itself",
        near(ground:projectPoint(V:new(1, 7, 2)).y, 0))

    local fromPoints = TL.Plane:new():setFromCoplanarPoints(
        V:new(0, 0, 0), V:new(1, 0, 0), V:new(0, 0, 1))
    ok("plane from three points is horizontal", near(math.abs(fromPoints.normal.y), 1))

    -- Ray
    local ray = TL.Ray:new(V:new(0, 0, 5), V:new(0, 0, -1))
    local hit = ray:intersectTriangle(
        V:new(-1, -1, 0), V:new(1, -1, 0), V:new(0, 1, 0), false, V:new())
    ok("ray hits a triangle", hit ~= nil and near(hit.z, 0))

    local miss = ray:intersectTriangle(
        V:new(5, 5, 0), V:new(6, 5, 0), V:new(5, 6, 0), false, V:new())
    ok("ray misses a triangle beside it", miss == nil)

    -- a triangle behind the origin is not on the ray
    local behind = TL.Ray:new(V:new(0, 0, -5), V:new(0, 0, -1)):intersectTriangle(
        V:new(-1, -1, 0), V:new(1, -1, 0), V:new(0, 1, 0), false, V:new())
    ok("ray ignores geometry behind it", behind == nil)

    ok("ray hits a sphere",
        ray:intersectSphere(TL.Sphere:new(V:new(0, 0, 0), 1), V:new()) ~= nil)
    ok("ray hits a box",
        ray:intersectBox(TL.Box3:new(V:new(-1, -1, -1), V:new(1, 1, 1)), V:new()) ~= nil)
    ok("ray hits a plane",
        near(ray:intersectPlane(TL.Plane:new(V:new(0, 0, 1), 0), V:new()).z, 0))

    -- applyMatrix4 must keep the direction a unit vector under scale
    local moved = TL.Ray:new(V:new(0, 0, 0), V:new(0, 0, -1))
                       :applyMatrix4(TL.Matrix4:new():makeScale(4, 4, 4))
    ok("ray direction stays normalised", near(moved.direction:length(), 1))

    -- Frustum
    local fcam = TL.PerspectiveCamera:new(60, 1, 0.1, 100)
    fcam.position:set(0, 0, 5)
    fcam:lookAt(0, 0, 0)
    fcam:updateMatrixWorld(true)

    local frustum = TL.Frustum:new():setFromProjectionMatrix(fcam:viewProjectionMatrix())
    ok("frustum contains a point ahead", frustum:containsPoint(V:new(0, 0, 0)))
    ok("frustum rejects a point behind", not frustum:containsPoint(V:new(0, 0, 50)))
    ok("frustum rejects a point far to the side", not frustum:containsPoint(V:new(500, 0, 0)))
    ok("frustum intersects a sphere at the origin",
        frustum:intersectsSphere(TL.Sphere:new(V:new(0, 0, 0), 1)))
    ok("frustum intersects a box at the origin",
        frustum:intersectsBox(TL.Box3:new(V:new(-1, -1, -1), V:new(1, 1, 1))))

    -- a sphere just outside still counts if its radius reaches in
    ok("frustum honours the radius",
        frustum:intersectsSphere(TL.Sphere:new(V:new(0, 0, 40), 45)))

    -- Raycaster
    local caster = TL.Raycaster:new()
    local target = TL.Mesh:new(TL.BoxGeometry:new(2, 2, 2),
                               TL.MeshStandardMaterial:new())
    local pickScene = TL.Scene:new()
    pickScene:add(target)
    pickScene:updateMatrixWorld(true)

    caster:set(V:new(0, 0, 10), V:new(0, 0, -1))
    local hits = caster:intersectObject(target, false)
    ok("raycaster hits a box", #hits > 0)
    ok("raycaster reports the object", hits[1] and hits[1].object == target)
    ok("raycaster measures to the near face", hits[1] and near(hits[1].distance, 9))
    ok("raycaster reports a uv", hits[1] and hits[1].uv ~= nil)

    -- hits arrive nearest first whatever order the geometry was walked in
    local sorted = true
    for i = 2, #hits do
        if hits[i].distance < hits[i - 1].distance then sorted = false end
    end
    ok("raycaster sorts nearest first", sorted)

    caster:set(V:new(0, 20, 10), V:new(0, 0, -1))
    ok("raycaster misses when aimed past", #caster:intersectObject(target, false) == 0)

    -- near/far must clip
    caster:set(V:new(0, 0, 10), V:new(0, 0, -1))
    caster.far = 5
    ok("raycaster honours far", #caster:intersectObject(target, false) == 0)
    caster.far = math.huge

    -- an invisible object is not picked
    target.visible = false
    ok("raycaster skips invisible objects", #caster:intersectObject(target, false) == 0)
    target.visible = true

    -- setFromCamera takes NDC, as in three.js; the centre of the screen must
    -- hit a box sitting on the camera's axis
    local pickCam = TL.PerspectiveCamera:new(60, 1, 0.1, 100)
    pickCam.position:set(0, 0, 10)
    pickCam:lookAt(0, 0, 0)
    pickCam:updateMatrixWorld(true)

    caster:setFromCamera({ x = 0, y = 0 }, pickCam)
    ok("setFromCamera aims through the screen centre",
        #caster:intersectObject(target, false) > 0)

    caster:setFromCamera({ x = 0.99, y = 0.99 }, pickCam)
    ok("setFromCamera misses at the corner",
        #caster:intersectObject(target, false) == 0)

    -- TorusGeometry
    local torus = TL.TorusGeometry:new(1, 0.3, 8, 16)
    ok("torus builds a mesh", torus.mesh ~= nil)
    ok("torus has vertices", #torus.vertices > 0)
    ok("torus indices are whole triangles", #torus.indices % 3 == 0)

    local tbox = torus:computeBoundingBox()
    ok("torus spans radius plus tube", near(tbox.max.x, 1.3, 1e-3))
    ok("torus is flat in the tube axis", near(tbox.max.z, 0.3, 1e-3))

    -- normals must point away from the tube centre, not from the origin: at the
    -- inner wall those two disagree, which is why the torus opts out of the
    -- convex orientation rule
    local inward = false
    for _, v in ipairs(torus.vertices) do
        local d = v[1] * v[6] + v[2] * v[7] + v[3] * v[8]
        if d < -0.5 then inward = true end
    end
    ok("torus has genuinely inward-facing normals", inward)

    -- lights
    local point = TL.PointLight:new(0xffffff, 2, 10)
    ok("point light carries distance", point.distance == 10)
    ok("point light decays by inverse square", point.decay == 2)
    ok("point light is a light", point:isLight() and point:isPointLight())

    local spot = TL.SpotLight:new(0xffffff, 1, 20, math.pi / 6, 0.3)
    ok("spot light carries its cone", near(spot.angle, math.pi / 6))
    spot.position:set(0, 5, 0)
    spot.target.position:set(0, 0, 0)
    ok("spot light aims at its target", near(spot:direction().y, -1))

    -- an unshaded light must still be safe to put in a scene
    local litScene = TL.Scene:new()
    litScene:add(point)
    litScene:add(spot)
    litScene:add(TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new()))

    local renderer = TL.WebGLRenderer:new()
    local drew, derr = pcall(function() renderer:render(litScene, fcam) end)
    ok("a scene with unshaded lights still renders", drew, tostring(derr))

    -- InstancedMesh
    local field = TL.InstancedMesh:new(TL.BoxGeometry:new(1, 1, 1),
                                       TL.MeshStandardMaterial:new(), 4)
    ok("instanced mesh reports its count", field.count == 4)
    ok("instanced mesh is a mesh", field:isMesh() and field:isInstancedMesh())

    local im = TL.Matrix4:new():makeTranslation(5, 0, 0)
    field:setMatrixAt(2, im)
    ok("instance matrix round-trips", near(field:getMatrixAt(2)[4], 5))

    -- out-of-range writes are ignored rather than growing the set silently
    field:setMatrixAt(99, im)
    ok("instance index is bounded", field.instanceMatrix[99] == nil)

    local instScene = TL.Scene:new()
    instScene:add(field)
    renderer:render(instScene, fcam)
    ok("instanced mesh draws once per instance", renderer.info.render.calls == 4)
    ok("instanced mesh counts as one mesh", renderer.info.render.meshes == 1)

    -- the object's own transform must carry the whole set
    field.position:set(100, 0, 0)
    instScene:updateMatrixWorld(true)
    local composed = renderer:_instanceMatrices(field)
    ok("instance transform composes onto the object", near(composed[2][4], 105))

    -- LOD
    local lod = TL.LOD:new()
    local hi = TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new())
    local lo = TL.Mesh:new(TL.BoxGeometry:new(1, 1, 1), TL.MeshStandardMaterial:new())
    lod:addLevel(hi, 0)
    lod:addLevel(lo, 10)

    local lodCam = TL.PerspectiveCamera:new(60, 1, 0.1, 100)

    lodCam.position:set(0, 0, 2)
    lodCam:updateMatrixWorld(true)
    lod:update(lodCam)
    ok("LOD picks the near level up close", hi.visible and not lo.visible)

    lodCam.position:set(0, 0, 50)
    lodCam:updateMatrixWorld(true)
    lod:update(lodCam)
    ok("LOD picks the far level at distance", lo.visible and not hi.visible)

    -- only the chosen level is drawn, which is what makes LOD need no renderer
    -- support at all
    local lodScene = TL.Scene:new()
    lodScene:add(lod)
    renderer:render(lodScene, lodCam)
    ok("LOD draws one level", renderer.info.render.meshes == 1)

    -- OrbitControls
    local ocam = TL.PerspectiveCamera:new(60, 1, 0.1, 100)
    ocam.position:set(0, 0, 5)
    local orbit = TL.OrbitControls:new(ocam, { enableDamping = false })
    ok("orbit seeds its radius from the camera", near(orbit.radius, 5))

    orbit:mousepressed(0, 0, 1)
    orbit:mousemoved(0, 0, 100, 0)
    orbit:update(1 / 60)
    ok("orbit keeps its distance while rotating",
        near(ocam.position:distanceTo(orbit.target), 5, 1e-3))
    ok("orbit actually moved the camera", math.abs(ocam.position.x) > 0.1)
    orbit:mousereleased(0, 0, 1)

    -- with no button held nothing should move
    local still = ocam.position:clone()
    orbit:mousemoved(0, 0, 100, 0)
    orbit:update(1 / 60)
    ok("orbit ignores movement with no button held",
        ocam.position:distanceTo(still) < 1e-6)

    orbit:wheelmoved(1)
    orbit:update(1 / 60)
    ok("wheel dollies in", ocam.position:distanceTo(orbit.target) < 5)

    -- the polar clamp must stop the camera reaching the pole, where the up
    -- vector flips and the view rolls over
    orbit:mousepressed(0, 0, 1)
    for _ = 1, 100 do orbit:mousemoved(0, 0, 0, -100) end
    orbit:update(1 / 60)
    orbit:mousereleased(0, 0, 1)
    ok("orbit clamps the polar angle", orbit.phi > 0 and orbit.phi < math.pi)

    orbit.enablePan = true
    local before = orbit.target:clone()
    orbit._dragging = "pan"
    orbit:mousemoved(0, 0, 50, 0)
    ok("right drag pans the target", orbit.target:distanceTo(before) > 0)

    -- TextureLoader
    local tex = TL.TextureLoader:new():load("assets/model/nothing-here.png")
    ok("texture loader returns nil for a missing file", tex == nil)

    local errored = false
    TL.TextureLoader:new():load("assets/model/nothing-here.png", nil, nil,
        function() errored = true end)
    ok("texture loader reports the error", errored)
end

function T.run()
    T.math()
    T.object3d()
    T.geometry()
    T.hygiene()
    T.integration()
    T.additions()

    print(("\n%d passed, %d failed"):format(passed, failed))
    for _, f in ipairs(failures) do print("  FAILED: " .. f) end

    return failed == 0
end

return T
