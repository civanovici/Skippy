import CoreGraphics

enum BookCardImageLayout {
    static let cardAspectRatio: CGFloat = 0.66

    static func scaledToFitSize(image: CGSize, in container: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else {
            return container
        }

        let scale = min(container.width / image.width, container.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    static func fitsInsideContainer(image: CGSize, container: CGSize) -> Bool {
        let scaled = scaledToFitSize(image: image, in: container)
        return scaled.width <= container.width + 0.0001 && scaled.height <= container.height + 0.0001
    }
}
