/**
 * API client with JWT auth and auto-refresh.
 */
import { getState, setState, logout } from './store.js';

const BASE = '/api/v1';

let _refreshPromise = null;

export async function api(path, options = {}) {
  const url = path.startsWith('http') ? path : `${BASE}${path}`;
  const token = getState('auth.accessToken');

  const headers = { ...options.headers };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (options.json) {
    headers['Content-Type'] = 'application/json';
  }

  const res = await fetch(url, {
    ...options,
    headers,
    body: options.json ? JSON.stringify(options.json) : options.body,
  });

  // Auto-refresh on 401
  if (res.status === 401 && getState('auth.refreshToken')) {
    const refreshed = await _refreshToken();
    if (refreshed) {
      // Retry with new token
      const newToken = getState('auth.accessToken');
      headers['Authorization'] = `Bearer ${newToken}`;
      return fetch(url, { ...options, headers, body: options.json ? JSON.stringify(options.json) : options.body });
    }
    // Refresh failed
    logout();
    window.location.hash = '#/login';
    throw new Error('Session expired');
  }

  return res;
}

export async function apiJson(path, options = {}) {
  const res = await api(path, options);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API ${res.status}: ${text}`);
  }
  return res.json();
}

export async function apiPost(path, data) {
  return apiJson(path, { method: 'POST', json: data });
}

export async function apiPatch(path, data) {
  return apiJson(path, { method: 'PATCH', json: data });
}

export async function apiDelete(path) {
  const res = await api(path, { method: 'DELETE' });
  if (!res.ok && res.status !== 204) {
    throw new Error(`API ${res.status}`);
  }
  return res;
}

/**
 * Fetch an authenticated image as a Blob URL.
 * Uses LRU cache to limit memory.
 */
const _imageCache = new Map();
const IMAGE_CACHE_MAX = 200;

export async function fetchImageUrl(path) {
  if (_imageCache.has(path)) return _imageCache.get(path);

  const res = await api(path);
  if (!res.ok) return null;

  const blob = await res.blob();
  const url = URL.createObjectURL(blob);

  // LRU eviction
  if (_imageCache.size >= IMAGE_CACHE_MAX) {
    const oldest = _imageCache.keys().next().value;
    URL.revokeObjectURL(_imageCache.get(oldest));
    _imageCache.delete(oldest);
  }
  _imageCache.set(path, url);
  return url;
}

/**
 * Upload a file via multipart/form-data with auth.
 */
export async function apiUpload(file) {
  const form = new FormData();
  form.append('file', file);
  return apiJson('/photos/upload', { method: 'POST', body: form });
}

export function clearImageCache() {
  for (const url of _imageCache.values()) {
    URL.revokeObjectURL(url);
  }
  _imageCache.clear();
}

async function _refreshToken() {
  if (_refreshPromise) return _refreshPromise;

  _refreshPromise = (async () => {
    try {
      const res = await fetch(`${BASE}/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          refresh_token: getState('auth.refreshToken'),
        }),
      });
      if (!res.ok) return false;
      const data = await res.json();
      setState('auth.accessToken', data.access_token);
      if (data.refresh_token) {
        setState('auth.refreshToken', data.refresh_token);
      }
      return true;
    } catch {
      return false;
    } finally {
      _refreshPromise = null;
    }
  })();

  return _refreshPromise;
}
