/**
 * Timeline view - Google Photos-style justified layout with upload and multi-select.
 */
import { apiJson, apiPost, apiUpload } from '../api.js';
import { getState, setState, updateState } from '../store.js';
import { navigate } from '../router.js';
import { groupByDate, throttle, el } from '../utils.js';
import { observeImages } from '../components/lazy-image.js';
import { showToast } from '../components/toast.js';

let _el;
let _gridContainer;
let _loading = false;

// Selection mode state
let _selectMode = false;
const _selected = new Set();
let _longPressTimer = null;

// Target row height for justified layout (responsive)
function _getTargetRowHeight() {
  const w = window.innerWidth;
  if (w >= 1920) return 280;
  if (w >= 1200) return 240;
  if (w >= 768) return 200;
  return 160;
}

export function init(container) {
  _el = container;
  container.innerHTML = `
    <div class="top-bar" id="tl-top-bar">
      <div class="top-bar-title">PhotoNest</div>
      <button class="top-bar-action" id="tl-search-btn" title="검색">
        <span class="material-symbols-outlined">search</span>
      </button>
    </div>
    <div class="select-action-bar" id="tl-select-bar" style="display:none">
      <button class="btn-icon" id="tl-select-close"><span class="material-symbols-outlined">close</span></button>
      <span class="select-count" id="tl-select-count">0장 선택</span>
      <div style="flex:1"></div>
      <button class="btn-icon" id="tl-select-fav" title="즐겨찾기"><span class="material-symbols-outlined">favorite</span></button>
      <button class="btn-icon" id="tl-select-album" title="앨범에 추가"><span class="material-symbols-outlined">photo_album</span></button>
      <button class="btn-icon" id="tl-select-delete" title="삭제"><span class="material-symbols-outlined">delete</span></button>
    </div>
    <div class="timeline-grid" id="timeline-grid"></div>
    <div class="spinner" id="timeline-loader" style="display:none"></div>
    <button class="fab" id="tl-upload-fab" title="사진 업로드">
      <span class="material-symbols-outlined">add</span>
    </button>
    <input type="file" id="tl-file-input" multiple accept="image/*,video/*" style="display:none" />
    <div class="upload-dropzone" id="tl-dropzone" style="display:none">
      <span class="material-symbols-outlined">cloud_upload</span>
      <p>사진을 여기에 놓으세요</p>
    </div>
  `;
  _gridContainer = container.querySelector('#timeline-grid');

  // Navigation
  container.querySelector('#tl-search-btn').addEventListener('click', () => navigate('/search'));

  // Upload via FAB
  const fileInput = container.querySelector('#tl-file-input');
  container.querySelector('#tl-upload-fab').addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', () => {
    if (fileInput.files.length) _uploadFiles([...fileInput.files]);
    fileInput.value = '';
  });

  // Drag & Drop
  const dropzone = container.querySelector('#tl-dropzone');
  container.addEventListener('dragover', e => { e.preventDefault(); dropzone.style.display = ''; });
  container.addEventListener('dragleave', e => {
    if (!container.contains(e.relatedTarget)) dropzone.style.display = 'none';
  });
  container.addEventListener('drop', e => {
    e.preventDefault();
    dropzone.style.display = 'none';
    const files = [...e.dataTransfer.files].filter(f => f.type.startsWith('image/') || f.type.startsWith('video/'));
    if (files.length) _uploadFiles(files);
  });

  // Selection bar actions
  container.querySelector('#tl-select-close').addEventListener('click', _exitSelectMode);
  container.querySelector('#tl-select-delete').addEventListener('click', _batchDelete);
  container.querySelector('#tl-select-fav').addEventListener('click', _batchFavorite);
  container.querySelector('#tl-select-album').addEventListener('click', _addToAlbum);

  // Infinite scroll
  container.addEventListener('scroll', throttle(_onScroll, 200), { passive: true });
}

export function onActivate() {
  const photos = getState('photos.items');
  if (photos.length === 0) _loadMore();
}

export function onDeactivate() {
  if (_selectMode) _exitSelectMode();
}

// --- Upload ---
async function _uploadFiles(files) {
  showToast(`${files.length}장 업로드 중...`);
  let success = 0;
  for (const file of files) {
    try {
      await apiUpload(file);
      success++;
    } catch (e) {
      console.error('Upload error:', e);
    }
  }
  showToast(`${success}장 업로드 완료`, { type: success ? 'success' : 'error' });
  if (success) _refreshTimeline();
}

