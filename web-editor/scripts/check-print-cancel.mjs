import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, expect } from '@playwright/test';
import { preview } from 'vite';

const directory = resolve(process.argv[2] || '');
assert(process.argv[2], 'Usage: node scripts/check-print-cancel.mjs NATIVE_EVIDENCE_DIRECTORY');
const server = await preview({ preview: { host: '127.0.0.1', port: 4190, strictPort: true } });
const browser = await chromium.launch({ headless: false });
try {
  const page = await browser.newPage({ acceptDownloads: true, locale: 'en-US' });
  const cdp = await browser.newBrowserCDPSession();
  await page.goto(server.resolvedUrls.local[0]);
  await page.locator('#file').setInputFiles(resolve(directory, 'Output/print-rich.4wp'));
  await expect(page.locator('#paper')).toContainText('TAILEND');
  await page.locator('#paper [contenteditable]').first().evaluate(element => {
    element.focus();
    getSelection().collapse(element.firstChild, 0);
  });
  await page.keyboard.insertText('EDIT');
  await page.locator('#undo').click();
  await page.locator('#zoom').selectOption('1.5');
  await page.locator('#settings-toggle').click();
  await page.locator('#theme').selectOption('dark');
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
    return {
      paper: document.querySelector('#paper').outerHTML,
      selection: { text: selected.toString(), anchor: selected.anchorNode?.parentElement?.dataset.run, offset: selected.anchorOffset },
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
  for (const phase of ['clean-with-redo', 'dirty-with-undo']) {
    if (phase === 'dirty-with-undo') await page.locator('#redo').click();
    await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
    await page.locator('#paper [contenteditable]').first().evaluate(element => {
      element.focus();
      getSelection().setBaseAndExtent(element.firstChild, 1, element.firstChild, 3);
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
    assert.deepEqual(await snapshot(), before, 'Real browser cancellation changed editing/history/recovery state');
    await page.screenshot({ path: resolve(directory, `Output/print-cancel-${phase}.png`) });
    results.push({ phase, actualBrowserPrintPreview: true, cancelButtonClicked: true, unchangedEditorSelectionHistoryRecovery: true });
  }
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  await (await pending).saveAs(resolve(directory, 'Output/print-cancel-dirty.4wp'));
  assert((await readFile(resolve(directory, 'Output/print-cancel-dirty.4wp'))).length > 0);
  await writeFile(resolve(directory, 'Output/print-cancel-report.json'), JSON.stringify({ browser: browser.version(), results }, null, 2));
  console.log('Actual headed Chromium print-preview cancellation preserved clean/redo and dirty/undo state, selection, zoom and IndexedDB snapshots.');
} finally {
  await browser.close();
  await new Promise(resolve => server.httpServer.close(resolve));
}
