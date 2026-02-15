/**
 * Albums view - full CRUD: create, rename, delete, add/remove photos.
 */
import { apiJson, apiPost, apiPatch, apiDelete } from '../api.js';
import { navigate } from '../router.js';
import { el } from '../utils.js';
import { observeImages } from '../components/lazy-image.js';
import { showToast } from '../components/toast.js';

let _el;
let _albums = [];
let _detailAlbum = null;
let _detailPhotos = [];

// Selection mode in album detail
let _selectMode = false;
const _selected = new Set();
let _longPressTimer = null;

export function init(container) {
  _el = container;
  container.innerHTML = `
    <div class="top-bar" id="album-top-bar">
      <button class="btn-icon" id="album-back" style="display:none">
        <span class="material-symbols-outlined">arrow_back</span>
      </button>
      <div class="top-bar-title" id="album-title">앨범</div>
      <div style="flex:1"></div>
      <button class="btn-icon" id="album-menu" style="display:none" title="메뉴">
        <span class="material-symbols-outlined">more_vert</span>
      </button>
    </div>
    <div class="select-action-bar" id="album-select-bar" style="display:none">
      <button class="btn-icon" id="album-select-close"><span class="material-symbols-outlined">close</span></button>
      <span class="select-count" id="album-select-count">0장 선택</span>
      <div style="flex:1"></div>
      <button class="btn-icon" id="album-select-remove" title="앨범에서 제거"><span class="material-symbols-outlined">remove_circle_outline</span></button>
    </div>
    <div id="album-list"></div>
    <div id="album-detail" style="display:none">
      <div class="photo-grid" id="album-photos-grid"></div>
    </div>
    <button class="fab" id="album-fab" title="새 앨범">
      <span class="material-symbols-outlined">add</span>
    </button>
    <div class="album-context-menu" id="album-context-menu" style="display:none">
      <button class="album-menu-item" id="menu-add-photos">
        <span class="material-symbols-outlined">add_photo_alternate</span> 사진 추가
      </button>
      <button class="album-menu-item" id="menu-rename">
        <span class="material-symbols-outlined">edit</span> 이름 변경
      </button>
      <button class="album-menu-item menu-danger" id="menu-delete">
        <span class="material-symbols-outlined">delete</span> 앨범 삭제
      </button>
    </div>
  `;

  container.querySelector('#album-back').addEventListener('click', () => {
    if (_selectMode) _exitSelectMode();
    else _showList();
  });
  container.querySelector('#album-fab').addEventListener('click', _onFabClick);
  container.querySelector('#album-menu').addEventListener('click', _toggleMenu);
  container.querySelector('#menu-add-photos').addEventListener('click', _addPhotosToAlbum);
  container.querySelector('#menu-rename').addEventListener('click', _renameAlbum);
  container.querySelector('#menu-delete').addEventListener('click', _deleteAlbum);
  container.querySelector('#album-select-close').addEventListener('click', _exitSelectMode);
  container.querySelector('#album-select-remove').addEventListener('click', _removeSelectedPhotos);

  // Close menu on outside click
  document.addEventListener('click', e => {
    const menu = _el.querySelector('#album-context-menu');
    if (menu.style.display !== 'none' && !menu.contains(e.target) && !_el.querySelector('#album-menu').contains(e.target)) {
      menu.style.display = 'none';
    }
  });
}

export async function onActivate() {
  await _loadAlbums();
}

export function onDeactivate() {
  if (_selectMode) _exitSelectMode();
}

// --- Album List ---
async function _loadAlbums() {
  _showList();
  try {
    const data = await apiJson('/albums');
    _albums = data.albums || data || [];
    _renderAlbums();
  } catch (e) {
    console.error('Albums load error:', e);
  }
}

