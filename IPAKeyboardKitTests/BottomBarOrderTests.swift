//
//  BottomBarOrderTests.swift
//  IPAKeyboardKitTests
//
//  Pins the per-idiom bottom-bar order behind `KeyboardView.bottomBar`
//  (issue #208): the panel-switch key keeps the left edge on iPhone, where
//  the system keyboard corners `123`, but yields it to the globe on iPad,
//  where the system keyboard corners the globe. Everything else about the
//  bar — which keys it has and the function row's own order — is identical
//  on both idioms.
//

import UIKit
import Testing
@testable import IPAKeyboardKit

struct BottomBarOrderTests {

    /// The bundled shape: every default layout's function row is
    /// globe / space / ⌫ / return, with a "more" switch key on the panel.
    private let switchKey = Key(action: .switchPanel("More"), label: "more")
    private let functionRow = [
        Key(action: .nextKeyboard, label: "🌐"),
        Key(action: .space, label: "space", widthFactor: 3),
        Key(action: .backspace, label: "⌫"),
        Key(action: .return, label: "return", widthFactor: 1.5),
    ]

    /// Idioms that are not iPad, including ones no build of this keyboard
    /// runs on — the rule is "iPad leads with the globe", so everything else
    /// must fall through to the iPhone order rather than to a special case.
    private let nonPadIdioms: [UIUserInterfaceIdiom] =
        [.phone, .unspecified, .mac, .tv, .carPlay]

    private func actions(_ keys: [Key]) -> [KeyAction] { keys.map(\.action) }

    // MARK: The two conventions

    @Test func iPhoneKeepsTheSwitchKeyAtTheLeftEdge() {
        let keys = BottomBarOrder.keys(
            switchKey: switchKey, functionRowKeys: functionRow, idiom: .phone)
        #expect(actions(keys) == [
            .switchPanel("More"), .nextKeyboard, .space, .backspace, .return,
        ])
    }

    @Test func iPadGivesTheLeftEdgeToTheGlobeWithTheSwitchKeyNext() {
        let keys = BottomBarOrder.keys(
            switchKey: switchKey, functionRowKeys: functionRow, idiom: .pad)
        #expect(actions(keys) == [
            .nextKeyboard, .switchPanel("More"), .space, .backspace, .return,
        ])
    }

    @Test func onlyIPadLeadsWithTheGlobe() {
        for idiom in nonPadIdioms {
            let keys = BottomBarOrder.keys(
                switchKey: switchKey, functionRowKeys: functionRow, idiom: idiom)
            #expect(actions(keys).first == .switchPanel("More"),
                    "idiom \(idiom.rawValue) should keep the iPhone order")
        }
    }

    @Test func bothIdiomsRenderTheSameKeysAndKeepTheFunctionRowsOwnOrder() {
        let phone = BottomBarOrder.keys(
            switchKey: switchKey, functionRowKeys: functionRow, idiom: .phone)
        let pad = BottomBarOrder.keys(
            switchKey: switchKey, functionRowKeys: functionRow, idiom: .pad)
        #expect(Set(phone) == Set(pad))
        // The switch key moves; the function row is never permuted.
        #expect(phone.filter { $0 != switchKey } == functionRow)
        #expect(pad.filter { $0 != switchKey } == functionRow)
    }

    // MARK: Bars without a globe to defer to

    @Test func strippedGlobeLeavesTheSwitchKeyLeftmostOnBothIdioms() {
        // What the extension renders when `needsInputModeSwitchKey` is false
        // (this keyboard is the only one installed): with the globe filtered
        // out, both conventions agree.
        let stripped = functionRow.filter { $0.action != .nextKeyboard }
        for idiom in [UIUserInterfaceIdiom.phone, .pad] {
            let keys = BottomBarOrder.keys(
                switchKey: switchKey, functionRowKeys: stripped, idiom: idiom)
            #expect(actions(keys) == [.switchPanel("More"), .space, .backspace, .return])
        }
    }

    @Test func aGlobeInsideTheRowDoesNotDisplaceTheSwitchKey() {
        // A user-authored function row that puts the globe somewhere other
        // than the front has chosen its own order: the switch key goes to the
        // front rather than being spliced in mid-row.
        let custom = [
            Key(action: .space, label: "space", widthFactor: 3),
            Key(action: .nextKeyboard, label: "🌐"),
            Key(action: .backspace, label: "⌫"),
        ]
        for idiom in [UIUserInterfaceIdiom.phone, .pad] {
            let keys = BottomBarOrder.keys(
                switchKey: switchKey, functionRowKeys: custom, idiom: idiom)
            #expect(actions(keys) == [.switchPanel("More"), .space, .nextKeyboard, .backspace])
        }
    }

    @Test func aSecondLeadingGlobeStaysWithTheFirst() {
        // Degenerate layout, defined behavior: the switch key clears the whole
        // leading globe run instead of splitting it.
        let doubled = [Key(action: .nextKeyboard)] + functionRow
        let keys = BottomBarOrder.keys(
            switchKey: switchKey, functionRowKeys: doubled, idiom: .pad)
        #expect(actions(keys) == [
            .nextKeyboard, .nextKeyboard, .switchPanel("More"),
            .space, .backspace, .return,
        ])
    }

    // MARK: Degenerate bars

    @Test func noSwitchKeyLeavesTheFunctionRowUntouched() {
        for idiom in [UIUserInterfaceIdiom.phone, .pad] {
            let keys = BottomBarOrder.keys(
                switchKey: nil, functionRowKeys: functionRow, idiom: idiom)
            #expect(keys == functionRow)
        }
    }

    @Test func aSwitchKeyWithNoFunctionRowIsTheWholeBar() {
        for idiom in [UIUserInterfaceIdiom.phone, .pad] {
            let keys = BottomBarOrder.keys(
                switchKey: switchKey, functionRowKeys: [], idiom: idiom)
            #expect(keys == [switchKey])
        }
    }

    @Test func neitherPieceMeansNoBar() {
        // `KeyboardView` renders no bottom bar at all for this — an empty
        // result is what it keys that decision off.
        for idiom in [UIUserInterfaceIdiom.phone, .pad] {
            let keys = BottomBarOrder.keys(
                switchKey: nil, functionRowKeys: [], idiom: idiom)
            #expect(keys.isEmpty)
        }
    }

    // MARK: Against the real bundled layouts

    @Test func everyBundledPanelCornersTheGlobeOnIPadAndTheSwitchKeyOnIPhone() throws {
        for layout in LayoutStore().bundledLayouts() {
            for arrangement in layout.arrangements {
                let functionRowKeys = try #require(arrangement.functionRow).keys
                for panel in arrangement.panels {
                    let switchKey = try #require(panel.switchKey)
                    let panelPath = "\(layout.name) / \(panel.name)"

                    let pad = actions(BottomBarOrder.keys(
                        switchKey: switchKey,
                        functionRowKeys: functionRowKeys,
                        idiom: .pad))
                    let padLead = Array(pad.prefix(2))
                    #expect(padLead == [.nextKeyboard, switchKey.action], "\(panelPath) on iPad")

                    let phone = actions(BottomBarOrder.keys(
                        switchKey: switchKey,
                        functionRowKeys: functionRowKeys,
                        idiom: .phone))
                    let phoneLead = Array(phone.prefix(2))
                    #expect(phoneLead == [switchKey.action, .nextKeyboard], "\(panelPath) on iPhone")
                }
            }
        }
    }
}
