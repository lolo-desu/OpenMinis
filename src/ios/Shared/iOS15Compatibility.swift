import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 1. Task.sleep(for:) & Duration Backport for iOS 15

public enum iOS15Duration: Sendable, Equatable {
    case nanoseconds(Int64)
    case microseconds(Int64)
    case milliseconds(Int64)
    case seconds(Double)

    public static func milliseconds(_ ms: Int) -> iOS15Duration {
        .milliseconds(Int64(ms))
    }

    public static func seconds(_ s: Int) -> iOS15Duration {
        .seconds(Double(s))
    }

    public var nanosecondsValue: UInt64 {
        switch self {
        case .nanoseconds(let ns): return UInt64(max(0, ns))
        case .microseconds(let us): return UInt64(max(0, us)) * 1_000
        case .milliseconds(let ms): return UInt64(max(0, ms)) * 1_000_000
        case .seconds(let s): return UInt64(max(0, s * 1_000_000_000))
        }
    }
}

public typealias Duration = iOS15Duration

extension Task where Success == Never, Failure == Never {
    @_disfavoredOverload
    public static func sleep(for duration: iOS15Duration) async throws {
        try await Task.sleep(nanoseconds: duration.nanosecondsValue)
    }
}

// MARK: - 2. ToolbarItemPlacement & Toolbar Visibility Backports

extension ToolbarItemPlacement {
    @_disfavoredOverload
    public static var topBarLeading: ToolbarItemPlacement {
        .navigationBarLeading
    }

    @_disfavoredOverload
    public static var topBarTrailing: ToolbarItemPlacement {
        .navigationBarTrailing
    }

    @_disfavoredOverload
    public static var secondaryAction: ToolbarItemPlacement {
        .navigationBarTrailing
    }
}

public enum CompatToolbarPlacement: Hashable, Sendable {
    case automatic
    case navigationBar
    case bottomBar
    case tabBar
}

public enum CompatToolbarVisibility: Hashable, Sendable {
    case automatic
    case visible
    case hidden
}

// MARK: - 3. LabeledContent Backport for iOS 15

public struct CompatLabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            label
            Spacer(minLength: 8)
            content
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension CompatLabeledContent where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = Text(titleKey)
        self.content = content()
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.label = Text(title)
        self.content = content()
    }
}

extension CompatLabeledContent where Label == Text, Content == Text {
    public init<S: StringProtocol>(_ titleKey: LocalizedStringKey, value: S) {
        self.label = Text(titleKey)
        self.content = Text(value)
    }

    @_disfavoredOverload
    public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2) {
        self.label = Text(title)
        self.content = Text(value)
    }
}

public typealias LabeledContent = CompatLabeledContent

// MARK: - 4. ShareLink Backport for iOS 15

public struct CompatShareLink<Label: View>: View {
    private let item: URL
    private let label: Label
    @State private var isPresented = false

    public init(item: URL, @ViewBuilder label: () -> Label) {
        self.item = item
        self.label = label()
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            label
        }
        .sheet(isPresented: $isPresented) {
            CompatActivityView(activityItems: [item])
        }
    }
}

extension CompatShareLink where Label == SwiftUI.Label<Text, Image> {
    public init(item: URL) {
        self.item = item
        self.label = SwiftUI.Label("Share", systemImage: "square.and.arrow.up")
    }
}

private struct CompatActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

public typealias ShareLink = CompatShareLink

// MARK: - 5. AnyShape & UnevenRoundedRectangle & Color.gradient Backports

public struct CompatAnyShape: Shape {
    private let _path: @Sendable (CGRect) -> Path

    public init<S: Shape>(_ shape: S) {
        let copy = shape
        self._path = { rect in copy.path(in: rect) }
    }

    public func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

public typealias AnyShape = CompatAnyShape

public struct CompatUnevenRoundedRectangle: Shape {
    public var topLeadingRadius: CGFloat
    public var bottomLeadingRadius: CGFloat
    public var bottomTrailingRadius: CGFloat
    public var topTrailingRadius: CGFloat
    public var style: RoundedCornerStyle

