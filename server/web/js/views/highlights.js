/**
 * Highlights view - list + generate.
 */
import { apiJson, apiPost, apiDelete } from '../api.js';
import { el, formatDuration } from '../utils.js';

let _el;
let _highlights = [];

export function init(container) {
  _el = container;
  container.innerHTML = `
    <div class="top-bar">
      <div class="top-bar-title">하이라이트</div>
    </div>
    <div id="highlights-list"></div>
    <button class="fab" id="highlight-fab" title="새 하이라이트">
      <span class="material-symbols-outlined">add</span>
    </button>
  `;

  container.querySelector('#highlight-fab').addEventListener('click', _showCreateDialog);
}

export async function onActivate() {
  await _loadHighlights();
}

async function _loadHighlights() {
  try {
    const data = await apiJson('/highlights');
    _highlights = data.highlights || data || [];
    _render();
  } catch (e) {
    console.error('Highlights load error:', e);
  }
}

function _render() {
  const list = _el.querySelector('#highlights-list');
  list.innerHTML = '';

  if (!_highlights.length) {
    list.innerHTML = `
      <div class="empty-state">
        <span class="material-symbols-outlined">movie_creation</span>
        <p>하이라이트 영상이 없습니다</p>
        <p>+ 버튼으로 새 하이라이트를 만들어보세요</p>
      </div>
    `;
    return;
  }

  for (const h of _highlights) {
    const statusClass = h.status || 'pending';
    const statusLabels = { completed: '완료', processing: '생성중', failed: '실패', pending: '대기' };

    const card = el('div', { className: 'card highlight-card' }, [
      el('div', { className: 'highlight-thumb' }, [
        h.status === 'completed'
          ? el('div', { className: 'highlight-play', innerHTML: '<span class="material-symbols-outlined">play_circle</span>' })
          : h.status === 'processing'
            ? el('div', { className: 'spinner' })
            : el('span', { className: 'material-symbols-outlined', textContent: 'movie_creation', style: { fontSize: '48px', color: 'var(--color-on-surface-variant)' } }),
      ]),
      el('div', { className: 'card-body' }, [
        el('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center' } }, [
          el('div', { className: 'card-title', textContent: h.title }),
          el('span', { className: `status-chip ${statusClass}`, textContent: statusLabels[statusClass] || '대기' }),
        ]),
        el('div', { className: 'card-subtitle', textContent: `${h.photo_count || 0}장 · ${formatDuration(h.duration_seconds)}` }),
        h.error_message ? el('div', { textContent: h.error_message, style: { color: 'var(--color-error)', fontSize: 'var(--font-size-xs)', marginTop: '4px' } }) : null,
      ]),
    ]);

    if (h.status === 'completed' && h.id) {
      card.style.cursor = 'pointer';
      card.addEventListener('click', () => _playHighlight(h));
    }

    list.appendChild(card);
  }
}

function _playHighlight(h) {
  const video = document.createElement('video');
  video.src = `/api/v1/highlights/${h.id}/video`;
  video.controls = true;
  video.autoplay = true;
  video.style.cssText = 'position:fixed;inset:0;z-index:9999;width:100%;height:100%;background:#000;object-fit:contain';
  video.addEventListener('click', e => { if (e.target === video) { video.pause(); video.remove(); } });
  document.addEventListener('keydown', function esc(e) {
    if (e.key === 'Escape') { video.pause(); video.remove(); document.removeEventListener('keydown', esc); }
  });
  document.body.appendChild(video);
}

function _showCreateDialog() {
  // Simple prompt-based creation
  const title = prompt('하이라이트 제목을 입력하세요:');
  if (!title?.trim()) return;

  apiPost('/highlights/generate', {
    title: title.trim(),
    source_type: 'date_range',
  }).then(() => {
    _loadHighlights();
  }).catch(e => {
    alert('생성 실패: ' + e.message);
  });
}
