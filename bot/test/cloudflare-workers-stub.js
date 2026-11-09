// The part of Cloudflare's DurableObject base class the bot uses.
export class DurableObject {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }
}