    public init(
        topLeadingRadius: CGFloat = 0,
        bottomLeadingRadius: CGFloat = 0,
        bottomTrailingRadius: CGFloat = 0,
        topTrailingRadius: CGFloat = 0,
        style: RoundedCornerStyle = .continuous
    ) {
        self.topLeadingRadius = topLeadingRadius
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
        self.topTrailingRadius = topTrailingRadius
        self.style = style
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let tr = min(min(topTrailingRadius, h / 2), w / 2)
        let tl = min(min(topLeadingRadius, h / 2), w / 2)
        let bl = min(min(bottomLeadingRadius, h / 2), w / 2)
        let br = min(min(bottomTrailingRadius, h / 2), w / 2)

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

public typealias UnevenRoundedRectangle = CompatUnevenRoundedRectangle

extension Color {
    @_disfavoredOverload
    public var gradient: LinearGradient {
        LinearGradient(colors: [self.opacity(0.85), self], startPoint: .top, endPoint: .bottom)
    }
}

extension HorizontalAlignment {
    @_disfavoredOverload
    public static var listRowSeparatorLeading: HorizontalAlignment {
        .leading
    }
}

// MARK: - 6. PresentationDetent & View Modifiers Backport for iOS 15

public enum CompatPresentationDetent: Hashable, Sendable {
    case medium
    case large
    case fraction(CGFloat)
    case height(CGFloat)
}

public typealias PresentationDetent = CompatPresentationDetent

public enum CompatScrollDismissesKeyboardMode: Hashable, Sendable {
    case automatic
    case immediately
    case interactively
    case never
}

public enum CompatScrollIndicatorVisibility: Hashable, Sendable {
    case automatic
    case visible
    case hidden
    case never
}

private struct CompatOnGeometryChangeModifier<T: Equatable>: ViewModifier {
    let transform: (GeometryProxy) -> T
    let action: (T) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let val = transform(proxy)
                Color.clear
                    .onAppear { action(val) }
                    .onChange(of: val) { newVal in action(newVal) }
            }
        )
    }
}

