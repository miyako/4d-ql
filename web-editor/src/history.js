import { DocumentError } from './archive.js';

export class LocalHistory {
  async open() {
    if (this.database) return this.database;
    this.database = await new Promise((resolve, reject) => {
      let request;
      try { request = indexedDB.open('4wp-editor-history', 1); }
      catch { reject(new DocumentError('storageError')); return; }
      let blocked = false;
      request.onupgradeneeded = () => request.result.createObjectStore('session');
      request.onsuccess = () => { if (blocked) request.result.close(); else resolve(request.result); };
      request.onerror = () => reject(new DocumentError('storageError'));
      request.onblocked = () => { blocked = true; reject(new DocumentError('storageError')); };
    });
    this.database.onversionchange = () => { this.database.close(); this.database = null; };
    return this.database;
  }

  async read() {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const request = database.transaction('session').objectStore('session').get('active');
      request.onsuccess = () => { this.token = request.result?.token ?? null; resolve(request.result); };
      request.onerror = () => reject(new DocumentError('storageError'));
    });
  }

  async write(record) {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = database.transaction('session', 'readwrite');
      const store = transaction.objectStore('session');
      const request = store.get('active');
      const token = crypto.randomUUID();
      let conflict = false;
      request.onsuccess = () => {
        if ((request.result?.token ?? null) !== (this.token ?? null)) {
          conflict = true;
          transaction.abort();
        } else store.put({ ...record, token }, 'active');
      };
      transaction.oncomplete = () => { this.token = token; resolve(); };
      transaction.onerror = transaction.onabort = () => reject(new DocumentError(conflict ? 'storageConflict' : 'storageError'));
    });
  }
}
