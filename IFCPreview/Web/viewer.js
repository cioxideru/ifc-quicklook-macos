// IFC preview: parse with web-ifc (WASM), render with three.js.
// All URLs are relative so the same page works under ifcql://app/ (Quick Look) and http://localhost (dev).
import * as THREE from './vendor/three.module.js';
import { OrbitControls } from './vendor/OrbitControls.js';
import { IfcAPI, LogLevel } from './vendor/web-ifc-api.js';

const params = new URLSearchParams(location.search);
const fileName = params.get('name') || 'model.ifc';
const fileSize = Number(params.get('size') || 0);
const tooBig = params.get('tooBig') === '1';
// Identifies the load this page belongs to, so a stale page cannot be served a newer file's bytes.
const modelToken = params.get('t') || '';

const overlay = document.getElementById('overlay');
const overlayTitle = overlay.querySelector('.title');
const overlayDetail = overlay.querySelector('.detail');
const hud = document.getElementById('hud');
const canvas = document.getElementById('c');

const post = (type, extra = {}) => {
  try { window.webkit?.messageHandlers?.host?.postMessage({ type, ...extra }); } catch (_) { /* not in WKWebView */ }
};
// Yield to the event loop so the overlay can repaint. Not requestAnimationFrame: that is
// suspended while the web view is not yet on screen (Quick Look shows it only after we report ready).
const yieldToUI = () => new Promise((r) => setTimeout(r, 0));
const t0 = performance.now();
const timings = [];
function mark(stage) {
  timings.push(`${stage} ${Math.round(performance.now() - t0)}ms`);
  console.info('[ifc]', timings[timings.length - 1]);
}

function setStatus(title, detail = '') {
  overlay.hidden = false;
  overlay.classList.remove('error');
  overlayTitle.textContent = title;
  overlayDetail.textContent = detail;
}
// `detail` is shown on screen; `logDetail` is what reaches the host log, so it must never
// carry the file name (the host writes it to the unified log).
function showError(title, detail = '', logDetail = detail) {
  overlay.hidden = false;
  overlay.classList.add('error');
  overlayTitle.textContent = title;
  overlayDetail.textContent = detail;
  post('error', { message: `${title}: ${logDetail}`.trim() });
}
// The inline script in index.html catches failures that happen before this module runs
// (a missing vendor file makes the whole module graph fail, so nothing here executes).
window.addEventListener('error', (e) => showError('Viewer error', e.message || String(e.error || e)));
window.addEventListener('unhandledrejection', (e) => showError('Viewer error', String(e.reason?.message || e.reason)));

function formatBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

// Colours by IFC type, used for elements whose file defines no surface style (web-ifc then
// reports plain white 1,1,1,1). Matched by prefix, first hit wins, so a more specific type
// must come before any entry that is a prefix of it. [r, g, b, alpha] as display (sRGB) values.
const TYPE_PALETTE = [
  ['IfcWindow',        [0.50, 0.72, 0.92, 0.45]],
  ['IfcCurtainWall',   [0.55, 0.75, 0.90, 0.55]],
  ['IfcPlate',         [0.62, 0.78, 0.90, 0.55]],
  ['IfcDoor',          [0.65, 0.42, 0.24, 1]],
  ['IfcWall',          [0.86, 0.82, 0.74, 1]],
  ['IfcSlab',          [0.66, 0.66, 0.66, 1]],
  ['IfcRoof',          [0.68, 0.34, 0.25, 1]],
  ['IfcColumn',        [0.52, 0.53, 0.60, 1]],
  ['IfcBeam',          [0.69, 0.54, 0.35, 1]],
  ['IfcMember',        [0.72, 0.61, 0.43, 1]],
  ['IfcStair',         [0.61, 0.56, 0.48, 1]],
  ['IfcRamp',          [0.61, 0.56, 0.48, 1]],
  ['IfcRailing',       [0.43, 0.50, 0.55, 1]],
  ['IfcCovering',      [0.88, 0.85, 0.78, 1]],
  ['IfcFooting',       [0.49, 0.49, 0.49, 1]],
  ['IfcPile',          [0.49, 0.49, 0.49, 1]],
  ['IfcFurnishing',    [0.77, 0.56, 0.37, 1]],
  ['IfcSanitary',      [0.92, 0.92, 0.94, 1]],
  ['IfcPipe',          [0.31, 0.62, 0.82, 1]],
  ['IfcDuct',          [0.55, 0.70, 0.78, 1]],
  ['IfcCable',         [0.85, 0.45, 0.25, 1]],
  ['IfcFlow',          [0.35, 0.66, 0.79, 1]],
  ['IfcDistribution',  [0.35, 0.66, 0.79, 1]],
  ['IfcMechanicalFastener', [0.40, 0.40, 0.40, 1]],
  ['IfcFastener',      [0.40, 0.40, 0.40, 1]],
  ['IfcGeographic',    [0.50, 0.65, 0.42, 1]],
  ['IfcSite',          [0.50, 0.65, 0.42, 1]],
  // IfcSpaceHeater is real building equipment and must not fall through to the IfcSpace row,
  // which is a prefix of it.
  ['IfcSpaceHeater',   [0.35, 0.66, 0.79, 1]],
  ['IfcSpace',         [0.60, 0.80, 0.60, 0.25]],
  ['IfcBuildingElementProxy', [0.74, 0.71, 0.66, 1]],
];
const DEFAULT_TYPE_COLOR = [0.78, 0.78, 0.78, 1];
const typeColorCache = new Map();
function colorForType(typeName) {
  let c = typeColorCache.get(typeName);
  if (!c) {
    const hit = TYPE_PALETTE.find(([prefix]) => typeName.startsWith(prefix));
    const [x, y, z, w] = hit ? hit[1] : DEFAULT_TYPE_COLOR;
    c = { x, y, z, w };
    typeColorCache.set(typeName, c);
  }
  return c;
}
const isUnstyled = (c) => c.x === 1 && c.y === 1 && c.z === 1 && c.w === 1;