extension View {
    @_disfavoredOverload
    @ViewBuilder
    public func presentationDetents(_ detents: Set<CompatPresentationDetent>) -> some View {
        if #available(iOS 16.0, *) {
            let mapped = Set(detents.map { d -> SwiftUI.PresentationDetent in
                switch d {
                case .medium: return .medium
                case .large: return .large
                case .fraction(let f): return .fraction(f)
                case .height(let h): return .height(h)
                }
            })
            self.presentationDetents(mapped)
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func presentationDetents(_ detents: Set<CompatPresentationDetent>, selection: Binding<CompatPresentationDetent>) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents(detents)
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func presentationDragIndicator(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDragIndicator(visibility)
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func scrollContentBackground(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(visibility)
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func scrollDismissesKeyboard(_ mode: CompatScrollDismissesKeyboardMode) -> some View {
        if #available(iOS 16.0, *) {
            switch mode {
            case .automatic: self.scrollDismissesKeyboard(.automatic)
            case .immediately: self.scrollDismissesKeyboard(.immediately)
            case .interactively: self.scrollDismissesKeyboard(.interactively)
            case .never: self.scrollDismissesKeyboard(.never)
            }
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func scrollIndicators(_ visibility: CompatScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View {
        if #available(iOS 16.0, *) {
            switch visibility {
            case .automatic: self.scrollIndicators(.automatic, axes: axes)
            case .visible: self.scrollIndicators(.visible, axes: axes)
            case .hidden: self.scrollIndicators(.hidden, axes: axes)
            case .never: self.scrollIndicators(.never, axes: axes)
            }
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func toolbarBackground(_ visibility: Visibility, for bars: CompatToolbarPlacement...) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(visibility, for: .navigationBar)
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: CompatToolbarPlacement...) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(style, for: .navigationBar)
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func toolbar(_ visibility: Visibility, for bars: CompatToolbarPlacement...) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(visibility, for: .navigationBar)
        } else {
            self.navigationBarHidden(visibility == .hidden)
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func persistentSystemOverlays(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            self.persistentSystemOverlays(visibility)
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func fontWeight(_ weight: Font.Weight?) -> some View {
        if #available(iOS 16.0, *) {
            self.fontWeight(weight)
        } else {
            self.font(Font.body.weight(weight ?? .regular))
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func bold() -> some View {
        if #available(iOS 16.0, *) {
            self.bold()
        } else {
            self.font(Font.body.bold())
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        if #available(iOS 16.0, *) {
            self.lineLimit(limit)
        } else {
            self.lineLimit(limit.upperBound)
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func navigationSplitViewColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View {
        if #available(iOS 16.0, *) {
            self.navigationSplitViewColumnWidth(min: min, ideal: ideal, max: max)
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func contextMenu<M: View, P: View>(
        @ViewBuilder menuItems: () -> M,
        @ViewBuilder preview: () -> P
    ) -> some View {
        if #available(iOS 16.0, *) {
            self.contextMenu(menuItems: menuItems, preview: preview)
        } else {
            self.contextMenu(menuItems: menuItems)
        }
    }

    @_disfavoredOverload
    public func onGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (T) -> Void
    ) -> some View {
        self.modifier(CompatOnGeometryChangeModifier(transform: transform, action: action))
    }

    @_disfavoredOverload
    @ViewBuilder
    public func draggable(_ payload: @autoclosure @escaping () -> String) -> some View {
        if #available(iOS 16.0, *) {
            self.draggable(payload())
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    public func dropDestination(
        for payloadType: String.Type = String.self,
        action: @escaping ([String], CGPoint) -> Bool,
        isTargeted: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        if #available(iOS 16.0, *) {
            self.dropDestination(for: payloadType, action: action, isTargeted: isTargeted)
        } else {
            self
        }
    }
}

// MARK: - 6b. iOS 26 SDK Stubs for Xcode 16 (iOS 18 SDK) Compatibility

public struct Glass: Sendable {
    public static let regular = Glass()
    public func tint(_ color: Color?) -> Glass { self }
    public func interactive(_ isInteractive: Bool = true) -> Glass { self }
}

public enum CompatGlassShape: Sendable {
    case capsule
    case circle
}

extension View {
    @_disfavoredOverload
    public func glassEffect(_ glass: Glass = .regular, in shape: CompatGlassShape) -> some View {
        self
    }

    @_disfavoredOverload
    public func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        self
    }

    @_disfavoredOverload
    public func glassEffectID<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        self
    }

    @_disfavoredOverload
    public func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View {
        self
    }

    @_disfavoredOverload
    public func toolbarBackgroundVisibility(_ visibility: CompatToolbarVisibility, for bars: CompatToolbarPlacement...) -> some View {
        self
    }

    @_disfavoredOverload
    @ViewBuilder
    public func contentShape(_ shape: CompatGlassShape) -> some View {
        switch shape {
        case .capsule:
            self.contentShape(Capsule())
        case .circle:
            self.contentShape(Circle())
        }
    }
}

// MARK: - 6c. TextField(axis:) Backport for iOS 15

public enum CompatAxis: Hashable, Sendable {
    case horizontal
    case vertical
}

extension TextField where Label == Text {
    @_disfavoredOverload
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: CompatAxis) {
        self.init(titleKey, text: text)
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: CompatAxis) {
        self.init(title, text: text)
    }
}

// MARK: - 6d. ProposedViewSize Backport for UIViewRepresentable on iOS 15

public struct CompatProposedViewSize: Equatable, Sendable {
    public var width: CGFloat?
    public var height: CGFloat?

    public static let zero = CompatProposedViewSize(width: 0, height: 0)
    public static let unspecified = CompatProposedViewSize(width: nil, height: nil)
    public static let infinity = CompatProposedViewSize(width: .infinity, height: .infinity)

    public init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }
}

public typealias ProposedViewSize = CompatProposedViewSize

// MARK: - 7. NavigationStack & NavigationSplitView Backport for iOS 15

public struct CompatNavigationPath: Equatable {
    public var elements: [AnyHashable] = []

    public init() {}

    public init<S: Sequence>(_ elements: S) where S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }

    public mutating func append<V: Hashable>(_ value: V) {
        elements.append(AnyHashable(value))
    }

    public mutating func removeLast(_ k: Int = 1) {
        guard k > 0, elements.count >= k else {
            elements.removeAll()
            return
        }
        elements.removeLast(k)
    }
}

public typealias NavigationPath = CompatNavigationPath

public struct CompatNavigationSplitViewVisibility: Equatable, Sendable {
    public static let automatic = CompatNavigationSplitViewVisibility()
    public static let all = CompatNavigationSplitViewVisibility()
    public static let doubleColumn = CompatNavigationSplitViewVisibility()
    public static let detailOnly = CompatNavigationSplitViewVisibility()
}

public typealias NavigationSplitViewVisibility = CompatNavigationSplitViewVisibility

public struct CompatNavigationSplitView<Sidebar: View, Detail: View>: View {
    @Binding private var columnVisibility: CompatNavigationSplitViewVisibility
    private let sidebar: Sidebar
    private let detail: Detail

    public init(
        columnVisibility: Binding<CompatNavigationSplitViewVisibility> = .constant(.automatic),
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self._columnVisibility = columnVisibility
        self.sidebar = sidebar()
        self.detail = detail()
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            SwiftUI.NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
        } else {
            NavigationView {
                sidebar
                detail
            }
            .navigationViewStyle(DoubleColumnNavigationViewStyle())
        }
    }
}

public typealias NavigationSplitView = CompatNavigationSplitView

public struct CompatNavigationStack<Root: View>: View {
    private var pathBinding: Binding<CompatNavigationPath>?
    private let root: Root

