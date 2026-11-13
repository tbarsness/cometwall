// Renders the 1024px app icon: swift scripts/make-icon.swift, then resize into
// CometWall/Assets.xcassets/AppIcon.appiconset.
import AppKit
import CoreGraphics

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])! }

// macOS icon grid: 824pt body centered, ~185pt corner radius, soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0, 0, 0, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(c(12, 16, 36)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [c(30, 40, 84), c(10, 13, 32)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 824, y: 100), options: [])

// faint stars
let stars: [(CGFloat, CGFloat, CGFloat)] = [(190,820,3),(300,870,2),(860,300,2.5),(820,180,2),(160,300,2),(470,880,2),(880,620,2)]
for (x, y, r) in stars { ctx.setFillColor(c(255,255,255,0.55)); ctx.fillEllipse(in: CGRect(x: x-r, y: y-r, width: 2*r, height: 2*r)) }

// 2x2 wall of screens
let gap: CGFloat = 34, tile: CGFloat = 268
let origin = CGPoint(x: 512 - tile - gap/2, y: 512 - tile - gap/2 - 10)
let tints: [CGColor] = [c(58, 92, 170), c(46, 74, 140), c(46, 74, 140), c(58, 92, 170)]
for row in 0..<2 { for col in 0..<2 {
    let r = CGRect(x: origin.x + CGFloat(col)*(tile+gap), y: origin.y + CGFloat(row)*(tile+gap), width: tile, height: tile*0.78)
    let p = CGPath(roundedRect: r, cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.saveGState(); ctx.addPath(p); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [tints[row*2+col], c(22, 32, 70)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.maxY), end: CGPoint(x: r.maxX, y: r.minY), options: [])
    // a few "UI" bars on each screen
    ctx.setFillColor(c(255,255,255,0.16))
    ctx.fill(CGRect(x: r.minX+28, y: r.maxY-50, width: r.width*0.45, height: 14))
    ctx.fill(CGRect(x: r.minX+28, y: r.maxY-82, width: r.width*0.62, height: 10))
    ctx.restoreGState()
    ctx.addPath(p); ctx.setStrokeColor(c(160, 190, 255, 0.45)); ctx.setLineWidth(5); ctx.strokePath()
    // stand
    ctx.setFillColor(c(120, 145, 210, 0.55))
    ctx.fill(CGRect(x: r.midX-34, y: r.minY-20, width: 68, height: 10))
}}

// comet: tapered tail from upper-left down-right... head lower-right? Head at upper right, tail streaming to lower left.
let head = CGPoint(x: 720, y: 735)
let tailEnd = CGPoint(x: 230, y: 330)
let dx = head.x - tailEnd.x, dy = head.y - tailEnd.y
let len = sqrt(dx*dx + dy*dy)
let nx = -dy/len, ny = dx/len
let wHead: CGFloat = 40, wEnd: CGFloat = 95
let tail = CGMutablePath()
tail.move(to: CGPoint(x: tailEnd.x + nx*wEnd, y: tailEnd.y + ny*wEnd))
tail.addQuadCurve(to: CGPoint(x: head.x + nx*wHead, y: head.y + ny*wHead),
                  control: CGPoint(x: (head.x+tailEnd.x)/2 + nx*wEnd*0.55, y: (head.y+tailEnd.y)/2 + ny*wEnd*0.55))
tail.addArc(center: head, radius: wHead, startAngle: atan2(ny, nx), endAngle: atan2(-ny, -nx), clockwise: true)
tail.addQuadCurve(to: CGPoint(x: tailEnd.x - nx*wEnd, y: tailEnd.y - ny*wEnd),
                  control: CGPoint(x: (head.x+tailEnd.x)/2 - nx*wEnd*0.55, y: (head.y+tailEnd.y)/2 - ny*wEnd*0.55))
tail.closeSubpath()
ctx.saveGState()
ctx.addPath(tail); ctx.clip()
let tg = CGGradient(colorsSpace: cs, colors: [c(120, 200, 255, 0), c(130, 205, 255, 0.35), c(220, 245, 255, 0.9)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(tg, start: tailEnd, end: head, options: [])
ctx.restoreGState()
// glow + core
let glow = CGGradient(colorsSpace: cs, colors: [c(200, 240, 255, 0.9), c(110, 200, 255, 0.35), c(110, 200, 255, 0)] as CFArray, locations: [0, 0.35, 1])!
ctx.drawRadialGradient(glow, startCenter: head, startRadius: 0, endCenter: head, endRadius: 150, options: [])
ctx.setFillColor(c(255, 255, 255)); ctx.fillEllipse(in: CGRect(x: head.x-38, y: head.y-38, width: 76, height: 76))
ctx.restoreGState()

// subtle top highlight on the body edge
ctx.addPath(bodyPath); ctx.setStrokeColor(c(255,255,255,0.10)); ctx.setLineWidth(3); ctx.strokePath()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
