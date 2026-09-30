// Keep raw messages/stacks private: they can contain URLs, tokens or page data.
const TYPES = new Set(['Error', 'TypeError', 'ReferenceError', 'RangeError', 'SyntaxError', 'TimeoutError', 'AggregateError']);
const FILES = new Set(['test-remote-native.mjs', 'controller.mjs', 'stability.mjs']);
export function failureMetadata(error) {
  const kind = TYPES.has(error?.name) ? error.name : 'OtherError';
  const frames = [];
  const stack = typeof error?.stack === 'string' ? error.stack.slice(0, 8192) : '';
  for (const match of stack.matchAll(/(?:[/\\])([a-z-]+\.mjs):(\d{1,6}):(\d{1,6})(?:\)|\s|$)/g)) {
    if (!FILES.has(match[1]) || frames.length >= 3) continue;
    const line = Number(match[2]), column = Number(match[3]);
    if (line > 0 && column > 0) frames.push({ source: match[1], line, column });
  }
  return { exception_type: kind, source_locations: frames };
}
