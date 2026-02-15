/**
 * Map view - Leaflet map with photo clusters.
 */
import { apiJson } from '../api.js';
import { navigate } from '../router.js';
import { el } from '../utils.js';
import { observeImages } from '../components/lazy-image.js';

let _el;
let _map = null;
let _markers = [];
let _leafletLoaded = false;

export function init(container) {
  _el = container;
  container.innerHTML = `
    <div class="top-bar">
      <div class="top-bar-title">지도</div>
    </div>
    <div class="map-container" id="map-canvas"></div>
    <div class="map-sidebar" id="map-sidebar" style="display:none">
      <div class="section-header" id="map-sidebar-title"></div>
      <div class="photo-grid" id="map-sidebar-grid"></div>
    </div>
  `;
}

export async function onActivate() {
  await _ensureLeaflet();
  if (!_map) _initMap();
  await _loadClusters();
  setTimeout(() => _map?.invalidateSize(), 100);
}

async function _ensureLeaflet() {
  if (_leafletLoaded) return;
  if (typeof L !== 'undefined') { _leafletLoaded = true; return; }

  // Load Leaflet CSS + JS from CDN
  await new Promise((resolve) => {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
    document.head.appendChild(link);

    const script = document.createElement('script');
    script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
    script.onload = resolve;
    document.head.appendChild(script);
  });
  _leafletLoaded = true;
}

function _initMap() {
  _map = L.map('map-canvas').setView([36.5, 127.8], 7); // Korea center
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap',
    maxZoom: 18,
  }).addTo(_map);
}

async function _loadClusters() {
  try {
    const data = await apiJson('/map/clusters?precision=2');
    const clusters = data.clusters || data || [];
    _clearMarkers();

    for (const c of clusters) {
      if (!c.lat || !c.lon) continue;
      const marker = L.circleMarker([c.lat, c.lon], {
        radius: Math.min(6 + Math.sqrt(c.count) * 3, 30),
        color: 'var(--color-primary)',
        fillColor: '#1a73e8',
        fillOpacity: 0.6,
        weight: 2,
      }).addTo(_map);

      marker.bindTooltip(`${c.location_name || '위치'} (${c.count}장)`);
      marker.on('click', () => _showClusterPhotos(c));
      _markers.push(marker);
    }

    // Fit bounds if markers exist
    if (_markers.length) {
      const group = L.featureGroup(_markers);
      _map.fitBounds(group.getBounds().pad(0.1));
    }
  } catch (e) {
    console.error('Map load error:', e);
  }
}

async function _showClusterPhotos(cluster) {
  const sidebar = _el.querySelector('#map-sidebar');
  sidebar.style.display = '';
  _el.querySelector('#map-sidebar-title').textContent = `${cluster.location_name || '위치'} (${cluster.count}장)`;

  try {
    const data = await apiJson(`/map/nearby?lat=${cluster.lat}&lon=${cluster.lon}&radius=5`);
    const photos = data.photos || data || [];
    const grid = _el.querySelector('#map-sidebar-grid');
    grid.innerHTML = '';

    for (const p of photos) {
      grid.appendChild(el('div', {
        className: 'photo-thumb',
        onClick: () => navigate(`/viewer/${p.id}`),
      }, [
        el('img', { 'data-src': `/api/v1/photos/${p.id}/thumb`, className: 'lazy-img', alt: '' }),
      ]));
    }
    observeImages(grid);
  } catch (e) {
    console.error('Cluster photos error:', e);
  }
}

function _clearMarkers() {
  for (const m of _markers) m.remove();
  _markers = [];
}
