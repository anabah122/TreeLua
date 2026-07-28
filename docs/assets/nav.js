// Общее меню слева, генерируется на клиенте, чтобы не дублировать разметку
// на полусотне страниц. Список классов — зеркало three/ и math/.
const TREE_NAV = [
  { title: "Math", items: [
    "Vector3", "Vector4", "Matrix4", "Quaternion", "Euler", "Color",
    "Box3", "Sphere", "Plane", "Ray", "Frustum",
  ]},
  { title: "Core", items: [
    "Object3D", "Group", "BufferGeometry", "Raycaster",
  ]},
  { title: "Scenes", items: ["Scene"] },
  { title: "Objects", items: [
    "Mesh", "SkinnedMesh", "Skeleton", "InstancedMesh", "LOD", "Model",
  ]},
  { title: "Geometries", items: [
    "BoxGeometry", "SphereGeometry", "PlaneGeometry", "CylinderGeometry",
    "ConeGeometry", "TorusGeometry",
  ]},
  { title: "Materials", items: ["Material", "MeshStandardMaterial"] },
  { title: "Cameras", items: [
    "Camera", "PerspectiveCamera", "OrthographicCamera",
  ]},
  { title: "Lights", items: [
    "Light", "AmbientLight", "DirectionalLight", "PointLight", "SpotLight",
  ]},
  { title: "Renderers", items: ["WebGLRenderer"] },
  { title: "Loaders", items: [
    "Loader", "GLTFLoader", "ColladaLoader", "TextureLoader",
  ]},
  { title: "Animation", items: [
    "AnimationClip", "AnimationAction", "AnimationMixer", "PoseAccumulator",
  ]},
  { title: "Controls", items: ["FlyControls", "OrbitControls"] },
];

function renderNav() {
  const current = document.body.getAttribute("data-page");
  const nav = document.createElement("nav");
  nav.className = "sidebar";

  const depth = document.body.getAttribute("data-depth") || "";

  nav.innerHTML = `
    <h1><a href="${depth}index.html" style="color:inherit;text-decoration:none">TreeLua docs</a></h1>
    <p class="subtitle" lang="en">local reference for TreeEngine</p>
    <p class="subtitle" lang="ru">локальная справка по TreeEngine</p>
    <div class="lang-toggle">
      <button data-lang="en">EN</button>
      <button data-lang="ru">RU</button>
    </div>
    <input class="search" type="search" placeholder="Search / Поиск..." oninput="filterNav(this.value)">
  `;

  for (const group of TREE_NAV) {
    const details = document.createElement("details");
    details.open = group.items.includes(current);
    const summary = document.createElement("summary");
    summary.textContent = group.title;
    details.appendChild(summary);

    const ul = document.createElement("ul");
    for (const name of group.items) {
      const li = document.createElement("li");
      const a = document.createElement("a");
      a.href = `${depth}page/${name}.html`;
      a.textContent = name;
      if (name === current) a.className = "active";
      li.appendChild(a);
      ul.appendChild(li);
    }
    details.appendChild(ul);
    nav.appendChild(details);
  }

  document.body.insertBefore(nav, document.body.firstChild);
}

function filterNav(query) {
  query = query.trim().toLowerCase();
  document.querySelectorAll("nav.sidebar details").forEach(details => {
    let anyVisible = false;
    details.querySelectorAll("li").forEach(li => {
      const match = li.textContent.toLowerCase().includes(query);
      li.style.display = match ? "" : "none";
      if (match) anyVisible = true;
    });
    details.style.display = anyVisible ? "" : "none";
    if (query) details.open = true;
  });
}

document.addEventListener("DOMContentLoaded", renderNav);
