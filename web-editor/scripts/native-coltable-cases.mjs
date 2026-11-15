import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { unzipSync, zipSync, strFromU8 } from 'fflate';
import { expect } from '@playwright/test';
import { nativeTableGrid } from '../src/native-ranges.js';
import { messages } from '../src/i18n.js';
import { geometry, inspectPDF } from './native-print-cases.mjs';
import { nativeBands } from './native-rowspan-cases.mjs';

// Expected browser outcome per native shape (wp_coltable_probe). Excluded shapes keep the localized atomic fallback.
export const coltableShapes = {
  two: null, three: null, header: null, 'two-headers': null, gap0: null, midcolumn: null, short: null, pages: null,
  rowspan: null, colspan: null, nowitness: null, lists: null, unicode: null,
  // Native 4D draws a table wider than its column across the gap into the next column (overlapping it).
  wide: 'pagedColumns',
  four: null,
  // Native 4D splits a vertically merged band taller than a column across columns; the browser never splits bands.
  tallband: 'pagedBand',
  mixed: null, center: null, right: null, colbreak: null,
};
const tokenPattern = /R\d+[ABC]/g;
const tokens = text => text.match(tokenPattern) || [];
const rowOf = token => Number(token.match(/^R(\d+)/)[1]);

// Column slots of a page from the native column getters and paper getters only (equal columns, wp_paged_column_probe).
export function nativeSlots(paper, columns) {
  const gap = parseFloat(columns.gap);
  const width = (paper.width - paper.left - paper.right - (columns.count - 1) * gap) / columns.count;
  return Array.from({ length: columns.count }, (_, index) => ({ left: paper.left + index * (width + gap), right: paper.left + index * (width + gap) + width }));
}

// Native PDF words of one slot. Rows are ordered by their anchor tokens (a row's own token in a cell that starts in
// that row): merged cells also print the tokens of the rows they cover, which must not reorder rows.
function slotRows(words, slot, paper, anchors) {
  const inside = words.filter(word => {
    const x = (word.x + word.right) / 2;
    const y = (word.y + word.bottom) / 2;
    return x >= slot.left - .25 && x <= slot.right + .25 && y >= paper.top && y <= paper.height - paper.bottom && tokens(word.text).length;
  });
  const rows = [];
  for (const word of [...inside].sort((a, b) => a.y - b.y || a.x - b.x)) {
    for (const token of tokens(word.text)) if (anchors.has(token) && !rows.includes(rowOf(token))) rows.push(rowOf(token));
  }
  return { rows, words: inside };
}

