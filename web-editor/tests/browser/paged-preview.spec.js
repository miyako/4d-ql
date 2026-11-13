import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { zipSync, unzipSync, strToU8, strFromU8 } from 'fflate';
import { messages } from '../../src/i18n.js';

const geometry = 'div.section0{-d4-page-width:300pt;-d4-page-height:360pt;-d4-page-margin:60pt 30pt}';
const localPNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADAAAAAgCAIAAADbtmxLAAAASklEQVR4nO3OMQ0AIBBD0VPCjCtM4gBhYOA6kg79Scef9NU9s91Yu93vvgABAhQHch2rHhAgQHkg17HqAQEClAdyHaseECBAcaAH191RiEIeQFYAAAAASUVORK5CYII=';
const xml = (style, body) => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Paged evidence</title><style>p{font:12pt Arial;line-height:18pt;margin:0;white-space:pre-wrap}${geometry}${style}</style></head><body>${body}</body></html>`;
async function open(page, style = '', body = '<p>BODY</p>') {
  await page.goto('/');
  await page.locator('#file').setInputFiles({ name: 'paged.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Document.html': strToU8(xml(style, body)), 'sentinel.bin': Uint8Array.of(0, 255, 17) })) });
  await expect(page.locator('#document-title')).toHaveText('Paged evidence');
}
async function preview(page) {
  await page.locator('#paged-panel > summary').click();
  await expect(page.locator('#paged-status')).not.toBeEmpty();
  await expect(page.locator('#paged-status')).not.toHaveText(messages.en.pagedLoading);
}
function contents(bytes) {
  const archive = unzipSync(bytes);
  return { xml: strFromU8(archive['Document.html']).replace(/<meta name="datetimeModified"[^>]*\/>/g, ''), sentinel: archive['sentinel.bin'] };
}
async function bytes(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  return readFileSync(await (await pending).path());
}
async function pdf(page, testInfo, name) {
  const path = testInfo.outputPath(`${name}.pdf`);
  await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
  const bbox = execFileSync('pdftotext', ['-bbox', path, '-'], { encoding: 'utf8' });
  return [...bbox.matchAll(/<page width="([\d.]+)" height="([\d.]+)">([\s\S]*?)<\/page>/g)].map(match => ({
    width: Math.round(Number(match[1])), height: Math.round(Number(match[2])),
    words: [...match[3].matchAll(/<word[^>]*>([^<]*)<\/word>/g)].map(word => word[1]),
  }));
}
function variants(section = 1) {
  return ['First', 'Left', 'Right'].map(variant => `div.section${section}${variant}{white-space:normal}`).join('') +
    ['', 'First', 'Left', 'Right'].flatMap(variant => ['Header', 'Footer'].map(kind =>
      `div.section${section}${variant}${kind}{margin:10pt 30pt}`)).join('');
}
function areas(section = 1) {
  return ['', 'First', 'Left', 'Right'].flatMap(variant => ['Header', 'Footer'].map(kind =>
    `<div class="section${section}${variant}${kind}" style="visibility:hidden;height:0"><p>S${section}${variant || 'Default'}${kind}</p></div>`)).join('');
}

for (const headers of [0, 1, 2]) test(`flat cell lists preserve complete rows, counters and ${headers} repeated header rows`, async ({ page }, testInfo) => {
  const row = index => `<tr${index < headers ? ' class="header"' : ''}><td class="narrow">${index < headers ? '' : `<p>INTRO${index}</p>`}<ol start="7"><li>TOK${index}A</li><li>TOK${index}B</li></ol></td><td class="wide"><ul><li>VALUE${index}A${index < headers ? '' : ' wrapped across lines'}</li><li>VALUE${index}B</li></ul></td></tr>`;
  const body = `<p style="-d4-section-break-after:continuous">SEAMSTART</p><p>BEFORE</p><table>${Array.from({ length: 16 }, (_, index) => row(index)).join('')}</table><p>AFTER</p>`;
  await open(page, 'ul,ol{margin:0;padding:0}li{font:12pt Arial;margin:0 0 0 24pt;line-height:18pt;white-space:pre-wrap}table{border-collapse:collapse}td{padding:3pt;border:1pt solid #234567}td.narrow{width:80pt}td.wide{width:90pt}tr.header{-d4-header:true;background-color:#ddeeff}',
    body);
  const before = await bytes(page);
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  await expect(sheets.nth(1)).toBeVisible();
  await expect(sheets.first()).toHaveAttribute('data-sections', '1 2');
  const fragments = await sheets.evaluateAll(sheets => sheets.map(sheet => {
    const origin = sheet.getBoundingClientRect();
    return [...sheet.querySelectorAll('.page-body table tr')].map(row => [...row.cells].map(cell => {
      const bounds = cell.getBoundingClientRect();
      return {
        text: cell.textContent, intro: cell.querySelector('p')?.textContent, width: bounds.width,
        x: (bounds.left - origin.left) * .75, y: (bounds.top - origin.top) * .75,
        right: (bounds.right - origin.left) * .75, bottom: (bounds.bottom - origin.top) * .75,
        markers: [...cell.querySelectorAll('.paged-list-marker')].map(marker => marker.textContent),
      };
    }));
  }));
  const data = fragments.flat().filter(row => row[0].intro);
  expect(data.map(row => row[0].intro)).toEqual(Array.from({ length: 16 - headers }, (_, index) => `INTRO${index + headers}`));
  for (const fragment of fragments.filter(rows => rows.length)) {
    for (let header = 0; header < headers; header++) expect(fragment[header][0].text).toContain(`TOK${header}A`);
    for (const row of fragment) {
      expect(row[0].markers).toEqual(['7.', '8.']);
      expect(row[1].markers).toEqual(['\u25cf', '\u25cf']);
      expect(row.map(cell => cell.width)).toEqual(fragments.flat()[0].map(cell => cell.width));
    }
  }
  const path = testInfo.outputPath(`cell-lists-${headers}.pdf`);
  await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
  const bbox = execFileSync('pdftotext', ['-bbox', path, '-'], { encoding: 'utf8' });
  const printed = [...bbox.matchAll(/<page[^>]*>([\s\S]*?)<\/page>/g)].map(sheet =>
    [...sheet[1].matchAll(/<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)<\/word>/g)]
      .map(word => ({ x: Number(word[1]), y: Number(word[2]), right: Number(word[3]), bottom: Number(word[4]), text: word[5] })));
  expect(printed.length).toBe(await sheets.count());
  const printCells = fragments.map((rows, index) => rows.map(row => row.map(cell =>
    printed[index].filter(word => {
      const x = (word.x + word.right) / 2;
      const y = (word.y + word.bottom) / 2;
      return x >= cell.x - .25 && x <= cell.right + .25 && y >= cell.y - .25 && y <= cell.bottom + .25;
    }).sort((a, b) => Math.abs(a.y - b.y) > 1 ? a.y - b.y : a.x - b.x).map(word => word.text).join('').replace(/\s/gu, ''))));
  expect(printCells).toEqual(fragments.map(rows => rows.map(row => row.map(cell => cell.text.replace(/\s/gu, '')))));
  await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
  expect(await bytes(page)).toEqual(before);
});

test('cell-list unsupported counters and marker/cell overflow keep explicit atomic fallback', async ({ page }) => {
  for (const list of [
    '<ol reversed=""><li>A</li></ol>', '<ol><li value="7">A</li></ol>', '<ul><li>A<ul><li>NESTED</li></ul></li></ul>',
    '<ol start="3999"><li>A</li><li>B</li></ol>', '<ul><li style="-d4-list-level:2">A</li></ul>',
    '<ul><li style="list-style-type:unknown">A</li></ul>',
    '<ol start="3998"><li style="margin-left:0">A</li></ol>',
    '<ol><li style="font-size:300pt;margin-left:300pt">OVERSIZE</li></ol>',
  ]) {
    await open(page, 'ul,ol{margin:0;padding:0}li{font:12pt Arial;margin-left:24pt}td{width:90pt}',
      `<p>BEFORE</p><table><tr><td>${list}</td></tr></table><p>AFTER</p>`);
    const before = await bytes(page);
    await preview(page);
    await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedTables);
    await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
    expect(await bytes(page)).toEqual(before);
  }
});

test('compatible continuous seams share measured physical pages and retain source identities and print membership', async ({ page }, testInfo) => {
  const first = Array.from({ length: 10 }, (_, i) => `<p${i === 9 ? ' style="-d4-section-break-after:continuous"' : ''}>SEAM1TOKEN${i}</p>`).join('');
  const second = Array.from({ length: 6 }, (_, i) => `<p${i === 5 ? ' style="-d4-section-break-after:continuous"' : ''}>SEAM2TOKEN${i}</p>`).join('');
  await open(page, "div.section1{-d4-section-name:'First'}div.section2{-d4-section-name:'Second';-d4-page-margin:60pt 30pt}div.section3{-d4-section-name:'Third'}",
    first + second + '<p>LAST</p>');
  const before = await bytes(page);
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  await expect(sheets).toHaveCount(2);
  const membership = await sheets.evaluateAll(sheets => sheets.map(sheet => ({
    owner: sheet.dataset.section, sections: sheet.dataset.sections,
    text: [...sheet.querySelectorAll('.page-body p')].map(paragraph => paragraph.textContent),
    identities: [...sheet.querySelectorAll('.page-body p')].map(paragraph => paragraph.dataset.section),
  })));
  expect(membership.map(sheet => [sheet.owner, sheet.sections])).toEqual([['1', '1 2'], ['2', '2 3']]);
  expect(membership[0].identities).toEqual([...Array(10).fill('1'), ...Array(3).fill('2')]);
  expect(membership[1].identities).toEqual(['2', '2', '2', '3']);
  expect(membership.flatMap(sheet => sheet.text)).toEqual([
    ...Array.from({ length: 10 }, (_, i) => `SEAM1TOKEN${i}`), ...Array.from({ length: 6 }, (_, i) => `SEAM2TOKEN${i}`), 'LAST',
  ]);
  expect((await pdf(page, testInfo, 'continuous-seams')).map(sheet => sheet.words)).toEqual(membership.map(sheet => sheet.text));
  await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
  await page.locator('#settings-toggle').click();
  await page.locator('#zoom').selectOption('2');
  await page.locator('#theme').selectOption('dark');
  await page.setViewportSize({ width: 390, height: 844 });
  expect((await pdf(page, testInfo, 'continuous-seams-mobile')).map(sheet => sheet.words)).toEqual(membership.map(sheet => sheet.text));
  expect(await bytes(page)).toEqual(before);
});

test('new-page sections after compatible seams keep section-first areas and physical parity', async ({ page }, testInfo) => {
  await open(page, variants(3),
    '<p style="-d4-section-break-after:continuous">FIRST</p><p style="page-break-after:always">SECOND</p><p style="page-break-after:always;-d4-section-break-after:always">NEXT</p><p style="page-break-after:always">THIRD</p><p>FOURTH</p>' + areas(3));
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  await expect(sheets).toHaveCount(4);
  expect(await sheets.evaluateAll(sheets => sheets.map(sheet => [sheet.dataset.page, sheet.dataset.section, sheet.dataset.sections,
    [...sheet.querySelectorAll('.page-area')].map(area => area.dataset.area)])))
    .toEqual([['1', '1', '1 2', []], ['2', '2', '2', []],
      ['3', '3', '3', ['section3FirstHeader', 'section3FirstFooter']],
      ['4', '3', '3', ['section3LeftHeader', 'section3LeftFooter']]]);
  const output = await pdf(page, testInfo, 'continuous-newpage');
  expect(output.slice(0, 4).map(sheet => sheet.words.filter(word => /^(FIRST|SECOND|NEXT|THIRD|FOURTH)$/.test(word))))
    .toEqual([['FIRST', 'SECOND'], ['NEXT'], ['THIRD'], ['FOURTH']]);
});

test('admitted lists, image, inert formula and rectangular table use residual capacity across a compatible seam', async ({ page }, testInfo) => {
  const rows = Array.from({ length: 20 }, (_, i) => `<tr><td class="narrow"><p>ROW${i}</p></td><td class="wide"><p>VALUE${i}</p></td></tr>`).join('');
  await open(page, 'table{border-collapse:collapse;width:180pt}td{padding:2pt;border:1pt solid #234567}td.narrow{width:60pt}td.wide{width:120pt}tr.header{-d4-header:true}',
    `<p>START</p><ol><li style="margin-left:18pt">LISTONE</li><li style="margin-left:18pt">LISTTWO</li></ol><p>LEFT<img src="${localPNG}" style="width:36pt;height:30pt"/>RIGHT</p><p style="-d4-section-break-after:continuous"><span style="-d4-ref:'1+1'">SAVED</span></p><p>BEFORE</p><table><tr class="header"><td class="narrow"><p>HEADA</p></td><td class="wide"><p>HEADB</p></td></tr>${rows}</table><p>AFTER</p>`);
  const before = await bytes(page);
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  const bodies = sheets.locator('.page-body');
  await expect(sheets.first()).toHaveAttribute('data-sections', '1 2');
  await expect(sheets.first().locator('table')).toHaveCount(1);
  expect(await sheets.count()).toBeGreaterThan(1);
  const texts = await bodies.allTextContents();
  const rowMembership = texts.map(text => text.match(/ROW\d+/g) || []);
  expect(rowMembership[0].length).toBeGreaterThan(0);
  expect(rowMembership[0].length).toBeLessThan(20);
  expect(rowMembership.flat()).toEqual(Array.from({ length: 20 }, (_, i) => `ROW${i}`));
  expect(texts.join('').match(/VALUE\d+/g)).toEqual(Array.from({ length: 20 }, (_, i) => `VALUE${i}`));
  expect(texts.join('').match(/START|LISTONE|LISTTWO|LEFT|RIGHT|SAVED|BEFORE|AFTER/g))
    .toEqual(['START', 'LISTONE', 'LISTTWO', 'LEFT', 'RIGHT', 'SAVED', 'BEFORE', 'AFTER']);
  await expect(bodies.locator('.paged-list-marker')).toHaveCount(2);
  await expect(bodies.locator('img')).toHaveCount(1);
  await expect(bodies.locator('.formula-source')).toContainText('1+1');
  await expect(bodies.locator('.formula-value')).toContainText('SAVED');
  const widths = await bodies.locator('table').evaluateAll(tables => tables.map(table => [...table.rows[0].cells].map(cell =>
    cell.getBoundingClientRect().width)));
  expect(widths.length).toBeGreaterThan(1);
  for (const width of widths) expect(width).toEqual(widths[0]);
  await expect(bodies.locator('tr').filter({ hasText: 'HEADA' })).toHaveCount(widths.length);
  expect(await bodies.evaluateAll(bodies => bodies.every(body => {
    const bounds = body.getBoundingClientRect();
    return [...body.querySelectorAll('p,li,.text-run,img,.preserved-object,td,th')].every(run =>
      [...run.getClientRects()].every(rect => rect.left >= bounds.left - .25 && rect.right <= bounds.right + .25 &&
        rect.top >= bounds.top - .25 && rect.bottom <= bounds.bottom + .25)) &&
      [...body.querySelectorAll('table')].every(table => table.rows.length > 1);
  }))).toBe(true);
  const output = await pdf(page, testInfo, 'continuous-rich-table');
  expect(output.map(sheet => sheet.words.filter(word => /^ROW\d+$/.test(word)))).toEqual(rowMembership);
  const normalize = text => text.replace(/\s/g, '');
  const ordered = words => words.map((word, i) => /^ROW\d+$/.test(word) ? [word, words[i + 1]] : null).filter(Boolean).flat();
  expect(output.flatMap(sheet => ordered(sheet.words))).toEqual(Array.from({ length: 20 }, (_, i) => [`ROW${i}`, `VALUE${i}`]).flat());
  expect(output.map(sheet => normalize(sheet.words.join('')))).toEqual(texts.map(normalize));
  expect(execFileSync('pdfimages', ['-list', testInfo.outputPath('continuous-rich-table.pdf')], { encoding: 'utf8' })).toMatch(/\d+\s+\d+\s+image/);
  await page.locator('#settings-toggle').click();
  await page.locator('#zoom').selectOption('2');
  await page.locator('#theme').selectOption('dark');
  await page.evaluate(() => {
    // Readiness must belong to the resize generation, not the still-visible previous projection.
    window.richSeamResize = new Promise(resolve => window.addEventListener('resize', () => resolve(), { once: true }));
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.evaluate(() => window.richSeamResize);
  await expect(sheets).toHaveCount(output.length);
  await expect(page.locator('#paged-status')).toHaveText(`${output.length} · ${messages.en.pagedSheet}`);
  expect(await pdf(page, testInfo, 'continuous-rich-mobile')).toEqual(output);
  expect(await bytes(page)).toEqual(before);
});

test('unsupported continuous seams use localized atomic fallback without partial pages or source changes', async ({ page }, testInfo) => {
  for (const [style, body] of [
    ['div.section2{-d4-page-margin:40pt}', '<p>TAIL</p>'],
    ['div.section0{column-count:2}', '<p>TAIL</p>'],
    ['div.section2{-d4-page-orientation:landscape}', '<p>TAIL</p>'],
    ['div.section2Header{margin:10pt}', '<p>TAIL</p><div class="section2Header" style="visibility:hidden;height:0"><p>STORED</p></div>'],
    ['div.section2First{white-space:normal}', '<p>TAIL</p>'],
  ]) {
    await open(page, style, '<p style="-d4-section-break-after:continuous">RETAINED</p>' + body);
    const before = await bytes(page);
    await preview(page);
    await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedContinuous);
    await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
    await expect(page.locator('#paper')).toContainText('RETAINED');
    expect((await pdf(page, testInfo, 'continuous-fallback')).flatMap(sheet => sheet.words).join('')).toContain('RETAINED');
    expect(await bytes(page)).toEqual(before);
    await page.locator('#settings-toggle').click();
    for (const language of ['ja', 'fr', 'de', 'es', 'it']) {
      await page.locator('#language').selectOption(language);
      await expect(page.locator('#paged-status')).toHaveText(messages[language].pagedContinuous);
    }
    await page.locator('#language').selectOption('en');
  }
});

test('equal columns exhaust vertical capacity sequentially with exact preview/print geometry and no balancing', async ({ page }, testInfo) => {
  await open(page, 'div.section0{column-count:2;column-gap:18pt}',
    Array.from({ length: 40 }, (_, i) => `<p>LINE${i}</p>`).join(''));
  const before = await bytes(page);
  await preview(page);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(2);
  const columns = page.locator('#paged-view .page-column');
  const tokens = (await columns.allTextContents()).map(text => text.match(/LINE\d+/g) || []);
  expect(tokens.map(items => items.length)).toEqual([13, 13, 13, 1]);
  expect(tokens.flat()).toEqual(Array.from({ length: 40 }, (_, i) => `LINE${i}`));
  const bounds = await columns.evaluateAll(columns => columns.map(column => {
    const rect = column.getBoundingClientRect();
    const page = column.closest('.browser-page').getBoundingClientRect();
    return { x: (rect.left - page.left) * .75, width: rect.width * .75,
      fits: [...column.children].every(child => child.getBoundingClientRect().bottom <= rect.bottom + .25) };
  }));
  expect(bounds.map(item => Math.round(item.x))).toEqual([30, 159, 30, 159]);
  for (const column of bounds) {
    expect(column.width).toBeCloseTo(111, 1);
    expect(column.fits).toBe(true);
  }
  const output = await pdf(page, testInfo, 'columns');
  expect(output.map(sheet => sheet.words.filter(word => /^LINE\d+$/.test(word)).sort((a, b) =>
    Number(a.slice(4)) - Number(b.slice(4))))).toEqual([tokens[0].concat(tokens[1]), tokens[2].concat(tokens[3])]);
  const bbox = execFileSync('pdftotext', ['-bbox', testInfo.outputPath('columns.pdf'), '-'], { encoding: 'utf8' });
  expect(Number(/<word xMin="([\d.]+)"[^>]*>LINE13<\/word>/.exec(bbox)[1])).toBeCloseTo(159, 1);
  await page.locator('#settings-toggle').click();
  await page.locator('#zoom').selectOption('2');
  await page.locator('#theme').selectOption('dark');
  await page.setViewportSize({ width: 390, height: 844 });
  expect(await pdf(page, testInfo, 'columns-mobile')).toEqual(output);
  expect(await columns.allTextContents()).toEqual(tokens.map(items => items.join('')));
  expect(await bytes(page)).toEqual(before);
});

test('column and page breaks retain physical parity and section-local first areas across mixed geometry', async ({ page }, testInfo) => {
  await open(page, `div.section0{column-count:2;column-gap:18pt}${variants()}${variants(2)}div.section2{column-count:3;column-gap:0pt;-d4-page-orientation:landscape}`,
    '<p style="break-after:column">A</p><p style="break-after:column">B</p><p style="page-break-after:always">C</p><p style="page-break-after:always;-d4-section-break-after:always">D</p><p style="break-after:column">E</p><p>F</p>' + areas() + areas(2));
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  await expect(sheets).toHaveCount(4);
  expect(await sheets.evaluateAll(sheets => sheets.map(sheet => [...sheet.querySelectorAll('.page-column')].map(column => column.textContent))))
    .toEqual([['A', 'B'], ['C', ''], ['D', ''], ['E', 'F', '']]);
  expect(await sheets.evaluateAll(sheets => sheets.map(sheet => sheet.querySelector('.page-area').dataset.area)))
    .toEqual(['section1FirstHeader', 'section1LeftHeader', 'section1RightHeader', 'section2FirstHeader']);
  expect((await pdf(page, testInfo, 'column-breaks')).slice(0, 4).map(sheet => [sheet.width, sheet.height]))
    .toEqual([[300, 360], [300, 360], [300, 360], [360, 300]]);
});

test('column fragments retain Unicode, whitespace, list markers and run formatting without editing the source', async ({ page }, testInfo) => {
  const text = Array.from({ length: 45 }, (_, i) => `TOKEN${i} \u{1f600}e\u0301  `).join('\n');
  await open(page, 'div.section0{column-count:3;column-gap:12pt;-d4-page-width:480pt}',
    `<p><span style="font-weight:bold;color:#135724">${text}</span></p><ol start="27"><li style="margin-left:18pt;list-style-type:upper-alpha">LIST</li></ol><p>TAIL</p>`);
  const before = await bytes(page);
  await preview(page);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(2);
  expect(await page.locator('#paged-view .page-column p .text-run').allTextContents()).toEqual(expect.arrayContaining(['TAIL']));
  expect((await page.locator('#paged-view .page-column p .text-run').allTextContents()).join('')).toBe(text + 'TAIL');
  await expect(page.locator('#paged-view .paged-list-marker')).toHaveText('AA.');
  expect(await page.locator('#paged-view .page-column p .text-run').filter({ hasText: /TOKEN\d+/ }).evaluateAll(runs =>
    runs.length > 0 && runs.every(run => getComputedStyle(run).fontWeight === '700' &&
      getComputedStyle(run).color === 'rgb(19, 87, 36)'))).toBe(true);
  const output = await pdf(page, testInfo, 'column-fragments');
  expect(output.flatMap(sheet => sheet.words).filter(word => /^TOKEN\d+$/.test(word)).sort((a, b) =>
    Number(a.slice(5)) - Number(b.slice(5)))).toEqual(Array.from({ length: 45 }, (_, i) => `TOKEN${i}`));
  expect(await bytes(page)).toEqual(before);
});

test('unsupported columns fall back atomically, retaining continuous content and existing print safety', async ({ page }, testInfo) => {
  for (const [style, body] of [
    ['div.section0{column-count:5}', '<p>RETAINED</p>'],
    ['div.section0{column-count:4}', '<p>RETAINED</p>'],
    ['div.section0{column-count:2;column-rule-style:solid}', '<p>RETAINED</p>'],
    ['div.section0{column-count:2}', '<p>BEFORE</p><table><tr><td><p>RETAINED</p></td></tr></table><p>TAIL</p>'],
  ]) {
    await open(page, style, body);
    const before = await bytes(page);
    await preview(page);
    await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedColumns);
    await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
    const output = (await pdf(page, testInfo, 'column-fallback')).flatMap(sheet => sheet.words).join('');
    if (/column-count:[45]/.test(style)) expect(output).toContain('Browserprintingrequiresatleast72pt');
    else expect(output).toContain('RETAINED');
    await expect(page.locator('#paper')).toContainText('RETAINED');
    expect(await bytes(page)).toEqual(before);
    await page.locator('#settings-toggle').click();
    for (const language of ['ja', 'fr', 'de', 'es', 'it']) {
      await page.locator('#language').selectOption(language);
      await expect(page.locator('#paged-status')).toHaveText(messages[language].pagedColumns);
    }
    await page.locator('#language').selectOption('en');
  }
});

test('rectangular tables split at measured rows with stable unequal columns, repeated native headers and matching print', async ({ page }, testInfo) => {
  const rows = Array.from({ length: 30 }, (_, index) => `<tr><td class="narrow"><p><span style="font-weight:bold;color:#135724">ROW${index}</span></p></td><td class="wide"><p>VALUE${index}</p></td></tr>`).join('');
  await open(page, 'table{border-collapse:collapse;width:200pt;margin:3pt 0}td{border:1pt solid #234567;padding:3pt}td.narrow{width:70pt}td.wide{width:130pt}tr.header{background-color:#ddeeff;-d4-header:true}',
    `<p>BEFORE</p><table><tr class="header"><td class="narrow"><p>HEADERA</p></td><td class="wide"><p>HEADERB</p></td></tr>${rows}</table><p>AFTER</p>`);
  const before = await bytes(page);
  await preview(page);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(4);
  const bodies = page.locator('#paged-view .browser-page .page-body');
  const texts = await bodies.allTextContents();
  expect(texts.length).toBeGreaterThan(2);
  const expected = texts.map(text => text.match(/ROW\d+/g) || []);
  expect(expected.map(rows => rows.length)).toEqual([7, 8, 8, 7]);
  expect(expected.flat()).toEqual(Array.from({ length: 30 }, (_, i) => `ROW${i}`));
  expect(texts.join('').match(/VALUE\d+/g)).toEqual(Array.from({ length: 30 }, (_, i) => `VALUE${i}`));
  const widths = await bodies.locator('table').evaluateAll(tables => tables.map(table =>
    [...table.rows[0].cells].map(cell => cell.getBoundingClientRect().width)));
  for (const width of widths) expect(width).toEqual(widths[0]);
  expect(widths[0][1]).toBeGreaterThan(widths[0][0]);
  expect(await bodies.locator('table').evaluateAll(tables => tables.every(table => {
    const header = getComputedStyle(table.rows[0]);
    return header.backgroundColor === 'rgb(221, 238, 255)' &&
      [...table.querySelectorAll('td')].every(cell => {
        const style = getComputedStyle(cell);
        return style.borderTopStyle === 'solid' && parseFloat(style.borderTopWidth) > 0 &&
          style.paddingTop === '4px';
      }) && [...table.querySelectorAll('td span[style*="font-weight"]')].every(span => {
        const style = getComputedStyle(span);
        return style.fontWeight === '700' && style.color === 'rgb(19, 87, 36)';
      });
  }))).toBe(true);
  await expect(bodies.locator('table')).toHaveCount(texts.length);
  await expect(bodies.locator('tr').filter({ hasText: 'HEADERA' })).toHaveCount(texts.length);
  expect(await bodies.evaluateAll(elements => elements.every(body => {
    const bounds = body.getBoundingClientRect();
    const rows = [...body.querySelectorAll('tr')];
    return rows.every(row => row.getBoundingClientRect().bottom <= bounds.bottom + .25) &&
      (!rows.length || rows.length > 1);
  }))).toBe(true);
  const output = await pdf(page, testInfo, 'table-rows');
  expect(output.map(sheet => sheet.words.filter(word => /^ROW\d+$/.test(word)))).toEqual(expected);
  expect(output.every(sheet => sheet.words.includes('HEADERA'))).toBe(true);
  expect(output.flatMap(sheet => sheet.words).filter(word => word === 'AFTER')).toHaveLength(1);
  await page.emulateMedia({ media: 'print' });
  await page.evaluate(() => dispatchEvent(new Event('beforeprint')));
  expect(await page.locator('#print-document table').evaluateAll(tables => tables.map(table =>
    [...table.rows[0].cells].map(cell => cell.getBoundingClientRect().width)))).toEqual(widths);
  await page.evaluate(() => dispatchEvent(new Event('afterprint')));
  await page.emulateMedia({ media: 'screen' });
  expect(await bytes(page)).toEqual(before);
});

test('table projection stays derived across mixed sections, zoom, resize, print Cancel and recovered Redo', async ({ page }, testInfo) => {
  const rows = Array.from({ length: 25 }, (_, i) => `<tr><td><p>CELL${i}</p></td><td><p>TEXT${i}</p></td></tr>`).join('');
  await open(page, `${variants()}${variants(2)}div.section2{-d4-page-orientation:landscape}table{border-collapse:collapse;width:100%}td{border:1pt solid #123456;padding:2pt}`,
    `<p>ORIGINAL</p><table>${rows}</table><p style="page-break-after:always;-d4-section-break-after:always">SECTIONEND</p><p>SECOND</p><table>${rows.replaceAll('CELL', 'NEXTCELL')}</table><p>TAIL</p>${areas()}${areas(2)}`);
  await page.locator('#paper [contenteditable]').first().fill('EDITED');
  const edited = contents(await bytes(page));
  await page.locator('#undo').click();
  const undone = await bytes(page);
  await preview(page);
  const output = await pdf(page, testInfo, 'table-sections');
  const bbox = execFileSync('pdftotext', ['-bbox', testInfo.outputPath('table-sections.pdf'), '-'], { encoding: 'utf8' });
  for (const token of ['CELL0', 'NEXTCELL0']) {
    const expectedX = await page.locator('#paged-view table .text-run').filter({ hasText: new RegExp(`^${token}$`) }).evaluate(run => {
      const range = document.createRange();
      range.selectNodeContents(run);
      return (range.getBoundingClientRect().left - run.closest('.browser-page').getBoundingClientRect().left) * .75;
    });
    const printedX = Number(new RegExp(`<word xMin="([\\d.]+)"[^>]*>${token}</word>`).exec(bbox)[1]);
    expect(printedX).toBeCloseTo(expectedX, 0);
  }
  const texts = await page.locator('#paged-view .browser-page').allTextContents();
  expect(output.slice(0, texts.length).map(sheet => [sheet.width, sheet.height])).toEqual(
    await page.locator('#paged-view .browser-page').evaluateAll(sheets => sheets.map(sheet =>
      [parseFloat(sheet.style.width), parseFloat(sheet.style.height)])));
  expect(texts.join('')).toContain('S2FirstHeader');
  await page.locator('#settings-toggle').click();
  await page.locator('#zoom').selectOption('2');
  await page.locator('#theme').selectOption('dark');
  await page.setViewportSize({ width: 390, height: 844 });
  expect(await pdf(page, testInfo, 'table-mobile')).toEqual(output);
  await page.evaluate(() => { window.print = () => { dispatchEvent(new Event('beforeprint')); dispatchEvent(new Event('afterprint')); }; });
  await page.locator('#print-toggle').click();
  await page.locator('#print-open').click();
  expect(await bytes(page)).toEqual(undone);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#redo').click();
  expect(contents(await bytes(page))).toEqual(edited);
  await preview(page);
  await expect(page.locator('#paged-view')).toContainText('EDITED');
});