function _renderAlbums() {
  const list = _el.querySelector('#album-list');
  list.innerHTML = '';

  if (!_albums.length) {
    list.innerHTML = '<div class="empty-state"><span class="material-symbols-outlined">photo_album</span><p>앨범이 없습니다</p><p>+ 버튼으로 새 앨범을 만들어보세요</p></div>';
    return;
  }

  const grid = el('div', { className: 'album-grid' });
  for (const album of _albums) {
    const card = el('div', {
      className: 'card album-card',
      onClick: () => _openAlbum(album),
    }, [
      el('div', { className: 'album-cover' }, [
        album.cover_photo
          ? el('img', { 'data-src': `/api/v1/photos/${album.cover_photo}/thumb`, className: 'lazy-img', alt: '' })
          : el('span', { className: 'material-symbols-outlined', textContent: 'photo_album', style: { fontSize: '48px', color: 'var(--color-on-surface-variant)' } }),
      ]),
      el('div', { className: 'card-body' }, [
        el('div', { className: 'card-title', textContent: album.name }),
        el('div', { className: 'card-subtitle', textContent: `${album.photo_count || 0}장` }),
      ]),
    ]);
    grid.appendChild(card);
  }
  list.appendChild(grid);
  observeImages(list);
}

// --- Album Detail ---
async function _openAlbum(album) {
  _detailAlbum = album;
  _el.querySelector('#album-list').style.display = 'none';
  _el.querySelector('#album-detail').style.display = '';
  _el.querySelector('#album-back').style.display = '';
  _el.querySelector('#album-menu').style.display = '';
  _el.querySelector('#album-title').textContent = album.name;
  _el.querySelector('#album-fab').style.display = 'none';

  try {
    const data = await apiJson(`/albums/${album.id}`);
    const photoIds = data.photos || [];
    // Load photo details for display
    _detailPhotos = [];
    if (photoIds.length) {
      const photoData = await apiJson(`/photos?limit=200`);
      const allPhotos = photoData.photos || [];
      const idSet = new Set(photoIds);
      _detailPhotos = allPhotos.filter(p => idSet.has(p.id));
    }
    _renderAlbumPhotos();
  } catch (e) {
    console.error('Album detail error:', e);
  }
}

function _renderAlbumPhotos() {
  const grid = _el.querySelector('#album-photos-grid');
  grid.innerHTML = '';

  if (!_detailPhotos.length) {
    grid.innerHTML = '<div class="empty-state"><p>앨범에 사진이 없습니다</p><p>메뉴에서 사진을 추가하세요</p></div>';
    return;
  }

  for (const p of _detailPhotos) {
    const thumb = el('div', {
      className: 'photo-thumb',
      'data-id': p.id,
    }, [
      el('img', { 'data-src': `/api/v1/photos/${p.id}/thumb`, className: 'lazy-img', alt: '' }),
      el('span', { className: 'thumb-check material-symbols-outlined', textContent: 'check_circle' }),
    ]);

    thumb.addEventListener('click', () => {
      if (_selectMode) _toggleSelect(p.id);
      else navigate(`/viewer/${p.id}`);
    });

    thumb.addEventListener('pointerdown', () => {
      _longPressTimer = setTimeout(() => _enterSelectMode(p.id), 500);
    });
    thumb.addEventListener('pointerup', () => clearTimeout(_longPressTimer));
    thumb.addEventListener('pointerleave', () => clearTimeout(_longPressTimer));

    grid.appendChild(thumb);
  }
  observeImages(grid);
}

function _showList() {
  _detailAlbum = null;
  _detailPhotos = [];
  _el.querySelector('#album-list').style.display = '';
  _el.querySelector('#album-detail').style.display = 'none';
  _el.querySelector('#album-back').style.display = 'none';
  _el.querySelector('#album-menu').style.display = 'none';
  _el.querySelector('#album-title').textContent = '앨범';
  _el.querySelector('#album-fab').style.display = '';
  _el.querySelector('#album-context-menu').style.display = 'none';
}

// --- FAB ---
function _onFabClick() {
  if (_detailAlbum) {
    _addPhotosToAlbum();
  } else {
    _createAlbum();
  }
}

// --- CRUD Operations ---
async function _createAlbum() {
  const name = prompt('새 앨범 이름을 입력하세요:');
  if (!name?.trim()) return;
  try {
    await apiPost('/albums', { name: name.trim() });
    showToast(`'${name.trim()}' 앨범 생성됨`, { type: 'success' });
    _loadAlbums();
  } catch (e) {
    showToast('앨범 생성 실패', { type: 'error' });
  }
}

