/* Gallery files kept in this browser until the server has them.

   A phone drops a tab in the background, a reload ends the page, and
   the picked file went with it. So every file the gallery sends is
   written to IndexedDB first, under the upload url of its entry, and
   leaves when the server took it or its admin removed it. The next
   editor of that entry finds what is left and offers it again.

   Nothing here is needed for an upload to work: a browser without
   IndexedDB, or one that is out of room, uploads exactly as before and
   only forgets on a reload. Every call swallows its errors for that
   reason. */

const DB = "texttile-uploads"
const STORE = "files"
/* a file nobody came back for in a month is not coming back */
const KEEP_MS = 30 * 24 * 60 * 60 * 1000

let opening = null

function db() {
  if (!opening) {
    opening = new Promise((resolve, reject) => {
      const req = indexedDB.open(DB, 1)
      req.onupgradeneeded = () => {
        const store = req.result.createObjectStore(STORE, {keyPath: "key"})
        store.createIndex("place", "place")
        store.createIndex("at", "at")
      }
      req.onsuccess = () => resolve(req.result)
      req.onerror = () => reject(req.error)
    })
    opening.catch(() => { opening = null })
  }
  return opening
}

function run(mode, work) {
  return db().then(conn => new Promise((resolve, reject) => {
    const tx = conn.transaction(STORE, mode)
    const result = work(tx.objectStore(STORE))
    tx.oncomplete = () => resolve(result && result.result)
    tx.onerror = tx.onabort = () => reject(tx.error)
  }))
}

/* Keeps a file for an entry and gives its key back at once, so the
   upload does not wait for the disk. A forget that follows lands after
   the write: IndexedDB runs write transactions on one store in the
   order they were opened. */
export function keep(place, file) {
  const key = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2)
  run("readwrite", store => store.put({key, place, file, name: file.name, type: file.type, at: Date.now()}))
    .catch(() => {})
  return key
}

export function forget(key) {
  if (!key) return Promise.resolve()
  return run("readwrite", store => store.delete(key)).catch(() => {})
}

/* The files an entry still owes the server, oldest first, as Files
   again. Anything past KEEP_MS, of any entry, is thrown away first. */
export async function waiting(place) {
  try {
    await run("readwrite", store => {
      const old = store.index("at").openKeyCursor(IDBKeyRange.upperBound(Date.now() - KEEP_MS))
      old.onsuccess = () => {
        const cursor = old.result
        if (!cursor) return
        store.delete(cursor.primaryKey)
        cursor.continue()
      }
    })
    const left = await run("readonly", store => store.index("place").getAll(place))
    return (left || [])
      .sort((a, b) => a.at - b.at)
      .map(item => ({key: item.key, file: new File([item.file], item.name, {type: item.type})}))
  } catch (_e) {
    return []
  }
}
