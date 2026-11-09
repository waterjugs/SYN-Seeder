// Lets Node load the Worker's own files, which import "cloudflare:workers".
// Node has no such module, so the tests get the small stand-in in
// cloudflare-workers-stub.js instead.
import { register } from 'node:module';

register('./stub-loader.js', import.meta.url);