test('intrinsic native column geometry is not stretched to the page body width', async ({ page }) => {
  await open(page, 'table{border-collapse:collapse}td{padding:3pt;border:1pt solid #234567}td.a{width:60pt}td.b{width:120pt}',
    '<p>BEFORE</p><table><tr><td class="a"><p>A</p></td><td class="b"><p>B</p></td></tr><tr><td class="a"><p>C</p></td><td class="b"><p>D</p></td></tr></table><p>AFTER</p>');
  const geometry = table => ({
    width: table.getBoundingClientRect().width,
    columns: [...table.rows[0].cells].map(cell => cell.getBoundingClientRect().width),
  });
  const original = await page.locator('#paper table').evaluate(geometry);
  await preview(page);
  const projected = await page.locator('#paged-view table').evaluate(geometry);
  expect(projected).toEqual(original);
});

test('oversized rows, spanning cells and nested table-cell lists fall back atomically with the entire table retained', async ({ page }) => {
  for (const [table, reason] of [
    ['<table><tr><td><p>' + 'TOOBIG<br/>'.repeat(30) + '</p></td></tr></table>', 'pagedOverflow'],
    ['<table><tr><td colspan="2"><p>MERGED</p></td></tr><tr><td><p>A</p></td><td><p>B</p></td></tr></table>', 'pagedTables'],
    ['<table><tr><td><ul><li>LIST<ul><li>NESTED</li></ul></li></ul></td></tr></table>', 'pagedTables'],
  ]) {
    await open(page, '', `<p>BEFORE</p>${table}<p>TAIL</p>`);
    const before = await bytes(page);
    await preview(page);
    await expect(page.locator('#paged-status')).toHaveText(messages.en[reason]);
    await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
    await expect(page.locator('#paper')).toContainText('TAIL');
    expect(await bytes(page)).toEqual(before);
  }
});

