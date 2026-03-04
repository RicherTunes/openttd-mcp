/**
 * OpenTTD Admin Port protocol enums and constants.
 * Based on: https://github.com/OpenTTD/OpenTTD/blob/master/src/network/core/tcp_admin.h
 */

/** Client-to-server packet types */
export enum AdminPacketType {
  ADMIN_JOIN = 0,
  ADMIN_QUIT = 1,
  ADMIN_UPDATE_FREQUENCY = 2,
  ADMIN_POLL = 3,
  ADMIN_CHAT = 4,
  ADMIN_RCON = 5,
  ADMIN_GAMESCRIPT = 6,
  ADMIN_PING = 7,
  ADMIN_EXTERNAL_CHAT = 8,
  ADMIN_JOIN_SECURE = 9,
  ADMIN_AUTH_RESPONSE = 10,
}

/** Server-to-client packet types */
export enum ServerPacketType {
  SERVER_FULL = 100,
  SERVER_BANNED = 101,
  SERVER_ERROR = 102,
  SERVER_PROTOCOL = 103,
  SERVER_WELCOME = 104,
  SERVER_NEWGAME = 105,
  SERVER_SHUTDOWN = 106,
  SERVER_DATE = 107,
  SERVER_CLIENT_JOIN = 108,
  SERVER_CLIENT_INFO = 109,
  SERVER_CLIENT_UPDATE = 110,
  SERVER_CLIENT_QUIT = 111,
  SERVER_CLIENT_ERROR = 112,
  SERVER_COMPANY_NEW = 113,
  SERVER_COMPANY_INFO = 114,
  SERVER_COMPANY_UPDATE = 115,
  SERVER_COMPANY_REMOVE = 116,
  SERVER_COMPANY_ECONOMY = 117,
  SERVER_COMPANY_STATS = 118,
  SERVER_CHAT = 119,
  SERVER_RCON = 120,
  SERVER_CONSOLE = 121,
  SERVER_CMD_NAMES = 122,
  SERVER_CMD_LOGGING_OLD = 123,
  SERVER_GAMESCRIPT = 124,
  SERVER_RCON_END = 125,
  SERVER_PONG = 126,
  SERVER_CMD_LOGGING = 127,
  SERVER_AUTH_REQUEST = 128,
  SERVER_ENABLE_ENCRYPTION = 129,
}

/** Update types for subscriptions and polling */
export enum AdminUpdateType {
  DATE = 0,
  CLIENT_INFO = 1,
  COMPANY_INFO = 2,
  COMPANY_ECONOMY = 3,
  COMPANY_STATS = 4,
  CHAT = 5,
  CONSOLE = 6,
  CMD_NAMES = 7,
  CMD_LOGGING = 8,
  GAMESCRIPT = 9,
  END = 10,
}

/** Update frequencies */
export enum AdminUpdateFrequency {
  POLL = 0x01,
  DAILY = 0x02,
  WEEKLY = 0x04,
  MONTHLY = 0x08,
  QUARTERLY = 0x10,
  ANNUALLY = 0x20,
  AUTOMATIC = 0x40,
}

/** Chat destination types */
export enum NetworkAction {
  CHAT = 0,
  CHAT_CLIENT = 1,
  CHAT_COMPANY = 2,
  SERVER_MESSAGE = 3,
  CHAT_EXTERNAL = 4,
}

/** Chat destination types for admin packets */
export enum DestType {
  BROADCAST = 0,
  TEAM = 1,
  CLIENT = 2,
}

/** Company colours */
export enum CompanyColour {
  DARK_BLUE = 0,
  PALE_GREEN = 1,
  PINK = 2,
  YELLOW = 3,
  RED = 4,
  LIGHT_BLUE = 5,
  GREEN = 6,
  DARK_GREEN = 7,
  BLUE = 8,
  CREAM = 9,
  MAUVE = 10,
  PURPLE = 11,
  ORANGE = 12,
  BROWN = 13,
  GREY = 14,
  WHITE = 15,
}

/** Vehicle types */
export enum VehicleType {
  TRAIN = 0,
  ROAD_VEHICLE = 1,
  SHIP = 2,
  AIRCRAFT = 3,
}

/** Special client/company IDs */
export const COMPANY_SPECTATOR = 255;
export const CLIENT_ID_SERVER = 1;
export const INVALID_CLIENT_ID = 0;

/** Maximum packet size */
export const SEND_MTU = 1460;

/** Default admin port */
export const DEFAULT_ADMIN_PORT = 3977;
