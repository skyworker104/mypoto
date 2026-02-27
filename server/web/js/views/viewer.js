/**
 * Photo viewer - fullscreen with swipe, info panel, map, description editing.
 */
import { apiJson, apiPatch, apiDelete, fetchImageUrl } from '../api.js';
import { navigate } from '../router.js';
import { getState, setState } from '../store.js';
import { formatDateKo, formatDateTimeKo, formatBytes, el } from '../utils.js';
import { showToast } from '../components/toast.js';

let _el;
let _photo = null;
let _photoList = [];
let _currentIndex = -1;
let _editingDesc = false;
let _infoPanelOpen = false;

const SCENE_LABELS = {
  beach: '해변', mountain: '산', food: '음식', building: '건물',
  indoor: '실내', outdoor: '야외', nature: '자연', city: '도시',
  night: '야경', portrait: '인물', landscape: '풍경',
};

export function init(container) {
  _el = container;
  container.innerHTML = `
    <div class="viewer-container">
      <div class="viewer-top-bar">
        <button class="btn-icon viewer-back" id="viewer-back">
          <span class="material-symbols-outlined">arrow_back</span>
        </button>
        <span class="viewer-date" id="viewer-date"></span>
        <div class="viewer-actions">
          <button class="btn-icon" id="viewer-info-btn" title="상세정보">
            <span class="material-symbols-outlined">info</span>
          </button>
          <button class="btn-icon" id="viewer-fav" title="좋아요">
            <span class="material-symbols-outlined">favorite_border</span>
          </button>
          <button class="btn-icon" id="viewer-delete" title="삭제">
            <span class="material-symbols-outlined">delete_outline</span>
          </button>
        </div>
      </div>
      <div class="viewer-body">
        <div class="viewer-image-wrap" id="viewer-img-wrap">
          <img class="viewer-image" id="viewer-img" alt="" />
          <video class="viewer-video" id="viewer-video" controls playsinline style="display:none"></video>
        </div>
        <div class="viewer-info-panel" id="viewer-info-panel" style="display:none">
          <div class="info-panel-header">
            <span class="info-panel-title">상세 정보</span>
            <button class="btn-icon" id="info-panel-close">
              <span class="material-symbols-outlined">close</span>
            </button>
          </div>
          <div class="info-panel-content" id="info-panel-content"></div>
        </div>
      </div>
      <div class="viewer-nav">
        <button class="btn-icon" id="viewer-prev"><span class="material-symbols-outlined">chevron_left</span></button>
        <button class="btn-icon" id="viewer-next"><span class="material-symbols-outlined">chevron_right</span></button>
      </div>
      <div class="viewer-detail" id="viewer-detail">
        <div class="viewer-desc" id="viewer-desc">
          <div class="viewer-desc-display" id="viewer-desc-display">
            <span class="viewer-desc-text" id="viewer-desc-text"></span>
            <button class="btn-icon btn-edit-desc" id="viewer-desc-edit" title="설명 편집">
              <span class="material-symbols-outlined">edit</span>
            </button>
          </div>
          <div class="viewer-desc-editor" id="viewer-desc-editor" style="display:none">
            <textarea class="input-field viewer-desc-input" id="viewer-desc-input" rows="2" placeholder="사진 설명을 입력하세요..."></textarea>
            <div class="viewer-desc-actions">
              <button class="btn btn-text" id="viewer-desc-cancel">취소</button>
              <button class="btn btn-primary" id="viewer-desc-save">저장</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  `;

  container.querySelector('#viewer-back').addEventListener('click', () => {
    _closeInfoPanel();
    navigate('/timeline');
  });
  container.querySelector('#viewer-prev').addEventListener('click', _prev);
  container.querySelector('#viewer-next').addEventListener('click', _next);
  container.querySelector('#viewer-fav').addEventListener('click', _toggleFav);
  container.querySelector('#viewer-delete').addEventListener('click', _deletePhoto);

  // Info panel toggle
  container.querySelector('#viewer-info-btn').addEventListener('click', _toggleInfoPanel);
  container.querySelector('#info-panel-close').addEventListener('click', _closeInfoPanel);

  // Description editing
  container.querySelector('#viewer-desc-edit').addEventListener('click', _startEditDesc);
  container.querySelector('#viewer-desc-cancel').addEventListener('click', _cancelEditDesc);
  container.querySelector('#viewer-desc-save').addEventListener('click', _saveDesc);

  // Keyboard nav
  document.addEventListener('keydown', _onKey);

  // Swipe support
  let touchStartX = 0;
  const wrap = container.querySelector('#viewer-img-wrap');
  wrap.addEventListener('touchstart', e => { touchStartX = e.touches[0].clientX; }, { passive: true });
  wrap.addEventListener('touchend', e => {
    const dx = e.changedTouches[0].clientX - touchStartX;
    if (Math.abs(dx) > 50) {
      if (dx > 0) _prev(); else _next();
    }
  });
}

