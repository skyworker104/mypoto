/**
 * PhotoNest Web App - Entry point.
 */
import { registerRoute, initRouter } from './router.js';
import { isAuthenticated, setState } from './store.js';
import { apiJson } from './api.js';
import * as login from './views/login.js';
import * as timeline from './views/timeline.js';
import * as viewer from './views/viewer.js';
import * as search from './views/search.js';
import * as albums from './views/albums.js';
import * as mapView from './views/map.js';
import * as highlights from './views/highlights.js';
import * as tv from './views/tv.js';
import * as settings from './views/settings.js';

// Register all routes
registerRoute('/login', login);
registerRoute('/timeline', timeline);
registerRoute('/viewer/:id', viewer);
registerRoute('/search', search);
registerRoute('/albums', albums);
registerRoute('/map', mapView);
registerRoute('/highlights', highlights);
registerRoute('/tv', tv);
registerRoute('/settings', settings);

// Auto-login for /local access (no PIN required)
async function _tryLocalAuth() {
  if (isAuthenticated()) return;
  if (!window.location.pathname.startsWith('/local')) return;
  try {
    const data = await apiJson('/auth/local', { method: 'POST', json: {} });
    setState('auth.accessToken', data.access_token);
    setState('auth.refreshToken', data.refresh_token);
    setState('auth.deviceId', data.device_id || null);
  } catch (e) {
    console.error('Local auto-auth failed:', e);
  }
}

// Initialize
const mainEl = document.getElementById('app-main');
await _tryLocalAuth();
initRouter(mainEl);

// Setup nav bar click handlers
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', (e) => {
    e.preventDefault();
    const route = item.dataset.route;
    if (route) window.location.hash = `#${route}`;
  });
});