test('automatic page boundaries retain each paragraph once and PDF matches actual preview pages', async ({ page }, testInfo) => {
  const body = Array.from({ length: 40 }, (_, i) => `<p>LINE${i} WORD</p>`).join('');
  await open(page, '', body);
  const before = await bytes(page);
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  await expect(sheets).toHaveCount(4);
  const texts = await sheets.locator('.page-body').allTextContents();
  expect(texts.map(text => [...text.matchAll(/LINE(\d+)/g)].map(match => Number(match[1])))).toEqual([
    Array.from({ length: 13 }, (_, i) => i), Array.from({ length: 13 }, (_, i) => i + 13),
    Array.from({ length: 13 }, (_, i) => i + 26), [39],
  ]);
  expect(await page.locator('#paged-view').locator('[contenteditable],[data-run]').count()).toBe(0);
  expect(await sheets.evaluateAll(elements => elements.every(sheet => {
    const body = sheet.querySelector('.page-body').getBoundingClientRect();
    return [...sheet.querySelectorAll('.page-body > p')].every(p => p.getBoundingClientRect().bottom <= body.bottom + .25);
  }))).toBe(true);
  const printed = await pdf(page, testInfo, 'boundaries');
  expect(printed).toHaveLength(4);
  expect(printed.map(sheet => sheet.words.filter(word => word.startsWith('LINE')))).toEqual(texts.map(text => text.match(/LINE\d+/g)));
  expect(printed.every(sheet => sheet.width === 300 && sheet.height === 360)).toBe(true);
  expect(await bytes(page)).toEqual(before);
});