export async function prepareColtableCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/coltable-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.deepEqual(report.cases.map(item => item.name), Object.keys(coltableShapes));
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/coltable-errors.json'), 'utf8')), []);
  const results = [];
  // The left offset of a left-aligned table's first cell token inside its column, from the native 'header' shape.
  let leftOffset = null;
  for (const item of report.cases) {
    const fallback = coltableShapes[item.name];
    const files = unzipSync(await readFile(resolve(directory, `Output/coltable-${item.name}-original.4wp`)));
    const html = strFromU8(files[Object.keys(files).find(name => name.endsWith('.html'))]);
    const dom = new JSDOM(html, { contentType: 'application/xhtml+xml' });
    const tables = [...dom.window.document.querySelectorAll('table')].map((element, index) => {
      const grid = nativeTableGrid(element);
      const native = item.tables[index];
      assert.equal(grid.rows.length, native.rows, `${item.name}: native row getters match the stored grid`);
      return { grid, first: native.first, headers: native.headers, rows: native.rows, bands: nativeBands(grid.rows),
        tokens: grid.rows.map(row => tokens(row.textContent).map(rowOf)), cells: native.cells,
        sourceRows: grid.rows.map(row => [...row.children].map(cell => tokens(cell.textContent))) };
    });
    // Token owner rows come from the native-exported XML: the grid row where the token's cell starts.
    const owners = new Map();
    for (const table of tables) table.sourceRows.forEach((row, index) => row.flat().forEach(token => owners.set(token, table.first + index)));
    const anchors = new Set([...owners].filter(([token, row]) => rowOf(token) === row).map(([token]) => token));
    assert.equal(tables.length, item.requested.second ? 2 : 1);
    // Native layout getters, and the same values after re-import of the stored file.
    assert.deepEqual(item.reopened.sections, item.layout.sections, `${item.name}: stored columns survive re-import`);
    const columns = item.layout.sections;
    const papers = item.sections.sections.map(section => geometry(section.geometry));
    assert.equal(columns[0].count, item.requested.count);
    if (item.requested.second) assert.equal(columns[1].count, item.requested.second.count);

    // ---- Independent native oracle: which rows appear in which column slot of which page (no coordinates). ----
    const native = inspectPDF(resolve(directory, `Output/coltable-${item.name}.pdf`));
    const reopenedPDF = inspectPDF(resolve(directory, `Output/coltable-${item.name}-reopened.pdf`));
    assert.equal(reopenedPDF.text, native.text, `${item.name}: the stored file alone reproduces the native layout`);
    let section = 0;
    const nativeSlotsList = [];
    native.pages.forEach((sheet, page) => {
      // A page belongs to section 2 from the page where its first paragraph is printed (section breaks start pages).
      if (item.requested.second && sheet.words.some(word => word.text === 'CTSECOND')) section = 1;
      const slots = nativeSlots(papers[section], columns[section]);
      slots.forEach((slot, column) => {
        const { rows, words } = slotRows(sheet.words, slot, papers[section], anchors);
        nativeSlotsList.push({ page: page + 1, column: column + 1, section: section + 1, count: columns[section].count, rows, words, slot });
      });
    });
    const nativeTables = tables.map(table => {
      const own = row => row >= table.first && row < table.first + table.rows;
      const slots = nativeSlotsList.map(slot => ({ ...slot, rows: slot.rows.filter(own) })).filter(slot => slot.rows.some(row => row >= table.first + table.headers));
      return { slots, own };
    });
    const nativeFacts = nativeTables.map((entry, index) => {
      const table = tables[index];
      const headers = Array.from({ length: table.headers }, (_, i) => table.first + i);
      const facts = { slots: entry.slots.map(slot => ({ page: slot.page, column: slot.column, rows: slot.rows })) };
      // Consecutive slots: the next column of the same page, else the first column of the next page.
      for (let i = 1; i < entry.slots.length; i++) {
        const [a, b] = [entry.slots[i - 1], entry.slots[i]];
        assert(b.page === a.page && b.column === a.column + 1 || b.page === a.page + 1 && b.column === 1 && a.column === a.count,
          `${item.name}: native table continues in the next column, then on the next page`);
      }
      // Every native fragment starts with the complete leading header rows, in order.
      for (const slot of entry.slots) assert.deepEqual(slot.rows.slice(0, headers.length), headers, `${item.name}: native headers repeat at every column and page`);
      // Data rows in order exactly once; 4D may continue one row across a slot boundary (split row).
      const data = entry.slots.flatMap(slot => slot.rows.slice(headers.length));
      facts.splitRows = [];
      const sequence = data.filter((row, i) => {
        if (i && data[i - 1] === row) { facts.splitRows.push(row); return false; }
        return true;
      });
      assert.deepEqual(sequence, Array.from({ length: table.rows - table.headers }, (_, i) => table.first + table.headers + i),
        `${item.name}: native data rows appear once, in order`);
      for (const row of facts.splitRows) {
        assert(entry.slots.some((slot, i) => slot.rows.at(-1) === row && entry.slots[i + 1]?.rows[headers.length] === row),
          `${item.name}: a native split row continues at the top of the next slot`);
      }
      // Rows whose own cells continue past a slot boundary in native 4D (split rows and split vertical bands).
      facts.splitOwners = [...new Set(entry.slots.flatMap(slot => slot.words.flatMap(word => tokens(word.text)).map(token => owners.get(token))))]
        .filter(row => entry.own(row) && !headers.includes(row) &&
          entry.slots.filter(slot => slot.words.some(word => tokens(word.text).some(token => owners.get(token) === row))).length > 1);
      // Every serialized token is printed exactly once per slot it belongs to (headers once per fragment).
      const printed = entry.slots.flatMap(slot => slot.words.flatMap(word => tokens(word.text))).filter(token => entry.own(rowOf(token)));
      for (const token of table.sourceRows.flat(2)) {
        assert.equal(printed.filter(value => value === token).length, headers.includes(rowOf(token)) ? entry.slots.length : 1,
          `${item.name}: complete native token ${token}`);
      }
      // Confinement: a fitting table never crosses its column; a too-wide table spills past its slot (counterexample).
      const outside = entry.slots.flatMap(slot => slot.words.filter(word => entry.own(rowOf(tokens(word.text)[0])) &&
        (word.x < slot.slot.left - .5 || word.right > slot.slot.right + .5)));
      if (item.name === 'wide') assert(outside.length > 0, 'Native 4D draws the wide table past its column');
      else assert.deepEqual(outside.map(word => word.text), [], `${item.name}: native table stays inside one column`);
      // Alignment is relative to the column: the first-column token offset is the same in every slot.
      const offsets = entry.slots.map(slot => Math.min(...slot.words.filter(word => /A/.test(tokens(word.text)[0] || '')).map(word => word.x)) - slot.slot.left);
      assert(offsets.every(offset => Math.abs(offset - offsets[0]) < .5), `${item.name}: native table offset is the same in every column`);
      facts.offset = offsets[0];
      return facts;
    });
    if (item.name === 'tallband') assert(nativeFacts[0].splitOwners.includes(3), 'Native 4D splits the tall band across columns');
    if (item.name === 'header') leftOffset = nativeFacts[0].offset;
    if (item.requested.align) {
      // Native outer table width from the stored cell getters: width + 2 x padding + 1pt border per column (the M2
      // rule), plus the table's closing 1pt border.
      const widths = tables[0].cells.filter(cell => cell.row === tables[0].headers + 1).map(cell => parseFloat(cell.width) + 2 * parseFloat(cell.padding) + 1);
      const free = nativeSlots(papers[0], columns[0])[0].right - nativeSlots(papers[0], columns[0])[0].left - widths.reduce((a, b) => a + b, 1);
      assert(leftOffset !== null);
      assert(Math.abs(nativeFacts[0].offset - leftOffset - (item.requested.align === 'center' ? free / 2 : free)) < .5,
        `${item.name}: native table is aligned within its column, not the page`);
    }
    if (item.name === 'colbreak') assert.deepEqual([nativeFacts[0].slots[0].page, nativeFacts[0].slots[0].column], [1, 2]);

    const source = `coltable-source-${item.name}.4wp`;
    files['Resources/coltable-sentinel.bin'] = Uint8Array.of(0, 255, 41, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `coltable-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/coltable-${item.name}-edited.4wp`)));
    const expected = { flow: { source, action: 'identity' }, resources: source };
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    const external = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith(url) && !request.url().startsWith('data:')) external.push(request.url()); });
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('CTSTART');
      await download(`coltable-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      let browserFacts = null;
      let printedSlots = null;
      let notices = [];
      if (fallback) {
        await expect(page.locator('#paged-status')).toHaveText(messages.en[fallback]);
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
        await expect(page.locator('#paper')).toContainText('CTEND');
      } else {
        const sheets = page.locator('#paged-view .browser-page');
        await expect(sheets.first()).toBeVisible();
        const count = await sheets.count();
        await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
        const measured = await sheets.evaluateAll(sheets => sheets.map(sheet => {
          const frame = sheet.getBoundingClientRect();
          const slots = sheet.querySelector('.page-columns') ? [...sheet.querySelectorAll('.page-column')] : [sheet.querySelector('.page-body')];
          return { section: Number(sheet.dataset.section), width: parseFloat(sheet.style.width), height: parseFloat(sheet.style.height),
            slots: slots.map(slot => {
              const box = slot.getBoundingClientRect();
              return { left: (box.left - frame.left) * .75, right: (box.right - frame.left) * .75,
                tables: [...slot.querySelectorAll(':scope > table')].map(table => {
                  const rect = table.getBoundingClientRect();
                  return { left: (rect.left - frame.left) * .75, right: (rect.right - frame.left) * .75, top: rect.top, bottom: rect.bottom,
                    rows: [...table.rows].map(row => [...row.cells].map(cell => cell.textContent)),
                    columns: [...table.querySelectorAll(':scope > colgroup > col')].map(col => col.style.width),
                    cells: [...table.querySelectorAll('td,th')].map(cell => {
                      const r = cell.getBoundingClientRect();
                      return { text: cell.textContent, x: (r.left - frame.left) * .75, y: (r.top - frame.top) * .75,
                        right: (r.right - frame.left) * .75, bottom: (r.bottom - frame.top) * .75 };
                    }),
                    inside: rect.left >= box.left - .25 && rect.right <= box.right + .25 && rect.top >= box.top - .25 && rect.bottom <= box.bottom + .25,
                    contained: [...table.querySelectorAll('td,th')].every(cell => {
                      const bounds = cell.getBoundingClientRect();
                      return [...cell.querySelectorAll('.text-run,.preserved-object,.paged-list-marker,img')].every(run =>
                        [...run.getClientRects()].every(r => r.left >= bounds.left - .25 && r.right <= bounds.right + .25 &&
                          r.top >= bounds.top - .25 && r.bottom <= bounds.bottom + .25));
                    }) };
                }),
                text: slot.textContent };
            }) };
        }));
        // Browser fragments, by table, in slot order.
        const browserSlots = measured.flatMap((sheet, index) => sheet.slots.map((slot, column) => ({ page: index + 1, column: column + 1,
          count: sheet.slots.length, ...slot })));
        browserFacts = tables.map((table, index) => {
          const headers = Array.from({ length: table.headers }, (_, i) => table.first + i);
          const own = nativeTables[index].own;
          const fragments = browserSlots.flatMap(slot => slot.tables.filter(fragment => fragment.rows.some(row => own(rowOf(tokens(row.join(''))[0] || 'R0A'))))
            .map(fragment => ({ page: slot.page, column: slot.column, count: slot.count, slotLeft: slot.left, slotRight: slot.right, ...fragment })));
          assert(fragments.length > 0, `${item.name}: table ${index + 1} is paged`);
          for (let i = 1; i < fragments.length; i++) {
            const [a, b] = [fragments[i - 1], fragments[i]];
            assert(b.page === a.page && b.column === a.column + 1 || b.page === a.page + 1 && b.column === 1 && a.column === a.count,
              `${item.name}: browser table continues in the next column, then on the next page (native rule)`);
          }
          for (const fragment of fragments) {
            assert(fragment.inside, `${item.name}: browser fragment stays inside its column`);
            assert(fragment.contained, `${item.name}: every run stays inside its cell`);
            assert.deepEqual(fragment.columns, fragments[0].columns, `${item.name}: frozen column widths in every fragment`);
            assert(Math.abs((fragment.right - fragment.left) - (fragments[0].right - fragments[0].left)) < .05, `${item.name}: same table width in every fragment`);
            const rows = fragment.rows.map(row => row.flatMap(text => tokens(text)));
            assert.deepEqual(rows.slice(0, headers.length), table.sourceRows.slice(0, headers.length).map(row => row.flat()),
              `${item.name}: browser repeats the complete leading header rows at every column and page (native rule)`);
          }
          const dataRows = fragments.flatMap(fragment => fragment.rows.slice(headers.length).map(row => row.flatMap(text => tokens(text))));
          assert.deepEqual(dataRows, table.sourceRows.slice(headers.length).map(row => row.flat()), `${item.name}: every data row once, in order`);
          const starts = [];
          let at = headers.length;
          for (const fragment of fragments) { starts.push(at); at += fragment.rows.length - headers.length; }
          const bandStarts = new Set(table.bands.map(([start]) => start));
          assert(starts.every(start => bandStarts.has(start)), `${item.name}: fragments start only at native band boundaries`);
          // Alignment within the column, as natively observed (offsets relative to the column, equal in every slot).
          const gaps = fragments.map(fragment => [fragment.left - fragment.slotLeft, fragment.slotRight - fragment.right]);
          for (const [left, right] of gaps) {
            if (item.requested.align === 'center') assert(Math.abs(left - right) < .5, `${item.name}: browser table centred in its column`);
            else if (item.requested.align === 'right') assert(right < .25 && left > 1, `${item.name}: browser table right-aligned in its column`);
            else assert(left < .25, `${item.name}: browser table left-aligned in its column`);
          }
          return { fragments: fragments.map(fragment => ({ page: fragment.page, column: fragment.column,
            rows: fragment.rows.map(row => rowOf(tokens(row.join(''))[0])) })) };
        });
        // Cross-check with the native PDF: the same first slot, header repetition and the multi-column flow.
        browserFacts.forEach((facts, index) => {
          const first = nativeFacts[index].slots[0];
          const browserFirst = facts.fragments[0];
          assert.deepEqual([browserFirst.page, browserFirst.column], [first.page, first.column], `${item.name}: table starts in the same page/column slot as 4D`);
          assert.equal(facts.fragments.length > 1, nativeFacts[index].slots.length > 1, `${item.name}: table continues past its first column in both renderings`);
        });
        notices = await page.locator('#paged-objects > p').evaluateAll(entries => entries.map(entry => entry.dataset.notice));
        assert.deepEqual(notices, columns.some(entry => entry.count > 1) ? ['pagedColumnTables'] : []);
        await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
        await page.locator('#settings-toggle').click();
        await page.locator('#theme').selectOption('dark');
        await page.locator('#zoom').selectOption('2');
        await page.evaluate(() => {
          window.coltableResize = new Promise(resolve => window.addEventListener('resize', resolve, { once: true }));
        });
        await page.setViewportSize({ width: 390, height: 844 });
        await page.evaluate(() => window.coltableResize);
        await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
        const pdf = resolve(directory, `Output/coltable-browser-${item.name}.pdf`);
        await page.pdf({ path: pdf, preferCSSPageSize: true, printBackground: true });
        const printed = inspectPDF(pdf);
        assert.equal(printed.pages.length, count);
        // Printed page/column/cell membership equals the measured preview: every printed token lies in the cell
        // that previews it (cells in reading order), and no printed table token lies elsewhere.
        printedSlots = measured.map((sheet, index) => sheet.slots.map(slot => slot.tables.map(table => table.cells.map(cell =>
          printed.pages[index].words.filter(word => {
            const x = (word.x + word.right) / 2;
            const y = (word.y + word.bottom) / 2;
            return x >= cell.x - .25 && x <= cell.right + .25 && y >= cell.y - .25 && y <= cell.bottom + .25;
          }).sort((a, b) => a.y - b.y || a.x - b.x).map(word => word.text).join('')).map(text => tokens(text)))));
        assert.deepEqual(printedSlots, measured.map(sheet => sheet.slots.map(slot => slot.tables.map(table => table.cells.map(cell => tokens(cell.text))))),
          `${item.name}: printed page/column/cell token membership equals the preview`);
        printed.pages.forEach((sheet, index) => {
          const cells = measured[index].slots.flatMap(slot => slot.tables.flatMap(table => table.cells));
          const stray = sheet.words.filter(word => /R\d/.test(word.text) && !cells.some(cell => {
            const x = (word.x + word.right) / 2;
            const y = (word.y + word.bottom) / 2;
            return x >= cell.x - .25 && x <= cell.right + .25 && y >= cell.y - .25 && y <= cell.bottom + .25;
          }));
          assert.deepEqual(stray.map(word => word.text), [], `${item.name}: no printed table token outside its previewed cell`);
        });
        for (const [index, sheet] of measured.entries()) {
          assert(Math.abs(printed.pages[index].width - sheet.width) < 1 && Math.abs(printed.pages[index].height - sheet.height) < 1, 'Unscaled paper');
        }
        await page.screenshot({ path: resolve(directory, `Output/coltable-${item.name}-mobile.png`) });
        assert(await page.locator('#paged-panel').evaluate(element => element.scrollWidth <= element.clientWidth), 'No mobile panel overflow');
      }
      await download(`coltable-after-${item.name}`, expected, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/coltable-after-${item.name}.4wp`)), Buffer.from(original));
      await page.locator('#paper [contenteditable]').first().fill('WEBCT');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`coltable-edited-${item.name}`, edited, page);
      if (!fallback) await expect(page.locator('#paged-view .browser-page').first()).toContainText('WEBCT');
      else await expect(page.locator('#paged-status')).toHaveText(messages.en[fallback]);
      await page.locator('#undo').click();
      await download(`coltable-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`coltable-recovered-redo-${item.name}`, edited, page);
      assert.deepEqual(errors, []);
      assert.deepEqual(external, []);
      results.push({ name: item.name, outcome: fallback || 'paged', requested: item.requested, nativeColumns: columns,
        nativeTables: nativeFacts, browserTables: browserFacts, printedSlots, notices, untouchedOriginalBytes: true,
        limits: 'Native page/column slot membership, header repetition, column confinement and in-column alignment only; ' +
          'rows per column, row splitting and page counts are browser-measured, not native parity.' });
    } finally {
      await page.close();
      dom.window.close();
    }
  }
  await writeFile(resolve(directory, 'Output/coltable-browser-report.json'), JSON.stringify(results, null, 2));
}
