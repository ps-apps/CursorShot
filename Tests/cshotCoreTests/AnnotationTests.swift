import CoreGraphics
import cshotCore
import XCTest

final class AnnotationTests: XCTestCase {
    func testNormalizedGeometryRoundTripsThroughImageCoordinates() {
        let imageSize = CGSize(width: 400, height: 300)
        let point = NormalizedPoint(pixelPoint: CGPoint(x: 100, y: 75), imageSize: imageSize)
        let rect = NormalizedRect(
            pixelRect: CGRect(x: 50, y: 40, width: 200, height: 120),
            imageSize: imageSize
        )

        XCTAssertEqual(point.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.25, accuracy: 0.0001)
        XCTAssertEqual(point.pixelPoint(in: imageSize).x, 100, accuracy: 0.0001)
        XCTAssertEqual(point.pixelPoint(in: imageSize).y, 75, accuracy: 0.0001)
        XCTAssertEqual(rect.pixelRect(in: imageSize).origin.x, 50, accuracy: 0.0001)
        XCTAssertEqual(rect.pixelRect(in: imageSize).origin.y, 40, accuracy: 0.0001)
        XCTAssertEqual(rect.pixelRect(in: imageSize).width, 200, accuracy: 0.0001)
        XCTAssertEqual(rect.pixelRect(in: imageSize).height, 120, accuracy: 0.0001)
    }

    func testAnnotationMetadataEncodesToolsAndElements() throws {
        let arrow = AnnotationElement.arrow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            start: NormalizedPoint(x: 0.1, y: 0.2),
            end: NormalizedPoint(x: 0.4, y: 0.5),
            colorHex: "#FF453A",
            strokeWidth: 4
        )
        let blur = AnnotationElement.blur(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            rect: NormalizedRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        )
        let metadata = AnnotationSessionMetadata(mode: .annotated, elements: [arrow, blur])

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(AnnotationSessionMetadata.self, from: data)

        XCTAssertEqual(decoded.mode, .annotated)
        XCTAssertEqual(decoded.redactionStyle, .blur)
        XCTAssertEqual(decoded.tools, [.arrow, .blur])
        XCTAssertEqual(decoded.elements, [arrow, blur])
    }

    func testRendererPreservesImageDimensions() throws {
        let image = try makeImage(width: 80, height: 60)
        let annotations: [AnnotationElement] = [
            .rectangle(
                rect: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
                colorHex: "#0A84FF",
                strokeWidth: 3
            ),
            .text(
                origin: NormalizedPoint(x: 0.2, y: 0.2),
                value: "Check",
                colorHex: "#FFD60A",
                strokeWidth: 3
            )
        ]

        let rendered = try AnnotationRenderer().render(image: image, annotations: annotations)

        XCTAssertEqual(rendered.width, image.width)
        XCTAssertEqual(rendered.height, image.height)
    }

    func testTextAnnotationCarriesFontAndTranslation() {
        let imageSize = CGSize(width: 400, height: 300)
        let text = AnnotationElement.text(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            origin: NormalizedPoint(x: 0.25, y: 0.25),
            value: "Move me",
            colorHex: "#FFFFFF",
            strokeWidth: 3,
            fontSize: 32,
            opacity: 0.9,
            fontName: "monospaced"
        )

        let moved = text.translatedBy(pixelDelta: CGPoint(x: 40, y: 30), imageSize: imageSize)

        XCTAssertEqual(moved.start?.x ?? 0, 0.35, accuracy: 0.0001)
        XCTAssertEqual(moved.start?.y ?? 0, 0.35, accuracy: 0.0001)
        XCTAssertEqual(moved.fontName, "monospaced")
        XCTAssertEqual(moved.text, "Move me")
    }

    func testCaptureMetadataCarriesAnnotationSession() {
        let artifact = makeArtifact(
            path: "/tmp/agent-shots/annotated.png",
            annotation: AnnotationSessionMetadata(
                mode: .discarded,
                elements: []
            )
        )

        let metadata = CaptureMetadata(artifact: artifact)

        XCTAssertEqual(metadata.imagePath, "/tmp/agent-shots/annotated.png")
        XCTAssertEqual(metadata.annotation?.mode, .discarded)
        XCTAssertEqual(metadata.annotation?.elements, [])
    }

    func testPayloadFactoryUsesFinalAnnotatedImageURL() {
        let artifact = makeArtifact(
            path: "/tmp/agent-shots/final-annotated.png",
            annotation: AnnotationSessionMetadata(
                mode: .annotated,
                elements: [
                    .arrow(
                        start: NormalizedPoint(x: 0, y: 0),
                        end: NormalizedPoint(x: 1, y: 1),
                        colorHex: "#FF453A",
                        strokeWidth: 4
                    )
                ]
            )
        )

        XCTAssertEqual(
            InjectionPayloadFactory().payload(for: artifact, targetProfile: .richPaste, mode: .smart),
            .image(
                URL(fileURLWithPath: "/tmp/agent-shots/final-annotated.png"),
                fallbackText: "Screenshot: /tmp/agent-shots/final-annotated.png"
            )
        )
    }

    private func makeArtifact(path: String, annotation: AnnotationSessionMetadata?) -> CaptureArtifact {
        let imageURL = URL(fileURLWithPath: path)
        let origin = OriginContext(
            pid: 123,
            bundleId: "com.notion.id",
            appName: "Notion",
            windowTitle: "Notes",
            focusedElement: nil,
            selectedRange: nil,
            mouseLocation: .zero,
            capturedAt: Date(timeIntervalSince1970: 1)
        )

        return CaptureArtifact(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            imageURL: imageURL,
            metadataURL: imageURL.deletingPathExtension().appendingPathExtension("json"),
            width: 80,
            height: 60,
            origin: origin,
            selection: .region(CGRect(x: 0, y: 0, width: 80, height: 60)),
            annotation: annotation
        )
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.18, green: 0.20, blue: 0.24, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw NSError(domain: "AnnotationTests", code: 1)
        }

        return image
    }
}
