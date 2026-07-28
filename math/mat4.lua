
local vectors = {}

function vectors.subtract(v1,v2,v3, v4,v5,v6)
    return v1-v4, v2-v5, v3-v6
end

function vectors.add(v1,v2,v3, v4,v5,v6)
    return v1+v4, v2+v5, v3+v6
end

function vectors.scalarMultiply(scalar, v1,v2,v3)
    return v1*scalar, v2*scalar, v3*scalar
end

function vectors.crossProduct(a1,a2,a3, b1,b2,b3)
    return a2*b3 - a3*b2, a3*b1 - a1*b3, a1*b2 - a2*b1
end

function vectors.dotProduct(a1,a2,a3, b1,b2,b3)
    return a1*b1 + a2*b2 + a3*b3
end

function vectors.normalize(x,y,z)
    local mag = math.sqrt(x^2 + y^2 + z^2)
    if mag ~= 0 then
        return x/mag, y/mag, z/mag
    else
        return 0, 0, 0
    end
end

function vectors.magnitude(x,y,z)
    return math.sqrt(x^2 + y^2 + z^2)
end



local vectorCrossProduct = vectors.crossProduct
local vectorDotProduct = vectors.dotProduct
local vectorNormalize = vectors.normalize






local matrix = {}
matrix.__index = matrix

function matrix:new()
    local self = setmetatable({}, matrix)

    -- initialize a matrix as the identity matrix
    self[1],  self[2],  self[3],  self[4]  = 1, 0, 0, 0
    self[5],  self[6],  self[7],  self[8]  = 0, 1, 0, 0
    self[9],  self[10], self[11], self[12] = 0, 0, 1, 0
    self[13], self[14], self[15], self[16] = 0, 0, 0, 1

    return self
end


