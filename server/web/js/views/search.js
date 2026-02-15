/**
 * Search view - person circles, scene chips, text search.
 */
import { apiJson } from '../api.js';
import { navigate } from '../router.js';
import { debounce, el } from '../utils.js';
import { observeImages } from '../components/lazy-image.js';

let _el;
let _faces = [];
let _scenes = [];

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
    <div id="search-browse">
      <div class="search-section" id="search-faces"></div>
      <div class="search-section" id="search-scenes"></div>
    </div>
    <div id="search-results" style="display:none">
      <div class="section-header" id="search-results-header"></div>
      <div class="photo-grid" id="search-results-grid"></div>
    </div>
  `;

  container.querySelector('#search-input').addEventListener('input',
    debounce(e => _doSearch(e.target.value.trim()), 400));
}

export async function onActivate() {
  await Promise.all([_loadFaces(), _loadScenes()]);
}

async function _loadFaces() {
  try {
    const data = await apiJson('/faces/clusters');
    _faces = data.clusters || data || [];
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
    const item = el('div', {
      className: 'face-item',
      onClick: () => _searchPerson(face.name || face.cluster_id),
    }, [
      el('div', { className: 'avatar avatar-lg' }, [
        face.representative_photo_id
          ? el('img', {
              'data-src': `/api/v1/photos/${face.representative_photo_id}/thumb`,
              className: 'lazy-img',
              alt: face.name || '',
            })
          : el('span', { className: 'material-symbols-outlined', textContent: 'person', style: { fontSize: '32px', color: 'var(--color-on-surface-variant)' } }),
      ]),
      el('span', { className: 'face-name', textContent: face.name || `인물 ${face.cluster_id}` }),
    ]);
    row.appendChild(item);
  }
  section.appendChild(row);
  observeImages(section);
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
  _el.querySelector('#search-results-header').textContent = title;
}

function _displayResults(photos) {
  const grid = _el.querySelector('#search-results-grid');
  grid.innerHTML = '';
  if (!photos.length) {
    grid.innerHTML = '<div class="empty-state"><span class="material-symbols-outlined">search_off</span><p>결과가 없습니다</p></div>';
    return;
  }
  for (const p of photos) {
    const thumb = el('div', {
      className: 'photo-thumb',
      onClick: () => navigate(`/viewer/${p.id}`),
    }, [
      el('img', { 'data-src': `/api/v1/photos/${p.id}/thumb`, className: 'lazy-img', alt: '' }),
    ]);
    grid.appendChild(thumb);
  }
  observeImages(grid);
}
