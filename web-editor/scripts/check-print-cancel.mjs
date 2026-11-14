import assert from 'node:assert/strict';
import { readFile, writeFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, expect } from '@playwright/test';
import { evidencePreview } from './evidence-preview.mjs';

const directory = resolve(process.argv[2] || '');
const paged = process.argv[3] === '--paged';
const expanded = process.argv[3] === '--expanded';
const tables = process.argv[3] === '--tables';
const columns = process.argv[3] === '--columns';
const seams = process.argv[3] === '--seams';
const cellLists = process.argv[3] === '--cell-lists';
const colspans = process.argv[3] === '--colspans';
const rowspans = process.argv[3] === '--rowspans';
const nowitnesses = process.argv[3] === '--nowitnesses';
const paginated = paged || expanded || tables || columns || seams || cellLists || colspans || rowspans || nowitnesses;
assert(process.argv[2], 'Usage: node scripts/check-print-cancel.mjs NATIVE_EVIDENCE_DIRECTORY [--paged|--expanded|--tables|--columns|--seams|--cell-lists|--colspans|--rowspans|--nowitnesses]');
const prefix = nowitnesses ? 'nowitnesses-cancel' : rowspans ? 'rowspans-cancel' : colspans ? 'colspans-cancel' : cellLists ? 'cell-lists-cancel' : seams ? 'seams-cancel' : columns ? 'columns-cancel' : tables ? 'tables-cancel' : expanded ? 'expanded-cancel' : paged ? 'paged-cancel' : 'print-cancel';
const manifest = paginated ? JSON.parse(await readFile(resolve(directory, 'Input/cases.json'), 'utf8')) : null;
if (paginated) {
  const files = new Set(await readdir(resolve(directory, 'Input')));
  for (const phase of ['clean-with-redo', 'dirty-with-undo']) {
    const name = `${prefix}-${phase}`;
    assert(!manifest.cases.some(entry => entry.name === name) && !files.has(`${name}.4wp`),
      'Choose fresh evidence: print-cancel downloads must not be overwritten');
  }
}
const server = await evidencePreview(directory, 4190, prefix);
const browser = await chromium.launch({ headless: false });
try {
  const page = await browser.newPage({ acceptDownloads: true, locale: 'en-US' });
  const cdp = await browser.newBrowserCDPSession();
  await page.goto(server.resolvedUrls.local[0]);
  await page.locator('#file').setInputFiles(resolve(directory, nowitnesses ? 'Input/nowitness-source-rich.4wp' : rowspans ? 'Input/rowspan-source-media.4wp' : colspans ? 'Input/colspan-source-rich.4wp' : cellLists ? 'Input/cell-list-source-mixed.4wp' : seams ? 'Input/continuous-paged-source-overflow.4wp' : columns ? 'Input/paged-column-source-mixed.4wp' : tables ? 'Input/paged-table-source-mixed.4wp' : expanded ? 'Input/expanded-source-images.4wp' : paged ? 'Input/paged-source-right.4wp' : 'Output/print-rich.4wp'));
  await expect(page.locator('#paper')).toContainText(nowitnesses ? 'NOWSTART' : rowspans ? 'ROWSTART' : colspans ? 'SPANSTART' : cellLists ? 'CELLSTART' : seams ? 'SEAMSTART' : columns ? 'COLUMNSTART' : tables ? 'TABLESTART' : expanded ? 'EXPANDED' : paged ? 'PAGED1' : 'TAILEND');
  if (paged) await page.locator('#editing-scope').selectOption('section1FirstFooter');
  if (tables || columns || cellLists || colspans || rowspans || nowitnesses) await page.locator('#editing-scope').selectOption('section1FirstHeader');
  await page.locator('#paper [contenteditable]').first().evaluate(element => {
    element.focus();
    getSelection().collapse(element.firstChild, 0);
  });
  if (paginated) await page.locator('#paper [contenteditable]').first().fill(nowitnesses ? 'WEBNOW' : rowspans ? 'WEBROW' : colspans ? 'WEBSPAN' : cellLists ? 'WEBCELL' : seams ? 'WEBSEAM' : columns ? 'WEBCOLUMN' : tables ? 'WEBTABLE' : expanded ? 'WEBEXPANDED' : 'WEBPAGED');
  else await page.keyboard.insertText('EDIT');
  await page.locator('#undo').click();
  await page.locator('#zoom').selectOption('1.5');
  await page.locator('#settings-toggle').click();
  await page.locator('#theme').selectOption('dark');
  let pages;
  if (paginated) {
    await page.locator('#paged-panel > summary').click();
    if (expanded || tables || columns || seams || cellLists || colspans || rowspans || nowitnesses) await expect(page.locator('#paged-view .browser-page').nth(1)).toBeVisible();
    else await expect(page.locator('#paged-view .browser-page')).toHaveCount(6);
    pages = await page.locator('#paged-view .browser-page').count();
  }
  await page.locator('#print-toggle').click();

  const snapshot = () => page.evaluate(async () => {
    const record = await new Promise((resolve, reject) => {
      const request = indexedDB.open('4wp-editor-history', 1);
      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const db = request.result;
        const read = db.transaction('session').objectStore('session').get('active');
        read.onsuccess = () => { resolve(read.result); db.close(); };
        read.onerror = () => { reject(read.error); db.close(); };
      };
    });
    const selected = getSelection();
    const path = node => {
      if (!node) return null;
      const indices = [];
      while (node !== document) {
        indices.unshift([...node.parentNode.childNodes].indexOf(node));
        node = node.parentNode;
      }
      return indices;
    };
    return {
      dom: document.documentElement.outerHTML,
      paper: document.querySelector('#paper').outerHTML,
      paged: document.querySelector('#paged-view').outerHTML,
      selection: { text: selected.toString(), anchor: selected.anchorNode?.parentElement?.dataset.run, offset: selected.anchorOffset,
        focus: selected.focusNode?.parentElement?.dataset.run, focusOffset: selected.focusOffset, ranges: selected.rangeCount,
        anchorPath: path(selected.anchorNode), focusPath: path(selected.focusNode) },
      zoom: document.querySelector('#zoom').value, scope: document.querySelector('#editing-scope').value,
      state: document.querySelector('#save-state').textContent,
      undo: document.querySelector('#undo').disabled, redo: document.querySelector('#redo').disabled,
      record,
    };
  });
  let commandId = 0;
  const command = (sessionId, method, params = {}) => new Promise((resolve, reject) => {
    const id = ++commandId;
    const listener = event => {
      if (event.sessionId !== sessionId) return;
      const message = JSON.parse(event.message);
      if (message.id !== id) return;
      cdp.off('Target.receivedMessageFromTarget', listener);
      if (message.error) reject(new Error(JSON.stringify(message.error)));
      else resolve(message.result);
    };
    cdp.on('Target.receivedMessageFromTarget', listener);
    cdp.send('Target.sendMessageToTarget', { sessionId, message: JSON.stringify({ id, method, params }) }).catch(reject);
  });
  const results = [];
  const exportBytes = async path => {
    const pending = page.waitForEvent('download');
    await page.locator('#download').click();
    await (await pending).saveAs(path);
    return readFile(path);
  };
  for (const phase of ['clean-with-redo', 'dirty-with-undo']) {
    if (phase === 'dirty-with-undo') await page.locator('#redo').click();
    await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
    if (paginated) await expect(page.locator('#paged-view .browser-page')).toHaveCount(pages);
    // Dirty downloads stamp modification time; keep it identical without freezing timers.
    await page.clock.setFixedTime(new Date());
    const sourceBefore = await exportBytes(resolve(directory, `Output/${prefix}-${phase}-before.4wp`));
    await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
    await page.locator('#paper [contenteditable]').first().evaluate(element => {
      element.focus();
      getSelection().setBaseAndExtent(element.firstChild, 1, element.firstChild, 3);
      document.dispatchEvent(new Event('selectionchange'));
    });
    const before = await snapshot();
    await page.evaluate(() => setTimeout(() => document.querySelector('#print-open').click(), 0));
    let target;
    await expect.poll(async () => {
      target = (await cdp.send('Target.getTargets')).targetInfos.find(item => item.url === 'chrome://print/');
      return Boolean(target);
    }).toBe(true);
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId: target.targetId, flatten: false });
    const expression = `(() => {
      const find = root => {
        for (const element of root.querySelectorAll('*')) {
          if (element.matches('cr-button.cancel-button')) return element;
          if (element.shadowRoot) { const result = find(element.shadowRoot); if (result) return result; }
        }
      };
      const cancel = find(document);
      if (!cancel) return 'loading';
      cancel.click();
      return 'canceled';
    })()`;
    await expect.poll(async () => {
      const result = await command(sessionId, 'Runtime.evaluate', { expression, returnByValue: true });
      assert(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
      return result.result.value;
    }, { timeout: 15000 }).toBe('canceled');
    await expect(page.locator('#print-document')).toHaveCount(0);
    await expect.poll(async () => (await cdp.send('Target.getTargets')).targetInfos.some(item => item.url === 'chrome://print/')).toBe(false);
    if (paginated) await expect(page.locator('#paged-view .browser-page')).toHaveCount(pages);
    const after = await snapshot();
    await writeFile(resolve(directory, `Output/${prefix}-${phase}-snapshots.json`), JSON.stringify({ before, after }, null, 2));
    assert.deepEqual(after, before, 'Real browser cancellation changed editing/history/recovery state');
    await page.screenshot({ path: resolve(directory, `Output/${prefix}-${phase}.png`) });
    if (paginated) {
      const sourceAfter = await exportBytes(resolve(directory, `Input/${prefix}-${phase}.4wp`));
      assert.deepEqual(sourceAfter, sourceBefore, 'Actual print Cancel must preserve clean and dirty export bytes');
      if (columns && phase === 'clean-with-redo') assert.deepEqual(
        await readFile(resolve(directory, `Input/${prefix}-${phase}.4wp`)),
        await readFile(resolve(directory, 'Input/paged-column-source-mixed.4wp')),
        'Actual print Cancel must leave clean multi-column source bytes unchanged');
      if (seams && phase === 'clean-with-redo') assert.deepEqual(sourceAfter,
        await readFile(resolve(directory, 'Input/continuous-paged-source-overflow.4wp')),
        'Actual print Cancel must leave clean continuous-seam source bytes unchanged');
      if (cellLists && phase === 'clean-with-redo') assert.deepEqual(sourceAfter,
        await readFile(resolve(directory, 'Input/cell-list-source-mixed.4wp')),
        'Actual print Cancel must leave clean cell-list source bytes unchanged');
      if (colspans && phase === 'clean-with-redo') assert.deepEqual(sourceAfter,
        await readFile(resolve(directory, 'Input/colspan-source-rich.4wp')),
        'Actual print Cancel must leave clean merged-table source bytes unchanged');
      if (rowspans && phase === 'clean-with-redo') assert.deepEqual(sourceAfter,
        await readFile(resolve(directory, 'Input/rowspan-source-media.4wp')),
        'Actual print Cancel must leave clean row-band source bytes unchanged');
      if (nowitnesses && phase === 'clean-with-redo') assert.deepEqual(sourceAfter,
        await readFile(resolve(directory, 'Input/nowitness-source-rich.4wp')),
        'Actual print Cancel must leave clean no-witness source bytes unchanged');
    } else {
      assert.deepEqual(await exportBytes(resolve(directory, `Output/${prefix}-${phase}-after.4wp`)), sourceBefore);
    }
    results.push({ phase, actualBrowserPrintPreview: true, cancelButtonClicked: true,
      unchangedFullDOMSelectionEndpointsScopeZoomHistoryRecovery: true, identicalSourceExportBytes: true });
  }
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  await (await pending).saveAs(resolve(directory, `Output/${prefix}-dirty.4wp`));
  assert((await readFile(resolve(directory, `Output/${prefix}-dirty.4wp`))).length > 0);
  if (paginated) {
    for (const [phase, stage] of [['clean-with-redo', 'original'], ['dirty-with-undo', 'edited']]) {
      const name = `${prefix}-${phase}`;
      manifest.cases.push(nowitnesses ? { name, file: `${name}.4wp`,
        flow: { source: stage === 'original' ? 'nowitness-source-rich.4wp' : 'nowitness-target-rich.4wp', action: 'identity' },
        resources: 'nowitness-source-rich.4wp', pagedTable: { rows: 26, columns: 3 } } : rowspans ? { name, file: `${name}.4wp`,
        flow: { source: stage === 'original' ? 'rowspan-source-media.4wp' : 'rowspan-target-media.4wp', action: 'identity' },
        resources: 'rowspan-source-media.4wp', pagedTable: { rows: 26, columns: 3 } } : colspans ? { name, file: `${name}.4wp`,
        flow: { source: stage === 'original' ? 'colspan-source-rich.4wp' : 'colspan-target-rich.4wp', action: 'identity' },
        resources: 'colspan-source-rich.4wp', pagedTable: { rows: 26, columns: 3 } } : cellLists ? { name, file: `${name}.4wp`,
        flow: { source: stage === 'original' ? 'cell-list-source-mixed.4wp' : 'cell-list-target-mixed.4wp', action: 'identity' },
        resources: 'cell-list-source-mixed.4wp', pagedTable: { rows: 26 } } : seams ? { name, file: `${name}.4wp`,
        flow: { source: stage === 'original' ? 'continuous-paged-source-overflow.4wp' : 'continuous-paged-target-overflow.4wp', action: 'identity' },
        resources: 'continuous-paged-source-overflow.4wp' } : columns ? { name, file: `${name}.4wp`,
        flow: { source: stage === 'original' ? 'paged-column-source-mixed.4wp' : 'paged-column-target-mixed.4wp', action: 'identity' },
        resources: 'paged-column-source-mixed.4wp' } : tables ? { name, file: `${name}.4wp`,
        flow: { source: stage === 'original' ? 'paged-table-source-mixed.4wp' : 'paged-table-target-mixed.4wp', action: 'identity' },
        resources: 'paged-table-source-mixed.4wp', pagedTable: { rows: 41 } } : expanded ? { name, file: `${name}.4wp`,
        flow: { source: stage === 'original' ? 'expanded-source-images.4wp' : 'expanded-target-images.4wp', action: 'identity' },
        resources: 'expanded-source-images.4wp' } :
        { name, file: `${name}.4wp`, header: { expected: `paged-right-${stage}.4wp` }, resources: 'paged-source-right.4wp' });
    }
    await writeFile(resolve(directory, 'Input/cases.json'), JSON.stringify(manifest, null, 2));
  }
  await writeFile(resolve(directory, `Output/${prefix}-report.json`), JSON.stringify({ browser: browser.version(), results }, null, 2));
  console.log('Actual headed Chromium print-preview cancellation preserved clean/redo and dirty/undo state, selection, zoom and IndexedDB snapshots.');
} finally {
  await browser.close();
  await server.close();
}
