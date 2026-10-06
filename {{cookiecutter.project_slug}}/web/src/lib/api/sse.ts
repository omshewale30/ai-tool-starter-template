/**
 * Reads a server-sent event stream from a fetch() Response.
 *
 * fetch() rather than EventSource, because EventSource cannot send the
 * Authorization header. Yields `{ event, data }` with `data` JSON-parsed.
 */
export interface ServerSentEvent<T = unknown> {
  event: string;
  data: T;
}

function parseBlock(block: string): ServerSentEvent | null {
  let event = "message";
  const data: string[] = [];
  for (const line of block.split("\n")) {
    if (line.startsWith("event:")) event = line.slice(6).trim();
    else if (line.startsWith("data:")) data.push(line.slice(5).trimStart());
  }
  if (data.length === 0) return null;
  return { event, data: JSON.parse(data.join("\n")) };
}

export async function* readServerSentEvents(response: Response): AsyncGenerator<ServerSentEvent> {
  if (!response.body) return;
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += value.replace(/\r\n/g, "\n");
      let boundary: number;
      while ((boundary = buffer.indexOf("\n\n")) !== -1) {
        const parsed = parseBlock(buffer.slice(0, boundary));
        buffer = buffer.slice(boundary + 2);
        if (parsed) yield parsed;
      }
    }
    const last = parseBlock(buffer.trim());
    if (last) yield last;
  } finally {
    reader.releaseLock();
  }
}
