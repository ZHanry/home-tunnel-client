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

// Machine values only, captured before Playwright drops custom Error fields.
const SESSION_CREATE_CODES = new Set([
  'RD_SESSION_LIMIT', 'RD_RATE_LIMITED', 'RD_PAIRING_REQUIRED', 'RD_GRANT_CONSUMED',
  'RD_HOST_UNAVAILABLE', 'RD_SCOPE_DENIED', 'RD_GRANT_REVOKED', 'RD_DISABLED',
  'RD_AUTH_REQUIRED', 'RD_AUTHORIZATION_INVALID', 'RD_SESSION_REVOKED',
  'RD_PROTOCOL_UNSUPPORTED', 'RD_IDEMPOTENCY_CONFLICT', 'RD_SIGNAL_BUDGET',
  'RD_INVITE_REQUIRED', 'RD_INVITE_INVALID', 'RD_SCOPE_UNSUPPORTED',
  'SESSION_REVOKED', 'USER_DISABLED', 'VALIDATION_ERROR', 'INTERNAL_ERROR',
]);
export function sessionCreateErrorMetadata(error) {
  return {
    error_code: SESSION_CREATE_CODES.has(error?.code) ? error.code : 'UNRECOGNIZED_API_FAILURE',
    http_status: Number.isInteger(error?.status) && error.status >= 400 && error.status <= 599 ? error.status : null,
  };
}
