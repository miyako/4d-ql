import './style.css';
import { WriteProDocument } from './document.js';
import { DocumentError, MAX_ARCHIVE } from './archive.js';
import { languages, messages, detectLanguage } from './i18n.js';

let locale = detectLanguage();
let theme = 'system';
try {
  const savedLanguage = localStorage.getItem('4wp-language');
  if (savedLanguage in messages) locale = savedLanguage;
  const savedTheme = localStorage.getItem('4wp-theme');
  if (['system', 'light', 'dark'].includes(savedTheme)) theme = savedTheme;
} catch (error) {
  console.warn('Preferences unavailable', error);
}
let model = WriteProDocument.create(messages[locale].untitled);
let saved = model.serialize();
let active = null;
let selection = null;
let errorCode = null;
let downloadReady = false;
let opening = false;
const t = key => messages[locale][key];

document.querySelector('#app').innerHTML = `
  <header class="app-header">
    <div class="brand"><div class="brand-mark" aria-hidden="true">W</div>
      <div><h1>4WP Editor <span class="pill" data-i18n="experimental"></span></h1><p data-i18n="tagline"></p></div>
    </div>
    <div class="file-actions">
      <button id="new" data-i18n="new"></button><button id="open" data-i18n="open"></button>
      <button id="download" class="primary" data-i18n="download"></button>
      <button id="settings-toggle" class="icon-button" data-label="settings" aria-expanded="false" aria-controls="settings">⚙</button>
    </div>
  </header>
  <section id="settings" class="settings" hidden>
    <label><span data-i18n="language"></span><select id="language"></select></label>
    <label><span data-i18n="theme"></span><select id="theme">
      <option value="system" data-i18n="system"></option><option value="light" data-i18n="light"></option><option value="dark" data-i18n="dark"></option>
    </select></label>
  </section>
  <main>
    <section class="workspace">
      <div class="document-bar"><div><span class="document-kind" data-i18n="document"></span><h2 id="document-title"></h2></div><span id="save-state" role="status"></span></div>
      <div class="toolbar" role="toolbar" aria-label="Text formatting">
        <button id="undo" data-label="undo">↶</button><button id="redo" data-label="redo">↷</button>
        <span class="separator"></span>
        <select id="font" data-label="font"><option>Arial</option><option>Helvetica</option><option>Times New Roman</option><option>Georgia</option><option>Courier New</option></select>
        <select id="size" data-label="size"><option>9</option><option>10</option><option selected>12</option><option>14</option><option>18</option><option>24</option><option>36</option></select>
        <button id="bold" data-label="bold"><b>B</b></button><button id="italic" data-label="italic"><i>I</i></button><button id="underline" data-label="underline"><u>U</u></button>
        <label class="color-control"><span data-i18n="color" class="sr-only"></span><input id="color" type="color" value="#327fce" data-label="color"></label>
        <span class="separator"></span>
        <button id="left" data-label="left">≡</button><button id="center" data-label="center">☰</button><button id="right" data-label="right">≡</button>
        <button id="paragraph" class="add-paragraph" data-i18n="paragraph"></button>
      </div>
      <div id="error" class="notice error" role="alert" hidden><strong data-i18n="errorTitle"></strong><p id="error-message"></p><button id="dismiss-error" data-i18n="close"></button></div>
      <div id="readonly-notice" class="notice" data-i18n="bookmarkNotice" hidden></div>
      <div class="paper-surround"><article id="paper" class="paper" data-label="editor"></article></div>
      <footer class="document-footer"><span id="statistics"></span><span data-i18n="local"></span></footer>
    </section>
    <aside class="guide">
      <div class="guide-symbol" aria-hidden="true">¶</div><h2 data-i18n="details"></h2><p data-i18n="intro"></p>
      <hr><p data-i18n="editing"></p><p data-i18n="preservation"></p><p class="limitations" data-i18n="limits"></p><small data-i18n="shortcut"></small>
    </aside>
  </main>
  <input id="file" type="file" accept=".4wp" hidden>
`;
const $ = id => document.getElementById(id);
for (const [value, label] of Object.entries(languages)) $('language').add(new Option(label, value));