test('the 500-sheet boundary is enforced without discarding any source paragraphs', async ({ page }) => {
  const body = count => Array.from({ length: count }, (_, index) =>
    `<p${index < count - 1 ? ' style="page-break-after:always"' : ''}>PAGE${index}</p>`).join('');
  await open(page, '', body(500));
  await expect(page.locator('#paper p')).toHaveCount(500);
  await preview(page);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(500);
  await open(page, '', body(501));
  await expect(page.locator('#paper p')).toHaveCount(501);
  const before = await bytes(page);
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedOverflow);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
  await expect(page.locator('#paper')).toContainText('PAGE500');
  expect(await bytes(page)).toEqual(before);
});

test('explicit page/section breaks select first/facing areas on mixed geometry and retain unused areas', async ({ page }, testInfo) => {
  await open(page, `${variants()}${variants(2)}div.section2{-d4-page-orientation:landscape}`,
    '<p style="page-break-after:always">ONE</p><p style="page-break-after:always">TWO</p><p style="page-break-after:always;-d4-section-break-after:always">THREE</p><p style="page-break-after:always">FOUR</p><p>FIVE</p>' + areas() + areas(2));
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  await expect(sheets).toHaveCount(5);
  expect(await sheets.evaluateAll(elements => elements.map(sheet => [...sheet.querySelectorAll('[data-area]')].map(area => area.dataset.area)))).toEqual([
    ['section1FirstHeader', 'section1FirstFooter'], ['section1LeftHeader', 'section1LeftFooter'],
    ['section1RightHeader', 'section1RightFooter'], ['section2FirstHeader', 'section2FirstFooter'],
    ['section2RightHeader', 'section2RightFooter'],
  ]);
  const output = await pdf(page, testInfo, 'variants');
  expect(output.slice(0, 5).map(sheet => [sheet.width, sheet.height])).toEqual([[300, 360], [300, 360], [300, 360], [360, 300], [360, 300]]);
  for (let i = 0; i < 5; i++) expect(output[i].words).toContain(['ONE', 'TWO', 'THREE', 'FOUR', 'FIVE'][i]);
  expect(output[1].words).toContain('S1LeftHeader');
  expect(output[4].words).toContain('S2RightFooter');
  expect(output.slice(5).flatMap(sheet => sheet.words)).toContain('S1DefaultHeader');
  expect(output.slice(5).flatMap(sheet => sheet.words)).toContain('S2LeftHeader');
});