export async function onActivate(params) {
  const id = params?.id;
  if (!id) { navigate('/timeline'); return; }

  _photoList = getState('photos.items') || [];
  _currentIndex = _photoList.findIndex(p => p.id === id);

  await _loadPhoto(id);
}

export function onDeactivate() {
  _photo = null;
  _cancelEditDesc();
  _closeInfoPanel();
}

async function _loadPhoto(id) {
  try {
    _photo = await apiJson(`/photos/${id}`);
    _cancelEditDesc();
    _render();
    if (_infoPanelOpen) _renderInfoPanel();

    const imgEl = _el.querySelector('#viewer-img');
    const videoEl = _el.querySelector('#viewer-video');

    if (_photo.is_video) {
      imgEl.style.display = 'none';
      imgEl.src = '';
      videoEl.style.display = '';
      const url = await fetchImageUrl(`/photos/${id}/file`);
      if (url) videoEl.src = url;
    } else {
      videoEl.style.display = 'none';
      videoEl.src = '';
      videoEl.pause();
      imgEl.style.display = '';
      imgEl.src = '';
      const url = await fetchImageUrl(`/photos/${id}/file`);
      if (url) imgEl.src = url;
    }
  } catch (e) {
    console.error('Viewer load error:', e);
  }
}

function _render() {
  if (!_photo) return;
  _el.querySelector('#viewer-date').textContent = formatDateKo(_photo.taken_at);

  const favBtn = _el.querySelector('#viewer-fav .material-symbols-outlined');
  favBtn.textContent = _photo.is_favorite ? 'favorite' : 'favorite_border';
  favBtn.style.color = _photo.is_favorite ? 'var(--color-error)' : '';

  // Description
  const descText = _el.querySelector('#viewer-desc-text');
  descText.textContent = _photo.description || '설명 없음';
  descText.style.color = _photo.description ? '' : 'var(--color-on-surface-variant)';
}

// --- Info Panel ---
function _toggleInfoPanel() {
  if (_infoPanelOpen) _closeInfoPanel();
  else _openInfoPanel();
}

function _openInfoPanel() {
  _infoPanelOpen = true;
  const panel = _el.querySelector('#viewer-info-panel');
  panel.style.display = '';
  _el.querySelector('.viewer-body').classList.add('info-open');
  _el.querySelector('#viewer-info-btn .material-symbols-outlined').style.color = 'var(--color-primary)';
  _renderInfoPanel();
}

function _closeInfoPanel() {
  _infoPanelOpen = false;
  const panel = _el.querySelector('#viewer-info-panel');
  if (panel) panel.style.display = 'none';
  const body = _el.querySelector('.viewer-body');
  if (body) body.classList.remove('info-open');
  const btn = _el.querySelector('#viewer-info-btn .material-symbols-outlined');
  if (btn) btn.style.color = '';
}

