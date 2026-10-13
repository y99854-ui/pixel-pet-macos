import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import PixelPetCore

final class PetModelTests: XCTestCase {
    let work = CGRect(x: -1280, y: 40, width: 1280, height: 760)

    func testBottomPoseRequiresVerticalDetachmentToToggle() {
        for style in PetStyle.allCases {
            var pet = PetModel(position: CGPoint(x: -500, y: 48), style: style)
            XCTAssertEqual(pet.drop(in: work), .settled)
            XCTAssertEqual(pet.pose, .rest)
            XCTAssertEqual(pet.position.y, work.minY)
            pet.drag(to: CGPoint(x: -450, y: 40), in: work)
            XCTAssertEqual(pet.drop(in: work), .settled)
            XCTAssertEqual(pet.pose, .rest, "Horizontal dragging must not toggle")
            pet.drag(to: CGPoint(x: -450, y: 81), in: work)
            pet.drag(to: CGPoint(x: -450, y: 40), in: work)
            _ = pet.drop(in: work)
            XCTAssertEqual(pet.pose, .peek)
            pet.drag(to: CGPoint(x: -450, y: 140), in: work)
            _ = pet.drop(in: work)
            XCTAssertEqual(pet.pose, .none)
            pet.drag(to: CGPoint(x: -450, y: 40), in: work)
            _ = pet.drop(in: work)
            XCTAssertEqual(pet.pose, .rest)
        }
    }

    func testEyesMustBeCompletelyOutsideBeforeChangingPet() {
        for style in PetStyle.allCases {
            var pet = PetModel(position: CGPoint(x: work.minX - style.eyes.maxX + 1, y: 200), style: style)
            XCTAssertEqual(pet.drop(in: work), .returnToCenter)
            pet.position.x = work.minX - style.eyes.maxX
            XCTAssertEqual(pet.drop(in: work), .switchPet)
            pet.position = CGPoint(x: work.maxX - style.eyes.minX - 1, y: 200)
            XCTAssertEqual(pet.drop(in: work), .returnToCenter)
            pet.position.x = work.maxX - style.eyes.minX
            XCTAssertEqual(pet.drop(in: work), .switchPet)
            pet.position = CGPoint(x: -500, y: work.maxY - PetModel.size.height + style.eyes.maxY)
            XCTAssertEqual(pet.drop(in: work), .switchPet)
        }
    }

    func testBottomContactTakesPriorityOverSideCrossing() {
        var pet = PetModel(position: CGPoint(x: work.minX - 20, y: work.minY), style: .grayCat)
        XCTAssertEqual(pet.drop(in: work), .settled)
        XCTAssertEqual(pet.pose, .rest)
        XCTAssertEqual(pet.position.x, work.minX)
    }

    func testScreenClampAndCenterWithNegativeMonitorCoordinates() {
        var pet = PetModel(position: CGPoint(x: -2000, y: 2000), style: .grayCat)
        pet.clampTo(work)
        XCTAssertEqual(pet.position, CGPoint(x: work.minX, y: work.maxY - 204))
        let center = PetModel.center(in: work)
        XCTAssertEqual(center.x + 108, work.midX)
        XCTAssertEqual(center.y + 102, work.midY)
        XCTAssertEqual(PetStyle.allCases.reduce(PetStyle.grayCat) { pet, _ in pet.next }, .grayCat)
    }

    func testAllSpriteVariantsAndCushionPawAlignment() throws {
        let catalog = try SpriteCatalog.load()
        XCTAssertEqual(catalog.frames.count, 6)
        XCTAssertEqual(Set(catalog.mats.values), Set([
            ["365B79", "689AC3", "A8D5EE", "DDF2FF"],
            ["356452", "69A88D", "AFE0C7", "DDF7E9"],
            ["8B6139", "C89550", "F0CE85", "FFF0C3"],
            ["785063", "BE819A", "E9B8CB", "FFE0EC"],
            ["68506F", "A17CA5", "D7B9D7", "F1DDEA"],
            ["864F42", "CA8569", "F1B99A", "FFE1C9"]
        ]))
        for style in PetStyle.allCases {
            XCTAssertEqual(catalog.frames[style.rawValue]?.count, 4)
            for tail in 0...1 {
                for blink in [false, true] {
                    let normal = catalog.rectangles(style: style, tail: tail, blink: blink, pose: .none)
                    XCTAssertGreaterThanOrEqual(normal.count, 30)
                    XCTAssertTrue(normal.allSatisfy { $0.width > 0 && $0.height > 0 && catalog.palette[$0.color] != nil })
                    for pose in [BottomPose.rest, .peek] {
                        let rects = catalog.rectangles(style: style, tail: tail, blink: blink, pose: pose)
                        let mat = rects.filter { $0.color.hasPrefix("#") }
                        let pet = rects.filter { !$0.color.hasPrefix("#") }
                        XCTAssertEqual(mat.count, 7)
                        XCTAssertEqual(mat.map { $0.y + $0.height }.max()!, 204, accuracy: 0.001)
                        XCTAssertEqual(pet.map { $0.y + $0.height }.max()!, 192, accuracy: 0.001)
                        XCTAssertFalse(pet.contains { $0.color == "Shadow" })
                    }
                }
            }
        }
    }

    func testHourlyWaitsForUnlockedAwakeSessionAndHidesAfter30Seconds() {
        let start = Date(timeIntervalSince1970: 0)
        var clock = HourlySchedule(now: start)
        XCTAssertFalse(clock.update(now: start.addingTimeInterval(3599), interactive: true))
        XCTAssertFalse(clock.update(now: start.addingTimeInterval(3600), interactive: false))
        XCTAssertFalse(clock.update(now: start.addingTimeInterval(7200), interactive: false))
        XCTAssertTrue(clock.update(now: start.addingTimeInterval(7201), interactive: true))
        XCTAssertTrue(clock.update(now: start.addingTimeInterval(7230), interactive: true))
        XCTAssertFalse(clock.update(now: start.addingTimeInterval(7231), interactive: true))
        XCTAssertFalse(clock.update(now: start.addingTimeInterval(10830), interactive: true))
        XCTAssertTrue(clock.update(now: start.addingTimeInterval(10831), interactive: true))
        XCTAssertFalse(clock.update(now: start.addingTimeInterval(10832), interactive: false))
    }
}