    public init(@ViewBuilder root: () -> Root) {
        self.pathBinding = nil
        self.root = root()
    }

    public init(path: Binding<CompatNavigationPath>, @ViewBuilder root: () -> Root) {
        self.pathBinding = path
        self.root = root()
    }

    public var body: some View {
        if let pathBinding = pathBinding {
            NavigationView {
                root
                    .environment(\.compatNavigationPath, pathBinding)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        } else {
            if #available(iOS 16.0, *) {
                SwiftUI.NavigationStack {
                    root
                }
            } else {
                NavigationView {
                    root
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }
}

public typealias NavigationStack = CompatNavigationStack

private struct CompatNavigationPathKey: EnvironmentKey {
    static let defaultValue: Binding<CompatNavigationPath>? = nil
}

extension EnvironmentValues {
    public var compatNavigationPath: Binding<CompatNavigationPath>? {
        get { self[CompatNavigationPathKey.self] }
        set { self[CompatNavigationPathKey.self] = newValue }
    }
}

private struct CompatNavigationDestinationModifier<D: Hashable, C: View>: ViewModifier {
    @Environment(\.compatNavigationPath) private var pathBinding
    let dataType: D.Type
    let destination: (D) -> C

    func body(content: Content) -> some View {
        let activeValue: D? = pathBinding?.wrappedValue.elements.last(where: { $0.base is D })?.base as? D
        let isActiveBinding = Binding<Bool>(
            get: { activeValue != nil },
            set: { newValue in
                if !newValue {
                    if var current = pathBinding?.wrappedValue, !current.isEmpty {
                        current.removeLast()
                        pathBinding?.wrappedValue = current
                    }
                }
            }
        )
        content.background(
            NavigationLink(
                isActive: isActiveBinding,
                destination: {
                    if let val = activeValue {
                        destination(val)
                    } else {
                        EmptyView()
                    }
                },
                label: { EmptyView() }
            )
            .hidden()
        )
    }
}

extension View {
    @_disfavoredOverload
    public func navigationDestination<D: Hashable, C: View>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View {
        modifier(CompatNavigationDestinationModifier(dataType: data, destination: destination))
    }
}

public struct CompatValueNavigationLink<V: Hashable, Label: View>: View {
    @Environment(\.compatNavigationPath) private var pathBinding
    let value: V
    let label: Label

    public init(value: V, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    public var body: some View {
        Button {
            pathBinding?.wrappedValue.append(value)
        } label: {
            label
        }
    }
}

// MARK: - 8. PhotosPicker & PHPickerViewController Backport for iOS 15

public struct CompatPhotosPickerItem: Equatable {
    public let id = UUID()
    public let itemProvider: NSItemProvider
    public let itemIdentifier: String?

    public var supportedContentTypes: [UTType] {
        itemProvider.registeredTypeIdentifiers.compactMap { UTType($0) }
    }

    public static func == (lhs: CompatPhotosPickerItem, rhs: CompatPhotosPickerItem) -> Bool {
        lhs.id == rhs.id
    }

    public func loadData() async -> Data? {
        for typeId in itemProvider.registeredTypeIdentifiers {
            if let ut = UTType(typeId), ut.conforms(to: .image) || ut.conforms(to: .data) {
                if let data = await loadDataRepresentation(for: typeId) {
                    return data
                }
            }
        }
        if let first = itemProvider.registeredTypeIdentifiers.first {
            return await loadDataRepresentation(for: first)
        }
        return nil
    }

    public func loadVideoURL() async -> URL? {
        for typeId in itemProvider.registeredTypeIdentifiers {
            if let ut = UTType(typeId), ut.conforms(to: .movie) || ut.conforms(to: .audiovisualContent) {
                if let url = await loadFileURL(for: typeId) {
                    return url
                }
            }
        }
        return await loadFileURL(for: UTType.movie.identifier)
    }

    private func loadDataRepresentation(for typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { cont in
            itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                cont.resume(returning: data)
            }
        }
    }

    private func loadFileURL(for typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { cont in
            itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url = url else {
                    cont.resume(returning: nil)
                    return
                }
                let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("picked_\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: url, to: tmp)
                    cont.resume(returning: tmp)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

public struct CompatPHPickerFilter {
    let filter: PHPickerFilter
    public static let images = CompatPHPickerFilter(filter: .images)
    public static let videos = CompatPHPickerFilter(filter: .videos)
    public static func any(of filters: [CompatPHPickerFilter]) -> CompatPHPickerFilter {
        CompatPHPickerFilter(filter: .any(of: filters.map(\.filter)))
    }
}

private struct CompatPHPickerSheet: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let maxSelectionCount: Int
    let filter: PHPickerFilter
    let onPicked: ([CompatPhotosPickerItem]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = maxSelectionCount
        config.filter = filter
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: CompatPHPickerSheet
        init(_ parent: CompatPHPickerSheet) {
            self.parent = parent
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard !results.isEmpty else { return }
            let items = results.map {
                CompatPhotosPickerItem(itemProvider: $0.itemProvider, itemIdentifier: $0.assetIdentifier)
            }
            parent.onPicked(items)
        }
    }
}

extension View {
    public func compatPhotosPicker(
        isPresented: Binding<Bool>,
        selection: Binding<[CompatPhotosPickerItem]>,
        maxSelectionCount: Int = 1,
        matching filter: CompatPHPickerFilter = .images
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            CompatPHPickerSheet(
                isPresented: isPresented,
                maxSelectionCount: maxSelectionCount,
                filter: filter.filter
            ) { items in
                selection.wrappedValue = items
            }
        }
    }

    public func compatPhotosPicker(
        isPresented: Binding<Bool>,
        selection: Binding<CompatPhotosPickerItem?>,
        matching filter: CompatPHPickerFilter = .images
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            CompatPHPickerSheet(
                isPresented: isPresented,
                maxSelectionCount: 1,
                filter: filter.filter
            ) { items in
                selection.wrappedValue = items.first
            }
        }
    }
}

// MARK: - 9. iOS 15 Hosting Content Configuration Backport (for UICollectionViewCell)

public final class CompatHostingContentConfiguration<Content: View>: NSObject, UIContentConfiguration {
    public let rootView: Content

    public init(@ViewBuilder content: () -> Content) {
        self.rootView = content()
    }

    public func minSize(width: CGFloat = 0, height: CGFloat = 0) -> Self { self }
    public func margins(_ edges: Edge.Set = .all, _ length: CGFloat = 0) -> Self { self }

    public func makeContentView() -> UIView & UIContentView {
        CompatHostingContentView(configuration: self)
    }

    public func updated(for state: UIConfigurationState) -> Self {
        self
    }
}

private final class CompatHostingContentView<Content: View>: UIView, UIContentView {
    var configuration: UIContentConfiguration {
        didSet {
            if let config = configuration as? CompatHostingContentConfiguration<Content> {
                hostingController.rootView = config.rootView
                hostingController.view.invalidateIntrinsicContentSize()
                setNeedsLayout()
            }
        }
    }

    private let hostingController: UIHostingController<Content>

    init(configuration: CompatHostingContentConfiguration<Content>) {
        self.configuration = configuration
        self.hostingController = UIHostingController(rootView: configuration.rootView)
        super.init(frame: .zero)
        backgroundColor = .clear
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let target = CGSize(
            width: targetSize.width > 0 ? targetSize.width : UIScreen.main.bounds.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        let size = hostingController.sizeThatFits(in: target)
        return CGSize(width: target.width, height: ceil(size.height))
    }
}
