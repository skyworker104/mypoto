/**
 * Settings view - system status, storage info, server URL.
 */
import { apiJson, apiPost } from '../api.js';
import { getState, logout } from '../store.js';
import { navigate } from '../router.js';
import { formatBytes, el } from '../utils.js';
import { showToast } from '../components/toast.js';

let _el;

export function init(container) {
  _el = container;
  container.innerHTML = `
    <div class="top-bar">
      <div class="top-bar-title">설정</div>
    </div>
    <div class="settings-content" id="settings-content">
      <div class="spinner"></div>
    </div>
  `;
}

export async function onActivate() {
  await _loadStatus();
}

async function _loadStatus() {
  const content = _el.querySelector('#settings-content');

  try {
    const status = await apiJson('/system/status');
    const photoCount = status.photo_count || 0;

    content.innerHTML = '';

    // Server info section with URL
    const serverUrl = status.server_url || `${location.protocol}//${location.host}`;
    content.appendChild(_section('서버 정보', [
      _row('서버 이름', status.server_name || 'PhotoNest'),
      _row('서버 ID', status.server_id || '-'),
      _urlRow('앱 접속 주소', serverUrl),
      _row('버전', status.version || '0.1.0'),
    ]));

    // Storage section
    const totalBytes = status.storage_total_bytes || 0;
    const usedBytes = status.storage_used_bytes || 0;
    const freeBytes = status.storage_free_bytes || 0;
    const usedPct = totalBytes ? Math.round((usedBytes / totalBytes) * 100) : 0;

    content.appendChild(_section('저장 공간', [
      _row('전체', formatBytes(totalBytes)),
      _row('사용중', `${formatBytes(usedBytes)} (${usedPct}%)`),
      _row('남은 공간', formatBytes(freeBytes)),
      _storageBar(usedPct),
    ]));

    // Photo stats
    content.appendChild(_section('사진', [
      _row('전체 사진 수', `${photoCount}장`),
      _row('사진 용량', formatBytes(status.total_size_bytes || 0)),
    ]));

    // Photo management
    content.appendChild(_section('사진 관리', [
      _actionButton('위치정보 재추출', 'location_on', '사진 EXIF에서 GPS 위치정보를 다시 추출하고 지명을 변환합니다.', _reprocessLocation),
    ]));

    // Logout
    const logoutBtn = el('button', {
      className: 'btn btn-outline',
      style: { width: '100%', marginTop: '24px', color: 'var(--color-error)' },
      textContent: '로그아웃',
      onClick: () => {
        if (confirm('로그아웃 할까요?')) {
          logout();
          navigate('/login');
        }
      },
    });
    content.appendChild(logoutBtn);

  } catch (e) {
    content.innerHTML = `<div class="empty-state"><p>상태 정보를 불러올 수 없습니다</p></div>`;
  }
}

function _section(title, children) {
  const section = el('div', { className: 'settings-section' }, [
    el('div', { className: 'settings-section-title', textContent: title }),
    ...children.filter(Boolean),
  ]);
  return section;
}

function _row(label, value) {
  return el('div', { className: 'settings-row' }, [
    el('span', { className: 'settings-label', textContent: label }),
    el('span', { className: 'settings-value', textContent: value }),
  ]);
}

function _urlRow(label, url) {
  const row = el('div', { className: 'settings-row settings-url-row' }, [
    el('span', { className: 'settings-label', textContent: label }),
    el('div', { className: 'settings-url-wrap' }, [
      el('code', { className: 'settings-url-value', textContent: url }),
      el('button', {
        className: 'btn-icon settings-url-copy',
        title: '복사',
        onClick: () => {
          navigator.clipboard.writeText(url).then(() => {
            copyBtn.querySelector('.material-symbols-outlined').textContent = 'check';
            setTimeout(() => {
              copyBtn.querySelector('.material-symbols-outlined').textContent = 'content_copy';
            }, 1500);
          });
        },
      }, [
        el('span', { className: 'material-symbols-outlined', textContent: 'content_copy' }),
      ]),
    ]),
  ]);
  const copyBtn = row.querySelector('.settings-url-copy');
  return row;
}

function _storageBar(pct) {
  const bar = el('div', { className: 'storage-bar' }, [
    el('div', { className: 'storage-bar-fill', style: { width: `${pct}%` } }),
  ]);
  return bar;
}

