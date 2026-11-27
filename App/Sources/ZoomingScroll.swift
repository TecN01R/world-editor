import SwiftUI
import UIKit

/// SwiftUI content of a known size in iOS's own zooming scroll view, as Photos zooms a picture
/// (Kevin, 2026-11-27, of Connections: "Won't the inability to zoom the connections be a
/// problem?"): pinch to zoom around the fingers, double-tap to zoom in, and again to see it all.
/// It opens at full size on `focus` (a point in the content), if one is given.
struct ZoomingScroll<Content: View>: UIViewRepresentable {
    let size: CGSize
    let focus: CGPoint?
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(UIHostingController(rootView: content())) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .clear
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.maximumZoomScale = 2
        scroll.contentInsetAdjustmentBehavior = .always
        let host = context.coordinator.host
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []   // the content is laid out by its own coordinates, not the screen's edges
        host.view.frame = CGRect(origin: .zero, size: size)
        context.coordinator.size = size
        scroll.addSubview(host.view)
        scroll.contentSize = size
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(double)
        context.coordinator.focus = focus
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let host = context.coordinator.host
        host.rootView = content()
        if context.coordinator.size != size {   // the world grew: the content's new size, at the zoom it's at
            context.coordinator.size = size
            host.view.frame = CGRect(origin: .zero, size: CGSize(width: size.width * scroll.zoomScale,
                                                                 height: size.height * scroll.zoomScale))
            scroll.contentSize = host.view.frame.size
        }
        // Zoomed out, it can show the whole world on the screen, and no further.
        DispatchQueue.main.async { context.coordinator.layOut(scroll) }
    }

    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<Content>
        var size: CGSize = .zero
        var focus: CGPoint?

        init(_ host: UIHostingController<Content>) { self.host = host }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centre(scrollView) }

        /// The smallest zoom shows the whole content on the screen; then the first time there's
        /// room, the view goes to `focus`.
        func layOut(_ scroll: UIScrollView) {
            guard scroll.bounds.width > 0, size.width > 0 else { return }
            let fit = min(scroll.bounds.width / size.width, scroll.bounds.height / size.height, 1)
            scroll.minimumZoomScale = fit
            centre(scroll)
            if let focus {
                self.focus = nil
                let offset = CGPoint(x: focus.x * scroll.zoomScale - scroll.bounds.width / 2,
                                     y: focus.y * scroll.zoomScale - scroll.bounds.height / 2)
                let most = CGPoint(x: max(0, scroll.contentSize.width - scroll.bounds.width),
                                   y: max(0, scroll.contentSize.height - scroll.bounds.height))
                scroll.contentOffset = CGPoint(x: min(max(0, offset.x), most.x), y: min(max(0, offset.y), most.y))
            }
        }

        /// Content smaller than the screen sits in its middle.
        private func centre(_ scroll: UIScrollView) {
            let x = max(0, (scroll.bounds.width - scroll.contentSize.width) / 2)
            let y = max(0, (scroll.bounds.height - scroll.contentSize.height) / 2)
            scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        /// Zoomed out: in to full size where it was tapped. Otherwise: out to see it all.
        @objc func doubleTapped(_ tap: UITapGestureRecognizer) {
            guard let scroll = tap.view as? UIScrollView else { return }
            if scroll.zoomScale < 1 {
                let point = tap.location(in: host.view)
                let width = scroll.bounds.width, height = scroll.bounds.height
                scroll.zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true)
            } else {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            }
        }
    }
}
