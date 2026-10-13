import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum PetStyle: String, CaseIterable, Codable {
    case grayCat = "GrayCat", corgi = "Corgi", hamster = "Hamster"
    case tuxCorgi = "TuxCorgi", blackCat = "BlackCat", flowerBloom = "FlowerBloom"

    public var title: String {
        switch self {
        case .grayCat: return "灰猫"
        case .corgi: return "柯基"
        case .hamster: return "饼干仓鼠"
        case .tuxCorgi: return "礼服柯基"
        case .blackCat: return "黑猫"
        case .flowerBloom: return "花开"
        }
    }

    // Windows sprite coordinates, measured from the top left.
    public var eyes: CGRect {
        switch self {
        case .grayCat: return CGRect(x: 84, y: 66, width: 78, height: 24)
        case .corgi: return CGRect(x: 72, y: 66, width: 90, height: 18)
        case .hamster: return CGRect(x: 72, y: 72, width: 102, height: 24)
        case .tuxCorgi: return CGRect(x: 78, y: 66, width: 96, height: 18)
        case .blackCat: return CGRect(x: 72, y: 72, width: 108, height: 18)
        case .flowerBloom: return CGRect(x: 78, y: 60, width: 108, height: 24)
        }
    }

    public var next: PetStyle {
        let styles = Self.allCases
        return styles[(styles.firstIndex(of: self)! + 1) % styles.count]
    }
}

public enum BottomPose { case none, rest, peek }
public enum DropAction: Equatable { case settled, switchPet, returnToCenter }

/// Global macOS coordinates: x grows right, y grows up; position is the pet's lower left.
public struct PetModel {
    public static let size = CGSize(width: 216, height: 204)
    public var position: CGPoint
    public var style: PetStyle
    public private(set) var pose: BottomPose = .none
    private var nextPose: BottomPose = .rest
    private var detached = false

    public init(position: CGPoint, style: PetStyle) {
        self.position = position
        self.style = style
    }

    public mutating func drag(to point: CGPoint, in work: CGRect) {
        position = point
        if pose != .none && point.y > work.minY + 40 { detached = true }
    }

    public mutating func drop(in work: CGRect) -> DropAction {
        let centerX = position.x + Self.size.width / 2
        if centerX >= work.minX && centerX <= work.maxX && position.y <= work.minY + 18 {
            if pose == .none || detached {
                pose = nextPose
                nextPose = pose == .rest ? .peek : .rest
            }
            detached = false
            position.x = clamp(position.x, work.minX, work.maxX - Self.size.width)
            position.y = work.minY
            return .settled
        }
        pose = .none
        let eyes = style.eyes
        let eyeLeft = position.x + eyes.minX
        let eyeRight = position.x + eyes.maxX
        let eyeBottom = position.y + Self.size.height - eyes.maxY
        if eyeRight <= work.minX || eyeLeft >= work.maxX || eyeBottom >= work.maxY {
            clampTo(work)
            return .switchPet
        }
        if position.x < work.minX - 1 || position.x + Self.size.width > work.maxX + 1
            || position.y + Self.size.height > work.maxY + 1 {
            return .returnToCenter
        }
        clampTo(work)
        return .settled
    }

    public mutating func resetPose() { pose = .none; detached = false }

    public mutating func clampTo(_ work: CGRect) {
        position.x = clamp(position.x, work.minX, work.maxX - Self.size.width)
        position.y = clamp(position.y, work.minY, work.maxY - Self.size.height)
    }

    public static func center(in work: CGRect) -> CGPoint {
        CGPoint(x: work.midX - size.width / 2, y: work.midY - size.height / 2)
    }
}

public func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
    max(lower, min(value, max(lower, upper)))
}

public struct PixelRect: Codable {
    public var x, y, width, height: Double
    public var color: String
    public var bounds: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

public struct SpriteCatalog: Decodable {
    public let palette: [String: [Int]] // alpha, red, green, blue
    public let frames: [String: [String: [PixelRect]]]
    public let mats: [String: [String]]

    public static func load() throws -> SpriteCatalog {
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let bundleURL = Bundle.main.url(forResource: "PixelPetMac_PixelPetCore", withExtension: "bundle"),
                  let bundle = Bundle(url: bundleURL) else { throw CocoaError(.fileNoSuchFile) }
            resources = bundle
        } else {
            resources = Bundle.module
        }
        guard let url = resources.url(forResource: "sprites", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    public func rectangles(style: PetStyle, tail: Int, blink: Bool,
                           pose: BottomPose, lookRight: Bool = false) -> [PixelRect] {
        let key = "\(tail % 2)-\((blink || pose == .rest) ? 1 : 0)"
        var result = frames[style.rawValue]?[key] ?? []
        guard pose != .none else { return result }
        result.removeAll { $0.color == "Shadow" }
        func fold(_ y: Double) -> Double {
            y <= 138 ? 75 + y * 0.72 : 174.36 + (y - 138) * 0.46
        }
        for i in result.indices {
            let end = fold(result[i].y + result[i].height)
            if pose == .peek && !blink && result[i].color == "Dark"
                && style.eyes.contains(result[i].bounds) {
                result[i].x += lookRight ? 3 : -3
            }
            result[i].y = fold(result[i].y)
            result[i].height = end - result[i].y
        }
        let lowest = result.map { $0.y + $0.height }.max() ?? 192
        for i in result.indices { result[i].y += 192 - lowest }
        let cushion: [(Double, Double, Double, Double, Int)] = [
            (2,30,32,4,0), (0,31,36,2,0), (2,31,32,2,1),
            (3,30,30,2,2), (1,31,34,1,2), (4,30,28,1,3), (3,32,30,1,1)
        ]
        return cushion.map { x, y, w, h, color in
            PixelRect(x: x * 6, y: y * 6, width: w * 6, height: h * 6,
                      color: "#" + mats[style.rawValue]![color])
        } + result
    }
}

public struct HourlySchedule {
    public let interval: TimeInterval
    public let duration: TimeInterval
    public private(set) var nextAppearance: Date
    public private(set) var hideAt: Date?

    public init(now: Date, interval: TimeInterval = 3600, duration: TimeInterval = 30) {
        self.interval = interval
        self.duration = duration
        nextAppearance = now.addingTimeInterval(interval)
    }

    /// A due appearance waits for the active, awake desktop; missed hours do not stack.
    public mutating func update(now: Date, interactive: Bool) -> Bool {
        if let end = hideAt {
            if now >= end || !interactive {
                hideAt = nil
                nextAppearance = now.addingTimeInterval(interval)
            }
        } else if now >= nextAppearance && interactive {
            hideAt = now.addingTimeInterval(duration)
        }
        return hideAt != nil
    }
}
