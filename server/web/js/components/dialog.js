/**
 * Modal dialog component.
 */
import { el } from '../utils.js';

let _overlay = null;

export function showDialog({ title, content, actions = [] }) {
  closeDialog();

  _overlay = el('div', { className: 'dialog-overlay', onClick: (e) => {
    if (e.target === _overlay) closeDialog();
  }});

  const dialog = el('div', { className: 'dialog' });

  if (title) {
    dialog.appendChild(el('div', { className: 'dialog-title', textContent: title }));
  }

  if (typeof content === 'string') {
    dialog.appendChild(el('div', { className: 'dialog-content', textContent: content }));
  } else if (content instanceof HTMLElement) {
    const wrap = el('div', { className: 'dialog-content' });
    wrap.appendChild(content);
    dialog.appendChild(wrap);
  }

  if (actions.length) {
    const bar = el('div', { className: 'dialog-actions' });
    for (const action of actions) {
      bar.appendChild(el('button', {
        className: `btn ${action.primary ? 'btn-primary' : 'btn-text'}`,
        textContent: action.label,
        onClick: () => {
          if (action.onClick) action.onClick();
          if (action.close !== false) closeDialog();
        },
      }));
    }
    dialog.appendChild(bar);
  }

  _overlay.appendChild(dialog);
  document.body.appendChild(_overlay);

  // Animate in
  requestAnimationFrame(() => _overlay.classList.add('dialog-open'));
}

export function closeDialog() {
  if (_overlay) {
    _overlay.remove();
    _overlay = null;
  }
}

/**
 * Confirm dialog: returns a promise that resolves to true/false.
 */
export function confirmDialog(message, title = '') {
  return new Promise(resolve => {
    showDialog({
      title,
      content: message,
      actions: [
        { label: '취소', onClick: () => resolve(false) },
        { label: '확인', primary: true, onClick: () => resolve(true) },
      ],
    });
  });
}