test('first-left parity, missing enabled areas and absent section areas do not inherit', async ({ page }) => {
  const content = areas().replace(/<div class="section1FirstHeader"[\s\S]*?<\/div>/, '')
    .replace(/<div class="section1LeftFooter"[\s\S]*?<\/div>/, '');
  await open(page, variants().replace('div.section1FirstHeader{margin:10pt 30pt}', '').replace('div.section1LeftFooter{margin:10pt 30pt}', '') +
    'div.section0{-d4-page-first-right:false}',
  '<p style="page-break-after:always">ONE</p><p style="page-break-after:always">TWO</p><p style="page-break-after:always;-d4-section-break-after:always">THREE</p><p>FOUR</p>' + content);
  await preview(page);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(4);
  expect(await page.locator('#paged-view .browser-page').evaluateAll(elements => elements.map(sheet =>
    [...sheet.querySelectorAll('[data-area]')].map(area => area.dataset.area)))).toEqual([
    ['section1FirstFooter'], ['section1RightHeader', 'section1RightFooter'], ['section1LeftHeader'], [],
  ]);
});

test('preview resize/zoom/themes, print cancellation, edits and recovery preserve archive and history', async ({ page }, testInfo) => {
  await open(page, '', '<p>ORIGINAL</p>');
  await page.locator('#paper [contenteditable]').fill('EDITED');
  const edited = await bytes(page);
  await page.locator('#undo').click();
  const undone = await bytes(page);
  await preview(page);
  const baseline = await pdf(page, testInfo, 'before');
  await page.locator('#settings-toggle').click();
  for (const theme of ['dark', 'system', 'light']) {
    await page.locator('#theme').selectOption(theme);
    await page.locator('#zoom').selectOption('2');
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(page.locator('#paged-view .browser-page')).toHaveCount(1);
    expect(await pdf(page, testInfo, theme)).toEqual(baseline);
  }
  await page.evaluate(() => {
    window.print = () => { dispatchEvent(new Event('beforeprint')); dispatchEvent(new Event('afterprint')); };
  });
  await page.locator('#print-toggle').click();
  await page.locator('#print-open').click();
  expect(await bytes(page)).toEqual(undone);
  await expect(page.locator('#redo')).toBeEnabled();
  await page.locator('#redo').click();
  await expect(page.locator('#paged-view')).toContainText('EDITED');
  expect(contents(await bytes(page))).toEqual(contents(edited));
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await preview(page);
  await expect(page.locator('#paged-view')).toContainText('EDITED');
  expect(contents(await bytes(page))).toEqual(contents(edited));
});

