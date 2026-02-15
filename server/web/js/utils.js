/**
 * Utility helpers.
 */

const KO_DAYS = ['일', '월', '화', '수', '목', '금', '토'];
const KO_MONTHS = ['1월', '2월', '3월', '4월', '5월', '6월', '7월', '8월', '9월', '10월', '11월', '12월'];

/** "2025년 3월 15일 토요일" */
export function formatDateKo(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  if (isNaN(d)) return dateStr;
  return `${d.getFullYear()}년 ${KO_MONTHS[d.getMonth()]} ${d.getDate()}일 ${KO_DAYS[d.getDay()]}요일`;
}

/** "2025. 3. 15" */
export function formatDateShort(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  if (isNaN(d)) return dateStr;
  return `${d.getFullYear()}. ${d.getMonth() + 1}. ${d.getDate()}`;
}

/** "3월 15일" */
export function formatMonthDay(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  if (isNaN(d)) return dateStr;
  return `${KO_MONTHS[d.getMonth()]} ${d.getDate()}일`;
}

/** Date grouping key: "2025-03-15" */
export function dateKey(dateStr) {
  if (!dateStr) return 'unknown';
  return dateStr.slice(0, 10);
}

/** Group photos by date → [{date, label, photos}] */
export function groupByDate(photos) {
  const groups = new Map();
  for (const photo of photos) {
    const key = dateKey(photo.taken_at || photo.created_at);
    if (!groups.has(key)) {
      groups.set(key, {
        date: key,
        label: formatDateKo(key),
        photos: [],
      });
    }
    groups.get(key).photos.push(photo);
  }
  return [...groups.values()];
}

/** Debounce */
export function debounce(fn, ms = 300) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

/** Throttle */
export function throttle(fn, ms = 100) {
  let last = 0;
  return (...args) => {
    const now = Date.now();
    if (now - last >= ms) {
      last = now;
      fn(...args);
    }
  };
}

/** Format bytes → "1.2 GB" */
export function formatBytes(bytes) {
  if (!bytes) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0;
  let val = bytes;
  while (val >= 1024 && i < units.length - 1) {
    val /= 1024;
    i++;
  }
  return `${val.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

/** Format duration → "1:30" */
export function formatDuration(seconds) {
  if (!seconds) return '0:00';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

/** Simple HTML escaping */
export function escapeHtml(str) {
  const el = document.createElement('span');
  el.textContent = str;
  return el.innerHTML;
}

/** Create element shorthand */
export function el(tag, attrs = {}, children = []) {
  const element = document.createElement(tag);
  for (const [key, val] of Object.entries(attrs)) {
    if (key === 'className') element.className = val;
    else if (key === 'textContent') element.textContent = val;
    else if (key === 'innerHTML') element.innerHTML = val;
    else if (key.startsWith('on')) element.addEventListener(key.slice(2).toLowerCase(), val);
    else if (key === 'style' && typeof val === 'object') Object.assign(element.style, val);
    else element.setAttribute(key, val);
  }
  for (const child of Array.isArray(children) ? children : [children]) {
    if (typeof child === 'string') element.appendChild(document.createTextNode(child));
    else if (child) element.appendChild(child);
  }
  return element;
}
