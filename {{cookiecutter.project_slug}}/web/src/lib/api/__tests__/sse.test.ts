import { describe, expect, it } from "vitest";

import { readServerSentEvents } from "@/lib/api/sse";

function streamOf(...chunks: string[]): Response {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const chunk of chunks) controller.enqueue(encoder.encode(chunk));
      controller.close();
    },
  });
  return new Response(body);
}

async function collect(response: Response) {
  const events = [];
  for await (const event of readServerSentEvents(response)) events.push(event);
  return events;
}

describe("readServerSentEvents", () => {
  it("parses events split across arbitrary chunk boundaries", async () => {
    const events = await collect(
      streamOf('event: delta\ndata: {"te', 'xt": "Hel"}\n\nevent: del', 'ta\ndata: {"text": "lo"}\n\n'),
    );
    expect(events).toEqual([
      { event: "delta", data: { text: "Hel" } },
      { event: "delta", data: { text: "lo" } },
    ]);
  });

  it("handles CRLF line endings and a final event without a trailing blank line", async () => {
    const events = await collect(streamOf('event: done\r\ndata: {"model": "m"}'));
    expect(events).toEqual([{ event: "done", data: { model: "m" } }]);
  });
});