test('oversized atoms and areas fall back explicitly without partial pages or lost print content', async ({ page }, testInfo) => {
  await open(page, '', '<p><span style="font-size:240pt">HUGE</span></p><p>TAIL</p>');
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedOverflow);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
  const output = await pdf(page, testInfo, 'fallback');
  const words = output.flatMap(sheet => sheet.words).join(' ');
  expect(words.replaceAll(' ', '')).toContain('HUGE');
  expect(words).toContain('TAIL');
  expect(words).toContain('Paged preview unavailable');
  await open(page, 'div.section1Header{margin:0pt}', '<p>BODY</p><div class="section1Header" style="visibility:hidden;height:0"><p>' + 'OVERFLOW<br/>'.repeat(10) + '</p></div>');
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedAreas);
  await expect(page.locator('#paper')).toContainText('BODY');
  await page.locator('#editing-scope').selectOption('section1Header');
  await expect(page.locator('#paper')).toContainText('OVERFLOW');
});

test('long paragraphs split at measured lines with exact whitespace, Unicode and run formatting in preview and PDF', async ({ page }, testInfo) => {
  const text = Array.from({ length: 40 }, (_, i) => `LINE${i} \u{1f600}e\u0301  `).join('\n');
  await open(page, '', `<p style="margin-top:6pt;margin-bottom:9pt"><span style="font-weight:bold;color:#135724">${text}</span></p><p>TAIL</p>`);
  const before = await bytes(page);
  await preview(page);
  const bodies = page.locator('#paged-view .page-body');
  expect(await bodies.count()).toBeGreaterThan(3);
  expect((await bodies.allTextContents()).join('')).toBe(text + 'TAIL');
  expect(await bodies.locator('p > span:not(.text-run)').evaluateAll(elements => elements.every(element =>
    getComputedStyle(element).fontWeight === '700' && getComputedStyle(element).color === 'rgb(19, 87, 36)'))).toBe(true);
  expect(await bodies.evaluateAll(elements => elements.every(body => {
    const bounds = body.getBoundingClientRect();
    return [...body.querySelectorAll('.text-run')].every(run => [...run.getClientRects()].every(rect =>
      rect.top >= bounds.top - .25 && rect.bottom <= bounds.bottom + .25));
  }))).toBe(true);
  const output = await pdf(page, testInfo, 'fragments');
  const sorted = words => words.toSorted((a, b) => Number(a.slice(4)) - Number(b.slice(4)));
  expect(output.map(sheet => sorted(sheet.words.filter(word => /^LINE\d+$/.test(word))))).toEqual(
    (await bodies.allTextContents()).map(text => sorted(text.match(/LINE\d+/g) || [])));
  expect(output.flatMap(sheet => sheet.words).filter(word => word === 'TAIL')).toHaveLength(1);
  expect(await bytes(page)).toEqual(before);
});

