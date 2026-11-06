import AppKit
import XCTest

@testable import RigiUI

@MainActor
final class ClassicFormControlTests: XCTestCase {
  // MARK: - Value slider

  func testTypedAndDraggedValuesAreClampedRoundedAndReportedOnce() {
    let slider = ClassicValueSlider(title: "Size", range: 1...500, value: 20, unit: "px")
    var reports: [(Double, ClassicValueSlider.Phase)] = []
    slider.onChange = { reports.append(($0, $1)) }

    slider.fieldControl.stringValue = "250px"
    slider.commit(ClassicValueSlider.number(from: slider.fieldControl.stringValue) ?? .nan,
                  phase: .committed)
    slider.commit(9999, phase: .committed)
    slider.commit(12.6, phase: .committed)
    slider.commit(12.6, phase: .committed)

    XCTAssertEqual(reports.map(\.0), [250, 500, 13])
    XCTAssertEqual(slider.value, 13)
    XCTAssertEqual(slider.fieldControl.stringValue, "13")
    XCTAssertEqual(slider.sliderControl.doubleValue, 13)
  }

  func testADragReportsTrackingAndItsReleaseCommitsEvenInPlace() {
    let slider = ClassicValueSlider(title: "Opacity", range: 0...100, value: 50, unit: "%")
    var phases: [ClassicValueSlider.Phase] = []
    slider.onChange = { _, phase in phases.append(phase) }

    slider.commit(60, phase: .tracking)
    slider.commit(70, phase: .tracking)
    slider.commit(70, phase: .committed)
    // Without a drag before it, a release that changes nothing is silent.
    slider.commit(70, phase: .committed)

    XCTAssertEqual(phases, [.tracking, .tracking, .committed])
  }

  func testTextThatIsNotANumberPutsTheValueBack() {
    XCTAssertEqual(ClassicValueSlider.number(from: " 42 % "), 42)
    XCTAssertEqual(ClassicValueSlider.number(from: "-3,5"), -3.5)
    XCTAssertNil(ClassicValueSlider.number(from: "abc"))
    XCTAssertNil(ClassicValueSlider.number(from: ""))

    let slider = ClassicValueSlider(title: nil, range: 0...1, value: 0.25, fractionDigits: 2)
    XCTAssertEqual(slider.fieldControl.stringValue, "0.25")
    slider.step(by: 1)
    XCTAssertEqual(slider.value, 0.26, accuracy: 1e-9)
    slider.step(by: -10)
    XCTAssertEqual(slider.value, 0.16, accuracy: 1e-9)
  }

  func testSettingTheValueOrDisablingDoesNotReport() {
    let slider = ClassicValueSlider(title: "Rate", range: 0...100, value: 10)
    var reports = 0
    slider.onChange = { _, _ in reports += 1 }

    slider.value = 80
    slider.isEnabled = false
    slider.commit(30, phase: .committed)

    XCTAssertEqual(reports, 0)
    XCTAssertEqual(slider.value, 80)
    XCTAssertFalse(slider.sliderControl.isEnabled)
    XCTAssertEqual(slider.sliderControl.accessibilityLabel(), "Rate")
    XCTAssertEqual(slider.fieldControl.accessibilityLabel(), "Rate value")
  }

  // MARK: - Palette button bar

  func testEachItemIsANamedButtonThatRunsItsAction() throws {
    var ran: [String] = []
    let image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) ?? NSImage()
    let bar = ClassicPaletteButtonBar(
      items: [
        .init(id: "new", title: "New Layer", image: image) { ran.append("new") },
        .init(id: "duplicate", title: "Duplicate Layer", image: image) { ran.append("duplicate") },
      ],
      trailingItems: [.init(id: "delete", title: "Delete Layer", image: image) { ran.append("delete") }]
    )

    let delete = try XCTUnwrap(bar.button(for: "delete"))
    XCTAssertEqual(delete.toolTip, "Delete Layer")
    XCTAssertEqual(delete.accessibilityLabel(), "Delete Layer")

    try XCTUnwrap(bar.button(for: "new")).performClick(nil)
    delete.performClick(nil)
    bar.setEnabled(false, forItem: "duplicate")
    try XCTUnwrap(bar.button(for: "duplicate")).performClick(nil)

    XCTAssertEqual(ran, ["new", "delete"])
    XCTAssertFalse(bar.isEnabled(item: "duplicate"))
    XCTAssertTrue(bar.isEnabled(item: "new"))
    XCTAssertEqual(bar.fittingSize.height, ClassicPaletteButtonBar.height)
  }

  // MARK: - Status bar

  func testAnEditableZoomReportsTypedZoomsAndKeepsTheShownOne() {
    let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 22))
    var zooms: [Int] = []
    bar.onZoomTo = { zooms.append($0) }
    bar.setZoom(percent: 100)

    XCTAssertTrue(bar.zoomFieldControl.isHidden, "Off by default, as Lucerne and Sion use it")
    bar.isZoomEditable = true
    XCTAssertFalse(bar.zoomFieldControl.isHidden)
    XCTAssertEqual(bar.zoomFieldControl.stringValue, "100%")

    bar.zoomFieldControl.stringValue = " 250 % "
    bar.zoomFieldControl.sendAction(bar.zoomFieldControl.action, to: bar.zoomFieldControl.target)
    bar.zoomFieldControl.stringValue = "lots"
    bar.zoomFieldControl.sendAction(bar.zoomFieldControl.action, to: bar.zoomFieldControl.target)

    XCTAssertEqual(zooms, [250])
    // The application decides the zoom and says so through setZoom.
    XCTAssertEqual(bar.zoomFieldControl.stringValue, "100%")
    bar.setZoom(percent: 250)
    XCTAssertEqual(bar.zoomFieldControl.stringValue, "250%")

    XCTAssertEqual(StatusBarView.zoomPercent(from: "12.6"), 13)
    XCTAssertNil(StatusBarView.zoomPercent(from: "0"))
    XCTAssertNil(StatusBarView.zoomPercent(from: "-50%"))
  }

  func testProgressShowsWithAnOptionalCancelAndAccessoriesSitBeforeTheZoom() {
    let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 22))
    var cancels = 0
    XCTAssertFalse(bar.isShowingProgress)

    bar.showProgress(fraction: 0.4) { cancels += 1 }
    XCTAssertTrue(bar.isShowingProgress)
    XCTAssertFalse(bar.progressControl.isIndeterminate)
    XCTAssertEqual(bar.progressControl.doubleValue, 0.4, accuracy: 1e-9)
    XCTAssertFalse(bar.cancelControl.isHidden)
    bar.cancelControl.performClick(nil)
    XCTAssertEqual(cancels, 1)

    bar.showProgress(fraction: nil)
    XCTAssertTrue(bar.progressControl.isIndeterminate)
    XCTAssertTrue(bar.cancelControl.isHidden, "No cancel handler, no button")

    bar.hideProgress()
    XCTAssertFalse(bar.isShowingProgress)

    let info = NSButton(title: "800 × 600", target: nil, action: nil)
    bar.setAccessoryViews([info])
    let row = bar.subviews.compactMap { $0 as? NSStackView }.first
    let order = row?.views(in: .trailing) ?? []
    XCTAssertEqual(order.firstIndex(of: info), order.count - 2, "Just before the zoom cluster")
    bar.setAccessoryViews([])
    XCTAssertFalse(row?.views.contains(info) ?? true)
  }
}
