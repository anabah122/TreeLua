-- dae/skeleton.lua — <visual_scene> hierarchy, <controller> skins
--
--   skeleton.build_nodes(root, ctx)          -> flat node list (1-based)
--   skeleton.build_skin(root, ctrl, nodes)   -> { joints, inverseBind, ... }
--
-- Collada addresses bones by NAME (sid), not index, so the node list is also
-- indexed by name and sid to resolve them.

local xml      = require "importer.dae.xml"
local sources  = require "importer.dae.sources"
local common   = require "importer.common"
local matClass = require "math.mat4"

local skeleton = {}

skeleton.compose      = common.compose
skeleton.update_world = common.update_world
skeleton.palette      = common.palette

-- ── local transform of a <node> ──────────────────────────────────────────────
-- A node's transform is the ordered product of its transform elements:
-- <matrix>, <translate>, <rotate>, <scale>. Order matters and follows document
-- order, so children are walked rather than looked up by tag.
local function node_matrix(node)
    local m = matClass:new()
    local any = false

    for _, c in ipairs(node.children) do
        local t

        if c.name == "matrix" then
            t = sources.matrix(xml.numbers(c.text))
        elseif c.name == "translate" then
            local n = xml.numbers(c.text)
            t = common.compose({ n[1] or 0, n[2] or 0, n[3] or 0 }, nil, nil)
        elseif c.name == "rotate" then
            local n = xml.numbers(c.text)
            local ax, ay, az = n[1] or 0, n[2] or 0, n[3] or 0
            local angle = math.rad(n[4] or 0)
            local len = math.sqrt(ax*ax + ay*ay + az*az)
            if len > 0 then
                ax, ay, az = ax/len, ay/len, az/len
                local s = math.sin(angle / 2)
                t = common.compose(nil, { ax*s, ay*s, az*s, math.cos(angle/2) }, nil)
            end
        elseif c.name == "scale" then
            local n = xml.numbers(c.text)
            t = common.compose(nil, nil, { n[1] or 1, n[2] or 1, n[3] or 1 })
        end

        if t then
            m = any and matClass:new():mul(m, t) or t
            any = true
        end
    end

    return m
end

-- ── hierarchy ────────────────────────────────────────────────────────────────
function skeleton.build_nodes(root, ctx)
    local scene_node = xml.deep(root, "visual_scene")
    local nodes = {}
    local by_id, by_sid, by_name = {}, {}, {}

    local function visit(el, parent_idx)
        local idx = #nodes + 1
        local node = {
            index    = idx,
            name     = el.attr.name or el.attr.id or ("node_" .. idx),
            id       = el.attr.id,
            sid      = el.attr.sid,
            type     = el.attr.type,
            parent   = parent_idx,
            children = {},
            localMatrix = node_matrix(el),
            element  = el,
        }
        nodes[idx] = node

        if node.id   then by_id[node.id]     = idx end
        if node.sid  then by_sid[node.sid]   = idx end
        if node.name then by_name[node.name] = idx end

        if parent_idx then
            table.insert(nodes[parent_idx].children, idx)
        end

        -- geometry/controller attachments live on the node
        local ig = xml.find(el, "instance_geometry")
        if ig then node.geometry = ig.attr.url end

        local ic = xml.find(el, "instance_controller")
        if ic then
            node.controller = ic.attr.url
            local sk = xml.find(ic, "skeleton")
            if sk and sk.text then node.skeletonRoot = sk.text:match("%S+") end
        end

        -- bind_material maps primitive symbols to real materials
        local bm = ig and xml.find(ig, "bind_material") or ic and xml.find(ic, "bind_material")
        if bm then
            node.materialBindings = {}
            local tc = xml.find(bm, "technique_common")
            for _, im in ipairs(tc and xml.findall(tc, "instance_material") or {}) do
                node.materialBindings[im.attr.symbol] = im.attr.target
            end
        end

        for _, c in ipairs(el.children) do
            if c.name == "node" then visit(c, idx) end
        end
    end

    for _, el in ipairs(scene_node and xml.findall(scene_node, "node") or {}) do
        visit(el, nil)
    end

    -- Axis flip and unit conversion are applied once at the roots, so every
    -- descendant inherits them without touching bone math.
    local root_matrix = nil
    if ctx and (ctx.up_axis ~= "Y_UP" or (ctx.unit_scale or 1) ~= 1) then
        root_matrix = sources.up_matrix(ctx.up_axis, ctx.unit_scale)
    end

    nodes.by_id   = by_id
    nodes.by_sid  = by_sid
    nodes.by_name = by_name
    nodes.rootMatrix = root_matrix

    return nodes
