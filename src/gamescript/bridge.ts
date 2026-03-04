/**
 * GameScript JSON bridge - sends commands to the in-game Squirrel GameScript
 * and awaits responses via the admin port.
 */

import { AdminClient } from "../admin-client.js";
import type { GameScriptResponse } from "../types/openttd.js";

export class GameScriptBridge {
  constructor(private client: AdminClient) {}

  /** Send a command and await the response */
  async send(
    action: string,
    params: Record<string, unknown> = {},
    timeoutMs: number = 10000
  ): Promise<GameScriptResponse> {
    return this.client.sendGameScriptCommand(action, params, timeoutMs);
  }

  /** Send a command and return the result, throwing on failure */
  async execute(
    action: string,
    params: Record<string, unknown> = {},
    timeoutMs: number = 10000
  ): Promise<unknown> {
    const response = await this.send(action, params, timeoutMs);
    if (!response.success) {
      throw new Error(response.error ?? `GameScript command '${action}' failed`);
    }
    return response.result;
  }
}
