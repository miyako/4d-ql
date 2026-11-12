import { DocumentError } from './archive.js';

export function paragraphBreak(values) {
  const page = values['page-break-after'] || 'auto';
  const section = values['-d4-section-break-after'] || 'auto';
  if (!['auto', 'always'].includes(page) || !['auto', 'always', 'continuous'].includes(section) ||
    section === 'always' && page !== 'always' || section === 'continuous' && page !== 'auto') {
    throw new DocumentError('sectionUnsupported');
  }
  return section === 'always' ? 'section' : section === 'continuous' ? 'continuous' : page === 'always' ? 'page' : null;
}

export const breakProperties = {
  page: { 'page-break-after': 'always', '-d4-section-break-after': 'auto' },
  section: { 'page-break-after': 'always', '-d4-section-break-after': 'always' },
  continuous: { 'page-break-after': 'auto', '-d4-section-break-after': 'continuous' },
  paragraph: { 'page-break-after': 'auto', '-d4-section-break-after': 'auto' },
};
