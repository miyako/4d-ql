import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { unzipSync, zipSync } from 'fflate';
import { expect } from '@playwright/test';
import { messages } from '../src/i18n.js';
import { inspectPDF } from './native-print-cases.mjs';
import { atParity } from './native-continuous-cases.mjs';

// Browser outcome per native shape (wp_contgeom_probe, full 4D 21.2 F0012102). Native PDFs, read page by page with
// pdfinfo page sizes, are the oracle for whether a continuous seam starts a new page, which geometry each page uses
// and which section's header and footer it draws. Never for positions, wrapping or page counts.
export const contgeomShapes = {
  'margin-left': 'paged', 'margin-right': 'paged', 'margin-top': 'paged', 'margin-bottom': 'paged', 'margin-all': 'paged',
  'margin-sides': 'paged', orientation: 'paged', 'orientation-back': 'paged', 'orientation-margin': 'paged',
  'orientation-first': 'paged', 'orientation-none': 'paged', 'margin-left-first': 'paged', 'orientation-long': 'paged',
  'margin-left-long': 'paged', 'margin-top-long': 'paged', 'margin-bottom-long': 'paged', 'orientation-chain': 'paged',
  'margin-chain': 'paged', unicode: 'paged', 'margin-top-only': 'paged', 'margin-bottom-only': 'paged',
  'margin-wider': 'paged', 'margin-wrap': 'paged', 'mixed-chain': 'paged',
};
const areaToken = /CG\d(?:DEFAULT|FIRST|LEFT|RIGHT)(?:HEADER|FOOTER)/g;
const bodyToken = /^(?:CGSTART|CG\d+BODY\d+)$/;
// Body tokens are ASCII words that start their lines; they are read in page position order (top to bottom), because
// pdftotext lists words in content-stream order, which Chromium does not keep for lines that mix in CJK/Greek runs.
const bodyWords = page => page.words.filter(word => bodyToken.test(word.text)).sort((a, b) => a.y - b.y || a.x - b.x).map(word => word.text);
const sectionOf = word => word === 'CGSTART' ? 1 : Number(word.match(/^CG(\d+)BODY/)[1]);
const points = value => {
  const [, number, unit] = String(value).match(/^([\d.]+)(pt|cm)$/);
  return Number(number) * (unit === 'cm' ? 72 / 2.54 : 1);
};
// Native getters (wp_page_stats) for the section's effective paper: orientation swaps the stored width and height.
const paperOf = geometry => {
  const sides = [points(geometry.width), points(geometry.height)];
  const [width, height] = geometry.orientation === 1 ? sides.reverse() : sides;
  return { width, height, top: points(geometry.top), right: points(geometry.right), bottom: points(geometry.bottom), left: points(geometry.left) };
};

// The native membership rule (wp_contheader_probe), independent of the editor.
function ruleAreas(requested, owner, startsHere, pageNumber) {
  const spec = requested[owner - 1];
  if (spec.areas === 'none') return [];
  const variant = startsHere && spec.areas.includes('first') ? 'FIRST' :
    spec.areas.includes('facing') ? (pageNumber % 2 ? 'RIGHT' : 'LEFT') : 'DEFAULT';
  return ['HEADER', 'FOOTER'].map(kind => `CG${owner}${variant}${kind}`).sort();
}
const firstWord = section => section === 1 ? 'CGSTART' : `CG${section}BODY1`;
// A page that holds only continuation lines of a split paragraph belongs to that paragraph's section.
function analyse(pages) {
  let carried = null;
  return pages.map((page, index) => {
    assert(page.body.length || carried, `Every page carries body text (page ${index + 1})`);
    const owner = page.body.length ? sectionOf(page.body[0]) : carried;
    if (page.body.length) carried = sectionOf(page.body.at(-1));
    return { page: index + 1, owner, startsHere: page.body.includes(firstWord(owner)), width: page.width, height: page.height,
      body: page.body, areas: [...page.areas].sort() };
  });
}