test('flat lists keep native indentation, mixed markers, starts and one marker per split item', async ({ page }, testInfo) => {
  const long = Array.from({ length: 30 }, (_, i) => `ITEMLINE${i}`).join('\n');
  await open(page, 'li{font:12pt Arial;line-height:18pt;white-space:pre-wrap;margin:0}',
    `<ol start="27"><li style="list-style-type:upper-latin;margin-left:12pt">${long}</li>` +
    '<li style="list-style-type:decimal;margin-left:24pt;-d4-list-string-format-ltr:\'(#)\'">NEXT</li>' +
    '<li style="-d4-list-style-type:hollow-square;margin-left:12pt">BULLET</li></ol><p>TAIL</p>');
  const before = await bytes(page);
  await preview(page);
  expect(await page.locator('#paged-view .browser-page').count()).toBeGreaterThan(2);
  expect(await page.locator('#paged-view .paged-list-marker').allTextContents()).toEqual(['AA.', '(28)', '\u25a1']);
  expect(await page.locator('#paged-view ol').evaluateAll(lists => lists.map(list => list.start))).toEqual([27, 27, 27, 28, 29]);
  const bodyText = await page.locator('#paged-view .page-body').allTextContents();
  expect(bodyText.join('')).toBe(`AA.${long}(28)NEXT\u25a1BULLETTAIL`);
  expect(await page.locator('#paged-view li').evaluateAll(elements => elements.filter(li =>
    li.textContent.includes('ITEMLINE')).every(li => getComputedStyle(li).marginLeft === '16px'))).toBe(true);
  const output = await pdf(page, testInfo, 'lists');
  expect(output.flatMap(sheet => sheet.words).filter(word => word === 'AA.')).toHaveLength(1);
  expect(output.flatMap(sheet => sheet.words).filter(word => word === '(28)')).toHaveLength(1);
  expect(output.map(sheet => sheet.words.filter(word => /^ITEMLINE\d+$/.test(word)))).toEqual(
    bodyText.map(text => text.match(/ITEMLINE\d+/g) || []));
  expect(await bytes(page)).toEqual(before);
});

test('inline images decode before measuring, move atomically and retain authored dimensions in print', async ({ page }, testInfo) => {
  const png = localPNG;
  const image = `<img src="${png}" alt="LOCAL" style="width:90pt;height:72pt;-d4-img-display-mode:proportionalCentered"/>`;
  await open(page, '', `<p>${Array.from({ length: 15 }, (_, i) => `BEFORE${i}<br/>`).join('')}LEFT${image}RIGHT<br/>END</p>`);
  const before = await bytes(page);
  await preview(page);
  await expect(page.locator('#paged-view img')).toHaveCount(1);
  expect(await page.locator('#paged-view .browser-page').count()).toBeGreaterThan(1);
  const imageBounds = await page.locator('#paged-view img').boundingBox();
  expect(imageBounds.width).toBeCloseTo(120);
  expect(imageBounds.height).toBeCloseTo(96);
  const count = await page.locator('#paged-view .browser-page').count();
  const output = await pdf(page, testInfo, 'inline-image');
  expect(output).toHaveLength(count);
  await page.emulateMedia({ media: 'print' });
  await page.evaluate(() => dispatchEvent(new Event('beforeprint')));
  expect(await page.locator('#print-document img').evaluate(image => [image.getBoundingClientRect().width, image.getBoundingClientRect().height])).toEqual([120, 96]);
  await page.emulateMedia({ media: 'screen' });
  await page.evaluate(() => dispatchEvent(new Event('afterprint')));
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.locator('#paged-view img')).toHaveCount(1);
  expect(await bytes(page)).toEqual(before);
  await open(page, '', `<p>HEAD<img src="${png}" style="width:300pt;height:72pt"/>TAIL</p>`);
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedOverflow);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
});

test('failed decoding and external images never return partial pages or fetch remote media', async ({ page }) => {
  const requests = [];
  page.on('request', request => { if (request.url().includes('invalid.example')) requests.push(request.url()); });
  for (const src of ['https://invalid.example/image.png', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA']) {
    await open(page, '', `<p>HEAD<img src="${src}" alt="BROKEN"/>TAIL</p>`);
    const before = await bytes(page);
    await preview(page);
    await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedShape);
    await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
    await expect(page.locator('#paper')).toContainText('TAIL');
    expect(await bytes(page)).toEqual(before);
  }
  expect(requests).toEqual([]);
});

