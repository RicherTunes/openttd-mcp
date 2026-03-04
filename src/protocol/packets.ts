/**
 * Packet builders and parsers for OpenTTD admin port protocol.
 */

import { PacketWriter } from "./writer.js";
import { PacketReader } from "./reader.js";
import {
  AdminPacketType,
  AdminUpdateType,
  AdminUpdateFrequency,
  DestType,
  VehicleType,
} from "./types.js";

// ============ Client-to-Server Packet Builders ============

/** Build ADMIN_JOIN packet for authentication (insecure, OpenTTD < 14) */
export function buildJoinPacket(
  password: string,
  botName: string,
  version: string
): Buffer {
  return new PacketWriter()
    .writeString(password)
    .writeString(botName)
    .writeString(version)
    .buildPacket(AdminPacketType.ADMIN_JOIN);
}

/** Build ADMIN_JOIN_SECURE packet for secure authentication (OpenTTD 14+) */
export function buildJoinSecurePacket(
  botName: string,
  version: string,
  supportedMethodsBitmask: number
): Buffer {
  return new PacketWriter()
    .writeString(botName)
    .writeString(version)
    .writeUint16(supportedMethodsBitmask)
    .buildPacket(AdminPacketType.ADMIN_JOIN_SECURE);
}

/** Build ADMIN_AUTH_RESPONSE packet */
export function buildAuthResponsePacket(
  clientPublicKey: Uint8Array,
  mac: Uint8Array,
  encryptedMessage: Uint8Array
): Buffer {
  return new PacketWriter()
    .writeBytes(Buffer.from(clientPublicKey))
    .writeBytes(Buffer.from(mac))
    .writeBytes(Buffer.from(encryptedMessage))
    .buildPacket(AdminPacketType.ADMIN_AUTH_RESPONSE);
}

/** Parse SERVER_AUTH_REQUEST */
export function parseAuthRequest(reader: PacketReader): {
  method: number;
  serverPublicKey: Buffer;
  nonce: Buffer;
} {
  const method = reader.readUint8();
  // Return copies (not views) to avoid byteOffset issues with crypto operations
  const serverPublicKey = Buffer.from(reader.readBytes(32));
  const nonce = Buffer.from(reader.readBytes(24));
  return { method, serverPublicKey, nonce };
}

/** Parse SERVER_ENABLE_ENCRYPTION — contains the 24-byte encryption nonce */
export function parseEnableEncryption(reader: PacketReader): {
  encryptionNonce: Buffer;
} {
  const encryptionNonce = reader.readBytes(24);
  return { encryptionNonce };
}

/** Build ADMIN_QUIT packet */
export function buildQuitPacket(): Buffer {
  return new PacketWriter().buildPacket(AdminPacketType.ADMIN_QUIT);
}

/** Build ADMIN_UPDATE_FREQUENCY packet */
export function buildUpdateFrequencyPacket(
  updateType: AdminUpdateType,
  frequency: AdminUpdateFrequency
): Buffer {
  return new PacketWriter()
    .writeUint16(updateType)
    .writeUint16(frequency)
    .buildPacket(AdminPacketType.ADMIN_UPDATE_FREQUENCY);
}

/** Build ADMIN_POLL packet */
export function buildPollPacket(
  updateType: AdminUpdateType,
  extra: number = 0xffffffff // 0xFFFFFFFF = all
): Buffer {
  return new PacketWriter()
    .writeUint8(updateType)
    .writeUint32(extra)
    .buildPacket(AdminPacketType.ADMIN_POLL);
}

/** Build ADMIN_CHAT packet */
export function buildChatPacket(
  action: number,
  destType: DestType,
  dest: number,
  message: string
): Buffer {
  return new PacketWriter()
    .writeUint8(action)
    .writeUint8(destType)
    .writeUint32(dest)
    .writeString(message)
    .buildPacket(AdminPacketType.ADMIN_CHAT);
}

/** Build ADMIN_RCON packet */
export function buildRconPacket(command: string): Buffer {
  return new PacketWriter()
    .writeString(command)
    .buildPacket(AdminPacketType.ADMIN_RCON);
}

/** Build ADMIN_GAMESCRIPT packet (send JSON to GameScript) */
export function buildGameScriptPacket(json: string): Buffer {
  return new PacketWriter()
    .writeString(json)
    .buildPacket(AdminPacketType.ADMIN_GAMESCRIPT);
}

/** Build ADMIN_PING packet */
export function buildPingPacket(payload: number): Buffer {
  return new PacketWriter()
    .writeUint32(payload)
    .buildPacket(AdminPacketType.ADMIN_PING);
}

