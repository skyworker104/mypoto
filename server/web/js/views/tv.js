/**
 * TV slideshow view - fullscreen slideshow mode.
 */
import { apiJson, apiPost, fetchImageUrl } from '../api.js';
import { getQueryParams } from '../router.js';
import { getState } from '../store.js';

let _el;
let _active = false;
let _paused = false;
let _timer = null;
let _photos = [];
let _index = 0;
let _cursorTimer = null;
let _syncWs = null;

export function init(container) {
  _el = container;
  container.innerHTML = `
    <div class="tv-setup" id="tv-setup">
      <div class="top-bar">
        <div class="top-bar-title">TV 슬라이드쇼</div>
      </div>
      <div class="tv-options">
        <div class="tv-option-group">
          <label>전환 간격</label>
          <div class="chip-row">
            <button class="chip active" data-interval="5">5초</button>
            <button class="chip" data-interval="10">10초</button>
            <button class="chip" data-interval="15">15초</button>
            <button class="chip" data-interval="30">30초</button>
          </div>
        </div>
        <button class="btn btn-primary" id="tv-start-btn" style="width:100%;margin-top:24px;height:48px;font-size:16px">
          <span class="material-symbols-outlined">slideshow</span>
          슬라이드쇼 시작
        </button>
      </div>
    </div>
    <div class="tv-player" id="tv-player" style="display:none">
      <img class="tv-image" id="tv-image" alt="" />
      <div class="tv-controls" id="tv-controls">
        <button class="btn-icon tv-ctrl" id="tv-prev"><span class="material-symbols-outlined">skip_previous</span></button>
        <button class="btn-icon tv-ctrl" id="tv-pause"><span class="material-symbols-outlined">pause</span></button>
        <button class="btn-icon tv-ctrl" id="tv-next"><span class="material-symbols-outlined">skip_next</span></button>
        <button class="btn-icon tv-ctrl" id="tv-exit"><span class="material-symbols-outlined">fullscreen_exit</span></button>
      </div>
      <div class="tv-info" id="tv-info"></div>
    </div>
    <div class="tv-display-overlay" id="tv-display-overlay" style="display:none">
      <div class="tv-response-text" id="tv-response-text"></div>
      <div class="tv-photo-grid" id="tv-photo-grid"></div>
      <button class="btn-icon tv-overlay-close" id="tv-overlay-close">
        <span class="material-symbols-outlined">close</span>
      </button>
    </div>
  `;

  // Interval chips
  _el.querySelectorAll('[data-interval]').forEach(chip => {
    chip.addEventListener('click', () => {
      _el.querySelectorAll('[data-interval]').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
    });
  });

  _el.querySelector('#tv-start-btn').addEventListener('click', _startSlideshow);
  _el.querySelector('#tv-prev').addEventListener('click', _prev);
  _el.querySelector('#tv-pause').addEventListener('click', _togglePause);
  _el.querySelector('#tv-next').addEventListener('click', _next);
  _el.querySelector('#tv-exit').addEventListener('click', _stopSlideshow);
  _el.querySelector('#tv-overlay-close').addEventListener('click', _hideOverlay);

  // Keyboard
  document.addEventListener('keydown', _onKey);

  // Mouse movement → show controls
  _el.querySelector('#tv-player').addEventListener('mousemove', _showControls);
}

export function onActivate() {
  const params = getQueryParams();
  if (params.auto === 'true') {
    setTimeout(_startSlideshow, 500);
  }
  _connectSyncWs();
}

export function onDeactivate() {
  _stopSlideshow();
  _disconnectSyncWs();
}

async function _startSlideshow() {
  const intervalChip = _el.querySelector('[data-interval].active');
  const interval = parseInt(intervalChip?.dataset.interval || '10') * 1000;

  try {
    // Use server API to get slideshow photos
    const data = await apiPost('/tv/slideshow/start', {});
    const photos = data.photos || [];

    if (!photos.length) {
      // Fallback: load recent photos
      const fallback = await apiJson('/photos?limit=100');
      _photos = fallback.photos || fallback.items || fallback || [];
    } else {
      _photos = photos;
    }

    if (!_photos.length) {
      alert('표시할 사진이 없습니다');
      return;
    }

    _index = 0;
    _active = true;
    _paused = false;

    // Enter fullscreen
    document.body.classList.add('tv-mode');
    _el.querySelector('#tv-setup').style.display = 'none';
    _el.querySelector('#tv-player').style.display = '';

    try {
      await _el.querySelector('#tv-player').requestFullscreen?.();
    } catch {}

    _showPhoto();
    _timer = setInterval(() => {
      if (!_paused) _next();
    }, interval);

    _showControls();
  } catch (e) {
    console.error('Slideshow start error:', e);
  }
}

function _stopSlideshow() {
  _active = false;
  clearInterval(_timer);
  clearTimeout(_cursorTimer);
  document.body.classList.remove('tv-mode');

  if (document.fullscreenElement) {
    document.exitFullscreen?.();
  }

  _el.querySelector('#tv-setup').style.display = '';
  _el.querySelector('#tv-player').style.display = 'none';

  // Notify server
  apiPost('/tv/slideshow/stop', {}).catch(() => {});
}