export async function prepareContgeomCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/contgeom-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.deepEqual(report.cases.map(item => item.name), Object.keys(contgeomShapes));
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/contgeom-errors.json'), 'utf8')), []);
  const results = [];
  for (const item of report.cases) {
    const outcome = contgeomShapes[item.name];
    const requested = item.requested;
    // Independent native getters: stored areas, sections, continuous breaks and the requested section geometry.
    const stored = item.areas.map(area => `${area.section}:${area.variant}:${area.kind}:${area.text}`).sort();
    const wanted = requested.flatMap((spec, index) => spec.areas === 'none' ? [] : ['DEFAULT',
      ...(spec.areas.includes('first') ? ['FIRST'] : []), ...(spec.areas.includes('facing') ? ['LEFT', 'RIGHT'] : [])]
      .flatMap(variant => ['HEADER', 'FOOTER'].map(kind => `${index + 1}:${variant}:${kind}:CG${index + 1}${variant}${kind}${spec.text || ''}`))).sort();
    assert.deepEqual(stored, wanted, `${item.name}: native area getters`);
    assert.deepEqual(item.reopened, item.sections, `${item.name}: re-imported native section getters`);
    assert.equal(item.sections.sections.length, requested.length);
    assert.deepEqual(item.sections.breaks.map(entry => entry.type).filter(type => type !== 4), item.joins.map(() => 5), `${item.name}: native continuous breaks`);
    const papers = item.sections.sections.map(section => paperOf(section.geometry));
    requested.forEach((spec, index) => {
      const geometry = spec.geometry || {};
      const margins = ['top', 'right', 'bottom', 'left'];
      // Native: a section margin setter stores all four sides; unset sides read back as 2.5cm, not the document's.
      const any = margins.some(side => geometry[side]);
      for (const side of margins) {
        const expected = geometry[side] ? points(geometry[side]) : any ? points('2.5cm') : { top: 60, right: 30, bottom: 60, left: 30 }[side];
        assert(Math.abs(papers[index][side] - expected) < .01, `${item.name}: section ${index + 1} ${side} margin getter`);
      }
      assert.deepEqual([papers[index].width, papers[index].height], geometry.orientation === 'landscape' ? [360, 300] : [300, 360],
        `${item.name}: section ${index + 1} paper getter`);
    });
    const pdfPath = resolve(directory, `Output/contgeom-${item.name}.pdf`);
    const native = inspectPDF(pdfPath);
    const reopened = inspectPDF(resolve(directory, `Output/contgeom-${item.name}-reopened.pdf`));
    assert.deepEqual(reopened.pages.map(page => [page.width, page.height, page.words.map(word => word.text)]),
      native.pages.map(page => [page.width, page.height, page.words.map(word => word.text)]), `${item.name}: stored file alone reproduces the native PDF`);
    // pdfinfo page sizes are an independent reading of the same PDF's media boxes.
    const info = execFileSync('pdfinfo', ['-f', '1', '-l', String(native.pages.length), pdfPath], { encoding: 'utf8' });
    assert.deepEqual([...info.matchAll(/^Page\s+\d+ size:\s+([\d.]+) x ([\d.]+) pts/gm)].map(match => [Number(match[1]), Number(match[2])]),
      native.pages.map(page => [page.width, page.height]), `${item.name}: pdfinfo page sizes`);
    const nativePages = analyse(native.pages.map(page => ({ width: page.width, height: page.height,
      body: bodyWords(page), areas: page.words.map(word => word.text).join(' ').match(areaToken) || [] })));
    assert.deepEqual(nativePages.flatMap(page => page.body), ['CGSTART', ...requested.flatMap((spec, index) =>
      Array.from({ length: spec.length }, (_, line) => `CG${index + 1}BODY${line + 1}`))], `${item.name}: every native paragraph once, in order`);
    // The native geometry rule: every page has its owner's paper; an orientation seam starts a new page, a margin seam
    // shares one; each body word starts at its own section's left margin; areas follow the membership rule.
    for (const page of nativePages) {
      assert.deepEqual([page.width, page.height], [papers[page.owner - 1].width, papers[page.owner - 1].height], `${item.name}: native page ${page.page} paper`);
      assert.deepEqual(page.areas, ruleAreas(requested, page.owner, page.startsHere, page.page), `${item.name}: native page ${page.page} areas`);
    }
    const seams = item.joins.map((join, index) => {
      const turned = papers[index].width !== papers[index + 1].width;
      const at = nativePages.find(page => page.body.includes(`CG${index + 2}BODY1`));
      assert.equal(at.body[0] === `CG${index + 2}BODY1`, turned, `${item.name}: seam ${index + 1} ${turned ? 'starts a new page' : 'shares the page'}`);
      return turned ? 'page' : 'shared';
    });
    native.pages.forEach((page, index) => {
      let section = 1;
      for (const word of page.words) {
        if (!bodyToken.test(word.text)) continue;
        section = sectionOf(word.text);
        assert(Math.abs(word.x - papers[section - 1].left) < .5, `${item.name}: native ${word.text} on page ${index + 1} at its section's left margin`);
      }
      // A shared page keeps the vertical geometry of the section at its top, whatever the incoming section stores.
      const ownerPaper = papers[nativePages[index].owner - 1];
      for (const word of page.words.filter(word => bodyToken.test(word.text))) {
        assert(word.y >= ownerPaper.top - 1 && word.bottom <= page.height - ownerPaper.bottom + 1,
          `${item.name}: native ${word.text} on page ${index + 1} within the page owner's top/bottom margins`);
      }
    });
    if (item.name === 'margin-wrap') {
      // Wrapping width changes at the break: section 1 lines exceed section 2's right limit, section 2 lines never do.
      let section = 1;
      const rights = { 1: 0, 2: 0 };
      for (const word of native.pages[0].words) {
        if (bodyToken.test(word.text)) section = sectionOf(word.text);
        else if (word.y > 40 && word.bottom < 300) rights[section] = Math.max(rights[section], word.right);
      }
      assert(rights[1] > 300 - 120 && rights[2] <= 300 - 120 + .5, `${item.name}: native wrapping width follows each section's margins`);
    }
    const files = unzipSync(await readFile(resolve(directory, `Output/contgeom-${item.name}-original.4wp`)));
    files['Resources/contgeom-sentinel.bin'] = Uint8Array.of(0, 255, 43, 128);
    const original = zipSync(files);
    const source = `contgeom-source-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `contgeom-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/contgeom-${item.name}-edited.4wp`)));
    const expected = { flow: { source, action: 'identity' }, resources: source };
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    const external = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith(url) && !request.url().startsWith('data:')) external.push(request.url()); });
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('CGSTART');
      await download(`contgeom-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      let browserPages = [];
      let printedAreas = [];
      let notices = [];
      if (outcome === 'fallback') {
        await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedContinuous);
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
      } else {
        const sheets = page.locator('#paged-view .browser-page');
        await expect(sheets.first()).toBeVisible();
        const count = await sheets.count();
        await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
        const measured = await sheets.evaluateAll(sheets => sheets.map(sheet => {
          const frame = sheet.getBoundingClientRect();
          return {
            owner: Number(sheet.dataset.section), width: Math.round(frame.width * .75), height: Math.round(frame.height * .75),
            body: [...sheet.querySelectorAll('.page-body')].flatMap(body => body.textContent.match(/CGSTART|CG\d+BODY\d+/g) || []),
            texts: [...sheet.querySelectorAll(':scope > .page-area')].map(area => area.textContent),
            sections: (sheet.dataset.sections || '').split(' ').map(Number),
            // Free height left below the last block, and the height of this sheet's first block, in points.
            remaining: (() => {
              const bodies = [...sheet.querySelectorAll('.page-body')];
              const body = bodies.at(-1);
              const last = body.lastElementChild;
              return last ? (body.getBoundingClientRect().bottom - last.getBoundingClientRect().bottom) * .75 : Infinity;
            })(),
            firstHeight: (sheet.querySelector('.page-body').firstElementChild?.getBoundingClientRect().height || 0) * .75,
            margins: [...sheet.querySelectorAll('.page-body p[data-section]')].map(paragraph => ({ section: Number(paragraph.dataset.section),
              left: (paragraph.getBoundingClientRect().left - frame.left) * .75, right: (frame.right - paragraph.getBoundingClientRect().right) * .75 })),
          };
        }));
        browserPages = analyse(measured.map(sheet => ({ width: sheet.width, height: sheet.height, body: sheet.body,
          areas: sheet.texts.join(' ').match(areaToken) || [] })));
        assert.deepEqual(browserPages.flatMap(sheet => sheet.body), nativePages.flatMap(sheet => sheet.body), `${item.name}: every browser paragraph once, in order`);
        browserPages.forEach((sheet, index) => {
          assert.equal(measured[index].owner, sheet.owner, `${item.name}: browser sheet owner is the section at its top`);
          assert.deepEqual([sheet.width, sheet.height], [papers[sheet.owner - 1].width, papers[sheet.owner - 1].height], `${item.name}: browser sheet ${sheet.page} paper`);
          assert.deepEqual(sheet.areas, ruleAreas(requested, sheet.owner, sheet.startsHere, sheet.page), `${item.name}: browser sheet ${sheet.page} follows the native rule`);
          for (const margin of measured[index].margins) {
            assert(Math.abs(margin.left - papers[margin.section - 1].left) < .25 && Math.abs(margin.right - papers[margin.section - 1].right) < .25,
              `${item.name}: browser sheet ${sheet.page} uses each section's own left/right margins`);
          }
        });
        // The browser applies the native decision: an orientation seam always starts a new sheet; a margin seam keeps
        // filling the shared sheet, so the incoming section moves on only when its first block did not fit there.
        seams.forEach((kind, index) => {
          const last = measured.findLastIndex(sheet => sheet.sections.includes(index + 1));
          const next = measured[last + 1];
          if (kind === 'page') {
            assert(!measured[last].sections.includes(index + 2) && next.owner === index + 2, `${item.name}: browser seam ${index + 1} starts a new sheet`);
          } else {
            assert(measured[last].sections.includes(index + 2) || measured[last].remaining < next.firstHeight,
              `${item.name}: browser seam ${index + 1} shares the sheet`);
          }
        });
        // Cross-check against the native PDF itself: page 1 and each section's first own page carry the same areas.
        // Left/right is mapped by physical parity where the browser's page number differs from 4D's (atParity).
        assert.deepEqual(browserPages[0].areas, nativePages[0].areas, `${item.name}: page 1 areas`);
        for (let section = 1; section <= requested.length; section++) {
          const nativeFirst = nativePages.find(entry => entry.owner === section);
          const browserFirst = browserPages.find(entry => entry.owner === section);
          assert.equal(Boolean(browserFirst), Boolean(nativeFirst), `${item.name}: section ${section} owns a page in both renderings`);
          if (nativeFirst) {
            assert.deepEqual(browserFirst.areas, atParity(nativeFirst.areas, nativeFirst.page, browserFirst.page), `${item.name}: first page owned by section ${section}`);
            assert.deepEqual([browserFirst.width, browserFirst.height], [nativeFirst.width, nativeFirst.height], `${item.name}: section ${section} paper in both renderings`);
          }
        }
        for (const text of measured.flatMap(sheet => sheet.texts)) {
          assert(item.areas.some(area => area.text === text.trim()), `${item.name}: complete area text ${text}`);
        }
        notices = await page.locator('#paged-objects > p').evaluateAll(items => items.map(entry => entry.dataset.notice));
        const sharedAreas = seams.some((kind, index) => kind === 'shared' && (requested[index].areas !== 'none' || requested[index + 1].areas !== 'none'));
        assert.deepEqual(notices, [...(sharedAreas ? ['pagedSeamAreas'] : []), 'pagedSeamGeometry']);
        await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
        await page.locator('#settings-toggle').click();
        await page.locator('#theme').selectOption('dark');
        await page.locator('#zoom').selectOption('2');
        await page.evaluate(() => {
          window.contgeomResize = new Promise(resolve => window.addEventListener('resize', resolve, { once: true }));
        });
        await page.setViewportSize({ width: 390, height: 844 });
        await page.evaluate(() => window.contgeomResize);
        await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
        const pdf = resolve(directory, `Output/contgeom-browser-${item.name}.pdf`);
        await page.pdf({ path: pdf, preferCSSPageSize: true, printBackground: true });
        const printed = inspectPDF(pdf);
        assert.equal(printed.pages.length, count + await page.locator('#paged-view .paged-unused').count());
        printedAreas = printed.pages.slice(0, count).map(sheet => (sheet.words.map(word => word.text).join(' ').match(areaToken) || []).sort());
        assert.deepEqual(printedAreas, browserPages.map(sheet => sheet.areas), `${item.name}: printed pages carry exactly the previewed areas`);
        assert.deepEqual(printed.pages.slice(0, count).map(bodyWords),
          browserPages.map(sheet => sheet.body), `${item.name}: printed body membership`);
        assert.deepEqual(printed.pages.slice(0, count).map(sheet => [Math.round(sheet.width), Math.round(sheet.height)]),
          browserPages.map(sheet => [sheet.width, sheet.height]), `${item.name}: printed paper per page`);
      }
      await download(`contgeom-after-${item.name}`, expected, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/contgeom-after-${item.name}.4wp`)), Buffer.from(original));
      await page.locator('#paper [contenteditable]').first().fill('WEBCG');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`contgeom-edited-${item.name}`, edited, page);
      if (outcome === 'paged') await expect(page.locator('#paged-view .browser-page').first()).toContainText('WEBCG');
      else await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedContinuous);
      await page.locator('#undo').click();
      await download(`contgeom-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`contgeom-recovered-redo-${item.name}`, edited, page);
      assert.deepEqual(errors, []);
      assert.deepEqual(external, []);
      results.push({ name: item.name, outcome, requested, joins: item.joins, seams,
        nativePages: nativePages.map(({ body, ...page }) => ({ ...page, firstBody: body[0], lastBody: body.at(-1) })),
        browserPages: browserPages.map(({ body, ...page }) => ({ ...page, firstBody: body[0], lastBody: body.at(-1) })), printedAreas, notices,
        untouchedOriginalBytes: true,
        limits: 'Native new-page/shared-page decision, per-page paper, per-section left/right margins and area page membership only; no position, wrapping or page-count parity. Browser pages are measured by the browser.' });
    } finally {
      await page.close();
    }
  }
  await writeFile(resolve(directory, 'Output/contgeom-browser-report.json'), JSON.stringify(results, null, 2));
}
