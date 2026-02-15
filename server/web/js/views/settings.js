/**
 * Settings view - system status, storage info, server URL.
 */
import { apiJson } from '../api.js';
import { logout } from '../store.js';
import { navigate } from '../router.js';
import { formatBytes, el } from '../utils.js';

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
