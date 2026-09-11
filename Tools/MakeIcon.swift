import Foundation
import CoreGraphics
import ImageIO

// MARK: - 「键盘热力图」App 图标生成器
//
// 纯 CoreGraphics 离屏绘制（无需 GUI / 窗口服务器），按 iconset 需要的每个像素尺寸
// 原生绘制一张 PNG，保证小尺寸也清晰。配色复用 app 的暖色热力色阶。
// 用法：makeicon <输出的 .iconset 目录>

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func C(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

// 品牌暖色色阶（与 HeatColor.lightStops 一致：奶油 → 橙 → 深红）
let stops: [(t: Double, r: Double, g: Double, b: Double)] = [
    (0.00, 0xFF/255, 0xEC/255, 0xD6/255),
    (0.28, 0xFF/255, 0xC5/255, 0x8A/255),
    (0.55, 0xFF/255, 0x8C/255, 0x42/255),
    (0.80, 0xF0/255, 0x56/255, 0x2B/255),
    (1.00, 0xC4/255, 0x21/255, 0x1B/255),
]

func heat(_ tIn: Double) -> (Double, Double, Double) {
    let t = min(1, max(0, tIn))
    var lo = stops[0], hi = stops[stops.count - 1]
    for i in 0..<(stops.count - 1) where t >= stops[i].t && t <= stops[i + 1].t {
        lo = stops[i]; hi = stops[i + 1]; break
    }
    let span = hi.t - lo.t
    let f = span > 0 ? (t - lo.t) / span : 0
    return (lo.r + (hi.r - lo.r) * f,
            lo.g + (hi.g - lo.g) * f,
            lo.b + (hi.b - lo.b) * f)
}

// 3×3 热力分布：最热在中心，向外渐冷（略带对角暖意）
let intensity: [[Double]] = [
    [0.42, 0.68, 0.34],
    [0.78, 1.00, 0.54],
    [0.28, 0.58, 0.40],
]

func drawIcon(_ W: Int) -> CGImage? {
    let w = CGFloat(W)
    guard let ctx = CGContext(data: nil, width: W, height: W,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // 圆角方块（squircle 近似）
    let margin = w * 0.085
    let rect = CGRect(x: margin, y: margin, width: w - 2 * margin, height: w - 2 * margin)
    let side = rect.width
    let radius = side * 0.2237
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 整体投影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.012), blur: w * 0.05, color: C(0, 0, 0, 0.35))
    ctx.addPath(bg); ctx.setFillColor(C(0.10, 0.09, 0.08)); ctx.fillPath()
    ctx.restoreGState()

    // 背景暖炭渐变 + 顶部高光
    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()
    let bgGrad = CGGradient(colorsSpace: cs, colors: [
        C(0x2E / 255, 0x27 / 255, 0x20 / 255), C(0x15 / 255, 0x12 / 255, 0x0F / 255),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    let topGlow = CGGradient(colorsSpace: cs, colors: [C(1, 1, 1, 0.10), C(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(topGlow, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY), options: [])
    ctx.restoreGState()

    // 3×3 键帽网格
    let inset = side * 0.16
    let grid = rect.insetBy(dx: inset, dy: inset)
    let gap = grid.width * 0.08
    let cell = (grid.width - 2 * gap) / 3
    let capR = cell * 0.24

    func cellRect(_ row: Int, _ col: Int) -> CGRect {
        let x = grid.minX + CGFloat(col) * (cell + gap)
        let yTop = grid.maxY - CGFloat(row) * (cell + gap) - cell   // row0 在顶部
        return CGRect(x: x, y: yTop, width: cell, height: cell)
    }

    // 中心热点辉光
    let hot = cellRect(1, 1)
    ctx.saveGState()
    let glow = CGGradient(colorsSpace: cs, colors: [
        C(1.0, 0.46, 0.16, 0.55), C(1.0, 0.46, 0.16, 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: hot.midX, y: hot.midY), startRadius: 0,
                           endCenter: CGPoint(x: hot.midX, y: hot.midY), endRadius: cell * 1.7, options: [])
    ctx.restoreGState()

    // 键帽
    for row in 0..<3 {
        for col in 0..<3 {
            let cr = cellRect(row, col)
            let (r, g, b) = heat(intensity[row][col])
            let cap = CGPath(roundedRect: cr, cornerWidth: capR, cornerHeight: capR, transform: nil)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -cell * 0.04), blur: cell * 0.10, color: C(0, 0, 0, 0.30))
            ctx.addPath(cap); ctx.setFillColor(C(r, g, b)); ctx.fillPath()
            ctx.restoreGState()

            // 顶亮底暗的光泽
            ctx.saveGState()
            ctx.addPath(cap); ctx.clip()
            let capGrad = CGGradient(colorsSpace: cs, colors: [
                C(min(1, r + 0.13), min(1, g + 0.11), min(1, b + 0.09)),
                C(r, g, b),
                C(max(0, r - 0.10), max(0, g - 0.08), max(0, b - 0.06)),
            ] as CFArray, locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(capGrad, start: CGPoint(x: cr.minX, y: cr.maxY), end: CGPoint(x: cr.minX, y: cr.minY), options: [])
            ctx.restoreGState()

            // 细边高光
            ctx.saveGState()
            ctx.addPath(cap); ctx.setStrokeColor(C(1, 1, 1, 0.18)); ctx.setLineWidth(max(0.5, cell * 0.02)); ctx.strokePath()
            ctx.restoreGState()
        }
    }
    return ctx.makeImage()
}

func writePNG(_ img: CGImage, _ url: URL) {
    guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dst, img, nil)
    _ = CGImageDestinationFinalize(dst)
}

// PNG 编码到内存
func pngData(_ img: CGImage) -> Data? {
    let buf = NSMutableData()
    guard let dst = CGImageDestinationCreateWithData(buf as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dst, img, nil)
    guard CGImageDestinationFinalize(dst) else { return nil }
    return buf as Data
}

func be32(_ v: UInt32) -> [UInt8] {
    [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
}

// 直接按 ICNS 格式打包各尺寸 PNG（绕开 iconutil）。
// 每个条目：4 字节 OSType + 4 字节大端长度(含 8 字节头) + PNG 数据。
func writeICNS(_ url: URL) {
    let entries: [(String, Int)] = [
        ("icp4", 16), ("icp5", 32), ("ic11", 32), ("ic12", 64),
        ("ic07", 128), ("ic13", 256), ("ic08", 256),
        ("ic14", 512), ("ic09", 512), ("ic10", 1024),
    ]
    var cache: [Int: Data] = [:]
    var body: [UInt8] = []
    for (ostype, size) in entries {
        let png: Data
        if let c = cache[size] { png = c }
        else if let img = drawIcon(size), let d = pngData(img) { png = d; cache[size] = d }
        else { continue }
        body += Array(ostype.utf8)          // 4 字节 ASCII
        body += be32(UInt32(8 + png.count)) // 长度含头
        body += [UInt8](png)
    }
    var file = Array("icns".utf8)
    file += be32(UInt32(8 + body.count))
    file += body
    try? Data(file).write(to: url)
    print("· AppIcon.icns (\(file.count) bytes)")
}


let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let dir = URL(fileURLWithPath: outDir, isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let files: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in files {
    if let img = drawIcon(px) { writePNG(img, dir.appendingPathComponent(name)); print("· \(name) (\(px)px)") }
    else { print("✗ \(name)") }
}

// 第 2 个参数 = .icns 输出路径（直接打包，不用 iconutil）
if CommandLine.arguments.count > 2 {
    writeICNS(URL(fileURLWithPath: CommandLine.arguments[2]))
}
print("done → \(dir.path)")

