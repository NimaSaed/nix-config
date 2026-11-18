/**
 * tmux-status — mirror Pi's session into the enclosing tmux window.
 *
 * - Renames the tmux window to "<glyph> <session name | cwd basename>".
 * - Sets the window user option `@pi_state` (idle|working|blocked|done) so
 *   tmux formats/filters can find Pi windows (see `prefix + P` in tmux.nix).
 * - Colors the window's status-bar entry when Pi needs you.
 *
 * No-op outside tmux or in non-interactive modes (-p / --mode json).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { basename } from "node:path";

type State = "idle" | "working" | "blocked" | "done";

// Glyph prefixed to the window name per state.
const GLYPH: Record<State, string> = {
	idle: "○", // Pi is open, nothing running
	working: "●", // agent run in progress
	blocked: "?", // a dialog is waiting for you (confirm/select/input)
	done: "✓", // run finished, waiting for your next prompt
};

// tmux `window-status-style` per state; empty string = inherit global style.
const STYLE: Record<State, string> = {
	idle: "",
	working: "",
	blocked: "fg=yellow,bold",
	done: "fg=green,bold",
};

export default function (pi: ExtensionAPI) {
	const pane = process.env.TMUX_PANE;
	if (!process.env.TMUX || !pane) return;

	let enabled = false;
	let state: State = "idle";
	let name = "";
	let cwd = "";
	// Serialize tmux calls so out-of-order events can't leave a stale name.
	let queue: Promise<unknown> = Promise.resolve();

	const tmux = (...args: string[]) =>
		pi.exec("tmux", args, { timeout: 2000 }).catch(() => undefined);

	function render() {
		if (!enabled) return;
		const title = name || basename(cwd) || "pi";
		const style = STYLE[state];
		queue = queue.then(async () => {
			await tmux("rename-window", "-t", pane, `${GLYPH[state]} ${title}`);
			await tmux("set-option", "-w", "-t", pane, "@pi_state", state);
			await (style
				? tmux("set-option", "-w", "-t", pane, "window-status-style", style)
				: tmux("set-option", "-w", "-t", pane, "-u", "window-status-style"));
		});
	}

	function set(next: State) {
		if (state === next) return;
		state = next;
		render();
	}

	pi.on("session_start", (_event, ctx) => {
		enabled = ctx.hasUI;
		cwd = ctx.cwd;
		name = pi.getSessionName() ?? "";
		state = ctx.isIdle() ? "idle" : "working";
		render();
	});

	pi.on("session_info_changed", (event) => {
		name = event.name ?? "";
		render();
	});

	pi.on("agent_start", () => set("working"));

	pi.on("agent_settled", (event) => set(event.aborted ? "idle" : "done"));

	pi.on("ui_prompt_start", () => set("blocked"));

	pi.on("ui_prompt_end", (_event, ctx) => set(ctx.isIdle() ? "idle" : "working"));

	// Hand the window back to tmux. Only on real exit: /new, /resume, /reload
	// and /fork replace the runtime and the next instance re-renders.
	pi.on("session_shutdown", async (event) => {
		if (!enabled || event.reason !== "quit") return;
		enabled = false;
		await queue;
		await tmux("set-option", "-w", "-t", pane, "-u", "@pi_state");
		await tmux("set-option", "-w", "-t", pane, "-u", "window-status-style");
		await tmux("set-option", "-w", "-t", pane, "automatic-rename", "on");
	});
}