// Both the palette and IFC surface styles give display (sRGB) values, but three.js treats a
// colour attribute as being in the linear working space and re-encodes it on output. Convert
// once per placed geometry so surfaces render at the colour they were authored at.
const _srgb = new THREE.Color();
const _rgba = { r: 0, g: 0, b: 0, a: 1 };
function toWorkingRGBA(x, y, z, w) {
  _srgb.setRGB(x, y, z, THREE.SRGBColorSpace);
  _rgba.r = _srgb.r; _rgba.g = _srgb.g; _rgba.b = _srgb.b; _rgba.a = w;
  return _rgba;
}

// Site, terrain, spaces and annotations routinely dwarf the building, so they are drawn but
// left out of the box the camera is framed on.
const FRAMING_EXCLUDED = new Set(['IfcSite', 'IfcSpace', 'IfcGeographicElement', 'IfcAnnotation']);

/** Accumulates transformed triangles for one material into a single BufferGeometry. */
class MeshBuilder {
  constructor() { this.positions = []; this.normals = []; this.colors = []; this.indices = []; this.vertexCount = 0; this.triangleCount = 0; }
  append(vertexData, indexData, matrix, rgba, framingBox) {
    const count = vertexData.length / 6;
    const pos = new Float32Array(count * 3);
    const nor = new Float32Array(count * 3);
    // itemSize 4: three.js only honours per-vertex alpha when the colour attribute has four
    // components, which is what lets each element keep the alpha its style or type asks for.
    const col = new Float32Array(count * 4);
    const normalMatrix = new THREE.Matrix3().getNormalMatrix(matrix);
    const v = new THREE.Vector3();
    for (let i = 0; i < count; i++) {
      v.set(vertexData[i * 6], vertexData[i * 6 + 1], vertexData[i * 6 + 2]).applyMatrix4(matrix);
      pos[i * 3] = v.x; pos[i * 3 + 1] = v.y; pos[i * 3 + 2] = v.z;
      if (framingBox) framingBox.expandByPoint(v);
      v.set(vertexData[i * 6 + 3], vertexData[i * 6 + 4], vertexData[i * 6 + 5]).applyMatrix3(normalMatrix).normalize();
      nor[i * 3] = v.x; nor[i * 3 + 1] = v.y; nor[i * 3 + 2] = v.z;
      col[i * 4] = rgba.r; col[i * 4 + 1] = rgba.g; col[i * 4 + 2] = rgba.b; col[i * 4 + 3] = rgba.a;
    }
    const idx = new Uint32Array(indexData.length);
    const base = this.vertexCount;
    for (let i = 0; i < indexData.length; i++) idx[i] = indexData[i] + base;
    this.positions.push(pos); this.normals.push(nor); this.colors.push(col); this.indices.push(idx);
    this.vertexCount += count;
    this.triangleCount += indexData.length / 3;
  }
  build() {
    if (this.vertexCount === 0) return null;
    const concat = (chunks, total, Type) => {
      const out = new Type(total); let o = 0;
      for (const c of chunks) { out.set(c, o); o += c.length; }
      return out;
    };
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(concat(this.positions, this.vertexCount * 3, Float32Array), 3));
    g.setAttribute('normal', new THREE.BufferAttribute(concat(this.normals, this.vertexCount * 3, Float32Array), 3));
    g.setAttribute('color', new THREE.BufferAttribute(concat(this.colors, this.vertexCount * 4, Float32Array), 4));
    g.setIndex(new THREE.BufferAttribute(concat(this.indices, this.triangleCount * 3, Uint32Array), 1));
    this.positions = this.normals = this.colors = this.indices = null;
    return g;
  }
}