end

-- ── skins ────────────────────────────────────────────────────────────────────
-- Returns the skin plus a per-position influence list, because collada indexes
-- weights by ORIGINAL position index (before de-indexing).
function skeleton.build_skin(root, ctrl_node, nodes)
    local skin_el = xml.find(ctrl_node, "skin")
    if not skin_el then return nil end

    local out = {
        name        = ctrl_node.attr.name or ctrl_node.attr.id,
        source      = skin_el.attr.source,   -- the geometry it deforms
        joints      = {},
        jointNames  = {},
        inverseBind = {},
    }

    -- bind_shape_matrix pre-transforms the mesh into bind space
    local bsm = xml.find(skin_el, "bind_shape_matrix")
    out.bindShapeMatrix = bsm and sources.matrix(xml.numbers(bsm.text)) or matClass:new()

    -- <joints> gives the name list and the inverse bind matrices
    local joints_el = xml.find(skin_el, "joints")
    if not joints_el then return nil end

    local jinputs = sources.inputs(joints_el)
    local name_src = jinputs.JOINT     and sources.read(root, jinputs.JOINT.source)
    local ibm_src  = jinputs.INV_BIND_MATRIX and sources.read(root, jinputs.INV_BIND_MATRIX.source)

    if not name_src then return nil end

    for k, jname in ipairs(name_src.data) do
        out.jointNames[k] = jname
        -- collada names bones; map each back to its node index
        local idx = nodes.by_sid[jname] or nodes.by_id[jname] or nodes.by_name[jname]
        out.joints[k] = idx or 1
        if ibm_src then
            out.inverseBind[k] = sources.matrix(ibm_src.data, (k-1) * 16)
        else
            out.inverseBind[k] = matClass:new()
        end
    end

    -- <vertex_weights> is the variable-length part: vcount says how many
    -- influences each vertex has, v holds (joint, weight) index pairs
    local vw = xml.find(skin_el, "vertex_weights")
    local vertex_joints = {}

    if vw then
        local winputs, wstride = sources.inputs(vw)
        local weight_src = winputs.WEIGHT and sources.read(root, winputs.WEIGHT.source)
        local joint_off  = winputs.JOINT  and winputs.JOINT.offset  or 0
        local weight_off = winputs.WEIGHT and winputs.WEIGHT.offset or 1

        local vcount_el = xml.find(vw, "vcount")
        local v_el      = xml.find(vw, "v")
        local vcounts = vcount_el and xml.numbers(vcount_el.text) or {}
        local v       = v_el and xml.numbers(v_el.text) or {}

        local cursor = 0
        for vi, n in ipairs(vcounts) do
            local list = {}
            for _ = 1, n do
                local ji = v[cursor + joint_off  + 1] or 0
                local wi = v[cursor + weight_off + 1] or 0
                local w  = weight_src and (weight_src.data[wi + 1] or 0) or 0
                -- joint index -1 means "bind shape", which we skip
                if ji >= 0 and w > 0 then
                    list[#list + 1] = { joint = ji, weight = w }
                end
                cursor = cursor + wstride
            end
            vertex_joints[vi] = list
        end
    end

    return out, vertex_joints
end

-- Find every <controller> keyed by its id, so nodes can resolve their url.
function skeleton.controllers(root)
    local out = {}
    local lib = xml.deep(root, "library_controllers")
    for _, c in ipairs(lib and xml.findall(lib, "controller") or {}) do
        if c.attr.id then out[c.attr.id] = c end
    end
    return out
end

return skeleton
