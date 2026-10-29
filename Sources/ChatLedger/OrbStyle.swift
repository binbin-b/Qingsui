import AppKit
import SwiftUI

enum OrbStyle: String, CaseIterable, Identifiable {
    case logo, mintRing, crayonApple, clearGlass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .logo: return "Logo 玻璃"
        case .mintRing: return "青绿圆环"
        case .crayonApple: return "蜡笔青苹果"
        case .clearGlass: return "纯净玻璃"
        }
    }
    var resource: String {
        switch self {
        case .logo: return "FloatingOrb"
        case .mintRing: return "FloatingOrbMint"
        case .crayonApple: return "FloatingOrbApple"
        case .clearGlass: return "FloatingOrbClear"
        }
    }
    // Lay out the supplied artwork inside a circular window, keeping its original pixels.
    // For glass artwork the viewport excludes the background and detached bottom shadow.
    var imageScale: CGFloat {
        switch self {
        case .logo: return 1.35
        case .mintRing: return 1.23
        case .crayonApple: return 1
        case .clearGlass: return 1.34
        }
    }
    var offset: CGSize {
        switch self {
        case .logo: return CGSize(width: 0.001, height: 0.0345)
        case .clearGlass: return CGSize(width: -0.004, height: 0.043)
        default: return .zero
        }
    }
}

struct OrbArtwork: View {
    let style: OrbStyle
    var diameter: CGFloat = 60
    private static let images: [OrbStyle: NSImage] = Dictionary(uniqueKeysWithValues: OrbStyle.allCases.compactMap { style in
        guard let url = Bundle.main.url(forResource: style.resource, withExtension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        return (style, image)
    })
    var body: some View {
        Group {
            if let image = Self.images[style] {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: diameter * style.imageScale, height: diameter * style.imageScale)
                    .offset(x: diameter * style.offset.width, y: diameter * style.offset.height)
            } else {
                Circle().fill(.mint.opacity(0.6)).overlay(Circle().stroke(.white, lineWidth: 1.3).frame(width: diameter * 0.22, height: diameter * 0.22))
            }
        }.frame(width: diameter, height: diameter).clipShape(Circle()).accessibilityHidden(true)
    }
}
