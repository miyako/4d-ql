import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { unzipSync, zipSync, strFromU8 } from 'fflate';
import { expect } from '@playwright/test';
import { messages } from '../src/i18n.js';
import { geometry, inspectPDF } from './native-print-cases.mjs';
import { nativeSlots } from './native-coltable-cases.mjs';
import { pageVectors, bounds } from './pdf-vectors.mjs';

// Expected browser outcome per native shape (wp_colrule_probe). Protected shapes keep the localized fallback.
export const colruleShapes = {
  solid: null, lastboth: null, short: null, three: null, 'three-two': null, four: null,
  dotted: null, dashed: null, double: null, groove: null, ridge: null, inset: null, outset: null, none: null, default: null,
  thin: null, thick: null,
  // Native 4D strokes a rule wider than its gap over the text of both columns; the paint order is not claimed.
  overgap: 'pagedColumns',
  // With a zero gap the native rule straddles the column boundary over both columns' text (same reason).
  gap0: 'pagedColumns',
  colbreak: null, pagebreak: null, fullcol: null, noareas: null, table: null, section2: null, docdefault: null, landscape: null,
  single: null,
  // Native 4D strokes the incoming section's rule over the whole shared page body, above the seam too, and a seam
  // between two ruled sections strokes it twice; continuous seams with columns keep the continuous fallback.
  'continuous-in': 'pagedContinuous', 'continuous-same': 'pagedContinuous',
  'three-partial': null, 'four-partial': null, skipcol: null, emptycol: null, cmwidth: null,
  // A table wider than its column (#67 protected shape): its overflow into the next column's area does not reach that
  // column natively, so no rule is drawn on its last page.
  'table-wide': 'pagedColumns',
};
// Native getter style codes (wk none … wk outset) as observed in wp_colrule_probe.
const styleNames = { 0: 'none', 1: 'solid', 2: 'dotted', 3: 'dashed', 4: 'double', 6: 'groove', 7: 'ridge', 8: 'inset', 9: 'outset' };
const tokenPattern = /^(CL\d+|R\d+[ABC]|CR[A-Z]+\d*)$/;
const points = value => {
  const [, number, unit] = String(value).match(/^([\d.]+)(pt|cm|mm|in)$/);
  return Number(number) * { pt: 1, cm: 72 / 2.54, mm: 72 / 25.4, in: 72 }[unit];
};
const channels = paint => {
  const values = paint.match(/[\d.]+/g).map(Number);
  return paint.includes('%') ? values.map(value => Math.round(value * 2.55)) : values.map(Math.round);
};
const rgb = color => [16, 8, 0].map(shift => (color >> shift) & 255);

// Vertical paint of one page inside one gap that spans (as a union of pieces) at least the given height.
function gapPaint(vectors, gap, minimum) {
  const inside = vectors.filter(box => box.left >= gap.left - .25 && box.right <= gap.right + .25 && box.bottom - box.top >= 4 &&
    (box.vector.stroke && box.vector.stroke !== 'none' || box.vector.fill && box.vector.fill !== 'none'));
  if (!inside.length) return null;
  const union = { left: Math.min(...inside.map(box => box.left)), right: Math.max(...inside.map(box => box.right)),
    top: Math.min(...inside.map(box => box.top)), bottom: Math.max(...inside.map(box => box.bottom)) };
  if (union.bottom - union.top < minimum) return null;
  // Stroked paths are widened by their stroke width; filled paths already carry their extent.
  const halves = inside.map(box => (box.vector.stroke && box.vector.stroke !== 'none' ? box.vector.strokeWidth / 2 : 0));
  return { ...union, paintLeft: Math.min(...inside.map((box, i) => box.left - halves[i])), paintRight: Math.max(...inside.map((box, i) => box.right + halves[i])),
    paints: [...new Set(inside.map(box => (box.vector.stroke && box.vector.stroke !== 'none' ? box.vector.stroke : box.vector.fill)))],
    pieces: inside.length, dash: inside.find(box => box.vector.dash)?.vector.dash ?? null,
    // Each painted piece across the rule: its centre, width, paint and dash pattern (stroke centre line or fill box).
    parts: inside.map((box, i) => ({ center: (box.left + box.right) / 2, width: halves[i] ? halves[i] * 2 : box.right - box.left,
      paint: channels(box.vector.stroke && box.vector.stroke !== 'none' ? box.vector.stroke : box.vector.fill),
      dash: box.vector.dash ? box.vector.dash.split(/[ ,]+/).map(Number) : null })).sort((a, b) => a.center - b.center) };
}

