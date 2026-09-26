// Client for the local viewer: verbs and live events over one /ws socket
// (Contract C in coms/PROTOCOL.md), and the view state kept in the URL query.

export type Color = 'white' | 'black';

export interface Awaiting {
  slot: number;
  color: Color;
  seat: string;
  external: boolean;
  game_id: string;
  ply: number;
  since: number;
}

export interface ChessEvent {
  session_id: string;
  kind: string;
  seq: number | null;
  data: any;
}

export class ApiError extends Error {
  constructor(public code: string, message: string) {
    super(message);
  }
}

type Pending = { resolve: (v: any) => void; reject: (e: ApiError) => void };

let sock: WebSocket | null = null;
let open = false;
let nextId = 1;
const pending = new Map<number, Pending>();
const outbox: string[] = [];
const eventListeners = new Set<(e: ChessEvent) => void>();
const statusListeners = new Set<(live: boolean) => void>();

function connect(): void {
  if (sock) return;
  const url = new URL('ws', window.location.href);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  const s = new WebSocket(url);
  sock = s;
  s.onopen = () => {
    open = true;
    for (const text of outbox.splice(0)) s.send(text);
    for (const fn of statusListeners) fn(true);
  };
  s.onmessage = (ev) => {
    if (typeof ev.data !== 'string') return;
    let frame: any;
    try {
      frame = JSON.parse(ev.data);
    } catch {
      return;
    }
    if (frame.event) {
      for (const fn of eventListeners) fn(frame.event);
      return;
    }
    const waiter = pending.get(frame.id);
    if (!waiter) return;
    pending.delete(frame.id);
    if (frame.ok) waiter.resolve(frame.result);
    else waiter.reject(new ApiError(frame.error?.code ?? 'error', frame.error?.message ?? 'request failed'));
  };
  s.onclose = () => {
    sock = null;
    const wasOpen = open;
    open = false;
    for (const waiter of pending.values()) waiter.reject(new ApiError('disconnected', 'lost the connection to the viewer'));
    pending.clear();
    if (wasOpen) for (const fn of statusListeners) fn(false);
    setTimeout(connect, 1000);
  };
}

export function call<T = any>(verb: string, args: Record<string, unknown> = {}): Promise<T> {
  connect();
  const id = nextId++;
  const text = JSON.stringify({ id, verb, args });
  return new Promise<T>((resolve, reject) => {
    pending.set(id, { resolve, reject });
    if (open) sock!.send(text);
    else outbox.push(text);
  });
}

/** Receive events until the returned function is called. `onStatus` reports connection changes. */
export function subscribe(onEvent: (e: ChessEvent) => void,
                          onStatus?: (live: boolean) => void): () => void {
  connect();
  eventListeners.add(onEvent);
  if (onStatus) statusListeners.add(onStatus);
  return () => {
    eventListeners.delete(onEvent);
    if (onStatus) statusListeners.delete(onStatus);
  };
}

/** Start receiving a session's events, and return a fresh `{seq, snapshot}`. */
export const follow = (sid: string) => call('follow', { session_id: sid });

export function unfollow(sid: string): void {
  if (open) void call('unfollow', { session_id: sid }).catch(() => {});
}

export type View =
  | { screen: 'lobby' }
  | { screen: 'live'; sid: string }
  | { screen: 'replay'; save: string | null; session: string | null; game: string | null };

export function readView(): View {
  const q = new URLSearchParams(window.location.search);
  const sid = q.get('sid');
  if (sid) return { screen: 'live', sid };
  const replay = q.get('replay');
  if (replay) {
    const session = replay.startsWith('session:') ? replay.slice('session:'.length) : null;
    return { screen: 'replay', save: session ? null : replay, session, game: q.get('game') };
  }
  return { screen: 'lobby' };
}

export function go(params: Record<string, string | null | undefined> = {}): void {
  const url = new URL(window.location.href);
  url.search = '';
  for (const [k, v] of Object.entries(params)) if (v) url.searchParams.set(k, v);
  window.history.pushState(null, '', url);
  window.dispatchEvent(new PopStateEvent('popstate'));
}

export const REASONS: Record<string, string> = {
  checkmate: 'checkmate',
  stalemate: 'stalemate',
  insufficient_material: 'insufficient material',
  seventyfive_moves: '75-move rule',
  fivefold_repetition: 'fivefold repetition',
  max_plies: 'move cap reached',
  resignation: 'resignation',
  illegal_move: 'illegal-move forfeit',
  timeout: 'timeout',
  disconnect: 'bot disconnected',
  protocol_error: 'bot protocol error',
  stopped: 'session stopped',
};

export const isExternal = (name: string | null | undefined) => !!name && name.startsWith('@');

export function randomColor(): Color {
  return Math.random() < 0.5 ? 'white' : 'black';
}
