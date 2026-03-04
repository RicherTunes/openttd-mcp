/**
 * Binary packet writer for OpenTTD admin port protocol.
 * All integers are little-endian. Strings are null-terminated.
 * Packet format: SIZE (uint16 LE) | TYPE (uint8) | DATA
 */

import { SEND_MTU } from "./types.js";

export class PacketWriter {
  private parts: Buffer[] = [];
  private size: number = 0;

  writeUint8(val: number): this {
    const buf = Buffer.alloc(1);
    buf.writeUInt8(val);
    this.parts.push(buf);
    this.size += 1;
    return this;
  }

  writeBool(val: boolean): this {
    return this.writeUint8(val ? 1 : 0);
  }

  writeUint16(val: number): this {
    const buf = Buffer.alloc(2);
    buf.writeUInt16LE(val);
    this.parts.push(buf);
    this.size += 2;
    return this;
  }

  writeInt16(val: number): this {
    const buf = Buffer.alloc(2);
    buf.writeInt16LE(val);
    this.parts.push(buf);
    this.size += 2;
    return this;
  }

  writeUint32(val: number): this {
    const buf = Buffer.alloc(4);
    buf.writeUInt32LE(val);
    this.parts.push(buf);
    this.size += 4;
    return this;
  }

  writeInt32(val: number): this {
    const buf = Buffer.alloc(4);
    buf.writeInt32LE(val);
    this.parts.push(buf);
    this.size += 4;
    return this;
  }

  writeUint64(val: bigint): this {
    const buf = Buffer.alloc(8);
    buf.writeBigUInt64LE(val);
    this.parts.push(buf);
    this.size += 8;
    return this;
  }

  /** Write a null-terminated string */
  writeString(val: string): this {
    const strBuf = Buffer.from(val, "utf8");
    const nullBuf = Buffer.alloc(1, 0);
    this.parts.push(strBuf, nullBuf);
    this.size += strBuf.length + 1;
    return this;
  }

  writeBytes(buf: Buffer): this {
    this.parts.push(buf);
    this.size += buf.length;
    return this;
  }

  /** Build final packet with SIZE header and TYPE byte */
  buildPacket(packetType: number): Buffer {
    // SIZE = 2 (size field) + 1 (type) + data
    const totalSize = 2 + 1 + this.size;
    if (totalSize > SEND_MTU) {
      throw new Error(`Packet too large: ${totalSize} > ${SEND_MTU}`);
    }
    const header = Buffer.alloc(3);
    header.writeUInt16LE(totalSize, 0);
    header.writeUInt8(packetType, 2);
    return Buffer.concat([header, ...this.parts]);
  }
}
