import { readFileSync } from 'node:fs';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [{
    name: 'distribution-licenses',
    generateBundle() {
      const notices = [
        ['4WP Studio', '../LICENSE'],
        ['fflate', 'node_modules/fflate/LICENSE'],
        ['css-tree', 'node_modules/css-tree/LICENSE'],
        ['mdn-data', 'node_modules/mdn-data/LICENSE'],
        ['source-map-js', 'node_modules/source-map-js/LICENSE'],
      ].map(([name, path]) => `${name}\n${'='.repeat(name.length)}\n\n${readFileSync(new URL(path, import.meta.url), 'utf8')}`);
      this.emitFile({ type: 'asset', fileName: 'THIRD_PARTY_NOTICES.txt', source: notices.join('\n\n') });
    },
  }],
});