function unsaved() { return model.serialize() !== saved; }

function showError(error) {
  errorCode = error instanceof DocumentError ? error.code : 'unexpected';
  if (!(error instanceof DocumentError)) console.error(error);
  $('error-message').textContent = t(errorCode);
  $('error').hidden = false;
}

function updateStatus() {
  $('document-title').textContent = model.title;
  document.title = `${unsaved() ? '• ' : ''}${model.title} — 4WP Editor`;
  $('save-state').textContent = t(model.readOnly ? 'readonly' : unsaved() ? 'changed' : downloadReady ? 'downloaded' : 'ready');
  $('save-state').classList.toggle('unsaved', unsaved());
  $('undo').disabled = model.undoStack.length === 0;
  $('redo').disabled = model.redoStack.length === 0;
  const editable = active !== null && model.runs[active] && !model.protected(model.runs[active].parentElement);
  for (const id of ['bold', 'italic', 'underline', 'font', 'size', 'color', 'left', 'center', 'right']) $(id).disabled = !editable;
  const block = active !== null ? $('paper').querySelector(`[data-run="${active}"]`)?.closest('[data-block]') : null;
  const sourceBlock = block ? model.blocks[Number(block.dataset.block)] : null;
  $('paragraph').disabled = model.readOnly || Boolean(sourceBlock &&
    (sourceBlock.parentElement.localName !== 'body' || model.protected(sourceBlock)));
  $('statistics').textContent = `${model.runs.length} ${t('runs')} · ${Object.keys(model.files).length || 1} ${t('resources')}`;
}

function render() {
  active = null;
  selection = null;
  model.render($('paper'), messages[locale]);
  $('readonly-notice').hidden = !model.readOnly;
  updateStatus();
}

function localize() {
  document.documentElement.lang = locale;
  document.documentElement.dataset.theme = theme;
  for (const element of document.querySelectorAll('[data-i18n]')) element.textContent = t(element.dataset.i18n);
  for (const element of document.querySelectorAll('[data-label]')) {
    element.setAttribute('aria-label', t(element.dataset.label));
    element.title = t(element.dataset.label);
  }
  document.querySelector('[role="toolbar"]').setAttribute('aria-label', t('editor'));
  $('language').value = locale;
  $('theme').value = theme;
  if (errorCode) $('error-message').textContent = t(errorCode);
  render();
}

function remember() {
  try {
    localStorage.setItem('4wp-language', locale);
    localStorage.setItem('4wp-theme', theme);
  } catch (error) {
    console.warn('Preferences could not be saved', error);
  }
}

function replaceDocument(next) {
  model = next;
  saved = model.serialize();
  errorCode = null;
  downloadReady = false;
  $('error').hidden = true;
  render();
}

async function openFile(file) {
  if (!file || opening) return;
  if (unsaved() && !confirm(t('discard'))) return;
  opening = true;
  $('open').disabled = true;
  try {
    if (file.size > MAX_ARCHIVE) throw new DocumentError('tooLarge');
    const bytes = new Uint8Array(await file.arrayBuffer());
    replaceDocument(WriteProDocument.open(bytes));
  } catch (error) {
    showError(error);
  } finally {
    opening = false;
    $('open').disabled = false;
    $('file').value = '';
  }
}

function download() {
  try {
    const bytes = model.export();
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([bytes], { type: 'application/zip' }));
    link.download = `${model.title.replace(/[<>:"/\\|?*\u0000-\u001f]/g, '_').slice(0, 100) || 'Document'}.4wp`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 60000);
    saved = model.serialize();
    downloadReady = true;
    updateStatus();
  } catch (error) {
    showError(error);
  }
}

