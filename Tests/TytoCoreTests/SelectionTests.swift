import Testing
@testable import TytoCore

@Suite struct SelectionModelTests {
    let bounds = PixelRect(x: 0, y: 0, width: 1000, height: 800)
    var model: SelectionModel { SelectionModel(bounds: bounds) }

    @Test func dragCreatesNormalizedSelection() {
        var m = model
        m.press(at: PixelPoint(x: 300, y: 300), slop: 8)
        m.drag(to: PixelPoint(x: 100, y: 150))
        #expect(m.rect == PixelRect(x: 100, y: 150, width: 200, height: 150))
        m.release()
        #expect(m.phase == .idle)
        #expect(m.hasSelection)
    }

    @Test func dragIsClampedToBounds() {
        var m = model
        m.press(at: PixelPoint(x: 900, y: 700), slop: 8)
        m.drag(to: PixelPoint(x: 5000, y: 5000))
        #expect(m.rect == PixelRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func zeroSizedDragClearsOnRelease() {
        var m = model
        m.press(at: PixelPoint(x: 10, y: 10), slop: 8)
        m.drag(to: PixelPoint(x: 10, y: 40))
        m.release()
        #expect(m.rect == nil)
        #expect(!m.hasSelection)
    }

    @Test func pressInsideMovesAndStaysInBounds() {
        var m = SelectionModel(bounds: bounds, rect: PixelRect(x: 100, y: 100, width: 200, height: 100))
        m.press(at: PixelPoint(x: 150, y: 150), slop: 8)
        #expect(m.phase == .moving(grabOffset: PixelPoint(x: 50, y: 50)))
        m.drag(to: PixelPoint(x: 950, y: 150))
        #expect(m.rect == PixelRect(x: 800, y: 100, width: 200, height: 100))
        m.release()
        #expect(m.rect?.size == PixelSize(width: 200, height: 100))
    }

    @Test func handleHitStartsResize() {
        var m = SelectionModel(bounds: bounds, rect: PixelRect(x: 100, y: 100, width: 200, height: 100))
        #expect(m.hitTest(PixelPoint(x: 303, y: 197), slop: 8) == .handle(.bottomRight))
        #expect(m.hitTest(PixelPoint(x: 200, y: 100), slop: 8) == .handle(.top))
        #expect(m.hitTest(PixelPoint(x: 200, y: 150), slop: 8) == .inside)
        #expect(m.hitTest(PixelPoint(x: 600, y: 600), slop: 8) == .outside)
        m.press(at: PixelPoint(x: 303, y: 197), slop: 8)
        m.drag(to: PixelPoint(x: 400, y: 300))
        #expect(m.rect == PixelRect(x: 100, y: 100, width: 300, height: 200))
    }

    @Test func resizingPastOppositeCornerFlips() {
        var m = SelectionModel(bounds: bounds, rect: PixelRect(x: 100, y: 100, width: 200, height: 100))
        m.press(at: PixelPoint(x: 100, y: 100), slop: 8)  // topLeft
        m.drag(to: PixelPoint(x: 400, y: 300))
        #expect(m.rect == PixelRect(x: 300, y: 200, width: 100, height: 100))
    }

    @Test func edgeHandleOnlyChangesItsAxis() {
        var m = SelectionModel(bounds: bounds, rect: PixelRect(x: 100, y: 100, width: 200, height: 100))
        m.press(at: PixelPoint(x: 300, y: 150), slop: 8)  // right
        m.drag(to: PixelPoint(x: 350, y: 700))
        #expect(m.rect == PixelRect(x: 100, y: 100, width: 250, height: 100))
    }

    @Test func pressOutsideExistingSelectionStartsNewOne() {
        var m = SelectionModel(bounds: bounds, rect: PixelRect(x: 100, y: 100, width: 200, height: 100))
        m.press(at: PixelPoint(x: 600, y: 600), slop: 8)
        #expect(m.rect == nil)
        m.drag(to: PixelPoint(x: 650, y: 650))
        #expect(m.rect == PixelRect(x: 600, y: 600, width: 50, height: 50))
    }

    @Test func setClampsAndRejectsEmpty() {
        var m = model
        m.set(PixelRect(x: 900, y: 700, width: 500, height: 500))
        #expect(m.rect == PixelRect(x: 900, y: 700, width: 100, height: 100))
        m.set(PixelRect(x: 2000, y: 2000, width: 10, height: 10))
        #expect(m.rect == nil)
    }
}