// --- Selection Mode ---
function _enterSelectMode(photoId) {
  _selectMode = true;
  _selected.clear();
  if (photoId) _toggleSelect(photoId);
  _el.querySelector('#tl-top-bar').style.display = 'none';
  _el.querySelector('#tl-select-bar').style.display = '';
  _el.querySelector('#tl-upload-fab').style.display = 'none';
  _el.classList.add('select-mode');
  _updateSelectCount();
}

function _exitSelectMode() {
  _selectMode = false;
  _selected.clear();
  _el.querySelector('#tl-top-bar').style.display = '';
  _el.querySelector('#tl-select-bar').style.display = 'none';
  _el.querySelector('#tl-upload-fab').style.display = '';
  _el.classList.remove('select-mode');
  _gridContainer.querySelectorAll('.photo-thumb.selected').forEach(t => t.classList.remove('selected'));
}

function _toggleSelect(photoId) {
  if (_selected.has(photoId)) _selected.delete(photoId);
  else _selected.add(photoId);

  const thumb = _gridContainer.querySelector(`[data-id="${photoId}"]`);
  if (thumb) thumb.classList.toggle('selected', _selected.has(photoId));
  _updateSelectCount();
}

function _updateSelectCount() {
  _el.querySelector('#tl-select-count').textContent = `${_selected.size}장 선택`;
}

async function _batchDelete() {
  if (!_selected.size) return;
  if (!confirm(`${_selected.size}장의 사진을 삭제할까요?`)) return;
  try {
    await apiPost('/photos/batch', { action: 'delete', photo_ids: [..._selected] });
    showToast(`${_selected.size}장 삭제됨`, { type: 'success' });
    _exitSelectMode();
    _refreshTimeline();
  } catch (e) {
    showToast('삭제 실패', { type: 'error' });
  }
}

async function _batchFavorite() {
  if (!_selected.size) return;
  try {
    await apiPost('/photos/batch', { action: 'favorite', photo_ids: [..._selected] });
    showToast(`${_selected.size}장 즐겨찾기 추가`, { type: 'success' });
    _exitSelectMode();
  } catch (e) {
    showToast('실패', { type: 'error' });
  }
}

async function _addToAlbum() {
  if (!_selected.size) return;
  // Load album list and let user pick
  try {
    const data = await apiJson('/albums');
    const albums = data.albums || data || [];
    if (!albums.length) {
      const name = prompt('새 앨범 이름을 입력하세요:');
      if (!name?.trim()) return;
      const newAlbum = await apiPost('/albums', { name: name.trim() });
      await apiPost(`/albums/${newAlbum.id}/photos`, { photo_ids: [..._selected] });
      showToast(`'${name.trim()}' 앨범에 추가됨`, { type: 'success' });
    } else {
      // Simple selection via prompt
      const choices = albums.map((a, i) => `${i + 1}. ${a.name}`).join('\n');
      const input = prompt(`앨범을 선택하세요:\n${choices}\n\n번호 입력 (새 앨범: 0):`);
      if (input === null) return;
      const idx = parseInt(input);
      let albumId;
      if (idx === 0) {
        const name = prompt('새 앨범 이름:');
        if (!name?.trim()) return;
        const newAlbum = await apiPost('/albums', { name: name.trim() });
        albumId = newAlbum.id;
      } else if (idx > 0 && idx <= albums.length) {
        albumId = albums[idx - 1].id;
      } else {
        return;
      }
      await apiPost(`/albums/${albumId}/photos`, { photo_ids: [..._selected] });
      showToast('앨범에 추가됨', { type: 'success' });
    }
    _exitSelectMode();
  } catch (e) {
    showToast('앨범 추가 실패', { type: 'error' });
  }
}

// --- Data Loading ---
async function _loadMore() {
  if (_loading || !getState('photos.hasMore')) return;
  _loading = true;
  _el.querySelector('#timeline-loader').style.display = '';

  try {
    const cursor = getState('photos.cursor');
    const url = cursor ? `/photos?limit=60&cursor=${cursor}` : '/photos?limit=60';
    const data = await apiJson(url);

    const newPhotos = data.photos || data.items || data;
    const items = Array.isArray(newPhotos) ? newPhotos : [];

    updateState('photos.items', old => [...old, ...items]);
    setState('photos.cursor', data.next_cursor || null);
    setState('photos.hasMore', !!data.next_cursor);

    _renderGroups(items);
  } catch (e) {
    console.error('Timeline load error:', e);
  } finally {
    _loading = false;
    _el.querySelector('#timeline-loader').style.display = 'none';
  }
}

function _refreshTimeline() {
  setState('photos.items', []);
  setState('photos.cursor', null);
  setState('photos.hasMore', true);
  _gridContainer.innerHTML = '';
  _loadMore();
}

