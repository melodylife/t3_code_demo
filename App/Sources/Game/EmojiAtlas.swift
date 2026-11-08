import SpriteKit
import UIKit

/// Rasterizes emoji and SF Symbols once per (glyph, point size).
///
/// Emoji glyphs differ in advance width and ascent, so drawing them into a fixed
/// square and using that image as the sprite texture is the only way to guarantee
/// every tile is centred identically.
final class EmojiAtlas {
    private var emojiCache: [String: SKTexture] = [:]
    private var symbolCache: [String: SKTexture] = [:]

    func emoji(_ symbol: String, pointSize: CGFloat) -> SKTexture {
        let key = "\(symbol)#\(Int(pointSize.rounded()))"
        if let cached = emojiCache[key] { return cached }

        let side = ceil(pointSize * 1.3)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { _ in
            let font = UIFont.systemFont(ofSize: pointSize)
            let attributed = NSAttributedString(string: symbol, attributes: [.font: font])
            let bounds = attributed.size()
            attributed.draw(at: CGPoint(x: (side - bounds.width) / 2,
                                        y: (side - bounds.height) / 2))
        }
        let texture = SKTexture(image: image)
        emojiCache[key] = texture
        return texture
    }

    func symbol(_ name: String, pointSize: CGFloat, color: UIColor) -> SKTexture? {
        let key = "\(name)#\(Int(pointSize.rounded()))#\(color.description)"
        if let cached = symbolCache[key] { return cached }

        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let base = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
        let tinted = base.withTintColor(color, renderingMode: .alwaysOriginal)
        let texture = SKTexture(image: tinted)
        symbolCache[key] = texture
        return texture
    }
}
