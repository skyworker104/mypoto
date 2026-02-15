/**
 * Reusable photo grid component.
 */
import { navigate } from '../router.js';
import { groupByDate, el } from '../utils.js';
import { observeImages } from './lazy-image.js';

/**
 * Create a date-grouped photo grid.
 * @param {HTMLElement} container
 * @param {Array} photos
 * @param {Object} options
 */
export function createPhotoGrid(container, photos, options = {}) {
  container.innerHTML = '';

  if (!photos.length) {
    container.innerHTML = `
      <div class="empty-state">
        <span class="material-symbols-outlined">${options.emptyIcon || 'photo_library'}</span>
        <p>${options.emptyText || '사진이 없습니다'}</p>
      </div>
    `;
    return;
  }

  if (options.grouped !== false) {
    const groups = groupByDate(photos);
    for (const group of groups) {
      const section = el('div', { className: 'timeline-section' });
      section.appendChild(el('div', { className: 'section-header', textContent: group.label }));
      const grid = el('div', { className: 'photo-grid' });
      _appendThumbs(grid, group.photos, options);
      section.appendChild(grid);
      container.appendChild(section);
    }
  } else {
    const grid = el('div', { className: 'photo-grid' });
    _appendThumbs(grid, photos, options);
    container.appendChild(grid);
  }

  observeImages(container);
}

function _appendThumbs(grid, photos, options) {
  for (const photo of photos) {
    const thumb = el('div', {
      className: 'photo-thumb',
      'data-id': photo.id,
      onClick: () => {
        if (options.onSelect) options.onSelect(photo);
        else navigate(`/viewer/${photo.id}`);
      },
    }, [
      el('img', {
        'data-src': `/api/v1/photos/${photo.id}/thumb`,
        alt: '',
        className: 'lazy-img',
      }),
    ]);

    if (photo.is_favorite) {
      thumb.appendChild(el('span', {
        className: 'thumb-fav material-symbols-outlined',
        textContent: 'favorite',
      }));
    }

    grid.appendChild(thumb);
  }
}