function _renderGroups(newPhotos) {
  const groups = groupByDate(newPhotos);
  for (const group of groups) {
    let existing = _gridContainer.querySelector(`[data-date="${group.date}"]`);
    if (existing) {
      const grid = existing.querySelector('.photo-grid');
      _appendPhotosToGrid(grid, group.photos);
    } else {
      const section = el('div', { className: 'timeline-section', 'data-date': group.date });
      section.appendChild(el('div', { className: 'section-header', textContent: group.label }));
      const grid = el('div', { className: 'photo-grid' });
      _appendPhotosToGrid(grid, group.photos);
      section.appendChild(grid);
      _gridContainer.appendChild(section);
    }
  }

  if (getState('photos.items').length === 0) {
    _gridContainer.innerHTML = `
      <div class="empty-state">
        <span class="material-symbols-outlined">photo_library</span>
        <p>사진이 없습니다</p>
        <p>+ 버튼으로 사진을 업로드해 보세요</p>
      </div>
    `;
  }

  observeImages(_gridContainer);
}

// --- Justified Layout Algorithm ---
function _justifiedLayout(photos, containerWidth) {
  const gap = 4;
  const targetHeight = _getTargetRowHeight();
  const rows = [];
  let currentRow = [];
  let currentAspectSum = 0;

  for (const photo of photos) {
    const w = photo.width || 400;
    const h = photo.height || 300;
    const aspect = w / h;
    currentRow.push({ photo, aspect });
    currentAspectSum += aspect;

    // Check if row is full (would the row height be <= target?)
    const usableWidth = containerWidth - gap * (currentRow.length - 1);
    const rowHeight = usableWidth / currentAspectSum;

    if (rowHeight <= targetHeight) {
      rows.push({ items: currentRow, height: rowHeight });
      currentRow = [];
      currentAspectSum = 0;
    }
  }

  // Last incomplete row: use target height but don't stretch beyond it
  if (currentRow.length > 0) {
    const usableWidth = containerWidth - gap * (currentRow.length - 1);
    const rowHeight = Math.min(targetHeight, usableWidth / currentAspectSum);
    rows.push({ items: currentRow, height: rowHeight });
  }

  return rows;
}

function _appendPhotosToGrid(grid, photos) {
  const containerWidth = grid.parentElement?.clientWidth || _gridContainer.clientWidth || window.innerWidth;
  const gridPadding = 8; // 2 * grid-gap (4px each side)
  const availableWidth = containerWidth - gridPadding;
  const gap = 4;

  const rows = _justifiedLayout(photos, availableWidth);

  for (const row of rows) {
    const rowEl = el('div', { className: 'photo-row' });

    for (const { photo, aspect } of row.items) {
      const thumbWidth = Math.floor(aspect * row.height);
      const thumbHeight = Math.floor(row.height);

      const thumb = el('div', {
        className: 'photo-thumb',
        'data-id': photo.id,
        style: { width: `${thumbWidth}px`, height: `${thumbHeight}px` },
      }, [
        el('img', {
          'data-src': `/api/v1/photos/${photo.id}/thumb?size=${thumbHeight > 200 ? 'medium' : 'small'}`,
          alt: '',
          className: 'lazy-img',
        }),
      ]);

      if (photo.is_video) {
        thumb.appendChild(el('span', { className: 'thumb-video material-symbols-outlined', textContent: 'play_circle' }));
        if (photo.duration) {
          const dur = photo.duration;
          const m = Math.floor(dur / 60).toString().padStart(2, '0');
          const s = Math.floor(dur % 60).toString().padStart(2, '0');
          thumb.appendChild(el('span', { className: 'thumb-duration', textContent: `${m}:${s}` }));
        }
      }

      if (photo.is_favorite) {
        thumb.appendChild(el('span', { className: 'thumb-fav material-symbols-outlined', textContent: 'favorite' }));
      }

      // Check mark overlay for selection mode
      thumb.appendChild(el('span', { className: 'thumb-check material-symbols-outlined', textContent: 'check_circle' }));

      // Click: navigate or toggle select
      thumb.addEventListener('click', () => {
        if (_selectMode) _toggleSelect(photo.id);
        else navigate(`/viewer/${photo.id}`);
      });

      // Long press: enter select mode
      thumb.addEventListener('pointerdown', () => {
        _longPressTimer = setTimeout(() => _enterSelectMode(photo.id), 500);
      });
      thumb.addEventListener('pointerup', () => clearTimeout(_longPressTimer));
      thumb.addEventListener('pointerleave', () => clearTimeout(_longPressTimer));

      rowEl.appendChild(thumb);
    }

    grid.appendChild(rowEl);
  }
}

function _onScroll() {
  if (_el.scrollTop + _el.clientHeight >= _el.scrollHeight - 600) {
    _loadMore();
  }
}
