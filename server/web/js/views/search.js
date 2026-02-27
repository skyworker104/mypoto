/**
 * Search view - person circles, scene chips, text search with filters.
 */
import { apiJson, apiPatch } from '../api.js';
import { navigate } from '../router.js';
import { getState, setState } from '../store.js';
import { debounce, el } from '../utils.js';
import { observeImages } from '../components/lazy-image.js';
import { showToast } from '../components/toast.js';

let _el;
let _faces = [];
let _scenes = [];
let _currentFilter = 'all'; // 'all', 'photo', 'video'

const SCENE_ICONS = {
  beach: 'beach_access', mountain: 'terrain', food: 'restaurant',
  building: 'apartment', indoor: 'house', outdoor: 'park',
  nature: 'eco', city: 'location_city', night: 'dark_mode',
  portrait: 'person', landscape: 'landscape',
};

export function init(container) {
  _el = container;
  container.innerHTML = `
    <div class="top-bar">
      <div class="top-bar-title">검색</div>
    </div>
    <div class="search-bar" id="search-bar">
      <span class="material-symbols-outlined">search</span>
      <input type="text" placeholder="검색어를 입력하세요" id="search-input" />
    </div>
    <div class="search-filters" id="search-filters" style="display:none">
      <button class="chip chip-active" data-filter="all">전체</button>
      <button class="chip" data-filter="photo">사진</button>
      <button class="chip" data-filter="video">동영상</button>
    </div>
    <div id="search-browse">
      <div class="search-section" id="search-faces"></div>
      <div class="search-section" id="search-scenes"></div>
    </div>
    <div id="search-results" style="display:none">
      <div class="section-header" id="search-results-header"></div>
      <div class="search-grid" id="search-results-grid"></div>
    </div>
  `;

  container.querySelector('#search-input').addEventListener('input',
    debounce(e => _doSearch(e.target.value.trim()), 400));

  // Filter buttons
  container.querySelector('#search-filters').addEventListener('click', e => {
    const btn = e.target.closest('[data-filter]');
    if (!btn) return;
    _currentFilter = btn.dataset.filter;
    container.querySelectorAll('#search-filters .chip').forEach(c =>
      c.classList.toggle('chip-active', c.dataset.filter === _currentFilter));
    // Re-run search with filter
    const query = container.querySelector('#search-input').value.trim();
    if (query) _doSearch(query);
  });

  // Listen for TV search event via WebSocket
  window.addEventListener('tv-search-result', (e) => {
    const { query, photos } = e.detail || {};
    if (query) {
      container.querySelector('#search-input').value = query;
      _showResults(`'${query}' TV 검색 결과`);
      _displayResults(photos || []);
    }
  });
}

export async function onActivate() {
  await Promise.all([_loadFaces(), _loadScenes()]);
}

export function onDeactivate() {}

async function _loadFaces() {
  try {
    const data = await apiJson('/faces');
    _faces = data.faces || data || [];
    _renderFaces();
  } catch (e) {
    console.error('Load faces error:', e);
  }
}

async function _loadScenes() {
  try {
    const data = await apiJson('/search/scenes');
    _scenes = data.scenes || data || [];
    _renderScenes();
  } catch (e) {
    console.error('Load scenes error:', e);
  }
}

function _renderFaces() {
  const section = _el.querySelector('#search-faces');
  if (!_faces.length) { section.innerHTML = ''; return; }

  section.innerHTML = '<div class="section-header">인물</div>';
  const row = el('div', { className: 'face-row' });
  for (const face of _faces.slice(0, 20)) {
    const faceId = face.id || face.cluster_id;
    const coverUrl = face.cover_thumb_url
      || (face.cover_photo_id ? `/api/v1/photos/${face.cover_photo_id}/thumb` : null)
      || (face.representative_photo_id ? `/api/v1/photos/${face.representative_photo_id}/thumb` : null);

    const avatarChildren = coverUrl
      ? [el('img', { 'data-src': coverUrl, className: 'lazy-img', alt: face.name || '' })]
      : [el('span', { className: 'material-symbols-outlined', textContent: 'person', style: { fontSize: '32px', color: 'var(--color-on-surface-variant)' } })];

    const item = el('div', {
      className: 'face-item',
    }, [
      el('div', { className: 'avatar avatar-lg' }, avatarChildren),
      el('span', {
        className: 'face-name',
        textContent: face.name || `인물 ${face.photo_count || ''}`,
      }),
    ]);

    // Click: search by face or show name dialog
    item.addEventListener('click', () => {
      if (face.name) {
        _searchPerson(face.name);
      } else {
        _showNameDialog(faceId, face);
      }
    });

    row.appendChild(item);
  }
  section.appendChild(row);
  observeImages(section);
}

