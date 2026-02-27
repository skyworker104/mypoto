/**
 * Lazy image loading with authenticated fetch + IntersectionObserver.
 * Uses fetch() + Blob URL to add Authorization header to image requests.
 * Includes offscreen unloading to limit memory usage on large timelines.
 */
import { getState } from '../store.js';

let _observer = null;
let _unloadObserver = null;

function _getObserver() {
  if (_observer) return _observer;

  _observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        const img = entry.target;
        _loadImage(img);
        _observer.unobserve(img);
        // Start watching for offscreen unloading
        _getUnloadObserver().observe(img);
      }
    }
  }, {
    rootMargin: '200px 0px',
    threshold: 0.01,
  });

  return _observer;
}

function _getUnloadObserver() {
  if (_unloadObserver) return _unloadObserver;

  _unloadObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) {
        const img = entry.target;
        // Revoke blob URL to free memory
        if (img.src && img.src.startsWith('blob:')) {
          URL.revokeObjectURL(img.src);
          img.src = '';
          img.classList.remove('lazy-loaded');
          // Re-observe for lazy loading when it comes back into view
          _unloadObserver.unobserve(img);
          _getObserver().observe(img);
        }
      }
    }
  }, {
    rootMargin: '2000px 0px', // unload when 2000px offscreen
    threshold: 0,
  });

  return _unloadObserver;
}

async function _loadImage(img) {
  const src = img.dataset.src;
  if (!src) return;

  try {
    const token = getState('auth.accessToken');
    const headers = {};
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const res = await fetch(src, { headers });
    if (!res.ok) {
      img.classList.add('lazy-error');
      return;
    }
    const blob = await res.blob();
    img.src = URL.createObjectURL(blob);
    img.classList.add('lazy-loaded');
  } catch {
    img.classList.add('lazy-error');
  }
}

/**
 * Observe all lazy images within a container.
 */
export function observeImages(container) {
  const observer = _getObserver();
  const images = container.querySelectorAll('img.lazy-img:not(.lazy-loaded):not(.lazy-error)');
  images.forEach(img => observer.observe(img));
}

/**
 * Force-load a single image (for viewer).
 */
export async function lazyLoad(img) {
  await _loadImage(img);
}
