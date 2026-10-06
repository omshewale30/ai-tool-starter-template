/** Largest request body the `/api/*` forwarder accepts. Raise it if your API takes uploads. */
export const MAX_FORWARD_BYTES = 1024 * 1024;

/**
 * Reads a request body without ever holding more than `limit` bytes.
 *
 * Returns null when the body is larger than `limit`, so a chunked or dishonest
 * request cannot make the server buffer an unbounded payload.
 */
export async function readBoundedBody(
  stream: ReadableStream<Uint8Array> | null,
  limit: number = MAX_FORWARD_BYTES,
): Promise<ArrayBuffer | null> {
  if (!stream) return new ArrayBuffer(0);

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      if (length + value.byteLength > limit) {
        await reader.cancel().catch(() => undefined);
        return null;
      }
      chunks.push(value);
      length += value.byteLength;
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(new ArrayBuffer(length));
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body.buffer;
}
