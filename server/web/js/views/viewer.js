/**
 * Photo viewer - fullscreen with swipe, description editing.
 */
import { apiJson, apiPatch, apiDelete, fetchImageUrl } from '../api.js';
import { navigate } from '../router.js';
import { getState, setState } from '../store.js';
import { formatDateKo, el } from '../utils.js';
import { showToast } from '../components/toast.js';

let _el;
let _photo = null;
let _photoList = [];
let _currentIndex = -1;
let _editingDesc = false;

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
          <button class="btn-icon" id="viewer-fav" title="좋아요">
            <span class="material-symbols-outlined">favorite_border</span>
          </button>
          <button class="btn-icon" id="viewer-delete" title="삭제">
            <span class="material-symbols-outlined">delete_outline</span>
          </button>
        </div>
      </div>
      <div class="viewer-image-wrap" id="viewer-img-wrap">
        <img class="viewer-image" id="viewer-img" alt="" />
      </div>
      <div class="viewer-nav">
        <button class="btn-icon" id="viewer-prev"><span class="material-symbols-outlined">chevron_left</span></button>
        <button class="btn-icon" id="viewer-next"><span class="material-symbols-outlined">chevron_right</span></button>
      </div>
      <div class="viewer-detail" id="viewer-detail">
        <div class="viewer-info" id="viewer-info"></div>
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

  container.querySelector('#viewer-back').addEventListener('click', () => navigate('/timeline'));
  container.querySelector('#viewer-prev').addEventListener('click', _prev);
  container.querySelector('#viewer-next').addEventListener('click', _next);
  container.querySelector('#viewer-fav').addEventListener('click', _toggleFav);
  container.querySelector('#viewer-delete').addEventListener('click', _deletePhoto);

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
}

async function _loadPhoto(id) {
  try {
    _photo = await apiJson(`/photos/${id}`);
    _cancelEditDesc();
    _render();

    const imgEl = _el.querySelector('#viewer-img');
    imgEl.src = '';
    const url = await fetchImageUrl(`/photos/${id}/file`);
    if (url) imgEl.src = url;
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

  // Info
  const info = _el.querySelector('#viewer-info');
  const parts = [];
  if (_photo.width && _photo.height) parts.push(`${_photo.width} x ${_photo.height}`);
  if (_photo.file_size) parts.push(`${((_photo.file_size || 0) / 1024 / 1024).toFixed(1)} MB`);
  if (_photo.location_name) parts.push(_photo.location_name);
  if (_photo.ai_scene) parts.push(_photo.ai_scene);
  info.textContent = parts.join(' · ');

  // Description
  const descText = _el.querySelector('#viewer-desc-text');
  descText.textContent = _photo.description || '설명 없음';
  descText.style.color = _photo.description ? '' : 'var(--color-on-surface-variant)';
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
  _el.querySelector('#viewer-desc-display').style.display = '';
  _el.querySelector('#viewer-desc-editor').style.display = 'none';
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
    // Reset timeline cache so it reloads
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
  if (_editingDesc) return; // Don't navigate while editing
  if (e.key === 'ArrowLeft') _prev();
  else if (e.key === 'ArrowRight') _next();
  else if (e.key === 'Escape') navigate('/timeline');
}