async function _showPhoto() {
  if (!_photos.length) return;
  const photo = _photos[_index];
  const img = _el.querySelector('#tv-image');

  const url = await fetchImageUrl(`/api/v1/photos/${photo.id}/file`);
  if (url) {
    img.style.opacity = '0';
    img.src = url;
    img.onload = () => { img.style.opacity = '1'; };
  }

  // Info
  const info = _el.querySelector('#tv-info');
  const parts = [];
  if (photo.taken_at) parts.push(photo.taken_at.slice(0, 10));
  if (photo.location_name) parts.push(photo.location_name);
  info.textContent = parts.join(' · ') || '';
}

function _next() {
  _index = (_index + 1) % _photos.length;
  _showPhoto();
}

function _prev() {
  _index = (_index - 1 + _photos.length) % _photos.length;
  _showPhoto();
}

function _togglePause() {
  _paused = !_paused;
  const icon = _el.querySelector('#tv-pause .material-symbols-outlined');
  icon.textContent = _paused ? 'play_arrow' : 'pause';
}

function _showControls() {
  const controls = _el.querySelector('#tv-controls');
  const info = _el.querySelector('#tv-info');
  controls.style.opacity = '1';
  info.style.opacity = '1';
  document.body.style.cursor = '';

  clearTimeout(_cursorTimer);
  _cursorTimer = setTimeout(() => {
    if (_active && !_paused) {
      controls.style.opacity = '0';
      info.style.opacity = '0';
      document.body.style.cursor = 'none';
    }
  }, 3000);
}

function _onKey(e) {
  if (!_active) return;
  switch (e.key) {
    case 'ArrowRight': _next(); _showControls(); break;
    case 'ArrowLeft': _prev(); _showControls(); break;
    case ' ': e.preventDefault(); _togglePause(); _showControls(); break;
    case 'Escape': _stopSlideshow(); _hideOverlay(); break;
  }
}

// --- Sync WebSocket for display_sync from voice commands ---

function _connectSyncWs() {
  const token = getState('auth.accessToken');
  if (!token) return;

  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const url = `${proto}//${location.host}/ws?token=${token}`;

  try {
    _syncWs = new WebSocket(url);
    _syncWs.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'display_sync') {
          _handleDisplaySync(msg);
        }
      } catch {}
    };
    _syncWs.onclose = () => {
      // Auto-reconnect after 5s
      setTimeout(() => {
        if (_el) _connectSyncWs();
      }, 5000);
    };
  } catch (e) {
    console.error('Sync WS error:', e);
  }
}

function _disconnectSyncWs() {
  if (_syncWs) {
    _syncWs.onclose = null; // Prevent auto-reconnect
    _syncWs.close();
    _syncWs = null;
  }
}

function _handleDisplaySync(msg) {
  const screen = msg.screen;
  const data = msg;

  switch (screen) {
    case 'photo_grid':
      _showPhotoGrid(data.photos || [], data.response || '');
      break;
    case 'slideshow':
      // Start slideshow with provided photos
      if (data.photos && data.photos.length) {
        _photos = data.photos;
        _index = 0;
        _active = true;
        _paused = false;
        document.body.classList.add('tv-mode');
        _el.querySelector('#tv-setup').style.display = 'none';
        _el.querySelector('#tv-player').style.display = '';
        _hideOverlay();
        _showPhoto();
        clearInterval(_timer);
        _timer = setInterval(() => { if (!_paused) _next(); }, 5000);
        _showControls();
      }
      break;
    case 'text':
      _showText(data.response || data.text || '');
      break;
    case 'map':
      _showText(data.response || '지도 표시 기능은 웹에서 준비 중입니다.');
      break;
    case 'system_info':
      _showText(data.response || '시스템 정보');
      break;
    default:
      if (data.response) _showText(data.response);
      break;
  }
}

function _showPhotoGrid(photos, responseText) {
  _hideOverlay();
  _stopSlideshow();

  const overlay = _el.querySelector('#tv-display-overlay');
  const textEl = _el.querySelector('#tv-response-text');
  const gridEl = _el.querySelector('#tv-photo-grid');

  textEl.textContent = responseText;
  gridEl.innerHTML = '';

  photos.slice(0, 20).forEach(photo => {
    const div = document.createElement('div');
    div.className = 'tv-grid-item';
    const img = document.createElement('img');
    img.alt = '';
    img.loading = 'lazy';
    fetchImageUrl(`/api/v1/photos/${photo.id}/thumb?size=medium`).then(url => {
      if (url) img.src = url;
    });
    div.appendChild(img);
    gridEl.appendChild(div);
  });

  overlay.style.display = '';
}

function _showText(text) {
  _hideOverlay();

  const overlay = _el.querySelector('#tv-display-overlay');
  const textEl = _el.querySelector('#tv-response-text');
  const gridEl = _el.querySelector('#tv-photo-grid');

  textEl.textContent = text;
  gridEl.innerHTML = '';
  overlay.style.display = '';
}

function _hideOverlay() {
  const overlay = _el.querySelector('#tv-display-overlay');
  if (overlay) overlay.style.display = 'none';
}