test('automatic wrapped lines retain all words across style boundaries, whitespace and empty paragraphs', async ({ page }, testInfo) => {
  const words = Array.from({ length: 150 }, (_, i) => `WORD${i}`);
  const first = '  ' + words.slice(0, 75).join(' ') + ' ';
  const second = words.slice(75).join(' ') + '  ';
  await open(page, '', `<p>\u200b</p><p><span style="font-weight:bold">${first}</span><span style="font-style:italic">${second}</span></p><p>\u200b</p>`);
  const before = await bytes(page);
  await preview(page);
  const bodies = page.locator('#paged-view .page-body');
  expect(await bodies.count()).toBeGreaterThan(2);
  expect((await bodies.allTextContents()).join('')).toBe('\u200b' + first + second + '\u200b');
  const output = await pdf(page, testInfo, 'wrapped');
  expect(output.map(sheet => sheet.words.filter(word => /^WORD\d+$/.test(word)))).toEqual(
    (await bodies.allTextContents()).map(text => text.match(/WORD\d+/g) || []));
  expect(output.flatMap(sheet => sheet.words).filter(word => /^WORD\d+$/.test(word))).toEqual(words);
  expect(await bytes(page)).toEqual(before);
});

test('fragment limits fail explicitly and keep every source character accessible', async ({ page }) => {
  const text = 'SAFE '.repeat(20001);
  await open(page, '', `<p>${text}</p><p>TAIL</p>`);
  const before = await bytes(page);
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedOverflow);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
  expect(await page.locator('#paper p').first().textContent()).toBe(text);
  expect(await bytes(page)).toEqual(before);
});

test('fragments preserve explicit section breaks and repeated area selection on physical pages', async ({ page }, testInfo) => {
  await open(page, variants() + variants(2) + 'div.section2{-d4-page-orientation:landscape}',
    '<p style="page-break-after:always;-d4-section-break-after:always">' +
    Array.from({ length: 30 }, (_, i) => `SPLIT${i}<br/>`).join('') + '</p><p>SECOND</p>' + areas() + areas(2));
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  await expect(sheets).toHaveCount(4);
  expect(await sheets.evaluateAll(sheets => sheets.map(sheet => [sheet.dataset.section,
    sheet.querySelector('.page-area').dataset.area]))).toEqual([
    ['1', 'section1FirstHeader'], ['1', 'section1LeftHeader'], ['1', 'section1RightHeader'], ['2', 'section2FirstHeader'],
  ]);
  const output = await pdf(page, testInfo, 'split-section');
  expect(output[3].words).toContain('SECOND');
  expect([output[3].width, output[3].height]).toEqual([360, 300]);
});

test('inert formula cards keep source and stored text without page-field evaluation', async ({ page }, testInfo) => {
  await open(page, '', '<p>START<span style="-d4-ref:\'This:C1470.pageNumber\'">SAVED</span>END</p>');
  await preview(page);
  await expect(page.locator('#paged-view .formula-source')).toContainText('pageNumber');
  await expect(page.locator('#paged-view .formula-value')).toContainText('SAVED');
  const output = await pdf(page, testInfo, 'formula');
  expect(output.flatMap(sheet => sheet.words).join(' ')).toContain('SAVED');
});

test('formula paragraphs near a page boundary keep identical measured heights in preview and print media', async ({ page }, testInfo) => {
  await open(page, '', '<p>LINE</p>'.repeat(10) + '<p><span style="-d4-ref:\'1+1\'">SAVED</span></p>');
  const before = await bytes(page);
  await preview(page);
  const count = await page.locator('#paged-view .browser-page').count();
  const heights = await page.locator('#paged-view .page-body > p').evaluateAll(elements =>
    elements.map(element => element.getBoundingClientRect().height));
  await page.emulateMedia({ media: 'print' });
  await page.evaluate(() => dispatchEvent(new Event('beforeprint')));
  expect(await page.locator('#print-document .browser-page').count()).toBe(count);
  expect(await page.locator('#print-document .page-body > p').evaluateAll(elements =>
    elements.map(element => element.getBoundingClientRect().height))).toEqual(heights);
  const output = await pdf(page, testInfo, 'formula-boundary');
  expect(output).toHaveLength(count);
  expect(output.flatMap(sheet => sheet.words).filter(word => word === 'SAVED')).toHaveLength(1);
  await page.emulateMedia({ media: 'screen' });
  await page.evaluate(() => dispatchEvent(new Event('afterprint')));
  expect(await bytes(page)).toEqual(before);
});

test('oversized unused areas fall back with all exported lines instead of clipping or returning partial pages', async ({ page }, testInfo) => {
  const unused = Array.from({ length: 50 }, (_, index) => `UNUSED${index} word word word<br/>`).join('');
  await open(page, 'div.section1First{white-space:normal}div.section1FirstHeader{margin:10pt 30pt}div.section1Header{margin:10pt 30pt}',
    '<p>BODY</p><div class="section1FirstHeader" style="visibility:hidden;height:0"><p>FIRST</p></div>' +
    `<div class="section1Header" style="visibility:hidden;height:0"><p>${unused}</p></div>`);
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedAreas);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
  const output = await pdf(page, testInfo, 'unused-long');
  const words = output.flatMap(sheet => sheet.words);
  for (let index = 0; index < 50; index++) expect(words.filter(word => word === `UNUSED${index}`)).toHaveLength(1);
  expect(words.filter(word => word === 'BODY')).toHaveLength(1);
  expect(words.filter(word => word === 'FIRST')).toHaveLength(1);
  expect(output.every(sheet => sheet.width === 300 && sheet.height === 360)).toBe(true);
});

for (const locale of ['en', 'ja', 'fr', 'de', 'es', 'it']) {
  test(`paged controls, fallback and keyboard work on mobile in ${locale}`, async ({ page }) => {
    await page.addInitScript(locale => localStorage.setItem('4wp-language', locale), locale);
    await page.setViewportSize({ width: 390, height: 844 });
    await open(page, 'div.section0{column-count:2;column-rule-style:solid}', '<p>BODY</p>');
    await page.locator('#paged-panel > summary').click();
    await expect(page.locator('#paged-status')).toHaveText(messages[locale].pagedColumns);
    expect(await page.locator('#paged-panel').evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
    await page.locator('#paged-panel > summary').focus();
    await page.keyboard.press('Escape');
    await expect(page.locator('#paged-panel')).not.toHaveAttribute('open');
    await expect(page.locator('#paged-panel > summary')).toBeFocused();
  });
}
