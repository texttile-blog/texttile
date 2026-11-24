/* A file that travels in pieces.

   The platform in front of the server drops a request body once it
   grows past a few megabytes (Bunny's edge, seen 2026-11-24: a 4 MB
   upload died at 3 MiB, every time, before the server could answer).
   So a file leaves here as 1 MiB pieces, one small request each, in
   order; the server stashes every piece and welds them together when
   the last one lands. A piece that dies on the way costs its own
   megabyte, not the file.

   The pieces ride as the bare body of the request, with the file's
   facts in the query: the token this upload travels under, where the
   piece sits, how many there are, how big the whole file is and the
   name it carries. The last piece's answer is the upload's answer:
   the same JSON the single-request upload always gave.

   sendChunks answers with {abort}, and speaks twice: onAnswer for the
   answer the last piece carried, whatever status, and onLost when a
   piece never became an answer at all. Both run synchronously out of
   the piece's own listeners, like a one-request upload always did. */

const CHUNK = 1024 * 1024

export {CHUNK}

export function sendChunks({url, csrf, file, name, onProgress, onUploaded, onAnswer, onLost, request}) {
  const mk = request || (() => new XMLHttpRequest())
  const token = [...crypto.getRandomValues(new Uint8Array(8))]
    .map(byte => byte.toString(16).padStart(2, "0"))
    .join("")
  const parts = Math.max(1, Math.ceil(file.size / CHUNK))
  let current = null
  let cancelled = false

  const send = index => {
    if (cancelled) return onLost({aborted: true})

    const start = index * CHUNK
    const end = Math.min(start + CHUNK, file.size)
    const last = index === parts - 1
    const xhr = mk()
    current = xhr
    xhr.open("POST", url + "?" + new URLSearchParams({
      upload: token,
      index,
      parts,
      size: file.size,
      name,
    }))
    if (csrf) xhr.setRequestHeader("x-csrf-token", csrf)
    xhr.setRequestHeader("Content-Type", "application/octet-stream")

    xhr.upload.onprogress = e => {
      if (e.lengthComputable) onProgress(Math.min(end, start + e.loaded))
    }
    if (last && onUploaded) xhr.upload.onload = () => onUploaded()

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300 && !last) return send(index + 1)
      onAnswer({status: xhr.status, response: read(xhr)})
    }
    xhr.onerror = xhr.ontimeout = () => onLost({xhr})
    xhr.onabort = () => onLost({aborted: true})

    xhr.send(file.slice(start, end))
  }

  send(0)

  return {abort}

  function abort() {
    cancelled = true
    if (current) current.abort()
  }

  /* a 204 piece answers with an empty body; only the caller knows
     which statuses carry JSON, so an unreadable body is null */
  function read(xhr) {
    try {
      return JSON.parse(xhr.responseText)
    } catch (_e) {
      return null
    }
  }
}
