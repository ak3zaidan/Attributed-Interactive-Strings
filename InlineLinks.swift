import SwiftUI

private let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

struct LinkColoredText: View {
    enum Component {
        case text(String)
        case link(String, URL)
    }

    let text: String
    let components: [Component]

    init(text: String, links: [NSTextCheckingResult]) {
        self.text = text
        let nsText = text as NSString

        var components: [Component] = []
        var index = 0
        for result in links {
            if result.range.location > index {
                components.append(.text(nsText.substring(with: NSRange(location: index, length: result.range.location - index))))
            }
            components.append(.link(nsText.substring(with: result.range), result.url!))
            index = result.range.location + result.range.length
        }
        if index < nsText.length {
            components.append(.text(nsText.substring(from: index)))
        }
        self.components = components
    }

    var body: some View {
        components.map { component in
            switch component {
            case .text(let text):
                return Text(verbatim: text)
            case .link(let text, _):
                return Text(verbatim: text)
                    .foregroundColor(.blue)
            }
        }.reduce(Text(""), +)
    }
}

struct LinkedText: View {
    @EnvironmentObject var popRoot: PopToRoot
    let text: String
    let istip: Bool
    let isMessage: Bool?
    let links: [NSTextCheckingResult]
    
    init (_ text: String, tip: Bool, isMess: Bool?) {
        self.text = text
        self.istip = tip
        self.isMessage = isMess
        let nsText = text as NSString
        let wholeString = NSRange(location: 0, length: nsText.length)
        links = linkDetector.matches(in: text, options: [], range: wholeString)
    }
    
    var body: some View {
        LinkColoredText(text: text, links: links)
            .overlay(LinkTapOverlay(text: text, isTip: istip, isMessage: isMessage, links: links))
    }
}

private struct LinkTapOverlay: UIViewRepresentable {
    @EnvironmentObject var popRoot: PopToRoot
    @EnvironmentObject var viewModel: ExploreViewModel
    let text: String
    let isTip: Bool
    let isMessage: Bool?
    let links: [NSTextCheckingResult]
    
    func makeUIView(context: Context) -> LinkTapOverlayView {
        let view = LinkTapOverlayView(frame: .zero, text: text, overlay: self)
        view.textContainer = context.coordinator.textContainer

        view.isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTapLabel(_:)))
        tapGesture.delegate = context.coordinator
        view.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didLongPressLabel(_:)))
        longPressGesture.delegate = context.coordinator
        view.addGestureRecognizer(longPressGesture)

        return view
    }
    
    func updateUIView(_ uiView: LinkTapOverlayView, context: Context) {
        let attributedString = NSAttributedString(string: text, attributes: [.font: UIFont.preferredFont(forTextStyle: .body)])
        context.coordinator.textStorage = NSTextStorage(attributedString: attributedString)
        context.coordinator.textStorage!.addLayoutManager(context.coordinator.layoutManager)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let overlay: LinkTapOverlay

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: .zero)
        var textStorage: NSTextStorage?
        
        init(_ overlay: LinkTapOverlay) {
            self.overlay = overlay
            
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.maximumNumberOfLines = 0
            layoutManager.addTextContainer(textContainer)
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let location = touch.location(in: gestureRecognizer.view!)
            let result = link(at: location)
            return result != nil
        }
        
        @objc func didTapLabel(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view!)
            guard let result = link(at: location) else {
                return
            }

            guard let url = result.url else {
                return
            }

            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        @objc func didLongPressLabel(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                if overlay.isTip {
                    UIPasteboard.general.string = overlay.text
                    overlay.viewModel.showCopyTip = true
                } else {
                    overlay.popRoot.TextToCopy = overlay.text
                    overlay.popRoot.showCopy = true
                }
                if (overlay.isMessage ?? false) == true {
                    overlay.popRoot.messageToDelete = true
                }
            }
        }

        private func link(at point: CGPoint) -> NSTextCheckingResult? {
            guard !overlay.links.isEmpty else {
                return nil
            }

            let indexOfCharacter = layoutManager.characterIndex(
                for: point,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            return overlay.links.first { $0.range.contains(indexOfCharacter) }
        }
    }
}

private class LinkTapOverlayView: UIView {
    private var overlay: LinkTapOverlay?
    var textContainer: NSTextContainer!
    var text: String?
    
    override init(frame: CGRect) {
        super.init(frame: frame)

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressLabel(_:)))
        addGestureRecognizer(longPressGesture)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    convenience init(frame: CGRect, text: String, overlay: LinkTapOverlay) {
        self.init(frame: frame)
        self.text = text
        self.overlay = overlay
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        var newSize = bounds.size
        newSize.height += 20
        textContainer.size = newSize
    }

    @objc func didLongPressLabel(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            if (overlay?.isTip ?? false) == true {
                UIPasteboard.general.string = text
                overlay?.viewModel.showCopyTip = true
            } else {
                overlay?.popRoot.TextToCopy = text ?? ""
                overlay?.popRoot.showCopy = true
            }
            if (overlay?.isMessage ?? false) == true {
                overlay?.popRoot.messageToDelete = true
            }
        }
    }
}
