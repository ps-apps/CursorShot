import AppKit
import CursorShotCore
import Foundation

final class AnnotationInspectorView: NSView {
    var onColorChanged: ((String) -> Void)?
    var onStrokeWidthChanged: ((Double) -> Void)?
    var onOpacityChanged: ((Double) -> Void)?
    var onFontSizeChanged: ((Double) -> Void)?
    var onFontNameChanged: ((String) -> Void)?

    private let colors: [(name: String, hex: String)] = [
        ("Red", "#FF453A"),
        ("Yellow", "#FFD60A"),
        ("Blue", "#0A84FF"),
        ("Green", "#32D74B"),
        ("White", "#FFFFFF"),
        ("Black", "#000000")
    ]
    private let fonts: [(name: String, value: String)] = [
        ("System", "system"),
        ("Rounded", "rounded"),
        ("Mono", "monospaced"),
        ("Serif", "serif")
    ]

    private let toolTitle = NSTextField(labelWithString: "Arrow")
    private let colorRow = NSStackView()
    private let strokeRow = NSStackView()
    private let opacityRow = NSStackView()
    private let fontRow = NSStackView()
    private let fontNameRow = NSStackView()
    private let colorPalette = NSStackView()
    private let fontNameControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private var colorButtons: [NSButton] = []
    private let strokeSlider = NSSlider(value: 4, minValue: 1, maxValue: 18, target: nil, action: nil)
    private let opacitySlider = NSSlider(value: 1, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let fontSlider = NSSlider(value: 28, minValue: 12, maxValue: 72, target: nil, action: nil)
    private let strokeValue = NSTextField(labelWithString: "4 px")
    private let opacityValue = NSTextField(labelWithString: "100%")
    private let fontValue = NSTextField(labelWithString: "28 pt")
    private let strokeLabel = NSTextField(labelWithString: "Stroke")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        buildLayout()
        configureControls()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        tool: AnnotationTool,
        colorHex: String,
        strokeWidth: Double,
        opacity: Double,
        fontSize: Double,
        fontName: String
    ) {
        toolTitle.stringValue = title(for: tool)
        strokeLabel.stringValue = strokeTitle(for: tool)

        updateColorSelection(colorHex)
        if let fontIndex = fonts.firstIndex(where: { $0.value == fontName }) {
            fontNameControl.selectItem(at: fontIndex)
        }

        strokeSlider.doubleValue = strokeWidth
        opacitySlider.doubleValue = opacity
        fontSlider.doubleValue = fontSize
        updateValueLabels()

        colorRow.isHidden = tool == .blur || tool == .crop
        strokeRow.isHidden = tool == .text || tool == .highlight || tool == .crop
        opacityRow.isHidden = tool == .blur || tool == .crop
        fontRow.isHidden = tool != .text
        fontNameRow.isHidden = tool != .text
    }