async function loadModel() {
  setStatus('Loading parser…', fileName);
  const api = new IfcAPI();
  api.SetWasmPath('./vendor/', true);
  await api.Init(undefined, /* forceSingleThread */ true);
  api.SetLogLevel(LogLevel.LOG_LEVEL_ERROR);
  mark('init');

  setStatus('Reading file…', `${fileName} · ${formatBytes(fileSize)}`);
  const response = await fetch(`./model.ifc?t=${encodeURIComponent(modelToken)}`);
  if (!response.ok) throw new Error(`Cannot read file (${response.status})`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  mark('read');

  setStatus('Parsing IFC…', `${fileName} · ${formatBytes(bytes.length)}`);
  await yieldToUI();
  const head = new TextDecoder().decode(bytes.subarray(0, 64));
  if (!head.trimStart().startsWith('ISO-10303-21')) {
    throw new Error('Not an IFC file: it does not start with the ISO-10303-21 (STEP) header.');
  }
  let modelID;
  try {
    modelID = api.OpenModel(bytes, { COORDINATE_TO_ORIGIN: true });
  } catch (e) {
    throw new Error(`web-ifc failed to parse this file (${e?.message || e}).`);
  }
  if (modelID === undefined || modelID < 0) throw new Error('web-ifc could not open this file.');
  mark('parse');
  let schema = '';
  try { schema = api.GetModelSchema(modelID) || ''; } catch (_) { /* older API */ }

  setStatus('Building geometry…', schema ? `${fileName} · ${schema}` : fileName);
  await yieldToUI();
  const opaque = new MeshBuilder();
  const transparent = new MeshBuilder();
  const framingBox = new THREE.Box3();
  let elements = 0;
  let typeColored = 0;
  const matrix = new THREE.Matrix4();
  api.StreamAllMeshes(modelID, (flatMesh) => {
    const geoms = flatMesh.geometries;
    const n = geoms.size();
    if (n === 0) return;
    const typeName = api.GetNameFromTypeCode(api.GetLineType(modelID, flatMesh.expressID)) || '';
    const framing = FRAMING_EXCLUDED.has(typeName) ? null : framingBox;
    for (let i = 0; i < n; i++) {
      const placed = geoms.get(i);
      const geometry = api.GetGeometry(modelID, placed.geometryExpressID);
      const vertexData = api.GetVertexArray(geometry.GetVertexData(), geometry.GetVertexDataSize());
      const indexData = api.GetIndexArray(geometry.GetIndexData(), geometry.GetIndexDataSize());
      matrix.fromArray(placed.flatTransformation);
      let color = placed.color;
      if (isUnstyled(color)) {
        color = colorForType(typeName);
        typeColored++;
      }
      const rgba = toWorkingRGBA(color.x, color.y, color.z, color.w);
      (rgba.a < 1 ? transparent : opaque).append(vertexData, indexData, matrix, rgba, framing);
      geometry.delete();
    }
    elements++;
  });
  api.CloseModel(modelID);
  mark('geometry');

  return {
    schema, elements, typeColored, framingBox,
    triangles: opaque.triangleCount + transparent.triangleCount,
    opaque: opaque.build(), transparent: transparent.build(),
  };
}

const FOV = 45;

function setupScene(model) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  const scene = new THREE.Scene();
  const dark = matchMedia('(prefers-color-scheme: dark)');
  const applyTheme = () => { renderer.setClearColor(dark.matches ? 0x1c1c1e : 0xeef0f3, 1); requestRender(); };

  const root = new THREE.Group();
  if (model.opaque) {
    root.add(new THREE.Mesh(model.opaque, new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide })));
  }
  if (model.transparent) {
    // opacity stays at 1 so the per-vertex alpha decides: geometry the file marks fully
    // transparent stays invisible, and each element keeps its own degree of transparency.
    root.add(new THREE.Mesh(model.transparent, new THREE.MeshLambertMaterial({
      vertexColors: true, side: THREE.DoubleSide, transparent: true, opacity: 1, depthWrite: false,
    })));
  }
  scene.add(root);

  // Frame on the building, falling back to everything when the model is only site or spaces.
  let box = model.framingBox && !model.framingBox.isEmpty()
    ? model.framingBox
    : new THREE.Box3().setFromObject(root);
  if (box.isEmpty()) box = new THREE.Box3(new THREE.Vector3(-1, -1, -1), new THREE.Vector3(1, 1, 1));
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const radius = Math.max(size.length() / 2, 0.01);

  // Fit the model in whichever of the two field of view angles is tighter, so a narrow
  // preview pane does not crop it.
  function fitDistance(aspect) {
    const vHalf = THREE.MathUtils.degToRad(FOV / 2);
    const hHalf = Math.atan(Math.tan(vHalf) * Math.max(aspect, 0.0001));
    return radius / Math.sin(Math.min(vHalf, hHalf)) * 1.1;
  }

  // Near is kept small in absolute terms so surfaces stay visible when the user zooms in on a
  // large model, and the orbit distance is clamped so the camera cannot cross either plane.
  const near = Math.max(radius / 1000, 0.01);
  const far = Math.max(radius * 40, near * 1000);
  const camera = new THREE.PerspectiveCamera(FOV, 1, near, far);
  const dir = new THREE.Vector3(1, 0.75, 1).normalize();
  camera.position.copy(center).addScaledVector(dir, fitDistance(1));
  camera.lookAt(center);

  scene.add(new THREE.HemisphereLight(0xffffff, 0x777777, 1.1));
  const key = new THREE.DirectionalLight(0xffffff, 1.6);
  key.position.set(0.3, 0.6, 1);
  camera.add(key);
  scene.add(camera);

  const controls = new OrbitControls(camera, canvas);
  controls.target.copy(center);
  controls.enableDamping = false;
  controls.minDistance = near * 2;
  controls.maxDistance = far * 0.5;
  controls.update();

  let pending = false;
  function renderNow() {
    pending = false;
    renderer.render(scene, camera);
  }
  function requestRender() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(renderNow);
  }

  let userMoved = false;
  controls.addEventListener('start', () => { userMoved = true; });

  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    renderer.setSize(w, h, false);
    const aspect = w / Math.max(h, 1);
    camera.aspect = aspect;
    camera.updateProjectionMatrix();
    if (!userMoved) {
      camera.position.copy(controls.target).addScaledVector(dir, fitDistance(aspect));
      camera.lookAt(controls.target);
      controls.update();
    }
    requestRender();
  }
  controls.addEventListener('change', requestRender);
  new ResizeObserver(resize).observe(document.body);
  dark.addEventListener('change', applyTheme);
  applyTheme();
  resize();
  // The panel is revealed only after we report ready, and requestAnimationFrame does not fire
  // before that, so paint the first frame synchronously.
  renderNow();
  return { size, render: renderNow };
}

