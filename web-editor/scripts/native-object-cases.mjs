import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import * as css from 'css-tree';
import { unzipSync, zipSync } from 'fflate';
import { expect } from '@playwright/test';
import { WriteProDocument } from '../src/document.js';
import { messages } from '../src/i18n.js';

const text = 'NEW BOX 😀 日é';
const ids = ['img2', 'textBox2'];
const targets = stage => stage === 'picture' || stage === 'removePicture' ? [ids[0]] :
  stage === 'box' || stage === 'removeBox' ? [ids[1]] : ids;
const placement = (stage, kind, id) => ({
  target: { section: kind === 'section' ? '2' : 'all', page: kind === 'section' ? 'all' : '2' },
  align: { hAlign: id === 'img2' ? 'right' : 'center', vAlign: id === 'img2' ? 'bottom' : 'center' },
  alignStart: { hAlign: 'offset', vAlign: 'offset' },
  layout: { layout: id === 'img2' ? 'behind' : 'wrap-square' },
  layoutSwap: { layout: id === 'img2' ? 'wrap-square' : 'behind' },
  front: { layout: 'front' },
  repeat: { section: 'all', page: 'all' },
})[stage];

export async function prepareObjectCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/object-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 3);
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  try {
    for (const item of report.cases) {
      assert.equal(item.stages.length, 14);
      assert.equal(item.stages[0].stats.objects.length, 2);
      assert.equal(item.stages.at(-2).stats.objects.length, 2);
      assert.equal(item.stages.at(-1).stats.objects.length, 4);
      let nativeOriginal;
      for (const stage of item.stages) {
        assert.deepEqual(stage.stats.body, item.stages[0].stats.body);
        for (const id of ['img1', 'textBox1']) assert.deepEqual(stage.stats.objects.find(object => object.id === id),
          item.stages[0].stats.objects.find(object => object.id === id));
        const native = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, `Output/object-${item.name}-${stage.name}.4wp`))));
        const retained = {
          bookmarks: native.bookmarks(),
          body: [...native.document.querySelectorAll('body > p')].map(node => node.outerHTML),
          header: native.document.querySelector('body > div.section1Header').outerHTML,
          formulas: native.formulaElements().map(node => node.outerHTML),
        };
        nativeOriginal ??= retained;
        assert.deepEqual(retained, nativeOriginal, `${item.name}/${stage.name}: independent native mutation changed retained content`);
      }
      for (let index = 1; index < item.stages.length - 1; index++) {
        const stage = item.stages[index].name, previous = item.stages[index - 1].name;
        const source = `source-object-${item.name}-${stage}.4wp`;
        const files = unzipSync(await readFile(resolve(directory, `Output/object-${item.name}-${previous}.4wp`)));
        files['Resources/object-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
        const bytes = zipSync(files);
        await writeFile(resolve(directory, 'Input', source), bytes);
        const metadata = { objects: { kind: item.name, stage, source }, resources: source };
        const model = WriteProDocument.open(bytes);
        for (const id of targets(stage)) {
          if (stage === 'picture') model.createObject('anchoredPicture', model.document.querySelector('img').getAttribute('src'));
          else if (stage === 'box') model.createObject('textBox', text);
          else {
            model.setScope(`object:${id}`);
            if (stage.startsWith('remove')) model.deleteObject();
            else if (stage === 'offset') model.setObjectGeometry(id === 'img2' ? { x: '12pt', y: '24pt' } : { x: '30pt', y: '40pt' });
            else model.setObjectPlacement(placement(stage, item.name, id));
          }
        }
        const name = `object-model-${item.name}-${stage}`;
        await writeFile(resolve(directory, 'Input', `${name}.4wp`), model.export());
        cases.push({ name, file: `${name}.4wp`, ...metadata });
        const page = await browser.newPage({ acceptDownloads: true });
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        page.on('dialog', dialog => dialog.accept());
        try {
          await page.goto(url);
          await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
          for (const id of targets(stage)) {
            if (stage === 'picture') {
              const src = model.document.querySelector('img').getAttribute('src');
              const mimeType = /^data:(image\/(?:png|jpeg));base64,/.exec(src)?.[1];
              assert(mimeType, 'Independent native picture must have an inert PNG/JPEG source');
              await page.locator('#object-picture-file').setInputFiles({
                name: `native-object.${mimeType === 'image/png' ? 'png' : 'jpg'}`,
                mimeType, buffer: Buffer.from(src.split(',')[1], 'base64'),
              });
              await expect(page.locator('#editing-scope')).toHaveValue('object:img2');
            } else if (stage === 'box') {
              await page.locator('#object-text').fill(text);
              await page.locator('#object-create-box').click();
              await expect(page.locator('#editing-scope')).toHaveValue('object:textBox2');
            } else {
              await page.locator('#editing-scope').selectOption(`object:${id}`);
              if (stage.startsWith('remove')) await page.locator('#object-delete').click();
              else if (stage === 'offset') {
                await page.locator('#object-units').selectOption('pt');
                await page.locator('#object-x').fill(id === 'img2' ? '12' : '30');
                await page.locator('#object-y').fill(id === 'img2' ? '24' : '40');
                await page.locator('#object-form button').click();
              } else {
                for (const [field, value] of Object.entries(placement(stage, item.name, id))) {
                  if (field === 'page') await page.locator('#object-page').fill(value);
                  else await page.locator(`#object-${field}`).selectOption(value);
                }
                await page.locator('#object-placement-form button').click();
              }
            }
          }
          await expect(page.getByRole('alert')).toBeHidden();
          await download(`object-browser-${item.name}-${stage}`, metadata, page);
          await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
          await page.reload();
          await expect(page.locator('#recovery-notice')).toBeVisible();
          await download(`object-recovered-${item.name}-${stage}`, metadata, page);
          for (let count = 0; count < targets(stage).length; count++) await page.locator('#undo').click();
          await download(`object-undo-${item.name}-${stage}`, {
            ...metadata, objects: { ...metadata.objects, stage: previous },
          }, page);
          await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
          await page.reload();
          await expect(page.locator('#recovery-notice')).toBeVisible();
          for (let count = 0; count < targets(stage).length; count++) await page.locator('#redo').click();
          await download(`object-recovered-redo-${item.name}-${stage}`, metadata, page);
          assert.deepEqual(errors, []);
        } finally { await page.close(); }
      }
    }
  } finally { dom.window.close(); }
}