function _renderInfoPanel() {
  if (!_photo) return;
  const content = _el.querySelector('#info-panel-content');
  content.innerHTML = '';

  // --- Basic Info ---
  const basicItems = [];
  if (_photo.taken_at) {
    basicItems.push(_infoItem('calendar_today', '촬영일', formatDateTimeKo(_photo.taken_at)));
  }
  if (_photo.width && _photo.height) {
    basicItems.push(_infoItem('aspect_ratio', '해상도', `${_photo.width} x ${_photo.height}`));
  }
  if (_photo.file_size) {
    basicItems.push(_infoItem('storage', '파일 크기', formatBytes(_photo.file_size)));
  }
  if (_photo.mime_type) {
    basicItems.push(_infoItem('image', '형식', _photo.mime_type.split('/')[1]?.toUpperCase() || _photo.mime_type));
  }
  if (basicItems.length) {
    content.appendChild(_infoSection('기본 정보', basicItems));
  }

  // --- Camera Info ---
  const camItems = [];
  if (_photo.camera_make) {
    camItems.push(_infoItem('photo_camera', '제조사', _photo.camera_make));
  }
  if (_photo.camera_model) {
    camItems.push(_infoItem('camera', '모델', _photo.camera_model));
  }
  // Parse EXIF data for extra details
  if (_photo.exif_data) {
    try {
      const exif = JSON.parse(_photo.exif_data);
      if (exif.focal_length) camItems.push(_infoItem('center_focus_strong', '초점 거리', `${exif.focal_length}mm`));
      if (exif.f_number) camItems.push(_infoItem('camera', '조리개', `f/${exif.f_number}`));
      if (exif.exposure_time) camItems.push(_infoItem('shutter_speed', '셔터 속도', exif.exposure_time));
      if (exif.iso) camItems.push(_infoItem('iso', 'ISO', `${exif.iso}`));
    } catch (e) { /* ignore parse errors */ }
  }
  if (camItems.length) {
    content.appendChild(_infoSection('카메라', camItems));
  }

  // --- AI / Scene ---
  const aiItems = [];
  if (_photo.ai_scene) {
    const label = SCENE_LABELS[_photo.ai_scene] || _photo.ai_scene;
    aiItems.push(_infoItem('landscape', '장면 분류', label));
  }
  if (aiItems.length) {
    content.appendChild(_infoSection('AI 분석', aiItems));
  }

  // --- Location ---
  if (_photo.latitude && _photo.longitude) {
    const locItems = [];
    if (_photo.location_name) {
      locItems.push(_infoItem('place', '장소', _photo.location_name));
    }
    locItems.push(_infoItem('my_location', '좌표', `${_photo.latitude.toFixed(6)}, ${_photo.longitude.toFixed(6)}`));

    const locSection = _infoSection('위치', locItems);

    // Map container (OpenStreetMap embed)
    const mapWrap = el('div', { className: 'info-map-wrap' });
    const lat = _photo.latitude;
    const lon = _photo.longitude;
    const bbox = `${lon - 0.01},${lat - 0.007},${lon + 0.01},${lat + 0.007}`;
    const mapFrame = el('iframe', {
      className: 'info-map-frame',
      src: `https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik&marker=${lat},${lon}`,
      frameBorder: '0',
      loading: 'lazy',
    });
    mapWrap.appendChild(mapFrame);

    // Link to full map
    const mapLink = el('a', {
      className: 'info-map-link',
      href: `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=15/${lat}/${lon}`,
      target: '_blank',
      textContent: '큰 지도로 보기',
    });
    mapWrap.appendChild(mapLink);

    locSection.appendChild(mapWrap);
    content.appendChild(locSection);
  } else if (_photo.location_name) {
    content.appendChild(_infoSection('위치', [
      _infoItem('place', '장소', _photo.location_name),
    ]));
  }

  // --- Upload Info ---
  const uploadItems = [];
  if (_photo.uploaded_by) {
    uploadItems.push(_infoItem('person', '업로드', _photo.uploaded_by));
  }
  if (_photo.created_at) {
    uploadItems.push(_infoItem('cloud_upload', '업로드 일시', formatDateTimeKo(_photo.created_at)));
  }
  if (uploadItems.length) {
    content.appendChild(_infoSection('업로드', uploadItems));
  }
}