// ============ Server-to-Client Packet Parsers ============

export interface ServerProtocol {
  version: number;
  supportedFrequencies: Map<AdminUpdateType, number>;
}

export function parseServerProtocol(reader: PacketReader): ServerProtocol {
  const version = reader.readUint8();
  const supportedFrequencies = new Map<AdminUpdateType, number>();
  while (reader.remaining > 0) {
    const next = reader.readBool();
    if (!next) break;
    const updateType = reader.readUint16() as AdminUpdateType;
    const freqMask = reader.readUint16();
    supportedFrequencies.set(updateType, freqMask);
  }
  return { version, supportedFrequencies };
}

export interface ServerWelcome {
  serverName: string;
  networkRevision: string;
  dedicated: boolean;
  mapName: string;
  mapSeed: number;
  landscape: number;
  startDate: number;
  mapSizeX: number;
  mapSizeY: number;
}

export function parseServerWelcome(reader: PacketReader): ServerWelcome {
  return {
    serverName: reader.readString(),
    networkRevision: reader.readString(),
    dedicated: reader.readBool(),
    mapName: reader.readString(),
    mapSeed: reader.readUint32(),
    landscape: reader.readUint8(),
    startDate: reader.readUint32(),
    mapSizeX: reader.readUint16(),
    mapSizeY: reader.readUint16(),
  };
}

export interface ServerDate {
  date: number;
}

export function parseServerDate(reader: PacketReader): ServerDate {
  return { date: reader.readUint32() };
}

export interface ClientInfo {
  clientId: number;
  hostname: string;
  name: string;
  language: number;
  joinDate: number;
  companyId: number;
}

export function parseClientInfo(reader: PacketReader): ClientInfo {
  return {
    clientId: reader.readUint32(),
    hostname: reader.readString(),
    name: reader.readString(),
    language: reader.readUint8(),
    joinDate: reader.readUint32(),
    companyId: reader.readUint8(),
  };
}

export interface ClientJoin {
  clientId: number;
}

export function parseClientJoin(reader: PacketReader): ClientJoin {
  return { clientId: reader.readUint32() };
}

export interface ClientUpdate {
  clientId: number;
  name: string;
  companyId: number;
}

export function parseClientUpdate(reader: PacketReader): ClientUpdate {
  return {
    clientId: reader.readUint32(),
    name: reader.readString(),
    companyId: reader.readUint8(),
  };
}

export interface ClientQuit {
  clientId: number;
}

export function parseClientQuit(reader: PacketReader): ClientQuit {
  return { clientId: reader.readUint32() };
}

export interface ClientError {
  clientId: number;
  errorCode: number;
}

export function parseClientError(reader: PacketReader): ClientError {
  return {
    clientId: reader.readUint32(),
    errorCode: reader.readUint8(),
  };
}

export interface CompanyInfo {
  companyId: number;
  name: string;
  president: string;
  colour: number;
  passworded: boolean;
  inauguratedYear: number;
  ai: boolean;
  quarterlyCount: number;
}

export function parseCompanyInfo(reader: PacketReader): CompanyInfo {
  return {
    companyId: reader.readUint8(),
    name: reader.readString(),
    president: reader.readString(),
    colour: reader.readUint8(),
    passworded: reader.readBool(),
    inauguratedYear: reader.readUint32(),
    ai: reader.readBool(),
    quarterlyCount: reader.readUint8(),
  };
}

export interface CompanyUpdate {
  companyId: number;
  name: string;
  president: string;
  colour: number;
  passworded: boolean;
  quarterlyCount: number;
}

export function parseCompanyUpdate(reader: PacketReader): CompanyUpdate {
  return {
    companyId: reader.readUint8(),
    name: reader.readString(),
    president: reader.readString(),
    colour: reader.readUint8(),
    passworded: reader.readBool(),
    quarterlyCount: reader.readUint8(),
  };
}

export interface CompanyNew {
  companyId: number;
}

export function parseCompanyNew(reader: PacketReader): CompanyNew {
  return { companyId: reader.readUint8() };
}

export interface CompanyRemove {
  companyId: number;
  reason: number;
}

export function parseCompanyRemove(reader: PacketReader): CompanyRemove {
  return {
    companyId: reader.readUint8(),
    reason: reader.readUint8(),
  };
}

export interface CompanyEconomy {
  companyId: number;
  money: bigint;
  currentLoan: bigint;
  income: bigint;
  deliveredCargo: number;
  // Previous quarters
  quarters: Array<{
    companyValue: bigint;
    performance: number;
    deliveredCargo: number;
  }>;
}

