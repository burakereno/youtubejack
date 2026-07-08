import Foundation

struct YTDLPInfo: Decodable {
    let id: String?
    let title: String?
    let webpageURL: String?
    let originalURL: String?
    let uploader: String?
    let channel: String?
    let duration: Double?
    let thumbnail: String?
    let entries: [YTDLPEntry]?
    let formats: [YTDLPFormat]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case webpageURL = "webpage_url"
        case originalURL = "original_url"
        case uploader
        case channel
        case duration
        case thumbnail
        case entries
        case formats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeStringIfPresent(forKey: .id)
        title = container.decodeStringIfPresent(forKey: .title)
        webpageURL = container.decodeStringIfPresent(forKey: .webpageURL)
        originalURL = container.decodeStringIfPresent(forKey: .originalURL)
        uploader = container.decodeStringIfPresent(forKey: .uploader)
        channel = container.decodeStringIfPresent(forKey: .channel)
        duration = container.decodeDoubleIfPresent(forKey: .duration)
        thumbnail = container.decodeStringIfPresent(forKey: .thumbnail)
        entries = try container.decodeIfPresent([YTDLPEntry].self, forKey: .entries)
        formats = try container.decodeIfPresent([YTDLPFormat].self, forKey: .formats)
    }
}

struct YTDLPFormat: Decodable {
    let formatID: String?
    let ext: String?
    let height: Int?
    let vcodec: String?
    let acodec: String?
    let filesize: Int64?
    let filesizeApprox: Int64?

    enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case ext
        case height
        case vcodec
        case acodec
        case filesize
        case filesizeApprox = "filesize_approx"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatID = container.decodeStringIfPresent(forKey: .formatID)
        ext = container.decodeStringIfPresent(forKey: .ext)
        height = container.decodeIntIfPresent(forKey: .height)
        vcodec = container.decodeStringIfPresent(forKey: .vcodec)
        acodec = container.decodeStringIfPresent(forKey: .acodec)
        filesize = container.decodeInt64IfPresent(forKey: .filesize)
        filesizeApprox = container.decodeInt64IfPresent(forKey: .filesizeApprox)
    }
}

struct YTDLPEntry: Decodable {
    let id: String?
    let title: String?
    let url: String?
    let webpageURL: String?
    let uploader: String?
    let channel: String?
    let duration: Double?
    let thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case webpageURL = "webpage_url"
        case uploader
        case channel
        case duration
        case thumbnail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeStringIfPresent(forKey: .id)
        title = container.decodeStringIfPresent(forKey: .title)
        url = container.decodeStringIfPresent(forKey: .url)
        webpageURL = container.decodeStringIfPresent(forKey: .webpageURL)
        uploader = container.decodeStringIfPresent(forKey: .uploader)
        channel = container.decodeStringIfPresent(forKey: .channel)
        duration = container.decodeDoubleIfPresent(forKey: .duration)
        thumbnail = container.decodeStringIfPresent(forKey: .thumbnail)
    }
}

extension KeyedDecodingContainer {
    func decodeStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeInt64IfPresent(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }
}
