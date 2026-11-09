// The seed-call flag: one small Cloudflare Durable Object that every request
// shares. Cloudflare runs one copy of it at a time and lets one call into it
// finish its storage work before the next starts, so two /seed commands at
// the same moment can't both get past the limits.

import { DurableObject } from 'cloudflare:workers';
import { checkLimits, liveCall, normalState, recordCall } from './rules.js';

export class SeedFlag extends DurableObject {
  async _state() {
    return normalState(await this.ctx.storage.get('state'));
  }

  // The latest call while PCs should act on it, as { id, calledAt }, or null.
  async latest() {
    return liveCall(await this._state(), Date.now());
  }

  // Whether a new call would be allowed now, without making one.
  async peek() {
    return checkLimits(await this._state(), Date.now());
  }

  // Makes a call with the random ID ``id`` if the limits allow it and it isn't
  // past ``deadline`` (a Date.now() time). A call stored after Discord has
  // given up waiting for the reply would reach the PCs with no message in the
  // channel naming who called, so a late one is refused. The time is checked
  // here, in the flag, so a call that Cloudflare retries can't slip in late
  // either. The Worker makes the ID, so that if this answer gets lost on the
  // way back, it can still find out whether its call was stored.
  // Returns { ok: true, id, calledAt }, { ok: false, reason: 'late' }, or
  // what checkLimits says.
  async call(deadline, id) {
    if (typeof id !== 'string' || !/^[0-9a-f]{32}$/.test(id)) {
      throw new TypeError('call() needs a call ID of 32 hex characters');
    }
    const state = await this._state();
    const now = Date.now();
    if (!(now <= deadline)) return { ok: false, reason: 'late' };
    const verdict = checkLimits(state, now);
    if (!verdict.ok) return verdict;
    await this.ctx.storage.put('state', recordCall(state, now, id));
    return { ok: true, id, calledAt: now };
  }
}
