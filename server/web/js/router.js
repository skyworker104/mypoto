/**
 * Hash-based SPA router.
 */
import { isAuthenticated } from './store.js';

const _routes = new Map();
let _currentView = null;
let _mainEl = null;

export function registerRoute(path, viewModule) {
  _routes.set(path, viewModule);
}

export function initRouter(mainElement) {
  _mainEl = mainElement;
  window.addEventListener('hashchange', _onHashChange);
  _onHashChange();
}

export function navigate(path) {
  window.location.hash = path;
}

export function getCurrentRoute() {
  return _parseHash().path;
}

export function getRouteParams() {
  return _parseHash().params;
}

export function getQueryParams() {
  const hash = window.location.hash.slice(1);
  const qIndex = hash.indexOf('?');
  if (qIndex === -1) return {};
  const search = new URLSearchParams(hash.slice(qIndex + 1));
  const params = {};
  for (const [k, v] of search) params[k] = v;
  return params;
}

function _parseHash() {
  const hash = window.location.hash.slice(1) || '/timeline';
  const qIndex = hash.indexOf('?');
  const pathPart = qIndex >= 0 ? hash.slice(0, qIndex) : hash;

  // Match routes with params like /viewer/:id
  for (const routePath of _routes.keys()) {
    const params = _matchRoute(routePath, pathPart);
    if (params !== null) {
      return { path: routePath, params, fullPath: pathPart };
    }
  }

  return { path: pathPart, params: {}, fullPath: pathPart };
}

function _matchRoute(pattern, path) {
  const patternParts = pattern.split('/');
  const pathParts = path.split('/');

  if (patternParts.length !== pathParts.length) return null;

  const params = {};
  for (let i = 0; i < patternParts.length; i++) {
    if (patternParts[i].startsWith(':')) {
      params[patternParts[i].slice(1)] = pathParts[i];
    } else if (patternParts[i] !== pathParts[i]) {
      return null;
    }
  }
  return params;
}

function _onHashChange() {
  const { path, params } = _parseHash();

  // Auth guard
  if (!isAuthenticated() && path !== '/login') {
    window.location.hash = '#/login';
    return;
  }
  if (isAuthenticated() && path === '/login') {
    window.location.hash = '#/timeline';
    return;
  }

  // Toggle nav bar visibility
  document.body.classList.toggle('no-nav', path === '/login');

  const viewModule = _routes.get(path);
  if (!viewModule) {
    window.location.hash = '#/timeline';
    return;
  }

  // Deactivate current view
  if (_currentView?.onDeactivate) _currentView.onDeactivate();

  // Hide all views
  _mainEl.querySelectorAll('.view').forEach(v => v.classList.remove('active'));

  // Show or create target view
  let viewEl = _mainEl.querySelector(`[data-view="${path}"]`);
  if (!viewEl) {
    viewEl = document.createElement('div');
    viewEl.className = 'view';
    viewEl.dataset.view = path;
    _mainEl.appendChild(viewEl);
    viewModule.init(viewEl);
  }
  viewEl.classList.add('active');

  _currentView = viewModule;
  if (viewModule.onActivate) viewModule.onActivate(params);

  // Update nav bar active state
  document.querySelectorAll('.nav-item').forEach(item => {
    const href = item.dataset.route;
    item.classList.toggle('active', href === path);
  });
}