async function _renameAlbum() {
  _el.querySelector('#album-context-menu').style.display = 'none';
  if (!_detailAlbum) return;
  const name = prompt('새 이름:', _detailAlbum.name);
  if (!name?.trim() || name.trim() === _detailAlbum.name) return;
  try {
    await apiPatch(`/albums/${_detailAlbum.id}`, { name: name.trim() });
    _detailAlbum.name = name.trim();
    _el.querySelector('#album-title').textContent = name.trim();
    showToast('이름이 변경되었습니다', { type: 'success' });
  } catch (e) {
    showToast('변경 실패', { type: 'error' });
  }
}

async function _deleteAlbum() {
  _el.querySelector('#album-context-menu').style.display = 'none';
  if (!_detailAlbum) return;
  if (!confirm(`'${_detailAlbum.name}' 앨범을 삭제할까요?\n(사진은 삭제되지 않습니다)`)) return;
  try {
    await apiDelete(`/albums/${_detailAlbum.id}`);
    showToast('앨범이 삭제되었습니다', { type: 'success' });
    _showList();
    _loadAlbums();
  } catch (e) {
    showToast('삭제 실패', { type: 'error' });
  }
}

async function _addPhotosToAlbum() {
  _el.querySelector('#album-context-menu').style.display = 'none';
  if (!_detailAlbum) return;

  // Load recent photos for selection
  try {
    const data = await apiJson('/photos?limit=100');
    const photos = data.photos || [];
    if (!photos.length) {
      showToast('추가할 사진이 없습니다');
      return;
    }

    // Simple prompt-based selection (photo count)
    const count = prompt(`최근 사진 ${photos.length}장 중 몇 장을 추가할까요?\n(숫자 입력, 예: 10)`);
    if (!count) return;
    const n = Math.min(parseInt(count) || 0, photos.length);
    if (n <= 0) return;

    const ids = photos.slice(0, n).map(p => p.id);
    const result = await apiPost(`/albums/${_detailAlbum.id}/photos`, { photo_ids: ids });
    showToast(`${result.added || n}장 추가됨`, { type: 'success' });
    _openAlbum(_detailAlbum);
  } catch (e) {
    showToast('추가 실패', { type: 'error' });
  }
}

// --- Selection Mode in Detail ---
function _enterSelectMode(photoId) {
  _selectMode = true;
  _selected.clear();
  if (photoId) _toggleSelect(photoId);
  _el.querySelector('#album-top-bar').style.display = 'none';
  _el.querySelector('#album-select-bar').style.display = '';
  _el.classList.add('select-mode');
  _updateSelectCount();
}

function _exitSelectMode() {
  _selectMode = false;
  _selected.clear();
  _el.querySelector('#album-top-bar').style.display = '';
  _el.querySelector('#album-select-bar').style.display = 'none';
  _el.classList.remove('select-mode');
  _el.querySelectorAll('.photo-thumb.selected').forEach(t => t.classList.remove('selected'));
}

function _toggleSelect(photoId) {
  if (_selected.has(photoId)) _selected.delete(photoId);
  else _selected.add(photoId);
  const thumb = _el.querySelector(`[data-id="${photoId}"]`);
  if (thumb) thumb.classList.toggle('selected', _selected.has(photoId));
  _updateSelectCount();
}

function _updateSelectCount() {
  _el.querySelector('#album-select-count').textContent = `${_selected.size}장 선택`;
}

async function _removeSelectedPhotos() {
  if (!_selected.size || !_detailAlbum) return;
  if (!confirm(`${_selected.size}장을 앨범에서 제거할까요?`)) return;
  try {
    await apiJson(`/albums/${_detailAlbum.id}/photos`, {
      method: 'DELETE',
      json: { photo_ids: [..._selected] },
    });
    showToast(`${_selected.size}장 제거됨`, { type: 'success' });
    _exitSelectMode();
    _openAlbum(_detailAlbum);
  } catch (e) {
    showToast('제거 실패', { type: 'error' });
  }
}

function _toggleMenu() {
  const menu = _el.querySelector('#album-context-menu');
  menu.style.display = menu.style.display === 'none' ? '' : 'none';
}
