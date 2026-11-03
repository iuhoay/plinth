import Foundation

struct Quote: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let source: String
}

/// Lines from the Zen classics, kept in the original Chinese.
enum Zen {
    /// Characters that drift up from the fish in "Zen characters" mode.
    static let words = [
        "静", "空", "寂", "定", "慧", "觉", "心", "无", "一", "如",
        "禅", "悟", "息", "安", "闲", "放下", "当下", "自在", "随缘", "如是",
    ]

    /// Bodhidharma's answer to Emperor Wu, shown on the first knock:
    /// counting merit is itself what Zen lets go of.
    static let noMerit = Quote(
        text: "梁武帝问：造寺度僧，有何功德？\n达摩答：并无功德。",
        source: "《景德传灯录》")

    static let quotes = [
        Quote(text: "本来无一物，何处惹尘埃。", source: "慧能《六祖坛经》"),
        Quote(text: "应无所住，而生其心。", source: "《金刚经》"),
        Quote(text: "一切有为法，如梦幻泡影，\n如露亦如电，应作如是观。", source: "《金刚经》"),
        Quote(text: "春有百花秋有月，夏有凉风冬有雪。\n若无闲事挂心头，便是人间好时节。", source: "无门慧开"),
        Quote(text: "日日是好日。", source: "云门文偃"),
        Quote(text: "平常心是道。", source: "南泉普愿"),
        Quote(text: "吃茶去。", source: "赵州从谂"),
        Quote(text: "放下着。", source: "赵州从谂"),
        Quote(text: "饥来吃饭，困来即眠。", source: "大珠慧海"),
        Quote(text: "行到水穷处，坐看云起时。", source: "王维《终南别业》"),
        Quote(text: "千江有水千江月，\n万里无云万里天。", source: "《嘉泰普灯录》"),
        Quote(text: "云在青天水在瓶。", source: "药山惟俨"),
        Quote(text: "竹影扫阶尘不动，\n月穿潭底水无痕。", source: "《五灯会元》"),
        Quote(text: "青青翠竹，尽是法身；\n郁郁黄花，无非般若。", source: "《景德传灯录》"),
        Quote(text: "不思善，不思恶，\n正与么时，那个是本来面目？", source: "慧能《六祖坛经》"),
    ]

    /// Why a fish: from the Baizhang monastic rules.
    static let whyFish = Quote(
        text: "鱼昼夜常醒，刻木象形击之，所以警昏惰也。",
        source: "《敕修百丈清规》")

    static func quoteOfTheDay(_ date: Date = .now) -> Quote {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return quotes[day % quotes.count]
    }
}
