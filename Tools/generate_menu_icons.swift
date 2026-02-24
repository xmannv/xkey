import Cocoa
import CoreGraphics

// Create PDF with rounded-rect background + star cutout (matches system input method icons)
// Uses even-odd fill rule: black rounded rect with star shape cut out (transparent)
func createStarPDF(at path: String, width: CGFloat, height: CGFloat) {
    let url = URL(fileURLWithPath: path)
    var rect = CGRect(x: 0, y: 0, width: width, height: height)
    
    guard let context = CGContext(url as CFURL, mediaBox: &rect, nil) else {
        print("Failed to create PDF context for \(path)")
        return
    }
    
    context.beginPage(mediaBox: &rect)
    
    // Set black fill
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    
    let combinedPath = CGMutablePath()
    
    // 1. Rounded rectangle background (corner radius ~3.5 proportional to height)
    let cornerRadius: CGFloat = 3.5
    let bgRect = CGRect(x: 0, y: 0, width: width, height: height)
    combinedPath.addRoundedRect(in: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
    
    // 2. Star cutout centered in the rect
    let cx = width / 2
    let cy = height / 2
    let outerRadius: CGFloat = min(width, height) / 2 * 0.78
    let innerRadius: CGFloat = outerRadius * 0.38
    let points = 5
    
    for i in 0..<(points * 2) {
        let angle = CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / CGFloat(points)
        let r = (i % 2 == 0) ? outerRadius : innerRadius
        let x = cx + r * cos(angle)
        let y = cy + r * sin(angle)
        
        if i == 0 {
            combinedPath.move(to: CGPoint(x: x, y: y))
        } else {
            combinedPath.addLine(to: CGPoint(x: x, y: y))
        }
    }
    combinedPath.closeSubpath()
    
    // Fill with even-odd rule: rounded rect is filled, star is cut out
    context.addPath(combinedPath)
    context.fillPath(using: .evenOdd)
    
    context.endPage()
    context.closePDF()
    
    print("✅ Created \(path) (\(Int(width))×\(Int(height))pt)")
}

// Create PDF with rounded-rect background + "VI" text cutout
func createVIPDF(at path: String, width: CGFloat, height: CGFloat) {
    let url = URL(fileURLWithPath: path)
    var rect = CGRect(x: 0, y: 0, width: width, height: height)
    
    guard let context = CGContext(url as CFURL, mediaBox: &rect, nil) else {
        print("Failed to create PDF context for \(path)")
        return
    }
    
    context.beginPage(mediaBox: &rect)
    
    let combinedPath = CGMutablePath()
    
    // 1. Rounded rectangle background
    let cornerRadius: CGFloat = 3.5
    let bgRect = CGRect(x: 0, y: 0, width: width, height: height)
    combinedPath.addRoundedRect(in: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
    
    // 2. "VI" text as path for cutout
    let font = CTFontCreateWithName("SFProText-Bold" as CFString, 12, nil)
    let text = "VI" as CFString
    let attrString = CFAttributedStringCreateMutable(nil, 0)!
    CFAttributedStringReplaceString(attrString, CFRange(location: 0, length: 0), text)
    CFAttributedStringSetAttribute(attrString, CFRange(location: 0, length: CFStringGetLength(text)), kCTFontAttributeName, font)
    
    let line = CTLineCreateWithAttributedString(attrString)
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    
    // Get text bounds for centering
    let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    let textX = (width - textBounds.width) / 2 - textBounds.origin.x
    let textY = (height - textBounds.height) / 2 - textBounds.origin.y
    
    // Convert text glyphs to path
    for run in runs {
        let runFont = CFDictionaryGetValue(CTRunGetAttributes(run) as CFDictionary, 
            Unmanaged.passUnretained(kCTFontAttributeName).toOpaque())
        let ctFont = unsafeBitCast(runFont, to: CTFont.self)
        
        let glyphCount = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
        var positions = [CGPoint](repeating: .zero, count: glyphCount)
        CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)
        
        for i in 0..<glyphCount {
            if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) {
                var transform = CGAffineTransform(translationX: textX + positions[i].x, y: textY + positions[i].y)
                if let movedPath = glyphPath.copy(using: &transform) {
                    combinedPath.addPath(movedPath)
                }
            }
        }
    }
    
    // Fill with even-odd rule: rounded rect filled, text cut out
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.addPath(combinedPath)
    context.fillPath(using: .evenOdd)
    
    context.endPage()
    context.closePDF()
    
    print("✅ Created \(path) (\(Int(width))×\(Int(height))pt)")
}

// Resolve output directory relative to this script's location (Tools/ -> ../XKeyIM/)
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let outputDir = (scriptDir as NSString).appendingPathComponent("../XKeyIM")

// Generate both icons at 20×16pt
let width: CGFloat = 20
let height: CGFloat = 16

createStarPDF(
    at: (outputDir as NSString).appendingPathComponent("MenuIcon.pdf"),
    width: width,
    height: height
)

createVIPDF(
    at: (outputDir as NSString).appendingPathComponent("MenuIconVI.pdf"),
    width: width,
    height: height
)

print("\nDone! Both icons: black rounded-rect background + white glyph cutout (even-odd fill).")
print("macOS will auto-tint these as template images in the menu bar.")