function focusRun(index, offset = null) {
  const element = $('paper').querySelector(`[data-run="${index}"][contenteditable]`);
  if (element) {
    element.focus();
    const range = document.createRange();
    range.selectNodeContents(element);
    if (offset === null) range.collapse(false);
    else if (element.firstChild) range.setStart(element.firstChild, offset);
    else range.setStart(element, 0);
    range.collapse(true);
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(range);
  }
}

function addParagraph() {
  try {
    const block = active !== null ? $('paper').querySelector(`[data-run="${active}"]`)?.closest('[data-block]') : null;
    model.addParagraph(block ? Number(block.dataset.block) : null);
    const paragraph = block ? model.blocks[Number(block.dataset.block)].nextElementSibling : model.document.querySelector('body').lastElementChild;
    render();
    const index = model.runs.findIndex(node => node.parentElement === paragraph);
    focusRun(index);
  } catch (error) {
    showError(error);
  }
}

function applyFormat(property, value) {
  try {
    if (active === null) throw new DocumentError('selection');
    if (selection?.crossRun) throw new DocumentError('selectionRange');
    const hasRange = selection && selection.end > selection.start;
    const text = model.formatRun(active, property, value, hasRange ? selection.start : 0, hasRange ? selection.end : null);
    render();
    focusRun(model.runs.indexOf(text));
  } catch (error) {
    showError(error);
  }
}

function toggleFormat(property, on, off) {
  const element = $('paper').querySelector(`[data-run="${active}"]`);
  let enabled = false;
  for (let current = element; current && current !== $('paper'); current = current.parentElement) {
    const computed = getComputedStyle(current).getPropertyValue(property);
    if (property === 'font-weight') {
      enabled = computed === 'bold' || Number(computed) >= 600;
      break;
    }
    if (computed.includes(on)) { enabled = true; break; }
    if (property !== 'text-decoration') break;
  }
  applyFormat(property, enabled ? off : on);
}

document.addEventListener('selectionchange', () => {
  const selected = window.getSelection();
  if (!selected?.rangeCount || !selected.anchorNode) return;
  const parent = node => node.nodeType === 1 ? node : node.parentElement;
  const first = parent(selected.anchorNode)?.closest('[data-run][contenteditable]');
  const last = parent(selected.focusNode)?.closest('[data-run][contenteditable]');
  if (!first) return;
  active = Number(first.dataset.run);
  const offset = (node, position) => {
    const range = document.createRange();
    range.selectNodeContents(first);
    range.setEnd(node, position);
    return range.toString().length;
  };
  selection = first !== last ? { crossRun: true } : {
    start: Math.min(offset(selected.anchorNode, selected.anchorOffset), offset(selected.focusNode, selected.focusOffset)),
    end: Math.max(offset(selected.anchorNode, selected.anchorOffset), offset(selected.focusNode, selected.focusOffset)),
  };
  updateStatus();
});