function _showNameDialog(faceId, face) {
  const name = prompt(`이 인물의 이름을 입력하세요:\n(사진 ${face.photo_count}장)`);
  if (!name?.trim()) {
    // Search by face ID if no name entered
    _searchFacePhotos(faceId);
    return;
  }
  // Tag the face with a name
  apiPatch(`/faces/${faceId}`, { name: name.trim() }).then(() => {
    showToast(`'${name.trim()}' 이름이 등록되었습니다`, { type: 'success' });
    _loadFaces(); // Refresh face list
    _searchPerson(name.trim());
  }).catch(() => {
    showToast('이름 등록 실패', { type: 'error' });
  });
}

async function _searchFacePhotos(faceId) {
  _showResults('인물 사진');
  try {
    const data = await apiJson(`/faces/${faceId}/photos`);
    _displayResults(data.photos || []);
  } catch (e) { _displayResults([]); }
}

function _renderScenes() {
  const section = _el.querySelector('#search-scenes');
  if (!_scenes.length) { section.innerHTML = ''; return; }

  section.innerHTML = '<div class="section-header">카테고리</div>';
  const row = el('div', { className: 'chip-row' });
  for (const scene of _scenes) {
    const icon = SCENE_ICONS[scene.scene || scene.label] || 'image';
    const chip = el('button', {
      className: 'chip',
      onClick: () => _searchScene(scene.scene || scene.label),
    }, [
      el('span', { className: 'material-symbols-outlined', textContent: icon, style: { fontSize: '18px' } }),
      document.createTextNode(` ${scene.label_ko || scene.scene || scene.label} (${scene.count})`),
    ]);
    row.appendChild(chip);
  }
  section.appendChild(row);
}

async function _searchPerson(name) {
  _showResults(`'${name}' 검색 결과`);
  try {
    const data = await apiJson(`/search?q=${encodeURIComponent(name)}&type=person`);
    _displayResults(data.results || data.photos || []);
  } catch (e) { _displayResults([]); }
}

async function _searchScene(scene) {
  _showResults(`'${scene}' 사진`);
  try {
    const data = await apiJson(`/search/scenes/${encodeURIComponent(scene)}`);
    _displayResults(data.photos || []);
  } catch (e) { _displayResults([]); }
}

async function _doSearch(query) {
  if (!query) {
    _el.querySelector('#search-browse').style.display = '';
    _el.querySelector('#search-results').style.display = 'none';
    _el.querySelector('#search-filters').style.display = 'none';
    return;
  }
  _showResults(`'${query}' 검색 결과`);
  try {
    const data = await apiJson(`/search?q=${encodeURIComponent(query)}`);
    // Merge all result types, dedup by id
    const seen = new Set();
    const merged = [];
    for (const group of [data.persons, data.places, data.descriptions, data.dates]) {
      if (!group) continue;
      for (const p of group) {
        if (!seen.has(p.id)) { seen.add(p.id); merged.push(p); }
      }
    }
    _displayResults(merged);
  } catch (e) { _displayResults([]); }
}

function _showResults(title) {
  _el.querySelector('#search-browse').style.display = 'none';
  _el.querySelector('#search-results').style.display = '';
  _el.querySelector('#search-filters').style.display = '';
  _el.querySelector('#search-results-header').textContent = title;
}

function _displayResults(photos) {
  const grid = _el.querySelector('#search-results-grid');
  grid.innerHTML = '';

  // Apply filter
  let filtered = photos;
  if (_currentFilter === 'photo') {
    filtered = photos.filter(p => !p.is_video);
  } else if (_currentFilter === 'video') {
    filtered = photos.filter(p => p.is_video);
  }

  if (!filtered.length) {
    grid.innerHTML = '<div class="empty-state"><span class="material-symbols-outlined">search_off</span><p>결과가 없습니다</p></div>';
    return;
  }
  for (const p of filtered) {
    const thumb = el('div', {
      className: 'photo-thumb search-thumb',
      onClick: () => navigate(`/viewer/${p.id}`),
    }, [
      el('img', { 'data-src': `/api/v1/photos/${p.id}/thumb?size=small`, className: 'lazy-img', alt: '' }),
    ]);

    if (p.is_video) {
      thumb.appendChild(el('span', { className: 'thumb-video material-symbols-outlined', textContent: 'play_circle' }));
    }

    grid.appendChild(thumb);
  }
  observeImages(grid);
}
