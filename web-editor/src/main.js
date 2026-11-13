import './style.css';
import { WriteProDocument } from './document.js';
import { createExampleDocument } from './example.js';
import { DocumentError, MAX_ARCHIVE } from './archive.js';
import { languages, messages, detectLanguage } from './i18n.js';
import { LocalHistory } from './history.js';
import { readImage } from './image.js';
import { pageUnits, paperPresets, pageFields, pageDisplay, pagePoints, pagePaperSize } from './page-setup.js';
import { paragraphBreak } from './sections.js';
import { tabTypes, tabLeaders, defaultTab } from './flow-settings.js';
import { createPrintProjection, printCapability } from './printing.js';

let locale = detectLanguage();
let theme = 'system';
let pageUnit = 'mm';
let pageDraft = null;
let pageChanges = {};
let pageTarget = 0;
let columnDraft = null;
let columnChanges = {};
let tabDraft = null;
let tabDefaultDraft = null;
let tabDefaultChanges = {};
let tabOriginalPosition = null;
try {
  const savedLanguage = localStorage.getItem('4wp-language');
  if (savedLanguage in messages) locale = savedLanguage;
  const savedTheme = localStorage.getItem('4wp-theme');
  if (['system', 'light', 'dark'].includes(savedTheme)) theme = savedTheme;
  const savedUnit = localStorage.getItem('4wp-page-unit');
  if (Object.hasOwn(pageUnits, savedUnit)) pageUnit = savedUnit;
} catch (error) {
  console.warn('Preferences unavailable', error);
}
let model = createExampleDocument();
let saved = model.serialize();
let active = null;
let selection = null;
let errorCode = null;
let downloadReady = false;
let opening = false;
let selectedImage = null;
let versions = [];
let persistTimer;
let pendingRecord = null;
let writing = false;
let storageReady = false;
let revision = 0;
let findIndex = -1;
let composition = null;
let draggedImage = null;
let draftStatus = null;
let plainPaste = false;
let currentBookmark = null;
let bookmarkHighlight = null;
let bookmarkSelection = null;
let protectedSelection = false;
const history = new LocalHistory();
const t = key => messages[locale][key];