$('paper').addEventListener('focusin', event => {
  if (event.target.dataset.run !== undefined) {
    active = Number(event.target.dataset.run);
    selection = null;
    updateStatus();
  }
});
$('paper').addEventListener('click', event => {
  if (event.target.closest('[data-run],.preserved-object,.locked-content')) return;
  const scope = event.target.closest('[data-block]') || $('paper');
  const runs = scope.querySelectorAll('[data-run][contenteditable]');
  if (runs.length) focusRun(Number(runs[runs.length - 1].dataset.run));
});
$('paper').addEventListener('input', event => {
  if (event.target.dataset.run === undefined) return;
  try {
    if (!event.target.textContent || event.target.textContent === '\u200b') event.target.dataset.empty = '';
    else delete event.target.dataset.empty;
    const last = model.editRun(Number(event.target.dataset.run), event.target.textContent);
    if (last) {
      render();
      focusRun(model.runs.indexOf(last));
    }
    downloadReady = false;
    updateStatus();
  } catch (error) {
    showError(error);
    render();
  }
});
$('paper').addEventListener('keydown', event => {
  if (event.key === 'Enter' && !event.isComposing) {
    event.preventDefault();
    if (!event.shiftKey) addParagraph();
    else {
      try {
        if (active === null) throw new DocumentError('selection');
        if (selection?.crossRun) throw new DocumentError('selectionRange');
        const node = model.runs[active];
        const start = selection?.start ?? node.length;
        const end = selection?.end ?? start;
        const last = model.editRun(active, `${node.data.slice(0, start)}\n${node.data.slice(end)}`);
        render();
        focusRun(model.runs.indexOf(last), 0);
      } catch (error) { showError(error); }
    }
  }
});
$('paper').addEventListener('beforeinput', event => {
  if (['historyUndo', 'historyRedo'].includes(event.inputType)) {
    event.preventDefault();
    model.undo(event.inputType === 'historyRedo');
    render();
  }
});
document.querySelector('.toolbar').addEventListener('mousedown', event => {
  if (event.target.closest('button')) event.preventDefault();
});
$('bold').onclick = () => toggleFormat('font-weight', 'bold', 'normal');
$('italic').onclick = () => toggleFormat('font-style', 'italic', 'normal');
$('underline').onclick = () => toggleFormat('text-decoration', 'underline', 'none');
$('font').onchange = event => applyFormat('font-family', `'${event.target.value}'`);
$('size').onchange = event => applyFormat('font-size', `${event.target.value}pt`);
$('color').onchange = event => applyFormat('color', event.target.value);
for (const alignment of ['left', 'center', 'right']) {
  $(alignment).onclick = () => {
    try {
      const block = $('paper').querySelector(`[data-run="${active}"]`)?.closest('[data-block]');
      if (!block) throw new DocumentError('selection');
      model.alignBlock(Number(block.dataset.block), alignment);
      render();
    } catch (error) { showError(error); }
  };
}
$('paragraph').onclick = addParagraph;
$('undo').onclick = () => { model.undo(); render(); };
$('redo').onclick = () => { model.undo(true); render(); };
$('new').onclick = () => {
  if (!unsaved() || confirm(t('discard'))) replaceDocument(WriteProDocument.create(t('untitled')));
};
$('open').onclick = () => $('file').click();
$('file').onchange = event => openFile(event.target.files[0]);
$('download').onclick = download;
$('dismiss-error').onclick = () => { errorCode = null; $('error').hidden = true; };
$('settings-toggle').onclick = () => {
  $('settings').hidden = !$('settings').hidden;
  $('settings-toggle').setAttribute('aria-expanded', String(!$('settings').hidden));
};
$('language').onchange = event => { locale = event.target.value; remember(); localize(); };
$('theme').onchange = event => { theme = event.target.value; remember(); localize(); };
window.addEventListener('beforeunload', event => {
  if (unsaved()) { event.preventDefault(); event.returnValue = ''; }
});
window.addEventListener('keydown', event => {
  if (!(event.metaKey || event.ctrlKey) || event.altKey || event.isComposing) return;
  const key = event.key.toLowerCase();
  if (['o', 's', 'z', 'b', 'i', 'u'].includes(key)) event.preventDefault();
  if (key === 'o') $('file').click();
  if (key === 's') download();
  if (key === 'z') { model.undo(event.shiftKey); render(); }
  if (key === 'b') $('bold').click();
  if (key === 'i') $('italic').click();
  if (key === 'u') $('underline').click();
});
window.addEventListener('dragover', event => {
  if (event.dataTransfer.types.includes('Files')) event.preventDefault();
});
window.addEventListener('drop', event => {
  if (!event.dataTransfer.files.length) return;
  event.preventDefault();
  openFile(event.dataTransfer.files[0]);
});
localize();