    private func buildLayout() {
        translatesAutoresizingMaskIntoConstraints = false

        let titleCaption = NSTextField(labelWithString: "Tool")
        titleCaption.font = .systemFont(ofSize: 11, weight: .semibold)
        titleCaption.textColor = .secondaryLabelColor

        toolTitle.font = .systemFont(ofSize: 18, weight: .semibold)

        colorRow.orientation = .vertical
        colorRow.spacing = 6
        colorRow.addArrangedSubview(rowLabel("Color"))
        colorPalette.orientation = .horizontal
        colorPalette.alignment = .centerY
        colorPalette.spacing = 8
        colorButtons = colors.enumerated().map { index, color in
            makeColorButton(index: index, colorHex: color.hex, accessibilityLabel: color.name)
        }
        colorButtons.forEach { colorPalette.addArrangedSubview($0) }
        colorRow.addArrangedSubview(colorPalette)

        strokeRow.orientation = .vertical
        strokeRow.spacing = 6
        strokeRow.addArrangedSubview(strokeLabel)
        strokeRow.addArrangedSubview(valueRow(slider: strokeSlider, value: strokeValue))

        opacityRow.orientation = .vertical
        opacityRow.spacing = 6
        opacityRow.addArrangedSubview(rowLabel("Opacity"))
        opacityRow.addArrangedSubview(valueRow(slider: opacitySlider, value: opacityValue))

        fontRow.orientation = .vertical
        fontRow.spacing = 6
        fontRow.addArrangedSubview(rowLabel("Text Size"))
        fontRow.addArrangedSubview(valueRow(slider: fontSlider, value: fontValue))

        fontNameRow.orientation = .vertical
        fontNameRow.spacing = 6
        fontNameRow.addArrangedSubview(rowLabel("Font"))
        fontNameRow.addArrangedSubview(fontNameControl)

        let stack = NSStackView(views: [
            titleCaption,
            toolTitle,
            separator(),
            colorRow,
            strokeRow,
            opacityRow,
            fontRow,
            fontNameRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 16, bottom: 18, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 264),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            fontNameControl.widthAnchor.constraint(equalToConstant: 218),
            strokeSlider.widthAnchor.constraint(equalToConstant: 166),
            opacitySlider.widthAnchor.constraint(equalToConstant: 166),
            fontSlider.widthAnchor.constraint(equalToConstant: 166)
        ])
    }

    private func configureControls() {
        fontNameControl.addItems(withTitles: fonts.map(\.name))
        fontNameControl.target = self
        fontNameControl.action = #selector(fontNameChanged)

        strokeSlider.numberOfTickMarks = 18
        strokeSlider.allowsTickMarkValuesOnly = true
        strokeSlider.target = self
        strokeSlider.action = #selector(strokeChanged)

        opacitySlider.numberOfTickMarks = 10
        opacitySlider.allowsTickMarkValuesOnly = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)

        fontSlider.numberOfTickMarks = 16
        fontSlider.allowsTickMarkValuesOnly = true
        fontSlider.target = self
        fontSlider.action = #selector(fontChanged)
    }

    @objc private func colorChanged(_ sender: NSButton) {
        let index = max(0, min(sender.tag, colors.count - 1))
        onColorChanged?(colors[index].hex)
        updateColorSelection(colors[index].hex)
    }

    @objc private func strokeChanged() {
        strokeSlider.doubleValue = round(strokeSlider.doubleValue)
        updateValueLabels()
        onStrokeWidthChanged?(strokeSlider.doubleValue)
    }

    @objc private func opacityChanged() {
        opacitySlider.doubleValue = max(0.1, min(1, opacitySlider.doubleValue))
        updateValueLabels()
        onOpacityChanged?(opacitySlider.doubleValue)
    }

    @objc private func fontChanged() {
        fontSlider.doubleValue = round(fontSlider.doubleValue)
        updateValueLabels()
        onFontSizeChanged?(fontSlider.doubleValue)
    }

    @objc private func fontNameChanged() {
        let index = max(0, min(fontNameControl.indexOfSelectedItem, fonts.count - 1))
        onFontNameChanged?(fonts[index].value)
    }

    private func updateValueLabels() {
        strokeValue.stringValue = "\(Int(round(strokeSlider.doubleValue))) px"
        opacityValue.stringValue = "\(Int(round(opacitySlider.doubleValue * 100)))%"
        fontValue.stringValue = "\(Int(round(fontSlider.doubleValue))) pt"
    }

    private func title(for tool: AnnotationTool) -> String {
        switch tool {
        case .arrow:
            "Arrow"
        case .line:
            "Line"
        case .rectangle:
            "Rectangle"
        case .oval:
            "Oval"
        case .highlight:
            "Highlight"
        case .text:
            "Text"
        case .blur:
            "Blur"
        case .crop:
            "Crop"
        }
    }

    private func strokeTitle(for tool: AnnotationTool) -> String {
        switch tool {
        case .blur:
            "Strength"
        default:
            "Stroke"
        }
    }

    private func valueRow(slider: NSSlider, value: NSTextField) -> NSStackView {
        value.alignment = .right
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        value.textColor = .secondaryLabelColor
        value.widthAnchor.constraint(equalToConstant: 46).isActive = true

        let stack = NSStackView(views: [slider, value])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func rowLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func makeColorButton(index: Int, colorHex: String, accessibilityLabel: String) -> NSButton {
        let button = NSButton(frame: CGRect(x: 0, y: 0, width: 26, height: 26))
        button.title = ""
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = nsColor(from: colorHex).cgColor
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.separatorColor.cgColor
        button.tag = index
        button.target = self
        button.action = #selector(colorChanged(_:))
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
        return button
    }

    private func updateColorSelection(_ colorHex: String) {
        for (index, button) in colorButtons.enumerated() {
            let selected = colors[index].hex == colorHex
            button.layer?.borderWidth = selected ? 3 : 1
            button.layer?.borderColor = selected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.cgColor
        }
    }

    private func nsColor(from hex: String) -> NSColor {
        let trimmed = hex
            .trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))

        guard trimmed.count == 6, let rawValue = UInt32(trimmed, radix: 16) else {
            return .systemRed
        }

        return NSColor(
            red: CGFloat((rawValue & 0xFF0000) >> 16) / 255,
            green: CGFloat((rawValue & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rawValue & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
