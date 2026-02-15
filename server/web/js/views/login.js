/**
 * Login view - PIN pairing.
 */
import { apiJson } from '../api.js';
import { setState } from '../store.js';
import { navigate } from '../router.js';
import { el } from '../utils.js';

let _el;
let _statusEl;
let _deviceName = 'Web Browser';

export function init(container) {
  _el = container;
  container.innerHTML = `
    <div class="login-page">
      <div class="login-card">
        <span class="material-symbols-outlined login-icon">photo_library</span>
        <h1>PhotoNest</h1>
        <p class="text-secondary">가족 사진 백업 & 감상</p>
        <div class="login-step" id="login-step-init">
          <button class="btn btn-primary login-btn" id="btn-init-pair">기기 연결하기</button>
        </div>
        <div class="login-step" id="login-step-pin" style="display:none">
          <p class="login-hint">서버 터미널에 표시된 6자리 PIN을 입력하세요</p>
          <div class="pin-input-row" id="pin-row"></div>
          <button class="btn btn-primary login-btn" id="btn-verify-pin" disabled>확인</button>
        </div>
        <p class="login-status" id="login-status"></p>
      </div>
    </div>
  `;

  // Build 6 PIN digit inputs
  const pinRow = container.querySelector('#pin-row');
  for (let i = 0; i < 6; i++) {
    const inp = el('input', {
      type: 'tel',
      className: 'pin-digit',
      maxLength: '1',
      inputMode: 'numeric',
      'data-index': String(i),
    });
    inp.addEventListener('input', _onPinInput);
    inp.addEventListener('keydown', _onPinKeydown);
    pinRow.appendChild(inp);
  }

  container.querySelector('#btn-init-pair').addEventListener('click', _initPairing);
  container.querySelector('#btn-verify-pin').addEventListener('click', _verifyPin);
}

export function onActivate() {}

function _setStatus(msg, isError = false) {
  _statusEl = _el.querySelector('#login-status');
  _statusEl.textContent = msg;
  _statusEl.style.color = isError ? 'var(--color-error)' : 'var(--color-on-surface-variant)';
}

async function _initPairing() {
  try {
    _setStatus('서버에 연결 중...');
    // pair/init generates a PIN shown on server console
    await apiJson('/pair/init', { method: 'POST', json: {} });
    _el.querySelector('#login-step-init').style.display = 'none';
    _el.querySelector('#login-step-pin').style.display = 'block';
    _setStatus('서버 터미널에서 PIN을 확인하세요');
    _el.querySelector('.pin-digit').focus();
  } catch (e) {
    _setStatus('연결 실패: ' + e.message, true);
  }
}

function _onPinInput(e) {
  const idx = parseInt(e.target.dataset.index);
  if (e.target.value && idx < 5) {
    _el.querySelectorAll('.pin-digit')[idx + 1].focus();
  }
  _updateVerifyBtn();
}

function _onPinKeydown(e) {
  const idx = parseInt(e.target.dataset.index);
  if (e.key === 'Backspace' && !e.target.value && idx > 0) {
    _el.querySelectorAll('.pin-digit')[idx - 1].focus();
  }
  if (e.key === 'Enter') _verifyPin();
}

function _updateVerifyBtn() {
  const digits = _el.querySelectorAll('.pin-digit');
  const pin = [...digits].map(d => d.value).join('');
  _el.querySelector('#btn-verify-pin').disabled = pin.length < 6;
}

async function _verifyPin() {
  const digits = _el.querySelectorAll('.pin-digit');
  const pin = [...digits].map(d => d.value).join('');
  if (pin.length < 6) return;

  try {
    _setStatus('인증 중...');
    const data = await apiJson('/pair', {
      method: 'POST',
      json: {
        pin,
        device_name: _deviceName,
        device_type: 'web',
      },
    });
    setState('auth.accessToken', data.access_token);
    setState('auth.refreshToken', data.refresh_token);
    setState('auth.deviceId', data.device_id || null);
    navigate('/timeline');
  } catch (e) {
    _setStatus('PIN이 올바르지 않습니다', true);
    digits.forEach(d => { d.value = ''; });
    digits[0].focus();
  }
}