export async function verifyObjectCase(directory, entry, actual) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/object-report.json'), 'utf8'));
  const expected = report.cases.find(item => item.name === entry.objects.kind).stages.find(stage => stage.name === entry.objects.stage).stats;
  // Native enumeration can change after layer transitions; IDs, not list indices, identify objects.
  const byIdentity = stats => ({ ...stats, objects: [...stats.objects].sort((a, b) => a.id.localeCompare(b.id)) });
  assert.deepEqual(byIdentity(actual.objectImported), byIdentity(expected), `${entry.name}: differs from independent full-4D operation`);
  assert.deepEqual(byIdentity(actual.objectReopened), byIdentity(expected), `${entry.name}: reopen changed object state`);
  const open = async path => WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, path))));
  const source = await open(`Input/${entry.objects.source}`), edited = await open(`Input/${entry.file}`);
  const action = /source-object-(?:paper|section|jpeg)-(.+)\.4wp$/.exec(entry.objects.source)[1];
  const active = targets(action);
  const retained = model => {
    const copy = model.document.cloneNode(true);
    const selectors = active.map(id => copy.getElementById(id)).filter(Boolean)
      .map(element => `${element.localName}.${element.getAttribute('class')}`);
    // Include a newly created object's owned rule when comparing its Undo export.
    for (const id of active) {
      const element = edited.document.getElementById(id) || source.document.getElementById(id);
      if (element) selectors.push(`${element.localName}.${element.getAttribute('class')}`);
    }
    for (const id of active) copy.getElementById(id)?.remove();
    for (const style of copy.querySelectorAll('head style')) {
      const ast = css.parse(style.textContent);
      ast.children.forEach((node, item) => {
        if (node.type === 'Rule' && selectors.includes(css.generate(node.prelude))) ast.children.remove(item);
      });
      style.textContent = css.generate(ast);
      if (!style.textContent) style.remove();
    }
    copy.querySelector('meta[name="datetimeModified"]')?.remove();
    return new XMLSerializer().serializeToString(copy);
  };
  assert.equal(retained(edited), retained(source), `${entry.name}: nonactive XML, formulas or associations changed`);
  assert.deepEqual(edited.formulaElements().map(node => node.outerHTML), source.formulaElements().map(node => node.outerHTML));
  assert.deepEqual(edited.bookmarks(), source.bookmarks());
  for (const image of source.document.querySelectorAll('img')) {
    const retainedImage = edited.document.getElementById(image.id);
    if (retainedImage) assert.equal(retainedImage.getAttribute('src'), image.getAttribute('src'), `${entry.name}: original media bytes changed`);
  }
}
