/**
 * TypeScript interfaces for OpenTTD game data.
 */

export interface ServerInfo {
  serverName: string;
  networkRevision: string;
  dedicated: boolean;
  mapName: string;
  mapSeed: number;
  landscape: string;
  startDate: string;
  mapSizeX: number;
  mapSizeY: number;
}

export interface Company {
  id: number;
  name: string;
  president: string;
  colour: string;
  passworded: boolean;
  inauguratedYear: number;
  ai: boolean;
}

export interface CompanyEconomyData {
  companyId: number;
  money: string;
  currentLoan: string;
  income: string;
  deliveredCargo: number;
  quarters: Array<{
    companyValue: string;
    performance: number;
    deliveredCargo: number;
  }>;
}

export interface CompanyStatsData {
  companyId: number;
  vehicles: Record<string, number>;
  stations: Record<string, number>;
}

export interface Client {
  clientId: number;
  hostname: string;
  name: string;
  companyId: number;
}

export interface GameScriptCommand {
  id: string;
  action: string;
  params: Record<string, unknown>;
}

export interface GameScriptResponse {
  id: string;
  success: boolean;
  result?: unknown;
  error?: string;
}

/** Landscape types */
export const LANDSCAPES = [
  "temperate",
  "arctic",
  "tropical",
  "toyland",
] as const;

/** Company colour names */
export const COLOUR_NAMES = [
  "dark_blue",
  "pale_green",
  "pink",
  "yellow",
  "red",
  "light_blue",
  "green",
  "dark_green",
  "blue",
  "cream",
  "mauve",
  "purple",
  "orange",
  "brown",
  "grey",
  "white",
] as const;
