import Foundation

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: TimeInterval
    let text: String
    var translation: String?
    var romaji: String?
}

struct ParsedLyrics: Hashable {
    var lines: [LyricLine] = []
    var isInstrumental = false
    var contributor: String?
    var translationContributor: String?

    var isEmpty: Bool { lines.isEmpty }

    func activeIndex(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let middle = (low + high) / 2
            if lines[middle].time <= time {
                result = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return result
    }
}

enum LyricsParser {
    private static let creditRoles: Set<String> = [
        "词", "曲", "唱", "作词", "作曲", "编曲", "演唱", "歌手", "制作人",
        "监制", "混音", "母带", "录音", "和声", "吉他", "贝斯", "鼓", "弦乐",
    ]
    private static let creditRoleMarkers = [
        "作词", "作曲", "词曲", "编曲", "制作", "监制", "混音", "母带", "录音",
        "和声", "合声", "合唱", "吉他", "贝斯", "鼓手", "键盘", "钢琴", "弦乐", "管弦乐",
        "配器", "乐器", "采样", "音效", "声音设计", "录音室", "企划", "统筹",
        "封面设计", "歌曲宣推", "音乐总监", "项目总监", "项目经理", "艺人统筹",
        "配唱", "音频编辑", "人声编辑", "人声制作", "混音室", "母带室", "版权", "营销",
        "发行", "出品", "厂牌", "唱片公司", "艺术指导", "特别感谢", "鸣谢",
        "lyrics", "composer", "arranger", "arrangement", "producer", "mixing", "mastering",
        "recording", "vocal", "guitar", "bass", "drum", "strings", "planning", "promotion",
        "coverdesign", "projectdirector", "musicdirector", "artdirector", "executiveproducer",
        "recordingengineer", "mixengineer", "masteringengineer", "soundengineer", "production",
        "publishedby", "publisher", "copyright", "marketing", "coordinator", "studio", "engineer",
        "harmony", "backingvocal", "chorus", "keyboard", "piano", "programming", "synthesizer",
        "orchestra", "orchestration", "instrument", "sampler", "sounddesign", "label",
    ]

    static func parseLRC(_ lrc: String) -> [(time: TimeInterval, text: String)] {
        var output: [(TimeInterval, String)] = []
        let pattern = #"\[(\d+):(\d+)(?:[.:](\d+))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, range: range)
            guard let last = matches.last,
                  let contentStart = Range(last.range, in: line)?.upperBound else { continue }
            let content = String(line[contentStart...]).trimmingCharacters(in: .whitespaces)

            for match in matches {
                guard match.numberOfRanges >= 3,
                      let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line) else { continue }
                let minutes = Double(line[minuteRange]) ?? 0
                let seconds = Double(line[secondRange]) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: line) {
                    let value = String(line[fractionRange])
                    fraction = (Double(value) ?? 0) / pow(10, Double(value.count))
                }
                output.append((minutes * 60 + seconds + fraction, content))
            }
        }
        return output.sorted(by: { left, right in left.0 < right.0 })
    }

    static func parse(_ response: LyricResponse) -> ParsedLyrics {
        var output = ParsedLyrics()
        output.contributor = response.lyricUser?.nickname
        output.translationContributor = response.transUser?.nickname

        guard let raw = response.lrc?.lyric, !raw.isEmpty else { return output }
        var primary = parseLRC(raw)
        let instrumentalMarker = "纯音乐，请欣赏"
        if primary.count <= 10, primary.contains(where: { $0.text.contains(instrumentalMarker) }) {
            output.isInstrumental = true
            primary.removeAll {
                $0.text.contains(instrumentalMarker)
                    || $0.text.range(of: #"^作(词|曲)\s*[:：]"#, options: .regularExpression) != nil
            }
        }

        var lines = primary.enumerated().map {
            LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text)
        }

        func merge(_ body: String?, keyPath: WritableKeyPath<LyricLine, String?>) {
            guard let body, !body.isEmpty else { return }
            var indexed: [Int: String] = [:]
            for (time, text) in parseLRC(body) where !text.isEmpty {
                indexed[Int((time * 100).rounded())] = text
            }
            for index in lines.indices {
                lines[index][keyPath: keyPath] = indexed[Int((lines[index].time * 100).rounded())]
            }
        }

        merge(response.tlyric?.lyric, keyPath: \.translation)
        merge(response.romalrc?.lyric, keyPath: \.romaji)
        output.lines = lines
            .filter { !isCreditLine($0.text) }
            .enumerated()
            .map { index, line in
                LyricLine(
                    id: index,
                    time: line.time,
                    text: line.text,
                    translation: line.translation,
                    romaji: line.romaji
                )
            }
        return output
    }

    private static func isCreditLine(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = normalized.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return false
        }
        let role = normalized[..<separator].trimmingCharacters(in: .whitespaces)
        if creditRoles.contains(role) { return true }
        let compactRole = role
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        if compactRole == "op" || compactRole == "sp" || compactRole == "a&r"
            || compactRole.hasPrefix("op/") || compactRole.hasPrefix("sp/") {
            return true
        }
        return creditRoleMarkers.contains { compactRole.contains($0) }
    }
}
