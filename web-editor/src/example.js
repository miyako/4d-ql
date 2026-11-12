import { WriteProDocument } from './document.js';

export function createExampleDocument() {
  const styles = `
body { -d4-version:2.20;background-color:#FFFFFF }
p,li { white-space:pre-wrap;margin:0pt 0pt 12pt;padding:0pt;-d4-font:'Georgia';font-family:'Georgia';font-size:10.5pt;line-height:155%;color:#334155 }
p.Normal,li.Normal { white-space:pre-wrap }
p.Kicker { -d4-font:'Arial';font-family:'Arial';font-size:8pt;letter-spacing:1.5pt;color:#60758F;margin:0pt 0pt 16pt }
p.Title { font-size:30pt;line-height:115%;color:#234F7D;margin:0pt 0pt 14pt }
p.Lead { font-size:12pt;line-height:150%;color:#62748A;margin:0pt 0pt 22pt }
p.Section { -d4-font:'Arial Bold';font-family:'Arial';font-size:9pt;font-weight:bold;color:#2769AB;margin:18pt 0pt 8pt }
p.Quote { font-size:14pt;font-style:italic;line-height:145%;color:#234F7D;margin:18pt 0pt;padding:0pt 0pt 0pt 14pt;border-style:none none none solid;border-width:2pt;border-color:#80ADD9 }
span.Emphasis { font-weight:bold }
table { border-collapse:collapse;width:100%;margin:4pt 0pt 0pt }
td { vertical-align:top;padding:7pt 0pt;border-style:none none solid;border-width:0.5pt;border-color:#DCE5EF }
td.Label { width:27%;padding:7pt 12pt 7pt 0pt }
p.TableText { margin:0pt;font-size:9.5pt;line-height:145% }
p.TableLabel { -d4-font:'Arial';font-family:'Arial';font-size:8pt;line-height:170%;color:#62748A;margin:0pt }
p.Footnote { -d4-font:'Arial';font-family:'Arial';font-size:8pt;color:#718096;margin:20pt 0pt 0pt }
`;
  const body = [
    '<p class="Kicker">NORTH ROOM   /   CONCEPT BRIEF</p>',
    '<p class="Title">A room for<br/>slower afternoons.</p>',
    '<p class="Lead">A neighbourhood reading room, built around daylight, good books and the pleasure of staying a little longer.</p>',
    '<p class="Section">The idea</p>',
    '<p class="Normal">The corner shop on the north side of the square has been empty for a year. We see a chance to give it a quieter second life: a shared table by the window, comfortable chairs along the shelves, and coffee that never comes with a time limit.</p>',
    '<p class="Normal">This is <span class="Emphasis">a living room for the neighbourhood</span>, not another workspace. People should feel equally welcome with a novel, a notebook or nothing planned at all.</p>',
    '<p class="Quote">The best measure of the room will be how often someone decides to stay for one more chapter.</p>',
    '<p class="Section">A modest beginning</p>',
    '<p class="Normal">Start with fewer things, chosen well. Keep the existing timber floor, borrow the first collection from local readers, and leave enough space for the room to find its own rhythm.</p>',
    '<table><tr><td class="Label"><p class="TableLabel">Space</p></td><td><p class="TableText">58 m&#xB2;, with windows facing the square</p></td></tr>',
    '<tr><td class="Label"><p class="TableLabel">First phase</p></td><td><p class="TableText">18 reading seats, one shared table, a small coffee counter</p></td></tr>',
    '<tr><td class="Label"><p class="TableLabel">Opening</p></td><td><p class="TableText">Six quiet weeks to try things out, with a conversation every Friday</p></td></tr></table>',
    '<p class="Footnote">Working draft &#xB7; November 2026</p>',
  ].join('');
  return new WriteProDocument(
    `<html xmlns="http://www.w3.org/1999/xhtml" xmlns:d4="http://www.4D.com"><head><title>North Room - concept brief</title><meta name="description" content="A proposal for a neighbourhood reading room"/><style type="text/css">${styles}</style></head><body>${body}</body></html>`,
    {},
    'North Room.html',
  );
}
