/**
 * Global state store with pub/sub.
 */
const _state = {
  auth: {
    accessToken: localStorage.getItem('pn_access_token') || null,
    refreshToken: localStorage.getItem('pn_refresh_token') || null,
    deviceId: localStorage.getItem('pn_device_id') || null,
    user: null,
  },
  photos: {
    items: [],
    cursor: null,
    hasMore: true,
    loading: false,
  },
  currentRoute: '',
};

const _listeners = new Map();

export function getState(path) {
  if (!path) return _state;
  return path.split('.').reduce((o, k) => o?.[k], _state);
}

export function setState(path, value) {
  const keys = path.split('.');
  const last = keys.pop();
  const target = keys.reduce((o, k) => o[k], _state);
  target[last] = value;

  // Persist auth tokens
  if (path.startsWith('auth.')) {
    _persistAuth();
  }

  _notify(path);
}

export function updateState(path, updater) {
  const current = getState(path);
  setState(path, updater(current));
}

export function subscribe(path, callback) {
  if (!_listeners.has(path)) _listeners.set(path, new Set());
  _listeners.get(path).add(callback);
  return () => _listeners.get(path)?.delete(callback);
}

function _notify(path) {
  // Notify exact match and parent paths
  for (const [key, cbs] of _listeners) {
    if (path.startsWith(key) || key.startsWith(path)) {
      cbs.forEach(cb => cb(getState(key)));
    }
  }
}

function _persistAuth() {
  const { accessToken, refreshToken, deviceId } = _state.auth;
  if (accessToken) localStorage.setItem('pn_access_token', accessToken);
  else localStorage.removeItem('pn_access_token');
  if (refreshToken) localStorage.setItem('pn_refresh_token', refreshToken);
  else localStorage.removeItem('pn_refresh_token');
  if (deviceId) localStorage.setItem('pn_device_id', deviceId);
  else localStorage.removeItem('pn_device_id');
}

export function isAuthenticated() {
  return !!_state.auth.accessToken;
}

export function logout() {
  setState('auth.accessToken', null);
  setState('auth.refreshToken', null);
  setState('auth.user', null);
}
