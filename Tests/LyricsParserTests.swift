import Foundation
import Testing
@testable import SonimbusCore

@Test("LRC 支持多时间戳与不同小数精度")
func parsesMultipleTimestamps() {
    let parsed = LyricsParser.parseLRC("""
    [00:01.50][00:02:750]第一句
    [01:03]第二句
    [ar:metadata]
    """)

    #expect(parsed.count == 3)
    #expect(parsed[0].time == 1.5)
    #expect(parsed[1].time == 2.75)
    #expect(parsed[2].time == 63)
    #expect(parsed[0].text == "第一句")
}

@Test("歌词二分查找返回当前行")
func findsActiveLine() {
    let lyrics = ParsedLyrics(lines: [
        LyricLine(id: 0, time: 1, text: "a"),
        LyricLine(id: 1, time: 4, text: "b"),
        LyricLine(id: 2, time: 9, text: "c"),
    ])

    #expect(lyrics.activeIndex(at: 0.9) == nil)
    #expect(lyrics.activeIndex(at: 1) == 0)
    #expect(lyrics.activeIndex(at: 8.99) == 1)
    #expect(lyrics.activeIndex(at: 30) == 2)
}

@Test("解析后的歌词过滤制作信息并重新编号")
func removesCreditsFromDisplayedLyrics() {
    let response = LyricResponse(
        lrc: .init(lyric: """
        [00:00.00]作词：某某
        [00:01.00]作曲 : 某某
        [00:02.00]演唱：某某
        [00:03.00]改编词曲：某某
        [00:04.00]母带工程师 Mastering Engineer：某某
        [00:05.00]人声录音室 Vocal Recording Studio：某录音室
        [00:06.00]OP：INDEcompany
        [00:07.00]歌曲宣推 Song Promotion：某某
        [00:08.00]项目总监 Project Director：宋旭辉 / 来建增
        [00:09.00]Recording Engineer：某某
        [00:10.00]合声/合声编写：王子@Soulkidz / 郑羽淇@啊菠萝
        [00:11.00]Backing Vocal & Harmony：某某
        [00:20.00]问题：答案在哪里
        [00:24.00]第一句歌词
        """),
        tlyric: nil,
        romalrc: nil,
        lyricUser: nil,
        transUser: nil
    )

    let lyrics = LyricsParser.parse(response)

    #expect(lyrics.lines.map(\.text) == ["问题：答案在哪里", "第一句歌词"])
    #expect(lyrics.lines.map(\.id) == [0, 1])
    #expect(lyrics.activeIndex(at: 19.9) == nil)
    #expect(lyrics.activeIndex(at: 22) == 0)
}

@Test("翻译与罗马音按时间合并到原文")
func mergesTranslatedAndRomanizedLyrics() {
    let response = LyricResponse(
        lrc: .init(lyric: """
        [00:01.23]第一句
        [00:05.00]第二句
        """),
        tlyric: .init(lyric: """
        [00:01.23]First line
        [00:05.00]Second line
        """),
        romalrc: .init(lyric: """
        [00:01.23]dai ichi gyou
        [00:05.00]dai ni gyou
        """),
        lyricUser: nil,
        transUser: nil
    )

    let lyrics = LyricsParser.parse(response)

    #expect(lyrics.lines.map(\.translation) == ["First line", "Second line"])
    #expect(lyrics.lines.map(\.romaji) == ["dai ichi gyou", "dai ni gyou"])
}

@Test("纯音乐标记不会显示成普通歌词")
func recognizesInstrumentalLyrics() {
    let response = LyricResponse(
        lrc: .init(lyric: """
        [00:00.00]作曲：某某
        [00:01.00]纯音乐，请欣赏
        """),
        tlyric: nil,
        romalrc: nil,
        lyricUser: nil,
        transUser: nil
    )

    let lyrics = LyricsParser.parse(response)

    #expect(lyrics.isInstrumental)
    #expect(lyrics.lines.isEmpty)
}