function _infoSection(title, children) {
  return el('div', { className: 'info-section' }, [
    el('div', { className: 'info-section-title', textContent: title }),
    ...children,
  ]);
}

function _infoItem(icon, label, value) {
  return el('div', { className: 'info-item' }, [
    el('span', { className: 'material-symbols-outlined info-item-icon', textContent: icon }),
    el('div', { className: 'info-item-text' }, [
      el('span', { className: 'info-item-label', textContent: label }),
      el('span', { className: 'info-item-value', textContent: value }),
    ]),
  ]);
}

// --- Description Editing ---
function _startEditDesc() {
  _editingDesc = true;
  _el.querySelector('#viewer-desc-display').style.display = 'none';
  _el.querySelector('#viewer-desc-editor').style.display = '';
  const input = _el.querySelector('#viewer-desc-input');
  input.value = _photo?.description || '';
  input.focus();
}

function _cancelEditDesc() {
  _editingDesc = false;
  const display = _el.querySelector('#viewer-desc-display');
  const editor = _el.querySelector('#viewer-desc-editor');
  if (display) display.style.display = '';
  if (editor) editor.style.display = 'none';
}

async function _saveDesc() {
  if (!_photo) return;
  const input = _el.querySelector('#viewer-desc-input');
  const desc = input.value.trim();
  try {
    await apiPatch(`/photos/${_photo.id}`, { description: desc || null });
    _photo.description = desc || null;
    _cancelEditDesc();
    _render();
    showToast('설명이 저장되었습니다', { type: 'success' });
  } catch (e) {
    showToast('저장 실패', { type: 'error' });
  }
}

// --- Navigation ---
function _prev() {
  if (_currentIndex > 0) {
    _currentIndex--;
    const p = _photoList[_currentIndex];
    window.location.hash = `#/viewer/${p.id}`;
    _loadPhoto(p.id);
  }
}

function _next() {
  if (_currentIndex < _photoList.length - 1) {
    _currentIndex++;
    const p = _photoList[_currentIndex];
    window.location.hash = `#/viewer/${p.id}`;
    _loadPhoto(p.id);
  }
}

async function _toggleFav() {
  if (!_photo) return;
  const newVal = !_photo.is_favorite;
  try {
    await apiPatch(`/photos/${_photo.id}`, { is_favorite: newVal });
    _photo.is_favorite = newVal;
    const items = getState('photos.items');
    const idx = items.findIndex(p => p.id === _photo.id);
    if (idx >= 0) items[idx].is_favorite = newVal;
    _render();
  } catch (e) {
    console.error('Toggle fav error:', e);
  }
}

async function _deletePhoto() {
  if (!_photo) return;
  if (!confirm('이 사진을 삭제할까요?')) return;
  try {
    await apiDelete(`/photos/${_photo.id}`);
    setState('photos.items', []);
    setState('photos.cursor', null);
    setState('photos.hasMore', true);
    navigate('/timeline');
  } catch (e) {
    console.error('Delete error:', e);
  }
}

function _onKey(e) {
  if (!_el.classList.contains('active')) return;
  if (_editingDesc) return;
  if (e.key === 'ArrowLeft') _prev();
  else if (e.key === 'ArrowRight') _next();
  else if (e.key === 'Escape') {
    if (_infoPanelOpen) _closeInfoPanel();
    else navigate('/timeline');
  }
  else if (e.key === 'i') _toggleInfoPanel();
}
