/**
 * Binary packet reader for OpenTTD admin port protocol.
 * All integers are little-endian. Strings are null-terminated.
 */

export class PacketReader {
  private buffer: Buffer;
  private offset: number;

  constructor(buffer: Buffer) {
    this.buffer = buffer;
    this.offset = 0;
  }

  get remaining(): number {
    return this.buffer.length - this.offset;
  }

  get position(): number {
    return this.offset;
  }

  readUint8(): number {
    const val = this.buffer.readUInt8(this.offset);
    this.offset += 1;
    return val;
  }

  readBool(): boolean {
    return this.readUint8() !== 0;
  }

  readUint16(): number {
    const val = this.buffer.readUInt16LE(this.offset);
    this.offset += 2;
    return val;
  }

  readInt16(): number {
    const val = this.buffer.readInt16LE(this.offset);
    this.offset += 2;
    return val;
  }

  readUint32(): number {
    const val = this.buffer.readUInt32LE(this.offset);
    this.offset += 4;
    return val;
  }

  readInt32(): number {
    const val = this.buffer.readInt32LE(this.offset);
    this.offset += 4;
    return val;
  }

  readUint64(): bigint {
    const val = this.buffer.readBigUInt64LE(this.offset);
    this.offset += 8;
    return val;
  }

  readInt64(): bigint {
    const val = this.buffer.readBigInt64LE(this.offset);
    this.offset += 8;
    return val;
  }

  /** Read a null-terminated string */
  readString(): string {
    const start = this.offset;
    let end = start;
    while (end < this.buffer.length && this.buffer[end] !== 0) {
      end++;
    }
    const str = this.buffer.toString("utf8", start, end);
    this.offset = end + 1; // skip null terminator
    return str;
  }

  readBytes(length: number): Buffer {
    const slice = this.buffer.subarray(this.offset, this.offset + length);
    this.offset += length;
    return slice;
  }
}