function matrix:newFromArr( arr )
    assert(#arr==16, 'create mat4 from array with len ~= 16')

    local self = setmetatable({}, matrix)
    for i,v in ipairs( arr ) do self[i]=v end
    
    return self
end



function matrix:__tostring()
    return ("%f\t%f\t%f\t%f\n%f\t%f\t%f\t%f\n%f\t%f\t%f\t%f\n%f\t%f\t%f\t%f"):format(unpack(self))
end



function matrix:setOrthographicMatrix(fov, size, near, far, aspectRatio)
    local top = size * math.tan(fov/2)
    local bottom = -1*top
    local right = top * aspectRatio
    local left = -1*right

    self[1],  self[2],  self[3],  self[4]  = 2/(right-left), 0, 0, -1*(right+left)/(right-left)
    self[5],  self[6],  self[7],  self[8]  = 0, 2/(top-bottom), 0, -1*(top+bottom)/(top-bottom)
    self[9],  self[10], self[11], self[12] = 0, 0, -2/(far-near), -(far+near)/(far-near)
    self[13], self[14], self[15], self[16] = 0, 0, 0, 1
    return self
end



function matrix:setTransformationMatrix(translation, rotation, scale)
    -- translations
    self[4]  = translation[1]
    self[8]  = translation[2]
    self[12] = translation[3]

    
    local ca, cb, cc = math.cos(rotation[3]), math.cos(rotation[2]), math.cos(rotation[1])
    local sa, sb, sc = math.sin(rotation[3]), math.sin(rotation[2]), math.sin(rotation[1])
    self[1], self[2],  self[3]  = ca*cb, ca*sb*sc - sa*cc, ca*sb*cc + sa*sc
    self[5], self[6],  self[7]  = sa*cb, sa*sb*sc + ca*cc, sa*sb*cc - ca*sc
    self[9], self[10], self[11] = -sb, cb*sc, cb*cc

    -- scale
    local sx, sy, sz = scale[1], scale[2], scale[3]
    self[1], self[2],  self[3]  = self[1] * sx, self[2]  * sy, self[3]  * sz
    self[5], self[6],  self[7]  = self[5] * sx, self[6]  * sy, self[7]  * sz
    self[9], self[10], self[11] = self[9] * sx, self[10] * sy, self[11] * sz

    -- fourth row is not used, just set it to the fourth row of the identity matrix
    self[13], self[14], self[15], self[16] = 0, 0, 0, 1
    return self

end


function matrix:setProjectionMatrix(fov, near, far, aspectRatio)
    local top = near * math.tan(fov/2)
    local bottom = -1*top
    local right = top * aspectRatio
    local left = -1*right

    self[1],  self[2],  self[3],  self[4]  = 2*near/(right-left), 0, (right+left)/(right-left), 0
    self[5],  self[6],  self[7],  self[8]  = 0, 2*near/(top-bottom), (top+bottom)/(top-bottom), 0
    self[9],  self[10], self[11], self[12] = 0, 0, -1*(far+near)/(far-near), -2*far*near/(far-near)
    self[13], self[14], self[15], self[16] = 0, 0, -1, 0
    return self
end


function matrix:setViewMatrix(eye, target, up)
    local z1, z2, z3 = vectorNormalize(eye[1] - target[1], eye[2] - target[2], eye[3] - target[3])
    local x1, x2, x3 = vectorNormalize(vectorCrossProduct(up[1], up[2], up[3], z1, z2, z3))
    local y1, y2, y3 = vectorCrossProduct(z1, z2, z3, x1, x2, x3)

    self[1],  self[2],  self[3],  self[4]  = x1, x2, x3, -1*vectorDotProduct(x1, x2, x3, eye[1], eye[2], eye[3])
    self[5],  self[6],  self[7],  self[8]  = y1, y2, y3, -1*vectorDotProduct(y1, y2, y3, eye[1], eye[2], eye[3])
    self[9],  self[10], self[11], self[12] = z1, z2, z3, -1*vectorDotProduct(z1, z2, z3, eye[1], eye[2], eye[3])
    self[13], self[14], self[15], self[16] = 0, 0, 0, 1
    return self
end



function matrix:mul(A,B)

    -- row 1
    self[1]  = A[1]*B[1]  + A[2]*B[5]  + A[3]*B[9]  + A[4]*B[13]
    self[2]  = A[1]*B[2]  + A[2]*B[6]  + A[3]*B[10] + A[4]*B[14]
    self[3]  = A[1]*B[3]  + A[2]*B[7]  + A[3]*B[11] + A[4]*B[15]
    self[4]  = A[1]*B[4]  + A[2]*B[8]  + A[3]*B[12] + A[4]*B[16]

    -- row 2
    self[5]  = A[5]*B[1]  + A[6]*B[5]  + A[7]*B[9]  + A[8]*B[13]
    self[6]  = A[5]*B[2]  + A[6]*B[6]  + A[7]*B[10] + A[8]*B[14]
    self[7]  = A[5]*B[3]  + A[6]*B[7]  + A[7]*B[11] + A[8]*B[15]
    self[8]  = A[5]*B[4]  + A[6]*B[8]  + A[7]*B[12] + A[8]*B[16]

    -- row 3
    self[9]  = A[9]*B[1]  + A[10]*B[5] + A[11]*B[9] + A[12]*B[13]
    self[10] = A[9]*B[2]  + A[10]*B[6] + A[11]*B[10]+ A[12]*B[14]
    self[11] = A[9]*B[3]  + A[10]*B[7] + A[11]*B[11]+ A[12]*B[15]
    self[12] = A[9]*B[4]  + A[10]*B[8] + A[11]*B[12]+ A[12]*B[16]

    -- row 4
    self[13] = A[13]*B[1] + A[14]*B[5] + A[15]*B[9] + A[16]*B[13]
    self[14] = A[13]*B[2] + A[14]*B[6] + A[15]*B[10]+ A[16]*B[14]
    self[15] = A[13]*B[3] + A[14]*B[7] + A[15]*B[11]+ A[16]*B[15]
    self[16] = A[13]*B[4] + A[14]*B[8] + A[15]*B[12]+ A[16]*B[16]

    return self
end



-- Транспонирование. Возвращает новую матрицу.
-- Нужно на границе с шейдером: здесь матрицы построчные, GLSL читает mat4
-- по столбцам.
function matrix:transpose()
    local m = self
    return matrix:newFromArr{
        m[1], m[5], m[9],  m[13],
        m[2], m[6], m[10], m[14],
        m[3], m[7], m[11], m[15],
        m[4], m[8], m[12], m[16],
    }
end


-- Умножение матрицы на вектор-столбец (x,y,z,w). Возвращает x',y',z',w'.
function matrix:mulVec4(x, y, z, w)
    local m = self
    return m[1]*x  + m[2]*y  + m[3]*z  + m[4]*w,
           m[5]*x  + m[6]*y  + m[7]*z  + m[8]*w,
           m[9]*x  + m[10]*y + m[11]*z + m[12]*w,
           m[13]*x + m[14]*y + m[15]*z + m[16]*w
end

-- Shared cofactor expansion, used by both determinant() and inverse().
-- Returns the four first-row cofactors plus the 2x2 minors of the bottom
-- half, which the full adjugate needs anyway.
local function cofactors(m)
    -- 2x2 minors of rows 3-4
    local s0 = m[9]*m[14]  - m[13]*m[10]
    local s1 = m[9]*m[15]  - m[13]*m[11]
    local s2 = m[9]*m[16]  - m[13]*m[12]
    local s3 = m[10]*m[15] - m[14]*m[11]
    local s4 = m[10]*m[16] - m[14]*m[12]
    local s5 = m[11]*m[16] - m[15]*m[12]

    local c0 =  m[6]*s5 - m[7]*s4 + m[8]*s3
    local c1 = -m[5]*s5 + m[7]*s2 - m[8]*s1
    local c2 =  m[5]*s4 - m[6]*s2 + m[8]*s0
    local c3 = -m[5]*s3 + m[6]*s1 - m[7]*s0

    return c0, c1, c2, c3, s0, s1, s2, s3, s4, s5
end

function matrix:determinant()
    local m = self
    local c0, c1, c2, c3 = cofactors(m)
    return m[1]*c0 + m[2]*c1 + m[3]*c2 + m[4]*c3
end

-- Обратная матрица (возвращает новую матрицу или nil)
function matrix:inverse()
    local det = self:determinant()
    if math.abs(det) < 1e-12 then
        return nil
    end

    local m = self
    local inv = matrix:new()

    -- 2x2 minors of the top half, mirroring the bottom-half ones in cofactors()
    local t0 = m[1]*m[6]  - m[5]*m[2]
    local t1 = m[1]*m[7]  - m[5]*m[3]
    local t2 = m[1]*m[8]  - m[5]*m[4]
    local t3 = m[2]*m[7]  - m[6]*m[3]
    local t4 = m[2]*m[8]  - m[6]*m[4]
    local t5 = m[3]*m[8]  - m[7]*m[4]

    local c0, c1, c2, c3, s0, s1, s2, s3, s4, s5 = cofactors(m)

    local invDet = 1.0 / det

    -- adjugate = transpose of the cofactor matrix, scaled by 1/det
    inv[1]  =  c0 * invDet
    inv[2]  = (-m[2]*s5 + m[3]*s4 - m[4]*s3) * invDet
    inv[3]  = ( m[14]*t5 - m[15]*t4 + m[16]*t3) * invDet
    inv[4]  = (-m[10]*t5 + m[11]*t4 - m[12]*t3) * invDet

    inv[5]  =  c1 * invDet
    inv[6]  = ( m[1]*s5 - m[3]*s2 + m[4]*s1) * invDet
    inv[7]  = (-m[13]*t5 + m[15]*t2 - m[16]*t1) * invDet
    inv[8]  = ( m[9]*t5 - m[11]*t2 + m[12]*t1) * invDet

    inv[9]  =  c2 * invDet
    inv[10] = (-m[1]*s4 + m[2]*s2 - m[4]*s0) * invDet
    inv[11] = ( m[13]*t4 - m[14]*t2 + m[16]*t0) * invDet
    inv[12] = (-m[9]*t4 + m[10]*t2 - m[12]*t0) * invDet

    inv[13] =  c3 * invDet
    inv[14] = ( m[1]*s3 - m[2]*s1 + m[3]*s0) * invDet
    inv[15] = (-m[13]*t3 + m[14]*t1 - m[15]*t0) * invDet
    inv[16] = ( m[9]*t3 - m[10]*t1 + m[11]*t0) * invDet

    return inv
end



function matrix:mulPoint(point)
    local x, y, z = point.x or point[1], point.y or point[2], point.z or point[3]
    local w = 1

    local nx = self[1]*x + self[2]*y + self[3]*z + self[4]*w
    local ny = self[5]*x + self[6]*y + self[7]*z + self[8]*w
    local nz = self[9]*x + self[10]*y + self[11]*z + self[12]*w
    local nw = self[13]*x + self[14]*y + self[15]*z + self[16]*w

    if nw ~= 0 and nw ~= 1 then
        nx, ny, nz = nx / nw, ny / nw, nz / nw
    end

    return {x = nx, y = ny, z = nz}
end




function matrix:mulVec3(vec)
    local x, y, z = vec.x or vec[1], vec.y or vec[2], vec.z or vec[3]
    local w = 0

    local nx = self[1]*x + self[2]*y + self[3]*z + self[4]*w
    local ny = self[5]*x + self[6]*y + self[7]*z + self[8]*w
    local nz = self[9]*x + self[10]*y + self[11]*z + self[12]*w

    return {x = nx, y = ny, z = nz}
end


return matrix