import Foundation
import zlib

enum ZipStoreArchive {

    static func write(entries: [(path: String, data: Data)], to url: URL) throws {
        try data(from: entries).write(to: url, options: .atomic)
    }

    static func data(from entries: [(path: String, data: Data)]) throws -> Data {
        var localFiles = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let nameLength = UInt16(nameData.count)

            var local = Data()
            local.appendUInt32LE(0x04034b50)
            local.appendUInt16LE(20)
            local.appendUInt16LE(0)
            local.appendUInt16LE(0)
            local.appendUInt16LE(0)
            local.appendUInt16LE(0)
            local.appendUInt32LE(crc)
            local.appendUInt32LE(size)
            local.appendUInt32LE(size)
            local.appendUInt16LE(nameLength)
            local.appendUInt16LE(0)
            local.append(nameData)
            local.append(entry.data)

            var central = Data()
            central.appendUInt32LE(0x02014b50)
            central.appendUInt16LE(20)
            central.appendUInt16LE(20)
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt32LE(crc)
            central.appendUInt32LE(size)
            central.appendUInt32LE(size)
            central.appendUInt16LE(nameLength)
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt32LE(0)
            central.appendUInt32LE(offset)
            central.append(nameData)

            offset += UInt32(local.count)
            localFiles.append(local)
            centralDirectory.append(central)
        }

        var end = Data()
        end.appendUInt32LE(0x06054b50)
        end.appendUInt16LE(0)
        end.appendUInt16LE(0)
        end.appendUInt16LE(UInt16(entries.count))
        end.appendUInt16LE(UInt16(entries.count))
        end.appendUInt32LE(UInt32(centralDirectory.count))
        end.appendUInt32LE(offset)
        end.appendUInt16LE(0)

        return localFiles + centralDirectory + end
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            let pointer = buffer.bindMemory(to: UInt8.self).baseAddress
            return UInt32(zlib.crc32(0, pointer, uInt(buffer.count)))
        }
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: 2))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: 4))
    }
}
