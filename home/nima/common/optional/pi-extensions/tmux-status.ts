/**
 * tmux-status — mirror Pi's session into the enclosing tmux window.
 *
 * - Renames the tmux window to "<glyph> <session name | cwd basename>".
 * - Sets the window user option `@pi_state` (idle|working|blocked|done) so
 *   tmux formats/filters can find Pi windows (see `prefix + P` in tmux.nix).
 * - Colors the window's status-bar entry when Pi needs you.
 * - Sends a desktop notification (notify-send) when a run finishes or a
 *   dialog starts waiting for you, unless you are already looking at the pane
 *   or are attached over SSH (the card would show on this machine's desktop).
 *
 * No-op outside tmux or in non-interactive modes (-p / --mode json).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
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

// Pid of the window that has sway focus, found by walking the layout tree.
function focusedPid(node: any): number | undefined {
	if (node?.focused) return node.pid;
	for (const child of [...(node?.nodes ?? []), ...(node?.floating_nodes ?? [])]) {
		const pid = focusedPid(child);
		if (pid !== undefined) return pid;
	}
	return undefined;
}

function descendsFrom(pid: number, ancestor: number): boolean {
	for (let hops = 0; pid > 1 && hops < 32; hops++) {
		if (pid === ancestor) return true;
		try {
			// comm (field 2) may contain spaces and parens, so split after its
			// closing paren: what follows is "<state> <ppid> ...".
			const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
			pid = Number(stat.slice(stat.lastIndexOf(")") + 2).split(" ")[1]);
		} catch {
			return false;
		}
	}
	return false;
}

// True when the process (a tmux client) was started from an SSH login.
function overSsh(pid: number): boolean {
	try {
		return readFileSync(`/proc/${pid}/environ`, "utf8")
			.split("\0")
			.some((entry) => entry.startsWith("SSH_CONNECTION="));
	} catch {
		return false;
	}
}

// The notification body is Pango markup under dunst's `markup = full`.
const escapeMarkup = (text: string) =>
	text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

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

	// True when you are looking at this pane: its window is the current one in
	// an attached tmux session, and the terminal showing it has sway focus.
	// tmux can't answer the second half itself (it only tracks terminal focus
	// with `focus-events on`), so ask sway which window is focused and check
	// that one of the local tmux clients attached to this session runs inside
	// it. Without sway the tmux half decides alone.
	async function watching(localClients: number[]): Promise<boolean> {
		const current = await tmux(
			"display-message", "-p", "-t", pane,
			"#{&&:#{window_active},#{session_attached}}",
		);
		if (current?.stdout.trim() !== "1") return false;

		const sway = await pi
			.exec("swaymsg", ["-t", "get_tree"], { timeout: 2000 })
			.catch(() => undefined);
		if (!sway || sway.code !== 0) return true;
		let tree: unknown;
		try {
			tree = JSON.parse(sway.stdout);
		} catch {
			return true;
		}
		const focused = focusedPid(tree);
		if (focused === undefined) return false;

		return localClients.some((pid) => descendsFrom(pid, focused));
	}

	async function notify(body: string) {
		if (!enabled) return;
		const list = await tmux("list-clients", "-t", pane, "-F", "#{client_pid}");
		const clients = (list?.stdout ?? "").split("\n").filter(Boolean).map(Number);
		const local = clients.filter((pid) => !overSsh(pid));
		// Attached only over SSH: you are at another machine, and notify-send
		// would put the card on this one's desktop.
		if (clients.length > 0 && local.length === 0) return;
		if (await watching(local)) return;
		const title = name || basename(cwd) || "pi";
		await pi
			.exec("notify-send", ["-a", "Pi", "--", title, escapeMarkup(body)], { timeout: 2000 })
			.catch(() => undefined);
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

	pi.on("agent_settled", (event) => {
		set(event.aborted ? "idle" : "done");
		if (!event.aborted) void notify("Finished");
	});

	pi.on("ui_prompt_start", (event) => {
		set("blocked");
		void notify(event.title ? `Waiting for input: ${event.title}` : "Waiting for input");
	});

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