export function parseCompanyEconomy(reader: PacketReader): CompanyEconomy {
  const companyId = reader.readUint8();
  const money = reader.readInt64();
  const currentLoan = reader.readUint64();
  const income = reader.readInt64();
  const deliveredCargo = reader.readUint16();

  const quarters = [];
  // Up to 2 previous quarters
  for (let i = 0; i < 2; i++) {
    if (reader.remaining < 12) break;
    quarters.push({
      companyValue: reader.readUint64(),
      performance: reader.readUint16(),
      deliveredCargo: reader.readUint16(),
    });
  }

  return { companyId, money, currentLoan, income, deliveredCargo, quarters };
}

export interface CompanyStats {
  companyId: number;
  vehicles: Record<string, number>;
  stations: Record<string, number>;
}

export function parseCompanyStats(reader: PacketReader): CompanyStats {
  const companyId = reader.readUint8();
  const vehicleTypes = ["trains", "road_vehicles", "ships", "aircraft"];
  const vehicles: Record<string, number> = {};
  const stations: Record<string, number> = {};

  for (const type of vehicleTypes) {
    vehicles[type] = reader.readUint16();
  }
  // There's a 5th type sometimes (trams / unused)
  if (reader.remaining >= 2) {
    vehicles["trams"] = reader.readUint16();
  }

  for (const type of vehicleTypes) {
    stations[type] = reader.readUint16();
  }
  if (reader.remaining >= 2) {
    stations["trams"] = reader.readUint16();
  }

  return { companyId, vehicles, stations };
}

export interface ChatMessage {
  action: number;
  destType: number;
  clientId: number;
  message: string;
  extra: bigint;
}

export function parseChatMessage(reader: PacketReader): ChatMessage {
  return {
    action: reader.readUint8(),
    destType: reader.readUint8(),
    clientId: reader.readUint32(),
    message: reader.readString(),
    extra: reader.readUint64(),
  };
}

export interface RconResponse {
  colour: number;
  output: string;
}

export function parseRconResponse(reader: PacketReader): RconResponse {
  return {
    colour: reader.readUint16(),
    output: reader.readString(),
  };
}

export interface RconEnd {
  command: string;
}

export function parseRconEnd(reader: PacketReader): RconEnd {
  return { command: reader.readString() };
}

export interface ConsoleMessage {
  origin: string;
  message: string;
}

export function parseConsoleMessage(reader: PacketReader): ConsoleMessage {
  return {
    origin: reader.readString(),
    message: reader.readString(),
  };
}

export interface GameScriptMessage {
  json: string;
}

export function parseGameScriptMessage(
  reader: PacketReader
): GameScriptMessage {
  return { json: reader.readString() };
}

export interface PongMessage {
  payload: number;
}

export function parsePongMessage(reader: PacketReader): PongMessage {
  return { payload: reader.readUint32() };
}

export interface ServerError {
  errorCode: number;
}

export function parseServerError(reader: PacketReader): ServerError {
  return { errorCode: reader.readUint8() };
}

// ============ Utility: Convert OpenTTD date to calendar ============

/** Convert OpenTTD date integer to a readable date string (YYYY-MM-DD) */
export function ottdDateToString(date: number): string {
  // OpenTTD dates: days since year 0. We use a simplified calculation.
  // Based on OpenTTD's ConvertDateToYMD
  let y = 0;
  let rem = date;

  // 400-year cycle = 146097 days
  const c400 = Math.floor(rem / 146097);
  rem -= c400 * 146097;
  y += c400 * 400;

  // 100-year cycle = 36524 days (except leap centuries)
  let c100 = Math.floor(rem / 36524);
  if (c100 === 4) c100 = 3;
  rem -= c100 * 36524;
  y += c100 * 100;

  // 4-year cycle = 1461 days
  const c4 = Math.floor(rem / 1461);
  rem -= c4 * 1461;
  y += c4 * 4;

  // 1-year cycle = 365 days
  let c1 = Math.floor(rem / 365);
  if (c1 === 4) c1 = 3;
  rem -= c1 * 365;
  y += c1;

  const isLeap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  const daysInMonth = [
    31,
    isLeap ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];

  let month = 0;
  while (month < 11 && rem >= daysInMonth[month]) {
    rem -= daysInMonth[month];
    month++;
  }

  return `${y}-${String(month + 1).padStart(2, "0")}-${String(rem + 1).padStart(2, "0")}`;
}