async function main() {
  if (tooBig) {
    showError('File too large for preview',
      `${fileName} is ${formatBytes(fileSize)}. Open it in a BIM application.`,
      `file of ${formatBytes(fileSize)} exceeds the preview limit`);
    post('ready', { message: 'too big' });
    return;
  }
  const model = await loadModel();
  if (!model.opaque && !model.transparent) {
    showError('No geometry found',
      `${fileName}${model.schema ? ' · ' + model.schema : ''} contains no renderable elements.`,
      `no renderable elements${model.schema ? ' (' + model.schema + ')' : ''}`);
    post('ready', { message: 'no geometry' });
    return;
  }
  const { size, render } = setupScene(model);
  const dims = `${size.x.toFixed(1)} × ${size.y.toFixed(1)} × ${size.z.toFixed(1)} m`;
  hud.innerHTML = '';
  for (const [label, value] of [
    ['', fileName],
    ['Schema', model.schema || '—'],
    ['Elements', model.elements.toLocaleString()],
    ['Colours', model.typeColored ? 'by type' : 'from file'],
    ['Triangles', model.triangles.toLocaleString()],
    ['Size', dims],
    ['File', formatBytes(fileSize || 0)],
  ]) {
    const item = document.createElement('div');
    if (label) { const s = document.createElement('span'); s.textContent = label + ' '; item.appendChild(s); }
    const b = document.createElement('b'); b.textContent = value; item.appendChild(b);
    hud.appendChild(item);
  }
  hud.hidden = false;
  overlay.hidden = true;
  render();
  mark('render');
  post('ready', { message: `${model.elements} elements, ${model.triangles} triangles; ${timings.join(', ')}` });
}

main().catch((e) => showError('Cannot preview this file', e?.message || String(e)));