document.querySelector('#app').innerHTML = `
  <header class="app-header">
    <div class="brand"><div class="brand-mark" aria-hidden="true">W</div>
      <div><h1>4WP Editor <span class="pill" data-i18n="experimental"></span></h1><p data-i18n="tagline"></p></div>
    </div>
    <div class="file-actions">
      <button id="new" data-i18n="new"></button><button id="open" data-i18n="open"></button>
      <button id="download" class="primary" data-i18n="download"></button>
      <button id="print-toggle" data-i18n="print" aria-expanded="false" aria-controls="print-panel"></button>
      <button id="history-toggle" data-i18n="history" aria-expanded="false" aria-controls="history-panel"></button>
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
        <select id="paragraph-style" data-label="paragraphStyle"></select>
        <select id="font" data-label="font"><option>Arial</option><option>Helvetica</option><option>Times New Roman</option><option>Georgia</option><option>Courier New</option></select>
        <select id="size" data-label="size"><option>9</option><option>10</option><option selected>12</option><option>14</option><option>18</option><option>24</option><option>36</option></select>
        <button id="bold" data-label="bold"><b>B</b></button><button id="italic" data-label="italic"><i>I</i></button><button id="underline" data-label="underline"><u>U</u></button>
        <button id="strike" data-label="strike"><s>S</s></button>
        <label class="color-control"><span data-i18n="color" class="sr-only"></span><input id="color" type="color" value="#327fce" data-label="color"></label>
        <select id="highlight" data-label="highlight"><option value="transparent" data-i18n="noHighlight"></option><option value="#fff2a8" data-i18n="yellow"></option><option value="#c7edce" data-i18n="green"></option><option value="#d0e7ff" data-i18n="blue"></option><option value="#f6d2e3" data-i18n="pink"></option></select>
        <button id="link-toggle" data-i18n="link" aria-expanded="false" aria-controls="link-panel"></button>
        <span id="selection-state" class="selection-state" role="status" hidden></span>
        <span class="separator"></span>
        <button id="left" data-label="left">≡</button><button id="center" data-label="center">☰</button><button id="right" data-label="right">≡</button>
        <button id="paragraph" class="add-paragraph" data-i18n="paragraph"></button>
        <button id="bullets" data-label="bullets">•</button><button id="numbering" data-label="numbering">1.</button>
        <button id="outdent" data-label="outdent">⇤</button><button id="indent" data-label="indent">⇥</button>
        <button id="find-toggle" data-i18n="find" aria-expanded="false" aria-controls="find-panel"></button>
        <button id="bookmarks-toggle" data-i18n="bookmarks" aria-expanded="false" aria-controls="bookmarks-panel"></button>
        <button id="page-toggle" data-i18n="pageSetup" aria-expanded="false" aria-controls="page-panel"></button>
        <button id="tabs-toggle" data-i18n="tabsSetup" aria-expanded="false" aria-controls="tabs-panel"></button>
        <button id="insert-tab" data-i18n="insertTab"></button>
      </div>
      <details class="editing-tools"><summary data-i18n="moreTools"></summary><div class="tool-groups">
        <label><span data-i18n="spacing"></span><select id="spacing"><option value="0">0 pt</option><option value="6">6 pt</option><option value="12">12 pt</option><option value="18">18 pt</option><option value="24">24 pt</option></select></label>
        <label><span data-i18n="lineHeight"></span><select id="line-height"><option value="100%">1</option><option value="150%">1.5</option><option value="200%">2</option></select></label>
        <label><span data-i18n="rows"></span><input id="table-rows" type="number" min="1" max="20" value="2"></label>
        <label><span data-i18n="columns"></span><input id="table-columns" type="number" min="1" max="10" value="2"></label>
        <button id="insert-table" data-i18n="insertTable"></button>
        <button id="add-row" data-i18n="addRow"></button><button id="remove-row" data-i18n="removeRow"></button>
        <button id="add-column" data-i18n="addColumn"></button><button id="remove-column" data-i18n="removeColumn"></button>
        <p id="table-capability" role="status" hidden></p>
        <button id="insert-image" data-i18n="insertImage"></button>
        <button id="paste-plain" data-i18n="pastePlain"></button>
      </div></details>
      <section id="link-panel" class="tool-panel" hidden>
        <label><span data-i18n="linkURLLabel"></span><input id="link-url" type="url" maxlength="2048"></label>
        <button id="apply-link" data-i18n="applyLink"></button><button id="remove-link" data-i18n="removeLink"></button>
      </section>
      <section id="print-panel" class="tool-panel print-panel" aria-labelledby="print-heading" hidden>
        <h3 id="print-heading" data-i18n="print"></h3>
        <p data-i18n="printHelp"></p><p data-i18n="printLimits"></p>
        <p id="print-protection" role="status" hidden></p>
        <button id="print-open" data-i18n="printOpen"></button>
        <button id="print-close" data-i18n="close"></button>
      </section>
      <section id="image-panel" class="tool-panel" hidden>
        <label><span data-i18n="imageWidth"></span><input id="image-width" type="number" min="12" max="1200" step="1"></label>
        <button id="resize-image" data-i18n="resizeImage"></button><button id="remove-image" data-i18n="removeImage"></button>
      </section>
      <section id="find-panel" class="tool-panel" hidden>
        <label><span data-i18n="find"></span><input id="find-query" type="search"></label>
        <label><span data-i18n="replacement"></span><input id="replacement" type="text"></label>
        <label><input id="match-case" type="checkbox"><span data-i18n="matchCase"></span></label>
        <button id="find-next" data-i18n="findNext"></button><span id="find-count" role="status"></span>
        <button id="replace-one" data-i18n="replace"></button><button id="replace-all" data-i18n="replaceAll"></button>
      </section>
      <section id="history-panel" class="tool-panel history-panel" hidden>
        <p data-i18n="historyHelp"></p><label><span data-i18n="versionName"></span><input id="version-name" type="text" maxlength="100"></label>
        <button id="save-version" data-i18n="saveVersion"></button><ol id="version-list"></ol>
      </section>
      <section id="bookmarks-panel" class="tool-panel bookmarks-panel" aria-labelledby="bookmarks-heading" hidden>
        <h3 id="bookmarks-heading" data-i18n="bookmarks"></h3><p data-i18n="bookmarkHelp"></p>
        <form id="bookmark-form">
          <label><span data-i18n="bookmarkName"></span><input id="bookmark-name" type="text" autocomplete="off" spellcheck="false" aria-describedby="bookmark-name-help"></label>
          <button id="bookmark-create" type="submit" data-i18n="bookmarkCreate"></button>
          <button id="bookmark-rename" type="button" data-i18n="bookmarkRename" disabled></button>
          <button id="bookmark-delete" type="button" data-i18n="bookmarkDelete" disabled></button>
        </form>
        <p id="bookmark-name-help" data-i18n="bookmarkNameHelp"></p>
        <p id="bookmark-status" role="status"></p><ul id="bookmark-list" data-label="bookmarks"></ul>
      </section>
      <section id="page-panel" class="tool-panel page-panel" aria-labelledby="page-heading" hidden>
        <h3 id="page-heading" data-i18n="pageSetup"></h3>
        <p data-i18n="sectionScope"></p><p id="page-overrides" data-i18n="pageOverrides" hidden></p>
        <p id="section-active" role="status"></p>
        <label><span data-i18n="sectionSetup"></span><select id="page-target"></select></label>
        <p id="page-protection" role="status"></p>
        <label><span data-i18n="pageUnits"></span><select id="page-units"><option>mm</option><option>cm</option><option>in</option><option>pt</option></select></label>
        <form id="page-form" novalidate aria-describedby="page-precision page-protection">
          <div id="section-controls" class="section-controls" hidden>
            <label><span data-i18n="sectionName"></span><input id="section-name" type="text" maxlength="1024"></label>
            <label><input id="section-inherit-orientation" type="checkbox" data-label="sectionInheritOrientation" aria-describedby="section-orientation-state"><span data-i18n="sectionInheritOrientation"></span><span id="section-orientation-state"></span></label>
            <label><input id="section-inherit-margins" type="checkbox" data-label="sectionInheritMargins" aria-describedby="section-margins-state"><span data-i18n="sectionInheritMargins"></span><span id="section-margins-state"></span></label>
          </div>
          <label><span data-i18n="pagePaper"></span><select id="page-preset">
            <option value="custom" data-i18n="pageCustom"></option>
            <option value="a4">A4</option><option value="a3">A3</option><option value="a5">A5</option>
            <option value="letter">Letter</option><option value="legal">Legal</option><option value="tabloid">Tabloid</option>
          </select></label>
          <label><span data-i18n="pageOrientation"></span><select id="page-orientation">
            <option value="portrait" data-i18n="pagePortrait"></option><option value="landscape" data-i18n="pageLandscape"></option>
          </select></label>
          ${pageFields.map(field => `<label><span data-i18n="page${field[0].toUpperCase() + field.slice(1)}"></span><input id="page-${field}" type="number" step="any" min="0" required aria-describedby="page-precision"><span class="page-unit" aria-hidden="true"></span></label>`).join('')}
          <p id="page-precision" data-i18n="pagePrecision"></p>
          <p><span data-i18n="pageNativeSize"></span>: <output id="page-native-size" aria-live="polite"></output></p>
          <button id="page-apply" type="submit" data-i18n="pageApply"></button>
        </form>
        <form id="columns-form" novalidate aria-describedby="flow-preview columns-protection">
          <h3 data-i18n="columnsSetup"></h3><p id="columns-protection" role="status"></p>
          <label id="column-inherit-count-label"><input id="column-inherit-count" type="checkbox"><span data-i18n="columnInheritCount"></span></label>
          <label><span data-i18n="columnCount"></span><input id="column-count" type="number" min="1" max="20" step="1"></label>
          <label id="column-inherit-gap-label"><input id="column-inherit-gap" type="checkbox"><span data-i18n="columnInheritGap"></span></label>
          <label><span data-i18n="columnGap"></span><input id="column-gap" type="number" min="0" step="any"><span class="page-unit" aria-hidden="true"></span></label>
          <button id="columns-apply" type="submit" data-i18n="pageApply"></button>
        </form>
        <p data-i18n="breakHelp"></p>
        <div class="section-controls">
          <label><span data-i18n="breakInsert"></span><select id="break-kind">
            <option value="page" data-i18n="breakPage"></option><option value="section" data-i18n="breakSection"></option><option value="continuous" data-i18n="breakContinuous"></option>
          </select></label><button id="break-insert" data-i18n="breakInsert"></button>
          <label><span data-i18n="breakChoose"></span><select id="break-list"></select></label><button id="break-remove" data-i18n="breakRemove"></button>
        </div>
        <p data-i18n="sectionPreview"></p>
        <p id="flow-preview" data-i18n="flowPreview"></p>
        <button id="page-close" data-i18n="close"></button>
      </section>
      <section id="tabs-panel" class="tool-panel tabs-panel" aria-labelledby="tabs-heading" hidden>
        <h3 id="tabs-heading" data-i18n="tabsSetup"></h3><p data-i18n="tabsHelp"></p>
        <p id="tabs-status" role="status"></p><p data-i18n="flowPreview"></p>
        <label><span data-i18n="pageUnits"></span><select id="tab-units"><option>mm</option><option>cm</option><option>in</option><option>pt</option></select></label>
        <form id="tab-stop-form" novalidate>
          <label><span data-i18n="tabStop"></span><select id="tab-stop-list"></select></label>
          <label><span data-i18n="tabPosition"></span><input id="tab-position" type="number" min="0" step="any"><span class="tab-unit" aria-hidden="true"></span></label>
          <label><span data-i18n="tabType"></span><select id="tab-type">${tabTypes.map(type => `<option value="${type}" data-i18n="tab${type[0].toUpperCase() + type.slice(1)}"></option>`).join('')}</select></label>
          <label><span data-i18n="tabLeader"></span><select id="tab-leader">${tabLeaders.map((leader, index) => `<option value="${leader}" ${index ? '' : 'data-i18n="tabNone"'}>${leader}</option>`).join('')}</select></label>
          <button id="tab-stop-apply" type="submit" data-i18n="tabSet"></button>
          <button id="tab-stop-remove" type="button" data-i18n="tabRemove"></button>
        </form>
        <form id="tab-default-form" novalidate>
          <label><span data-i18n="tabInterval"></span><input id="tab-interval" type="number" min="0" step="any"><span class="tab-unit" aria-hidden="true"></span></label>
          <label><span data-i18n="tabType"></span><select id="tab-default-type">${tabTypes.map(type => `<option value="${type}" data-i18n="tab${type[0].toUpperCase() + type.slice(1)}"></option>`).join('')}</select></label>
          <label><span data-i18n="tabLeader"></span><select id="tab-default-leader">${tabLeaders.map((leader, index) => `<option value="${leader}" ${index ? '' : 'data-i18n="tabNone"'}>${leader}</option>`).join('')}</select></label>
          <button id="tab-default-apply" type="submit" data-i18n="tabDefaultApply"></button>
        </form>
        <button id="tab-reset" data-i18n="tabReset"></button><button id="tabs-close" data-i18n="close"></button>
      </section>
      <p id="recovery-notice" class="notice" data-i18n="recovered" hidden></p>
      <div id="error" class="notice error" role="alert" hidden><strong data-i18n="errorTitle"></strong><p id="error-message"></p><button id="dismiss-error" data-i18n="close"></button></div>
      <div id="readonly-notice" class="notice" hidden></div>
      <details id="capabilities" class="notice" hidden><summary data-i18n="capabilityTitle"></summary><ul id="capability-list"></ul></details>
      <div id="unsupported-notice" class="notice" data-i18n="unsupportedNotice" hidden></div>
      <div class="paper-surround"><article id="paper" class="paper" data-label="editor"></article></div>
      <footer class="document-footer"><span id="statistics"></span><span id="draft-state" role="status"></span>
        <label><span data-i18n="zoom"></span><select id="zoom"><option value=".75">75%</option><option value="1" selected>100%</option><option value="1.25">125%</option><option value="1.5">150%</option><option value="2">200%</option></select></label><span data-i18n="local"></span></footer>
    </section>
    <aside class="guide">
      <div class="guide-symbol" aria-hidden="true">¶</div><h2 data-i18n="details"></h2><p data-i18n="intro"></p>
      <hr><p data-i18n="editing"></p><p data-i18n="preservation"></p><p class="limitations" data-i18n="limits"></p><small data-i18n="shortcut"></small>
    </aside>
  </main>
  <input id="file" type="file" accept=".4wp" hidden>
  <input id="image-file" type="file" accept="image/png,image/jpeg" multiple hidden>
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
  for (const [id, labels] of [['undo', model.undoLabels], ['redo', model.redoLabels]]) {
    const label = labels.at(-1);
    $(id).title = label ? `${t(id)} · ${t(label === 'image' ? 'historyImage' : label)}` : t(id);
  }
  const editable = active !== null && model.runs[active] && !model.protected(model.runs[active].parentElement);
  for (const id of ['bold', 'italic', 'underline', 'strike', 'font', 'size', 'color', 'highlight', 'link-toggle', 'apply-link', 'remove-link', 'left', 'center', 'right', 'paragraph-style', 'bullets', 'numbering', 'outdent', 'indent', 'spacing', 'line-height']) $(id).disabled = !editable;
  $('paste-plain').disabled = model.readOnly;
  $('bookmark-create').disabled = model.readOnly || !bookmarkSelection;
  $('bookmark-rename').disabled = model.readOnly || currentBookmark === null;
  $('bookmark-delete').disabled = model.readOnly || currentBookmark === null;
  $('selection-state').hidden = true;
  const block = active !== null ? $('paper').querySelector(`[data-run="${active}"]`)?.closest('[data-block]') : null;
  const sourceBlock = block ? model.blocks[Number(block.dataset.block)] : null;
  const sectionIndex = sourceBlock ? model.sectionIndex(sourceBlock) : null;
  $('section-active').textContent = `${t('sectionActive')}: ${sectionIndex ?? '—'}`;
  $('break-insert').disabled = model.readOnly || !selection;
  $('break-remove').disabled = model.readOnly || !$('break-list').options.length;
  $('paragraph').disabled = model.readOnly;
  $('insert-tab').disabled = !editable || !selection;
  $('insert-table').disabled = model.readOnly || Boolean(sourceBlock && sourceBlock.parentElement.localName !== 'body');
  $('insert-image').disabled = model.readOnly;
  const cell = active !== null && $('paper').querySelector(`[data-run="${active}"]`)?.closest('[data-cell]');
  for (const id of ['add-row', 'remove-row', 'add-column', 'remove-column']) {
    $(id).disabled = !cell || !editable;
    $(id).setAttribute('aria-describedby', 'table-capability');
  }
  const tableReasons = cell ? [...new Set(['addRow', 'addColumn'].map(action =>
    model.tableCapability(Number(cell.dataset.cell), action)).filter(Boolean))] : [];
  $('table-capability').hidden = !tableReasons.length;
  $('table-capability').textContent = tableReasons.map(t).join(' ');
  for (const id of ['replace-one', 'replace-all']) $(id).disabled = model.readOnly;
  const blockText = new Map();
  for (const node of model.runs) {
    const block = node.parentElement.closest('p,li');
    blockText.set(block, (blockText.get(block) || '') + node.data);
  }
  const text = model.blocks.map(block => blockText.get(block) || '').join('\n').replace(/\u200b/g, '');
  const words = [...new Intl.Segmenter(locale, { granularity: 'word' }).segment(text)].filter(item => item.isWordLike).length;
  $('statistics').textContent = `${words.toLocaleString(locale)} ${t('words')} · ${[...text].length.toLocaleString(locale)} ${t('characters')}`;
  const element = active !== null && $('paper').querySelector(`[data-run="${active}"]`);
  if (element && editable) {
    const runs = selection && (selection.startRun !== selection.endRun || selection.start !== selection.end) ?
      model.runs.map((node, index) => ({ node, index })).filter(({ node, index }) =>
        index >= selection.startRun && index <= selection.endRun && node.length &&
        (index !== selection.startRun || selection.start < node.length) &&
        (index !== selection.endRun || selection.end > 0)).map(({ index }) => $('paper').querySelector(`[data-run="${index}"]`)) : [element];
    if (!runs.length) runs.push(element);
    const styles = runs.map(run => getComputedStyle(run));
    const common = values => values.every(value => value === values[0]) ? values[0] : null;
    const option = (id, value) => {
      const key = value ?? '__mixed__';
      if (![...$(id).options].some(item => item.value === key)) {
        const item = new Option(value ?? t('mixed'), key);
        if (value === null) { item.disabled = true; item.dataset.i18n = 'mixed'; }
        $(id).add(item);
      }
      $(id).value = key;
    };
    option('font', common(styles.map(style => style.fontFamily.split(',')[0].replace(/^["']|["']$/g, ''))));
    option('size', common(styles.map(style => String(Math.round(parseFloat(style.fontSize) * .75 * 10) / 10))));
    const color = common(styles.map(style => style.color));
    const rgb = color?.match(/^rgba?\(([\d.,\s]+)\)$/)?.[1].match(/[\d.]+/g);
    if (rgb?.length >= 3) $('color').value = '#' + rgb.slice(0, 3).map(value => Number(value).toString(16).padStart(2, '0')).join('');
    $('color').toggleAttribute('data-mixed', color === null);
    $('color').title = color === null ? `${t('color')} (${t('mixed')})` : t('color');
    const backgrounds = runs.map(run => {
      const values = run.style.backgroundColor.match(/[\d.]+/g);
      if (!values || values[3] === '0') return 'transparent';
      return '#' + values.slice(0, 3).map(value => Number(value).toString(16).padStart(2, '0')).join('');
    });
    option('highlight', common(backgrounds));
    for (const [id, read] of [
      ['bold', style => style.fontWeight === 'bold' || Number(style.fontWeight) >= 600],
      ['italic', style => style.fontStyle === 'italic'],
      ['underline', style => style.textDecorationLine.includes('underline')],
      ['strike', style => style.textDecorationLine.includes('line-through')],
    ]) {
      const pressed = common(styles.map(read));
      $(id).setAttribute('aria-pressed', pressed === null ? 'mixed' : String(pressed));
    }
    const mixed = ['font', 'size', 'highlight'].some(id => $(id).value === '__mixed__') ||
      color === null || ['bold', 'italic', 'underline', 'strike'].some(id => $(id).getAttribute('aria-pressed') === 'mixed');
    $('selection-state').hidden = !mixed;
    $('selection-state').textContent = mixed ? t('mixed') : '';
    if (sourceBlock) {
      const blocks = [...new Set(runs.map(run => run.closest('[data-block]')))];
      const paragraphs = blocks.map(block => getComputedStyle(block));
      option('paragraph-style', common(blocks.map(block => {
        const source = model.blocks[Number(block.dataset.block)];
        return model.styleNames().find(name => source.classList.contains(name)) || '';
      })));
      option('spacing', common(paragraphs.map(style => String(Math.round(parseFloat(style.marginBottom) * .75)))));
      option('line-height', common(paragraphs.map(style => {
        const ratio = parseFloat(style.lineHeight) / parseFloat(style.fontSize);
        return Number.isFinite(ratio) ? `${Math.round(ratio * 100)}%` : '';
      })));
      for (const alignment of ['left', 'center', 'right']) {
        const state = common(paragraphs.map(style => style.textAlign === alignment));
        $(alignment).setAttribute('aria-pressed', state === null ? 'mixed' : String(state));
      }
      for (const [id, kind] of [['bullets', 'ul'], ['numbering', 'ol']]) {
        const state = common(blocks.map(block => model.blocks[Number(block.dataset.block)].closest('ul,ol')?.localName === kind));
        $(id).setAttribute('aria-pressed', state === null ? 'mixed' : String(state));
      }
    }
  }
}

function render(caret = null) {
  clearBookmarkHighlight();
  bookmarkSelection = null;
  protectedSelection = false;
  active = null;
  selection = null;
  selectedImage = null;
  model.selection = null;
  $('image-panel').hidden = true;
  model.render($('paper'), messages[locale]);
  $('paper').setAttribute('aria-description', t('previewHelp'));
  const styleLabels = { Normal: 'normalStyle', Heading_1: 'heading1Style', Heading_2: 'heading2Style', Quote: 'quoteStyle' };
  $('paragraph-style').replaceChildren(...model.styleNames().map(name => new Option(styleLabels[name] ? t(styleLabels[name]) : name.replaceAll('_', ' '), name)));
  $('readonly-notice').hidden = !model.readOnly && !model.hasBookmarks;
  $('readonly-notice').textContent = t(model.readOnly ? model.readOnlyReason : 'bookmarkEditingNotice');
  const capabilities = model.capabilityCodes();
  $('capabilities').hidden = !capabilities.length;
  $('capability-list').replaceChildren(...capabilities.map(code => {
    const item = document.createElement('li');
    item.textContent = t(code);
    return item;
  }));
  $('unsupported-notice').hidden = !$('paper').querySelector('.preserved-object:not([data-image]),.locked-content');
  updateStatus();
  if (caret?.node) focusRun(model.runs.indexOf(caret.node), caret.offset);
  else if (caret?.selection) restoreSelection(caret.selection);
  renderHistory();
  refreshFindCount();
  renderBookmarks();
  renderPageSetup();
  renderTabs();
  const printBlocked = printCapability(model);
  $('print-open').disabled = Boolean(printBlocked);
  $('print-protection').hidden = !printBlocked;
  $('print-protection').textContent = printBlocked ? t(printBlocked) : '';
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
  if (draftStatus) $('draft-state').textContent = t(draftStatus);
  render();
}

function remember() {
  try {
    localStorage.setItem('4wp-language', locale);
    localStorage.setItem('4wp-theme', theme);
    localStorage.setItem('4wp-page-unit', pageUnit);
  } catch (error) {
    console.warn('Preferences could not be saved', error);
  }
}

function replaceDocument(next) {
  clearTimeout(persistTimer);
  model = next;
  saved = model.serialize();
  errorCode = null;
  downloadReady = false;
  versions = [];
  currentBookmark = null;
  $('bookmark-name').value = '';
  $('recovery-notice').hidden = true;
  $('error').hidden = true;
  render();
  schedulePersist('initial');
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
    schedulePersist('download');
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
    captureSelection(true);
  }
}

function restoreSelection(bookmark) {
  const saved = model.resolveSelection(bookmark);
  const first = $('paper').querySelector(`[data-run="${saved.startRun}"]`);
  const last = $('paper').querySelector(`[data-run="${saved.endRun}"]`);
  (saved.backward ? last : first).focus();
  const selection = window.getSelection();
  const start = [first.firstChild || first, saved.start];
  const end = [last.firstChild || last, saved.end];
  selection.setBaseAndExtent(...(saved.backward ? end : start), ...(saved.backward ? start : end));
  captureSelection();
  updateStatus();
}

function addParagraph() {
  perform('paragraph', () => {
    if (selection) return model.splitParagraph(selection);
    return model.addParagraph();
  });
}

function applyFormat(property, value) {
  formatOperation(range => model.formatSelection(range, property, value));
}

function formatOperation(operation) {
  perform('format', () => {
    const range = formattingSelection();
    const bookmark = model.selection;
    operation(range);
    return bookmark ? { selection: bookmark } : null;
  });
}

function toggleFormat(property, on, off) {
  const id = property === 'font-weight' ? 'bold' : property === 'font-style' ? 'italic' : on === 'underline' ? 'underline' : 'strike';
  const enabled = $(id).getAttribute('aria-pressed') !== 'true';
  if (property === 'text-decoration') formatOperation(range => model.decorateSelection(range, on, enabled));
  else applyFormat(property, enabled ? on : off);
}

function captureSelection(inputCaret = false) {
  if (composition) return;
  const selected = window.getSelection();
  if (!selected?.rangeCount || !selected.anchorNode) return;
  const parent = node => node.nodeType === 1 ? node : node.parentElement;
  const browserRange = selected.getRangeAt(0);
  if (!$('paper').contains(browserRange.startContainer) || !$('paper').contains(browserRange.endContainer)) return;
  bookmarkSelection = browserRange.cloneRange();
  protectedSelection = [...$('paper').querySelectorAll('.formula-object')].some(element =>
    element.contains(browserRange.startContainer) || element.contains(browserRange.endContainer) ||
    !browserRange.collapsed && browserRange.intersectsNode(element));
  if (protectedSelection) {
    selection = null;
    active = null;
    return;
  }
  const startRun = parent(browserRange.startContainer)?.closest('[data-run]');
  const endRun = parent(browserRange.endContainer)?.closest('[data-run]');
  const intersected = startRun && endRun ? [] : [...$('paper').querySelectorAll('[data-run]')].filter(run => browserRange.intersectsNode(run));
  const first = startRun || intersected[0];
  const last = endRun || intersected.at(-1);
  if (!first || !$('paper').contains(first)) return;
  active = Number(first.dataset.run);
  if (!last || !$('paper').contains(last)) return;
  const offset = (element, node, position, fallback) => {
    if (!element.contains(node)) return fallback;
    const range = document.createRange();
    range.selectNodeContents(element);
    range.setEnd(node, position);
    return range.toString().length;
  };
  selection = {
    startRun: Number(first.dataset.run), endRun: Number(last.dataset.run),
    start: offset(first, browserRange.startContainer, browserRange.startOffset, 0),
    end: offset(last, browserRange.endContainer, browserRange.endOffset, last.textContent.length),
    backward: !selected.isCollapsed && selected.anchorNode === browserRange.endContainer && selected.anchorOffset === browserRange.endOffset,
  };
  if (selection.start <= model.runs[selection.startRun].length && selection.end <= model.runs[selection.endRun].length) {
    const before = model.selection;
    const after = model.rememberSelection(selection);
    if (!inputCaret && before && JSON.stringify(before) !== JSON.stringify(after)) model.endGroup();
  }
}
document.addEventListener('selectionchange', () => {
  const before = JSON.stringify(selection);
  captureSelection();
  updateStatus();
  if (before !== JSON.stringify(selection)) renderTabs();
});

$('paper').addEventListener('focusin', event => {
  if (event.target.dataset.run !== undefined) {
    selectedImage = null;
    $('image-panel').hidden = true;
    active = Number(event.target.dataset.run);
    selection = null;
    updateStatus();
  }
});
$('paper').addEventListener('pointerdown', clearBookmarkHighlight);
$('paper').addEventListener('focusout', event => { if ($('bookmarks-panel').contains(event.relatedTarget)) captureSelection(); });
$('bookmarks-panel').addEventListener('pointerdown', () => captureSelection());
$('paper').addEventListener('click', event => {
  model.endGroup();
  const image = event.target.closest('[data-image]');
  if (image && image.getAttribute('role') === 'button') {
    selectedImage = Number(image.dataset.image);
    active = null;
    selection = null;
    $('image-panel').hidden = false;
    const picture = image.querySelector('img');
    $('image-width').value = String(Math.round(picture.getBoundingClientRect().width * .75));
    updateStatus();
    return;
  }
  selectedImage = null;
  $('image-panel').hidden = true;
  if (event.target.closest('[data-run],.preserved-object,.locked-content')) return;
  const scope = event.target.closest('[data-block],.section-flow,.section-paper') || $('paper');
  const runs = scope.querySelectorAll('[data-run][contenteditable]');
  if (runs.length) focusRun(Number(runs[runs.length - 1].dataset.run));
});
$('paper').addEventListener('input', event => {
  if (composition || event.inputType === 'insertCompositionText') return;
  if (event.target.dataset.run === undefined) return;
  try {
    if (model.tracksNativeEdits) throw new DocumentError('protected');
    if (!event.target.textContent || event.target.textContent === '\u200b') event.target.dataset.empty = '';
    else delete event.target.dataset.empty;
    const last = model.editRun(Number(event.target.dataset.run), event.target.textContent);
    if (last) {
      render();
      focusRun(model.runs.indexOf(last));
    }
    captureSelection(true);
    downloadReady = false;
    updateStatus();
    refreshFindCount();
    schedulePersist('typing');
  } catch (error) {
    showError(error);
    render();
  }
});
$('paper').addEventListener('keydown', event => {
  clearBookmarkHighlight();
  if (event.isComposing) return;
  if (event.key.toLowerCase() === 'v') plainPaste = Boolean((event.ctrlKey || event.metaKey) && event.shiftKey);
  if ((event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === 'a') {
    event.preventDefault();
    const runs = [...$('paper').querySelectorAll('[data-run]')];
    if (runs.length) {
      const range = document.createRange();
      range.setStart(runs[0].firstChild || runs[0], 0);
      range.setEnd(runs.at(-1).firstChild || runs.at(-1), runs.at(-1).textContent.length);
      window.getSelection().removeAllRanges();
      window.getSelection().addRange(range);
      captureSelection();
    }
    return;
  }
  if (selectedImage !== null && ['Backspace', 'Delete'].includes(event.key)) {
    event.preventDefault();
    perform('image', () => model.changeImage(selectedImage));
    return;
  }
  if (event.target.closest('[data-image]') && ['Enter', ' '].includes(event.key)) {
    event.preventDefault();
    event.target.closest('[data-image]').click();
    return;
  }
  captureSelection();
  if (model.tracksNativeEdits && ['Backspace', 'Delete'].includes(event.key) && (event.altKey || event.ctrlKey || event.metaKey)) {
    event.preventDefault();
    showError(new DocumentError('protected'));
    return;
  }
  if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) model.endGroup();
  if (event.key === 'Enter' && !event.isComposing) {
    event.preventDefault();
    perform('paragraph', () => model.splitParagraph(currentSelection(), event.shiftKey));
  }
  if (['Backspace', 'Delete'].includes(event.key) && deleteAtBoundary(event.key === 'Backspace')) event.preventDefault();
  if (selection && selection.startRun === selection.endRun && selection.start === selection.end &&
    !event.shiftKey && ['ArrowLeft', 'ArrowRight'].includes(event.key)) {
    const backward = event.key === 'ArrowLeft';
    const node = model.runs[active];
    if (backward ? selection.start === 0 : selection.end === node.length) {
      const index = active + (backward ? -1 : 1);
      if (model.runs[index] && !model.protected(model.runs[index].parentElement)) {
        event.preventDefault();
        focusRun(index, backward ? model.runs[index].length : 0);
      }
    }
  }
});
$('paper').addEventListener('beforeinput', event => {
  if (event.isComposing || composition) return;
  captureSelection();
  if (['historyUndo', 'historyRedo'].includes(event.inputType)) {
    event.preventDefault();
    perform(event.inputType === 'historyRedo' ? 'redo' : 'undo', () => model.undo(event.inputType === 'historyRedo'));
  } else if (['insertParagraph', 'insertLineBreak'].includes(event.inputType)) {
    event.preventDefault();
    perform('paragraph', () => model.splitParagraph(currentSelection(), event.inputType === 'insertLineBreak'));
  } else if (protectedSelection) {
    event.preventDefault();
    showError(new DocumentError('protected'));
  } else if (event.inputType === 'insertText' && selection && (model.tracksNativeEdits || selection.startRun !== selection.endRun || model.runs[selection.startRun].data === '\u200b')) {
    event.preventDefault();
    perform('typing', () => model.replaceText(selection, event.data || ''));
  } else if (['deleteContentBackward', 'deleteContentForward'].includes(event.inputType) && deleteAtBoundary(event.inputType === 'deleteContentBackward')) {
    event.preventDefault();
  } else if (model.tracksNativeEdits) {
    event.preventDefault();
    perform('typing', () => {
      if (!selection || !['deleteContentBackward', 'deleteContentForward'].includes(event.inputType)) throw new DocumentError('protected');
      const backward = event.inputType === 'deleteContentBackward';
      const node = model.runs[selection.startRun];
      const segments = [...new Intl.Segmenter(locale, { granularity: 'grapheme' }).segment(node.data)];
      const segment = backward ? segments.findLast(item => item.index < selection.start) : segments.find(item => item.index + item.segment.length > selection.end);
      if (!segment) return;
      return model.replaceText({
        ...selection,
        start: backward ? segment.index : selection.start,
        end: backward ? selection.end : segment.index + segment.segment.length,
      }, '');
    });
  }
});
$('paper').addEventListener('compositionstart', event => {
  try { composition = currentSelection(); }
  catch (error) {
    event.preventDefault();
    composition = null;
    showError(error);
    render();
  }
});
$('paper').addEventListener('compositionend', event => {
  const range = composition;
  composition = null;
  if (range) perform('typing', () => model.replaceText(range, event.data));
});
$('paper').addEventListener('paste', event => {
  event.preventDefault();
  const plain = plainPaste;
  plainPaste = false;
  const files = [...event.clipboardData.files];
  if (files.length) {
    try { insertImages(files, currentSelection()); }
    catch (error) { showError(error); }
  }
  else perform('paste', () => model.paste(currentSelection(), plain ? '' : event.clipboardData.getData('text/html'), event.clipboardData.getData('text/plain')));
});
window.addEventListener('keyup', event => { if (event.key.toLowerCase() === 'v') plainPaste = false; });
window.addEventListener('blur', () => { plainPaste = false; });
$('paper').addEventListener('cut', event => {
  event.preventDefault();
  event.clipboardData.setData('text/plain', window.getSelection().getRangeAt(0).toString());
  perform('cut', () => model.replaceText(currentSelection(), '', 'cut'));
});
document.querySelector('.toolbar').addEventListener('mousedown', event => {
  if (event.target.closest('button')) event.preventDefault();
});
$('bold').onclick = () => toggleFormat('font-weight', 'bold', 'normal');
$('italic').onclick = () => toggleFormat('font-style', 'italic', 'normal');
$('underline').onclick = () => toggleFormat('text-decoration', 'underline', 'none');
$('strike').onclick = () => toggleFormat('text-decoration', 'line-through', 'none');
$('font').onchange = event => applyFormat('font-family', `'${event.target.value}'`);
$('size').onchange = event => applyFormat('font-size', `${event.target.value}pt`);
$('color').onchange = event => applyFormat('color', event.target.value);
$('highlight').onchange = event => applyFormat('background-color', event.target.value);
for (const alignment of ['left', 'center', 'right']) {
  $(alignment).onclick = () => {
    try {
      perform('paragraph', () => model.paragraphProperty(currentSelection(), 'text-align', alignment));
    } catch (error) { showError(error); }
  };
}
$('paragraph').onclick = addParagraph;
function undoDocument(redo = false) {
  captureSelection();
  perform(redo ? 'redo' : 'undo', () => model.undo(redo));
}
$('undo').onclick = () => undoDocument();
$('redo').onclick = () => undoDocument(true);
$('new').onclick = () => {
  if (!unsaved() || confirm(t('discard'))) replaceDocument(WriteProDocument.create(t('untitled')));
};
$('open').onclick = () => $('file').click();
$('file').onchange = event => openFile(event.target.files[0]);
$('download').onclick = download;
let printing = false;
let printRoot = null;
const printStyle = document.createElement('style');
printStyle.media = 'print';
document.head.append(printStyle);
function preparePrint() {
  if (composition) throw new DocumentError('printFailed');
  const projection = createPrintProjection(model, messages[locale]);
  printRoot?.remove();
  printRoot = projection.root;
  document.body.append(printRoot);
  printStyle.textContent = projection.rules;
  return printRoot;
}
function closePrintPanel() {
  $('print-panel').hidden = true;
  $('print-toggle').setAttribute('aria-expanded', 'false');
  $('print-toggle').focus();
}
$('print-toggle').onclick = () => {
  togglePanel('print-toggle', 'print-panel');
  if (!$('print-panel').hidden) $('print-close').focus();
};
$('print-close').onclick = closePrintPanel;
$('print-panel').onkeydown = event => {
  if (event.key === 'Escape') { event.preventDefault(); closePrintPanel(); }
};
$('print-open').onclick = async () => {
  if (printing) return;
  printing = true;
  try {
    const printRevision = revision;
    const root = preparePrint();
    await document.fonts.ready;
    await Promise.all([...root.querySelectorAll('img')].map(image => image.decode()));
    if (revision !== printRevision || composition) throw new DocumentError('printFailed');
    window.print();
  } catch (error) {
    console.error('Browser print preparation failed', error);
    showError(error instanceof DocumentError ? error : new DocumentError('printFailed'));
  } finally { printing = false; }
};
window.addEventListener('beforeprint', () => {
  if (printing) return;
  try { preparePrint(); }
  catch (error) {
    showError(error);
    printRoot?.remove();
    printRoot = document.createElement('div');
    printRoot.id = 'print-document';
    printRoot.textContent = t(error instanceof DocumentError ? error.code : 'printFailed');
    document.body.append(printRoot);
    printStyle.textContent = '';
  }
});
window.addEventListener('afterprint', () => {
  printRoot?.remove();
  printRoot = null;
  printStyle.textContent = '';
});
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
  if (event.target.closest('input,textarea,select') && !['o', 's'].includes(key)) return;
  if (['o', 's', 'z', 'b', 'i', 'u', 'f'].includes(key)) event.preventDefault();
  if (key === 'o') $('file').click();
  if (key === 's') download();
  if (key === 'z') undoDocument(event.shiftKey);
  if (key === 'b') $('bold').click();
  if (key === 'i') $('italic').click();
  if (key === 'u') $('underline').click();
  if (key === 'f') { $('find-panel').hidden = false; $('find-toggle').setAttribute('aria-expanded', 'true'); $('find-query').focus(); }
});
window.addEventListener('dragover', event => {
  if (event.dataTransfer.types.includes('Files') || draggedImage) event.preventDefault();
});
$('paper').addEventListener('dragstart', event => {
  const frame = event.target.closest('[data-image]');
  if (!frame || frame.getAttribute('role') !== 'button') { event.preventDefault(); return; }
  draggedImage = model.images[Number(frame.dataset.image)];
  event.dataTransfer.setData('application/x-4wp-image', 'move');
  event.dataTransfer.effectAllowed = 'move';
});
$('paper').addEventListener('dragend', () => { draggedImage = null; });
window.addEventListener('drop', event => {
  if (!event.dataTransfer.files.length && !draggedImage) return;
  event.preventDefault();
  const files = [...event.dataTransfer.files];
  if (files.length === 1 && /\.4wp$/i.test(files[0].name)) openFile(files[0]);
  else {
    const position = document.caretPositionFromPoint?.(event.clientX, event.clientY);
    let range = document.caretRangeFromPoint?.(event.clientX, event.clientY);
    if (!range && position) {
      range = document.createRange();
      range.setStart(position.offsetNode, position.offset);
      range.collapse(true);
    }
    if (range && $('paper').contains(range.startContainer)) {
      window.getSelection().removeAllRanges();
      window.getSelection().addRange(range);
      captureDropSelection(range);
    }
    if (draggedImage) {
      const index = model.images.indexOf(draggedImage);
      draggedImage = null;
      perform('image', () => model.moveImage(index, currentSelection()));
    } else {
      try { insertImages(files, currentSelection()); }
      catch (error) { showError(error); }
    }
  }
});

function currentSelection() {
  captureSelection();
  if (protectedSelection) throw new DocumentError('protected');
  if (selection) return selection;
  const index = active ?? model.runs.findLastIndex(node => !model.protected(node.parentElement));
  const node = model.runs[index];
  if (!node) throw new DocumentError('selection');
  const range = { startRun: index, endRun: index, start: node.length, end: node.length };
  model.rememberSelection(range);
  return range;
}

function formattingSelection() {
  const range = currentSelection();
  if (range.startRun === range.endRun && range.start === range.end) return { ...range, start: 0, end: model.runs[range.startRun].length };
  return range;
}

function perform(label, operation) {
  const bookmark = model.selection;
  try {
    const before = model.serialize();
    const fallback = active !== null && model.runs[active] ? {
      node: model.runs[active], offset: selection?.start ?? model.runs[active].length,
    } : null;
    const image = selectedImage !== null ? model.images[selectedImage] : null;
    const caret = operation();
    render(caret || (fallback?.node.isConnected ? fallback : null));
    if (image?.isConnected && model.images.includes(image)) {
      $('paper').querySelector(`[data-image="${model.images.indexOf(image)}"]`)?.click();
    }
    if (model.serialize() !== before) { downloadReady = false; schedulePersist(label); }
  } catch (error) {
    render(bookmark ? { selection: bookmark } : null);
    showError(error);
  }
}

function deleteAtBoundary(backward) {
  if (!selection || active === null) return false;
  if (selection.startRun !== selection.endRun || selection.start !== selection.end) {
    perform('typing', () => model.replaceText(selection, ''));
    return true;
  }
  const node = model.runs[active];
  if (backward ? selection.start !== 0 : selection.end !== node.length) return false;
  const block = node.parentElement.closest('p,li');
  const neighbors = backward ? model.runs.slice(0, active).reverse() : model.runs.slice(active + 1);
  const other = neighbors.find(candidate => candidate.length || candidate.parentElement.closest('p,li') !== block);
  const otherIndex = model.runs.indexOf(other);
  if (other?.parentElement.closest('p,li') === block) {
    const segments = [...new Intl.Segmenter(locale, { granularity: 'grapheme' }).segment(other.data)];
    const range = backward ? {
      startRun: otherIndex, start: segments.at(-1)?.index ?? 0, endRun: active, end: 0,
    } : { startRun: active, start: node.length, endRun: otherIndex, end: segments[0]?.segment.length ?? 0 };
    perform('typing', () => model.deleteInlineBoundary(active, backward) || model.replaceText(range, ''));
  } else perform('paragraph', () => model.deleteInlineBoundary(active, backward) || model.mergeBoundary(active, backward));
  return true;
}

function captureDropSelection(range) {
  const node = range.startContainer;
  const run = (node.nodeType === 1 ? node : node.parentElement).closest('[data-run]');
  if (!run) return;
  const prefix = document.createRange();
  prefix.selectNodeContents(run);
  prefix.setEnd(node, range.startOffset);
  active = Number(run.dataset.run);
  selection = { startRun: active, endRun: active, start: prefix.toString().length, end: prefix.toString().length };
}

async function insertImages(files, target) {
  try {
    let range = target;
    for (const file of files) {
      const originalModel = model;
      const originalXML = model.serialize();
      const image = await readImage(file);
      if (originalModel !== model || originalXML !== model.serialize()) throw new DocumentError('staleInsertion');
      const caret = model.insertImage(range, image.src, image.width, image.height, file.name);
      render(caret);
      range = { startRun: model.runs.indexOf(caret.node), endRun: model.runs.indexOf(caret.node), start: caret.offset, end: caret.offset };
      schedulePersist('image');
    }
  } catch (error) { showError(error); }
}

$('paragraph-style').onchange = event => perform('style', () => model.styleBlocks(currentSelection(), event.target.value));
for (const [id, kind] of [['bullets', 'ul'], ['numbering', 'ol']]) {
  $(id).onclick = () => perform('list', () => {
    const block = model.runs[active]?.parentElement.closest('p,li');
    model.toggleList(model.blocks.indexOf(block), kind);
  });
}
for (const [id, delta] of [['indent', 18], ['outdent', -18]]) $(id).onclick = () => perform('paragraph', () => {
  const element = $('paper').querySelector(`[data-run="${active}"]`)?.closest('[data-block]');
  const value = Math.max(0, (parseFloat(getComputedStyle(element).marginLeft) || 0) * .75 + delta);
  model.paragraphProperty(currentSelection(), 'margin-left', `${value}pt`);
});
$('spacing').onchange = event => perform('paragraph', () => model.paragraphProperty(currentSelection(), 'margin-bottom', `${event.target.value}pt`));
$('line-height').onchange = event => perform('paragraph', () => model.paragraphProperty(currentSelection(), 'line-height', event.target.value));
$('insert-table').onclick = () => perform('table', () => {
  const block = active !== null ? model.runs[active].parentElement.closest('p,li') : null;
  model.insertTable(model.blocks.indexOf(block), Number($('table-rows').value), Number($('table-columns').value));
});
for (const [id, action] of [['add-row', 'addRow'], ['remove-row', 'removeRow'], ['add-column', 'addColumn'], ['remove-column', 'removeColumn']]) {
  $(id).onclick = () => perform('table', () => {
    const cell = $('paper').querySelector(`[data-run="${active}"]`)?.closest('[data-cell]');
    model.tableEdit(Number(cell.dataset.cell), action);
  });
}
$('insert-image').onclick = () => $('image-file').click();
$('paste-plain').onclick = async () => {
  try {
    currentSelection();
    const target = model.selection;
    const document = model;
    const xml = model.serialize();
    let text;
    try { text = await navigator.clipboard.readText(); }
    catch { throw new DocumentError('clipboardError'); }
    if (model !== document || model.serialize() !== xml) throw new DocumentError('staleClipboard');
    perform('paste', () => model.paste(model.resolveSelection(target), '', text));
  } catch (error) { showError(error); }
};
$('image-file').onchange = event => {
  try { insertImages([...event.target.files], currentSelection()); }
  catch (error) { showError(error); }
  event.target.value = '';
};
$('resize-image').onclick = () => perform('image', () => {
  const image = $('paper').querySelector(`[data-image="${selectedImage}"] img`);
  model.changeImage(selectedImage, Number($('image-width').value), image.naturalHeight / image.naturalWidth);
});
$('remove-image').onclick = () => perform('image', () => model.changeImage(selectedImage));
$('zoom').onchange = event => { $('paper').style.zoom = event.target.value; };

function togglePanel(button, panel) {
  $(panel).hidden = !$(panel).hidden;
  $(button).setAttribute('aria-expanded', String(!$(panel).hidden));
}
function pageSizeStatus() {
  try { $('page-native-size').textContent = pagePaperSize(pageDraft).join(' × '); }
  catch (error) {
    if (!(error instanceof DocumentError)) throw error;
    $('page-native-size').textContent = t('pageInvalid');
  }
}

function pageInputs() {
  $('page-units').value = pageUnit;
  for (const field of pageFields) $('page-' + field).value = pageDisplay(pageDraft[field], pageUnit);
  for (const element of document.querySelectorAll('.page-unit')) element.textContent = pageUnit;
  $('page-orientation').value = pageDraft.orientation;
  const dimensions = [pagePoints(pageDraft.width), pagePoints(pageDraft.height)];
  $('page-preset').value = Object.keys(paperPresets).find(key => paperPresets[key].every((value, index) => Math.abs(value - dimensions[index]) < 1e-8)) || 'custom';
  pageSizeStatus();
}

function renderPageSetup() {
  const setup = model.pageSetup();
  const layout = model.sectionLayout();
  if (!layout.sections.some(section => section.index === pageTarget)) pageTarget = 0;
  const section = pageTarget ? model.sectionSetup(pageTarget) : null;
  $('page-target').replaceChildren(new Option(t('sectionDefaults'), '0'), ...layout.sections.map(item => {
    const name = model.sectionSetup(item.index).name;
    return new Option(`${t('sectionLabel')} ${item.index}${name ? ` · ${name}` : ''}`, String(item.index));
  }));
  $('page-target').value = String(pageTarget);
  pageDraft = { ...(section?.geometry || setup.geometry) };
  pageChanges = {};
  $('page-overrides').hidden = ![...setup.sections.keys()].some(index => index > 0);
  const reason = section?.reason || setup.reason;
  $('page-protection').textContent = reason ? t(reason) : '';
  for (const control of $('page-form').querySelectorAll('input,select,button')) control.disabled = Boolean(reason);
  $('section-controls').hidden = !section;
  if (section) {
    $('section-name').value = section.name;
    $('section-inherit-orientation').checked = !Object.hasOwn(section.overrides, 'orientation');
    $('section-inherit-margins').checked = !Object.hasOwn(section.overrides, 'top');
  }
  pageInheritance(reason);
  pageInputs();
  renderColumns();
  const breaks = model.blocks.flatMap((block, index) => {
    if (block.localName !== 'p' || block.parentElement.localName !== 'body') return [];
    try {
      const kind = paragraphBreak(model.values(block));
      return kind ? [new Option(`${index + 1} · ${t({ page: 'breakPage', section: 'breakSection', continuous: 'breakContinuous' }[kind])}`, String(index))] : [];
    } catch (error) {
      if (!(error instanceof DocumentError)) throw error;
      return [];
    }
  });
  $('break-list').replaceChildren(...breaks);
  $('break-remove').disabled = model.readOnly || !breaks.length;
}

function pageInheritance(reason = null) {
  if (!pageTarget) return;
  const inheritedOrientation = $('section-inherit-orientation').checked;
  const inheritedMargins = $('section-inherit-margins').checked;
  for (const id of ['page-preset', 'page-width', 'page-height']) $(id).disabled = true;
  $('page-orientation').disabled = Boolean(reason) || inheritedOrientation;
  for (const side of ['top', 'right', 'bottom', 'left']) $('page-' + side).disabled = Boolean(reason) || inheritedMargins;
  $('section-orientation-state').textContent = t(inheritedOrientation ? 'sectionInherited' : 'sectionOverride');
  $('section-margins-state').textContent = t(inheritedMargins ? 'sectionInherited' : 'sectionOverride');
}
$('page-target').onchange = event => { pageTarget = Number(event.target.value); renderPageSetup(); };
for (const group of ['orientation', 'margins']) $('section-inherit-' + group).onchange = () => {
  const defaults = model.pageSetup().geometry;
  if ($('section-inherit-' + group).checked) {
    for (const field of group === 'orientation' ? ['orientation'] : ['top', 'right', 'bottom', 'left']) pageDraft[field] = defaults[field];
  }
  pageInheritance();
  pageInputs();
};
$('break-insert').onclick = () => perform('breakEdit', () => model.insertBreak(currentSelection(), $('break-kind').value));
$('break-remove').onclick = () => perform('breakEdit', () => model.removeBreak(Number($('break-list').value)));
$('page-toggle').onclick = () => {
  captureSelection();
  togglePanel('page-toggle', 'page-panel');
  if (!$('page-panel').hidden) { renderPageSetup(); $('page-units').focus(); }
};
function closePageSetup() {
  $('page-panel').hidden = true;
  $('page-toggle').setAttribute('aria-expanded', 'false');
  $('page-toggle').focus();
}
$('page-close').onclick = closePageSetup;
$('page-panel').addEventListener('keydown', event => {
  if (event.key === 'Escape') { event.preventDefault(); closePageSetup(); }
});
$('page-units').onchange = event => {
  changeUnits(event.target.value);
};
for (const field of pageFields) $('page-' + field).oninput = event => {
  pageChanges[field] = pageDraft[field] = `${event.target.value}${pageUnit}`;
  if (field === 'width' || field === 'height') $('page-preset').value = 'custom';
  pageSizeStatus();
};
$('page-orientation').onchange = event => {
  pageChanges.orientation = pageDraft.orientation = event.target.value;
  pageSizeStatus();
};
$('page-preset').onchange = event => {
  const preset = paperPresets[event.target.value];
  if (!preset) return;
  for (const [index, field] of ['width', 'height'].entries()) pageChanges[field] = pageDraft[field] = `${preset[index]}pt`;
  pageInputs();
};
$('page-form').onsubmit = event => {
  event.preventDefault();
  if (pageTarget) perform('sectionSetup', () => model.setSectionSetup(pageTarget, {
    name: $('section-name').value,
    orientation: $('section-inherit-orientation').checked ? null : pageDraft.orientation,
    margins: $('section-inherit-margins').checked ? null : Object.fromEntries(['top', 'right', 'bottom', 'left'].map(side => [side, pageDraft[side]])),
  }));
  else perform('pageSetup', () => model.setPageSetup(pageChanges));
  $('page-apply').focus();
};

function columnInputs() {
  if (!columnDraft) return;
  $('column-count').value = columnDraft.count;
  $('column-gap').value = pageDisplay(columnDraft.gap, pageUnit);
}
function renderColumns() {
  const setup = model.columnSetup(pageTarget);
  columnDraft = { ...setup.settings };
  columnChanges = {};
  $('columns-protection').textContent = setup.reason ? t(setup.reason) : '';
  for (const control of $('columns-form').querySelectorAll('input,button')) control.disabled = Boolean(setup.reason);
  for (const field of ['count', 'gap']) {
    $('column-inherit-' + field + '-label').hidden = !pageTarget;
    $('column-inherit-' + field).checked = pageTarget > 0 && !Object.hasOwn(setup.overrides, field);
    $('column-' + field).disabled ||= $('column-inherit-' + field).checked;
  }
  columnInputs();
}
for (const field of ['count', 'gap']) {
  $('column-inherit-' + field).onchange = event => {
    columnChanges[field] = event.target.checked ? null : columnDraft[field];
    if (event.target.checked) columnDraft[field] = model.columnSetup().settings[field];
    $('column-' + field).disabled = event.target.checked;
    columnInputs();
  };
  $('column-' + field).oninput = event => {
    columnChanges[field] = columnDraft[field] = field === 'count' && event.target.value !== '' ? Number(event.target.value) : field === 'count' ? NaN : `${event.target.value}${pageUnit}`;
  };
}
$('columns-form').onsubmit = event => {
  event.preventDefault();
  perform('columnsSetup', () => model.setColumns(pageTarget, columnChanges));
  $('columns-apply').focus();
};

function selectedTabSettings() {
  captureSelection();
  if (protectedSelection) throw new DocumentError('protected');
  if (!selection) throw new DocumentError('selection');
  return model.tabBlocks(selection).map(block => model.paragraphTabs(block));
}
function tabInputs() {
  $('tab-units').value = pageUnit;
  for (const unit of document.querySelectorAll('.tab-unit')) unit.textContent = pageUnit;
  if ($('tabs-panel').hidden || !tabDraft || !tabDefaultDraft) return;
  $('tab-position').value = pageDisplay(tabDraft.position, pageUnit);
  $('tab-type').value = tabDraft.type;
  $('tab-leader').value = tabDraft.leader;
  $('tab-interval').value = pageDisplay(tabDefaultDraft.position, pageUnit);
  $('tab-default-type').value = tabDefaultDraft.type;
  $('tab-default-leader').value = tabDefaultDraft.leader;
}
function chooseTabStop() {
  const settings = selectedTabSettings();
  const position = $('tab-stop-list').value;
  tabOriginalPosition = position === 'new' ? null : Number(position);
  const stops = settings.flatMap(item => item.stops);
  tabDraft = { ...(stops.find(stop => pagePoints(stop.position) === tabOriginalPosition) || { ...defaultTab, position: '36pt' }) };
  $('tab-stop-remove').disabled = tabOriginalPosition === null;
  tabInputs();
}
function renderTabs() {
  if ($('tabs-panel').hidden) return;
  let settings;
  let reason;
  try { settings = selectedTabSettings(); if (!settings.length) throw new DocumentError('selection'); }
  catch (error) {
    if (!(error instanceof DocumentError)) throw error;
    reason = error.code;
  }
  for (const control of $('tabs-panel').querySelectorAll('input,select,button:not(#tabs-close)')) control.disabled = Boolean(reason);
  $('tabs-status').textContent = reason ? t(reason) : `${settings.length} · ${t('tabsSelected')}${settings.some(item => JSON.stringify(item) !== JSON.stringify(settings[0])) ? ` · ${t('mixed')}` : ''}`;
  if (reason) { tabDraft = null; tabDefaultDraft = null; return; }
  const positions = [...new Set(settings.flatMap(item => item.stops.map(stop => pagePoints(stop.position))))].sort((a, b) => a - b);
  $('tab-stop-list').replaceChildren(new Option(t('tabNew'), 'new'), ...positions.map(position =>
    new Option(`${pageDisplay(`${position}pt`, pageUnit)} ${pageUnit}`, String(position))));
  tabDefaultDraft = { ...settings[0].default };
  tabDefaultChanges = {};
  chooseTabStop();
}
function tabPerform(operation) {
  const bookmark = model.selection;
  perform('tabsSetup', () => { operation(); return bookmark ? { selection: bookmark } : null; });
}
$('tabs-toggle').onclick = () => {
  captureSelection();
  togglePanel('tabs-toggle', 'tabs-panel');
  if (!$('tabs-panel').hidden) { renderTabs(); $('tabs-close').focus(); }
};
function closeTabs() {
  $('tabs-panel').hidden = true;
  $('tabs-toggle').setAttribute('aria-expanded', 'false');
  $('tabs-toggle').focus();
}
$('tabs-close').onclick = closeTabs;
$('tabs-panel').addEventListener('keydown', event => {
  if (event.key === 'Escape') { event.preventDefault(); closeTabs(); }
});
$('tab-stop-list').onchange = () => { try { chooseTabStop(); } catch (error) { showError(error); } };
$('tab-position').oninput = event => { tabDraft.position = `${event.target.value}${pageUnit}`; };
$('tab-type').onchange = event => { tabDraft.type = event.target.value; };
$('tab-leader').onchange = event => { tabDraft.leader = event.target.value; };
$('tab-interval').oninput = event => { tabDefaultChanges.position = tabDefaultDraft.position = `${event.target.value}${pageUnit}`; };
$('tab-default-type').onchange = event => { tabDefaultChanges.type = tabDefaultDraft.type = event.target.value; };
$('tab-default-leader').onchange = event => { tabDefaultChanges.leader = tabDefaultDraft.leader = event.target.value; };
function changeUnits(unit) {
  try {
    for (const field of pageFields) pagePoints(pageDraft[field]);
    if (columnDraft) pagePoints(columnDraft.gap);
    if (!$('tabs-panel').hidden && tabDraft && tabDefaultDraft) {
      pagePoints(tabDraft.position);
      pagePoints(tabDefaultDraft.position);
    }
    pageUnit = unit;
    remember();
    tabInputs();
    pageInputs();
    columnInputs();
  } catch (error) {
    $('page-units').value = $('tab-units').value = pageUnit;
    showError(error);
  }
}
$('tab-units').onchange = event => changeUnits(event.target.value);
$('tab-stop-form').onsubmit = event => {
  event.preventDefault();
  const stop = { ...tabDraft };
  const original = tabOriginalPosition;
  tabPerform(() => model.setParagraphTabs(currentSelection(), settings => {
    const position = pagePoints(stop.position);
    if (original !== position && settings.stops.some(item => pagePoints(item.position) === position)) throw new DocumentError('tabsDuplicate');
    settings.stops = settings.stops.filter(item => pagePoints(item.position) !== original && pagePoints(item.position) !== position);
    settings.stops.push(stop);
    settings.stops.sort((a, b) => pagePoints(a.position) - pagePoints(b.position));
    return settings;
  }));
};
$('tab-stop-remove').onclick = () => {
  const position = tabOriginalPosition;
  tabPerform(() => model.setParagraphTabs(currentSelection(), settings => ({ ...settings, stops: settings.stops.filter(stop => pagePoints(stop.position) !== position) })));
};
$('tab-default-form').onsubmit = event => {
  event.preventDefault();
  const changes = { ...tabDefaultChanges };
  tabPerform(() => model.setParagraphTabs(currentSelection(), settings => ({ ...settings, default: { ...settings.default, ...changes } })));
};
$('tab-reset').onclick = () => tabPerform(() => model.resetParagraphTabs(currentSelection()));
$('insert-tab').onclick = () => perform('typing', () => model.replaceText(currentSelection(), '\t'));
$('find-toggle').onclick = () => { togglePanel('find-toggle', 'find-panel'); if (!$('find-panel').hidden) $('find-query').focus(); };
$('history-toggle').onclick = () => { togglePanel('history-toggle', 'history-panel'); renderHistory(); };
$('bookmarks-toggle').onclick = () => {
  captureSelection();
  togglePanel('bookmarks-toggle', 'bookmarks-panel');
  if (!$('bookmarks-panel').hidden) { renderBookmarks(); $('bookmark-name').focus(); }
};
$('bookmarks-panel').addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    $('bookmarks-panel').hidden = true;
    $('bookmarks-toggle').setAttribute('aria-expanded', 'false');
    clearBookmarkHighlight();
    $('bookmarks-toggle').focus();
  }
});
$('bookmark-form').onsubmit = event => {
  event.preventDefault();
  perform('bookmark', () => {
    const savedSelection = model.selection;
    if (!bookmarkSelection) throw new DocumentError('selection');
    model.changeBookmark($('bookmark-name').value, { selection: model.sourceRange(bookmarkSelection) });
    currentBookmark = $('bookmark-name').value;
    return savedSelection ? { selection: savedSelection } : null;
  });
  $('bookmark-name').focus();
};
for (const [id, remove] of [['bookmark-rename', false], ['bookmark-delete', true]]) $(id).onclick = () => {
  perform('bookmark', () => {
    if (currentBookmark === null) throw new DocumentError('bookmarkMissing');
    model.changeBookmark($('bookmark-name').value, { previous: currentBookmark, remove });
    currentBookmark = remove ? null : $('bookmark-name').value;
  });
  $('bookmark-name').focus();
};

function clearBookmarkHighlight() {
  CSS.highlights?.delete('bookmark');
  for (const element of $('paper').querySelectorAll('.bookmark-boundary')) element.classList.remove('bookmark-boundary');
  bookmarkHighlight = null;
}

function navigateBookmark(name) {
  try {
    clearBookmarkHighlight();
    const { range, selection: selected } = model.bookmarkRange(name);
    currentBookmark = name;
    $('bookmark-name').value = name;
    window.getSelection().removeAllRanges();
    active = null;
    selection = null;
    model.selection = null;
    bookmarkSelection = null;
    if (selected) {
      model.rememberSelection(selected);
      restoreSelection(model.selection);
    }
    bookmarkHighlight = range;
    if (CSS.highlights) CSS.highlights.set('bookmark', new Highlight(range));
    const node = range.startContainer.nodeType === 1 ? range.startContainer : range.startContainer.parentElement;
    if (range.collapsed || !selected) node.classList.add('bookmark-boundary');
    node.scrollIntoView({ block: 'nearest' });
    renderBookmarks();
    if (!selected) [...$('bookmark-list').querySelectorAll('button')].find(button => button.textContent === name)?.focus();
    updateStatus();
  } catch (error) {
    showError(error instanceof DocumentError && error.code === 'protected' ? new DocumentError('bookmarkNavigation') : error);
  }
}

function renderBookmarks() {
  let items;
  try { items = model.bookmarks(); }
  catch (error) {
    if (!(error instanceof DocumentError) || error.code !== 'protected') throw error;
    $('bookmark-list').replaceChildren();
    $('bookmark-status').textContent = t('bookmarkUnavailable');
    currentBookmark = null;
    updateStatus();
    return;
  }
  if (!items.some(item => item.name === currentBookmark)) currentBookmark = null;
  $('bookmark-list').replaceChildren(...items.map(item => {
    const li = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = item.name;
    button.setAttribute('aria-pressed', String(item.name === currentBookmark));
    button.onclick = () => navigateBookmark(item.name);
    const bounds = document.createElement('span');
    bounds.textContent = `[${item.start - 1}, ${item.end - 1})`;
    li.append(button, bounds);
    return li;
  }));
  const chosen = items.find(item => item.name === currentBookmark);
  $('bookmark-status').textContent = chosen ? `${chosen.name} · [${chosen.start - 1}, ${chosen.end - 1}) · ${t(bookmarkHighlight ? 'bookmarkLocated' : 'bookmarkSelected')}` : t(items.length ? 'bookmarkChoose' : 'bookmarkEmpty');
  updateStatus();
}
$('link-toggle').onclick = () => {
  captureSelection();
  togglePanel('link-toggle', 'link-panel');
  if (!$('link-panel').hidden) {
    $('link-url').value = model.runs[active]?.parentElement.closest('a')?.getAttribute('href') || '';
    $('link-url').focus();
  }
};
for (const [id, operation] of [
  ['apply-link', range => model.setLink(range, $('link-url').value.trim())],
  ['remove-link', range => model.removeLink(range)],
]) $(id).onclick = () => perform('link', () => {
  const range = currentSelection();
  const bookmark = model.selection;
  operation(range);
  return bookmark ? { selection: bookmark } : null;
});

function selectMatch(match) {
  const first = $('paper').querySelector(`[data-run="${match.startRun}"]`);
  const last = $('paper').querySelector(`[data-run="${match.endRun}"]`);
  const range = document.createRange();
  range.setStart(first.firstChild || first, match.start);
  range.setEnd(last.firstChild || last, match.end);
  window.getSelection().removeAllRanges();
  window.getSelection().addRange(range);
  first.scrollIntoView({ block: 'nearest' });
}
function findNext() {
  try {
    const matches = model.find($('find-query').value, $('match-case').checked);
    findIndex = matches.length ? (findIndex + 1) % matches.length : -1;
    $('find-count').textContent = `${findIndex + 1} / ${matches.length}`;
    if (findIndex >= 0) selectMatch(matches[findIndex]);
  } catch (error) { showError(error); }
}
function refreshFindCount() {
  if (!$('find-query').value) { $('find-count').textContent = ''; return; }
  try {
    const matches = model.find($('find-query').value, $('match-case').checked);
    findIndex = matches.length ? Math.max(0, Math.min(findIndex, matches.length - 1)) : -1;
    $('find-count').textContent = `${findIndex + 1} / ${matches.length}`;
  } catch (error) { showError(error); }
}
$('find-next').onclick = findNext;
$('find-query').oninput = () => { findIndex = -1; findNext(); };
$('match-case').onchange = () => { findIndex = -1; findNext(); };
$('replace-one').onclick = () => perform('replace', () => model.replaceMatches($('find-query').value, $('replacement').value, false, Math.max(0, findIndex), $('match-case').checked));
$('replace-all').onclick = () => perform('replace', () => model.replaceMatches($('find-query').value, $('replacement').value, true, 0, $('match-case').checked));

function renderHistory() {
  $('version-list').replaceChildren(...versions.toReversed().map(version => {
    const item = document.createElement('li');
    const label = document.createElement('span');
    label.textContent = `${version.name || t(version.label === 'image' ? 'historyImage' : version.label)} · ${new Intl.DateTimeFormat(locale, { dateStyle: 'short', timeStyle: 'medium' }).format(version.at)}`;
    const button = document.createElement('button');
    button.textContent = t('restore');
    button.onclick = () => perform('restore', () => model.restoreVersion(version.xml));
    item.append(label, button);
    return item;
  }));
}

function setDraftStatus(code) {
  draftStatus = code;
  $('draft-state').textContent = t(code);
}

function schedulePersist(label) {
  if (!storageReady) return;
  // An older in-flight write must not mark newer, still-debounced edits as saved.
  revision++;
  clearTimeout(persistTimer);
  setDraftStatus('draftSaving');
  persistTimer = setTimeout(() => persist(label), 450);
}

async function persist(label, name = '') {
  clearTimeout(persistTimer);
  const xml = model.serialize();
  const now = Date.now();
  if (!versions.length) versions.push({ xml: model.initial, label: 'initial', at: now - 1 });
  if (versions.at(-1).xml !== xml || name) {
    if (label === 'typing' && versions.at(-1).label === 'typing' && now - versions.at(-1).at < 1500) versions.pop();
    versions.push({ xml, label, name, at: now });
  }
  while (versions.length > 1 && (versions.length > 20 || versions.reduce((sum, item) => sum + item.xml.length, 0) > 4 * 1024 * 1024)) versions.shift();
  pendingRecord = { document: model.pack(), saved, versions: [...versions], revision: ++revision };
  renderHistory();
  if (writing) return;
  writing = true;
  try {
    while (pendingRecord) {
      const record = pendingRecord;
      pendingRecord = null;
      await history.write(record);
      if (record.revision === revision) setDraftStatus('draftSaved');
    }
  } catch (error) {
    setDraftStatus('storageError');
    showError(error);
  } finally { writing = false; }
}
$('save-version').onclick = () => { persist('manual', $('version-name').value.trim()); $('version-name').value = ''; };

async function start() {
  localize();
  document.querySelector('#app').inert = true;
  $('new').disabled = true;
  $('open').disabled = true;
  try {
    const record = await history.read();
    if (record) {
      const restored = WriteProDocument.unpack(record.document);
      if (!Array.isArray(record.versions) || record.versions.length > 20 ||
        record.versions.some(version => !version || typeof version.xml !== 'string' || version.xml.length > 32 * 1024 * 1024 ||
          typeof version.label !== 'string' || !(version.label in messages.en) ||
          version.name !== undefined && (typeof version.name !== 'string' || version.name.length > 100) ||
          !Number.isFinite(version.at)) ||
        record.versions.reduce((sum, version) => sum + version.xml.length, 0) > 36 * 1024 * 1024) throw new DocumentError('storageError');
      model = restored;
      saved = typeof record.saved === 'string' ? record.saved : model.initial;
      versions = record.versions;
      render(model.selection ? { selection: model.selection } : null);
      $('recovery-notice').hidden = false;
      setDraftStatus('draftSaved');
    }
  } catch (error) { showError(error); }
  finally {
    storageReady = true;
    document.querySelector('#app').inert = false;
    $('new').disabled = false;
    $('open').disabled = false;
  }
}
start();