export async function prepareColruleCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/colrule-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.deepEqual(report.cases.map(item => item.name), Object.keys(colruleShapes));
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/colrule-errors.json'), 'utf8')), []);
  const results = [];
  for (const item of report.cases) {
    const fallback = colruleShapes[item.name];
    const files = unzipSync(await readFile(resolve(directory, `Output/colrule-${item.name}-original.4wp`)));
    const html = strFromU8(files[Object.keys(files).find(name => name.endsWith('.html'))]);
    // Native getters, and the same values after re-import of the stored file.
    assert.deepEqual(item.reopened, item.applied, `${item.name}: stored rule survives re-import`);
    const papers = item.sections.sections.map(section => geometry(section.geometry));
    const settings = item.applied.map(section => ({ count: section.count, gap: points(section.gap), style: styleNames[section.style],
      width: points(section.width), color: section.color }));
    assert(settings.every(setting => setting.style), `${item.name}: known native style codes`);

    // ---- Independent native oracle: which pages carry rules in which gaps, their extent and paint. ----
    const native = inspectPDF(resolve(directory, `Output/colrule-${item.name}.pdf`));
    assert.equal(inspectPDF(resolve(directory, `Output/colrule-${item.name}-reopened.pdf`)).text, native.text,
      `${item.name}: the stored file alone reproduces the native layout`);
    // A continuous seam shares pages: native strokes the incoming (ruled) section's rule there, so its setting applies.
    let section = item.requested.second?.continuous ? 1 : 0;
    const nativePages = native.pages.map((sheet, page) => {
      if (item.requested.second && !item.requested.second.continuous && sheet.words.some(word => word.text === 'CRSECOND')) section = 1;
      const setting = settings[section];
      const paper = papers[section];
      const slots = nativeSlots(paper, { count: setting.count, gap: String(setting.gap) });
      const words = sheet.words.filter(word => tokenPattern.test(word.text));
      const reach = slots.findLastIndex(slot => words.some(word => {
        const x = (word.x + word.right) / 2;
        const y = (word.y + word.bottom) / 2;
        return x >= slot.left - .25 && x <= slot.right + .25 && y >= paper.top && y <= paper.height - paper.bottom;
      })) + 1;
      const gaps = slots.slice(1).map((slot, index) => ({ left: setting.gap ? slots[index].right : slot.left - 6, right: setting.gap ? slot.left : slot.left + 6 }));
      const vectors = pageVectors(resolve(directory, `Output/colrule-${item.name}.pdf`), page + 1).map(vector => ({ ...bounds(vector), vector }));
      const body = paper.height - paper.top - paper.bottom;
      const paints = gaps.map(gap => gapPaint(vectors, { left: gap.left - (setting.width > setting.gap ? setting.width : 0), right: gap.right + (setting.width > setting.gap ? setting.width : 0) }, body / 2));
      return { page: page + 1, section: section + 1, reach, gaps, paper, setting, paints,
        drawn: paints.map((paint, index) => (paint ? index + 1 : 0)).filter(Boolean) };
    });
    // Native relation: a rule in every gap left of the last column the page's text reaches, full body height, centred
    // in its gap. 'emptycol' reaches its second column with an empty paragraph only (no printed word there).
    for (const entry of nativePages) {
      const { setting, paper } = entry;
      if (setting.style === 'none' || setting.count === 1) {
        assert.deepEqual(entry.drawn, [], `${item.name}: no native rule without a style or with one column (page ${entry.page})`);
        continue;
      }
      if (item.name === 'table-wide' && entry.page === 2) {
        assert.equal(entry.reach, 2, 'table-wide: the overflowing table prints words in the second column area');
        assert.deepEqual(entry.drawn, [], 'table-wide: table overflow does not reach the second column natively');
        continue;
      }
      const reach = item.name === 'emptycol' && entry.page === 1 ? 2 : entry.reach;
      if (item.name === 'emptycol' && entry.page === 1) assert.equal(entry.reach, 1, 'emptycol: the second column holds no word natively');
      if (item.name === 'continuous-same' && entry.page === 1) {
        // Two rule strokes on the shared page: one per section (protected counterexample).
        assert.equal(entry.paints[0].pieces, 2, 'continuous-same: native strokes the rule once per section on the shared page');
      }
      assert.deepEqual(entry.drawn, Array.from({ length: Math.max(0, reach - 1) }, (_, i) => i + 1),
        `${item.name}: native rules in every gap left of the reached column (page ${entry.page})`);
      for (const [index, paint] of entry.paints.entries()) {
        if (!paint) continue;
        const gap = entry.gaps[index];
        const center = setting.gap ? (gap.left + gap.right) / 2 : gap.left + 6;
        assert(Math.abs((paint.paintLeft + paint.paintRight) / 2 - center) < .5, `${item.name}: native rule centred in its gap`);
        assert(Math.abs(paint.top - paper.top) < .5 && Math.abs(paint.bottom - (paper.height - paper.bottom)) < .5,
          `${item.name}: native rule spans the full body height (page ${entry.page})`);
        assert(Math.abs(paint.paintRight - paint.paintLeft - setting.width) < .05, `${item.name}: native rule width equals the getter width`);
        const color = rgb(setting.color);
        const dark = color.map(value => value / 2);
        const expected = setting.style === 'inset' ? [dark] : ['groove', 'ridge'].includes(setting.style) ? [dark, color] : [color];
        assert.deepEqual(paint.paints.map(channels).sort(), expected.map(values => values.map(Math.round)).sort(),
          `${item.name}: native rule paint (${setting.style})`);
        if (setting.width > setting.gap) assert(paint.paintRight - paint.paintLeft > setting.gap, `${item.name}: native rule wider than its gap`);
      }
    }
    if (item.name === 'continuous-in') {
      // The 2-column section's rule starts at the body top although the seam's single-column text is above it.
      const words = native.pages[0].words;
      assert(words.find(word => word.text === 'CRSECOND').y > nativePages[0].paints[0].top + 20, 'continuous-in: native rule covers the single-column part above the seam');
    }

    const source = `colrule-source-${item.name}.4wp`;
    files['Resources/colrule-sentinel.bin'] = Uint8Array.of(0, 255, 52, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `colrule-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/colrule-${item.name}-edited.4wp`)));
    const expected = { flow: { source, action: 'identity' }, resources: source };
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    const external = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith(url) && !request.url().startsWith('data:')) external.push(request.url()); });
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('CRSTART');
      await download(`colrule-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      let browserPages = null;
      let printedPages = null;
      let notices = [];
      if (fallback) {
        await expect(page.locator('#paged-status')).toHaveText(messages.en[fallback]);
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
        await expect(page.locator('#paper')).toContainText('CREND');
      } else {
        const sheets = page.locator('#paged-view .browser-page');
        await expect(sheets.first()).toBeVisible();
        const count = await sheets.count();
        await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
        browserPages = await sheets.evaluateAll(sheets => sheets.map(sheet => {
          const frame = sheet.getBoundingClientRect();
          const pt = value => value * .75;
          const body = sheet.querySelector('.page-body').getBoundingClientRect();
          const columns = [...sheet.querySelectorAll('.page-column')];
          const boxes = columns.map(column => column.getBoundingClientRect());
          return { section: Number(sheet.dataset.section), width: parseFloat(sheet.style.width), height: parseFloat(sheet.style.height),
            reach: columns.findLastIndex(column => column.children.length) + 1,
            body: { top: pt(body.top - frame.top), bottom: pt(body.bottom - frame.top) },
            gaps: boxes.slice(1).map((box, i) => ({ left: pt(boxes[i].right - frame.left), right: pt(box.left - frame.left) })),
            rules: [...sheet.querySelectorAll('.page-column-rule')].map(rule => {
              const box = rule.getBoundingClientRect();
              const length = value => [...value.matchAll(/([\d.]+)(px|pt)?/g)].map(([, number, unit]) => Number(number) * (unit === 'pt' ? 1 : .75));
              return { index: Number(rule.dataset.rule), hidden: rule.getAttribute('aria-hidden'), left: pt(box.left - frame.left), right: pt(box.right - frame.left),
                top: pt(box.top - frame.top), bottom: pt(box.bottom - frame.top),
                pieces: [...rule.querySelectorAll('line')].map(line => {
                  const style = getComputedStyle(line);
                  return { x: line.x1.baseVal.value * .75, width: length(style.strokeWidth)[0], paint: style.stroke,
                    dash: style.strokeDasharray === 'none' ? null : length(style.strokeDasharray) };
                }) };
            }) };
        }));
        for (const sheet of browserPages) {
          const setting = settings[sheet.section - 1];
          const ruled = setting.count > 1 && setting.style !== 'none';
          // The native relation applied to the browser's own pagination.
          assert.deepEqual(sheet.rules.map(rule => rule.index), ruled ? Array.from({ length: Math.max(0, sheet.reach - 1) }, (_, i) => i + 1) : [],
            `${item.name}: browser rules in every gap left of the reached column (native rule)`);
          for (const rule of sheet.rules) {
            const gap = sheet.gaps[rule.index - 1];
            assert.equal(rule.hidden, 'true');
            assert(Math.abs((rule.left + rule.right) / 2 - (gap.left + gap.right) / 2) < .05, `${item.name}: browser rule centred in its gap`);
            assert(Math.abs(rule.right - rule.left - setting.width) < .05, `${item.name}: browser rule box has the native width`);
            assert(Math.abs(rule.top - sheet.body.top) < .05 && Math.abs(rule.bottom - sheet.body.bottom) < .05, `${item.name}: browser rule spans the body`);
            // Comparison mapping derived from native data: the browser's SVG pieces, as offsets from the gap centre,
            // equal the native PDF pieces of the first native rule drawn with the same setting (centre, width, paint, dash).
            const reference = nativePages.find(entry => entry.setting === setting && entry.paints.some(Boolean))?.paints.find(Boolean);
            assert(reference, `${item.name}: a native rule exists for the browser rule's setting`);
            const nativeCenter = (reference.paintLeft + reference.paintRight) / 2;
            const browserCenter = (gap.left + gap.right) / 2;
            const nativeParts = reference.parts.map(part => ({ offset: part.center - nativeCenter, width: part.width, paint: part.paint, dash: part.dash }));
            const browserParts = rule.pieces.map(piece => ({ offset: rule.left + piece.x - browserCenter, width: piece.width, paint: channels(piece.paint), dash: piece.dash }))
              .sort((a, b) => a.offset - b.offset);
            assert.equal(browserParts.length, nativeParts.length, `${item.name}: browser rule has the native piece count`);
            browserParts.forEach((part, i) => {
              const other = nativeParts[i];
              assert(Math.abs(part.offset - other.offset) < .05 && Math.abs(part.width - other.width) < .05, `${item.name}: browser rule piece geometry follows native`);
              assert(part.paint.every((channel, c) => Math.abs(channel - other.paint[c]) <= 1), `${item.name}: browser rule piece paint follows native`);
              assert.equal(Boolean(part.dash), Boolean(other.dash), `${item.name}: browser rule dashing follows native`);
              if (part.dash) assert(part.dash.every((value, d) => Math.abs(value - other.dash[d]) < .05), `${item.name}: browser dash pattern follows native`);
            });
          }
        }
        notices = await page.locator('#paged-objects > p').evaluateAll(entries => entries.map(entry => entry.dataset.notice));
        const expectedNotices = [];
        if (item.requested.table) expectedNotices.push('pagedColumnTables');
        if (browserPages.some(sheet => sheet.rules.length)) expectedNotices.push('pagedColumnRules');
        assert.deepEqual(notices, expectedNotices);
        await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
        await page.locator('#settings-toggle').click();
        await page.locator('#theme').selectOption('dark');
        await page.locator('#zoom').selectOption('2');
        await page.evaluate(() => {
          window.colruleResize = new Promise(resolve => window.addEventListener('resize', resolve, { once: true }));
        });
        await page.setViewportSize({ width: 390, height: 844 });
        await page.evaluate(() => window.colruleResize);
        await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
        const pdf = resolve(directory, `Output/colrule-browser-${item.name}.pdf`);
        await page.pdf({ path: pdf, preferCSSPageSize: true, printBackground: true });
        const printed = inspectPDF(pdf);
        assert.equal(printed.pages.length, count);
        // Printed rules (dark theme): paint in exactly the previewed gaps of each page, over the body, in the document colours.
        printedPages = browserPages.map((sheet, index) => {
          assert(Math.abs(printed.pages[index].width - sheet.width) < 1 && Math.abs(printed.pages[index].height - sheet.height) < 1, 'Unscaled paper');
          const vectors = pageVectors(pdf, index + 1).map(vector => ({ ...bounds(vector), vector }));
          const paints = sheet.gaps.map(gap => gapPaint(vectors, gap, (sheet.body.bottom - sheet.body.top) / 2));
          const drawn = paints.map((paint, i) => (paint ? i + 1 : 0)).filter(Boolean);
          assert.deepEqual(drawn, sheet.rules.map(rule => rule.index), `${item.name}: printed rules equal the preview (page ${index + 1})`);
          const setting = settings[sheet.section - 1];
          for (const paint of paints.filter(Boolean)) {
            // Chrome prints a dashed stroke as its dash segments, so the last segment may end one dash gap above the body
            // bottom (as the native dashed stroke's last dash does).
            const gapLength = { dotted: setting.width, dashed: 3 * setting.width }[setting.style] ?? 0;
            assert(Math.abs(paint.top - sheet.body.top) < 1.5 && paint.bottom <= sheet.body.bottom + 1.5 && paint.bottom >= sheet.body.bottom - gapLength - 1.5,
              `${item.name}: printed rule spans the body`);
            const color = rgb(setting.color);
            const dark = color.map(value => Math.round(value / 2));
            for (const value of paint.paints.map(channels)) {
              assert(value.every((channel, i) => Math.abs(channel - color[i]) <= 1) || value.every((channel, i) => Math.abs(channel - dark[i]) <= 1),
                `${item.name}: printed rule keeps the document colour in the dark theme`);
            }
          }
          return drawn;
        });
        await page.screenshot({ path: resolve(directory, `Output/colrule-${item.name}-mobile.png`) });
        assert(await page.locator('#paged-panel').evaluate(element => element.scrollWidth <= element.clientWidth), 'No mobile panel overflow');
      }
      await download(`colrule-after-${item.name}`, expected, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/colrule-after-${item.name}.4wp`)), Buffer.from(original));
      await page.locator('#paper [contenteditable]').first().fill('WEBCR');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`colrule-edited-${item.name}`, edited, page);
      if (!fallback) await expect(page.locator('#paged-view .browser-page').first()).toContainText('WEBCR');
      else await expect(page.locator('#paged-status')).toHaveText(messages.en[fallback]);
      await page.locator('#undo').click();
      await download(`colrule-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`colrule-recovered-redo-${item.name}`, edited, page);
      assert.deepEqual(errors, []);
      assert.deepEqual(external, []);
      // Comparison facts: native and browser pages are paginated independently, so the native relation is asserted in
      // each rendering; the per-page rule lists are recorded side by side (equal only where both paginations agree).
      results.push({ name: item.name, outcome: fallback || 'paged', requested: item.requested, nativeSettings: item.applied,
        nativePages: nativePages.map(entry => ({ page: entry.page, section: entry.section, reach: entry.reach, drawn: entry.drawn,
          paint: entry.paints.map(paint => paint && { left: paint.paintLeft, right: paint.paintRight, top: paint.top, bottom: paint.bottom, paints: paint.paints, pieces: paint.pieces, dash: paint.dash }) })),
        browserPages: browserPages?.map(sheet => ({ section: sheet.section, reach: sheet.reach, rules: sheet.rules.map(rule => rule.index) })) ?? null,
        printedPages, firstPageAgrees: browserPages ? JSON.stringify(browserPages[0].rules.map(rule => rule.index)) === JSON.stringify(nativePages[0].drawn) : null,
        notices, sourceHasRule: /column-rule-style:(?!none)/.test(html), untouchedOriginalBytes: true,
        limits: 'Native rule pages, gaps, full-body extent and paint colours only; line patterns, exact coordinates, ' +
          'column reach per page and page counts are browser-measured, not native parity.' });
    } finally {
      await page.close();
    }
  }
  await writeFile(resolve(directory, 'Output/colrule-browser-report.json'), JSON.stringify(results, null, 2));
}