function _actionButton(label, icon, description, onClick) {
  const btn = el('button', {
    className: 'btn btn-outline settings-action-btn',
    onClick,
  }, [
    el('span', { className: 'material-symbols-outlined', textContent: icon }),
    el('div', { className: 'settings-action-text' }, [
      el('span', { className: 'settings-action-label', textContent: label }),
      el('span', { className: 'settings-action-desc', textContent: description }),
    ]),
  ]);
  return btn;
}

function _reprocessLocation(e) {
  const btn = e.currentTarget;
  const label = btn.querySelector('.settings-action-label');
  const origText = label.textContent;

  btn.disabled = true;
  label.textContent = '처리 중...';

  // Create or reuse log panel
  let logPanel = _el.querySelector('#reprocess-log');
  if (!logPanel) {
    logPanel = el('div', { id: 'reprocess-log', className: 'reprocess-log' });
    // Insert after the photo management section
    btn.closest('.settings-section').after(logPanel);
  }
  logPanel.innerHTML = '';
  logPanel.style.display = '';

  // Progress bar
  const progressWrap = el('div', { className: 'reprocess-progress' }, [
    el('div', { className: 'reprocess-progress-bar', id: 'reprocess-bar' }),
  ]);
  logPanel.appendChild(progressWrap);

  // Status summary line
  const statusLine = el('div', { className: 'reprocess-status', id: 'reprocess-status', textContent: '준비 중...' });
  logPanel.appendChild(statusLine);

  // Scrollable log area
  const logArea = el('div', { className: 'reprocess-log-area', id: 'reprocess-log-area' });
  logPanel.appendChild(logArea);

  const token = getState('auth.accessToken');
  const url = `/api/v1/system/reprocess-location-stream?token=${encodeURIComponent(token)}`;
  const es = new EventSource(url);

  es.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      _handleSSEEvent(data, logArea, statusLine);
    } catch { /* ignore parse errors */ }
  };

  es.onerror = () => {
    es.close();
    btn.disabled = false;
    label.textContent = origText;
    // If no done message was received, show error
    if (!logPanel.dataset.done) {
      showToast('위치정보 재추출 연결 종료', { type: 'error' });
    }
  };
}

function _handleSSEEvent(data, logArea, statusLine) {
  const bar = _el.querySelector('#reprocess-bar');
  const logPanel = _el.querySelector('#reprocess-log');

  if (data.type === 'start') {
    statusLine.textContent = data.message;
    return;
  }

  if (data.type === 'progress' || data.type === 'geocode') {
    // Update progress bar
    if (bar && data.total > 0) {
      const pct = Math.round((data.current / data.total) * 100);
      bar.style.width = `${pct}%`;
    }
    statusLine.textContent = `${data.current} / ${data.total}`;
  }

  if (data.type === 'phase') {
    // Phase separator
    const line = el('div', { className: 'reprocess-line reprocess-phase', textContent: data.message });
    logArea.appendChild(line);
    statusLine.textContent = data.message;
    // Reset progress bar for geocode phase
    if (bar) bar.style.width = '0%';
  }

  if (data.type === 'progress') {
    const statusClass = _statusClass(data.status);
    const line = el('div', { className: `reprocess-line ${statusClass}` }, [
      el('span', { className: 'reprocess-icon', textContent: _statusIcon(data.status) }),
      el('span', { textContent: data.message }),
    ]);
    logArea.appendChild(line);
    logArea.scrollTop = logArea.scrollHeight;
  }

  if (data.type === 'geocode') {
    const line = el('div', { className: 'reprocess-line reprocess-geocode' }, [
      el('span', { className: 'reprocess-icon', textContent: '📍' }),
      el('span', { textContent: data.message }),
    ]);
    logArea.appendChild(line);
    logArea.scrollTop = logArea.scrollHeight;
  }

  if (data.type === 'done') {
    if (logPanel) logPanel.dataset.done = '1';
    statusLine.textContent = data.message;
    if (bar) bar.style.width = '100%';
    showToast(data.message, { type: 'success' });
    // Re-enable button
    const btn = _el.querySelector('.settings-action-btn');
    if (btn) {
      btn.disabled = false;
      btn.querySelector('.settings-action-label').textContent = '위치정보 재추출';
    }
  }
}

function _statusIcon(status) {
  switch (status) {
    case 'skip': return '⏭️';
    case 'extracted': return '✅';
    case 'no_gps': return '📷';
    case 'error': return '❌';
    default: return '•';
  }
}

function _statusClass(status) {
  switch (status) {
    case 'skip': return 'reprocess-skip';
    case 'extracted': return 'reprocess-success';
    case 'no_gps': return 'reprocess-nogps';
    case 'error': return 'reprocess-error';
    default: return '';
  }
}
