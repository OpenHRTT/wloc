import AppKit
import CoreLocation
import MapKit
import SnapKit

private final class WLocArrowCursorMapView: MKMapView {
    private var arrowTrackingArea: NSTrackingArea?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let arrowTrackingArea {
            removeTrackingArea(arrowTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        arrowTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseMoved(with: event)
    }
}

private final class WLocMacActionButton: NSButton {
    private let baseColor: NSColor?
    private var trackingAreaToken: NSTrackingArea?
    private var isPointerInside = false
    var stateTintColor: NSColor? {
        didSet { updateAppearance() }
    }

    init(title: String, color: NSColor? = nil) {
        baseColor = color
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 9
        font = .systemFont(ofSize: 13, weight: .semibold)
        alignment = .center
        imageScaling = .scaleProportionallyDown
        imagePosition = .imageLeading
        imageHugsTitle = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaToken = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        updateAppearance()
    }

    /// 主按钮使用品牌底色，图标按钮使用淡底色，并根据鼠标和禁用状态调整外观。
    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = baseColor.map { isPointerInside ? ($0.blended(withFraction: 0.08, of: .black) ?? $0) : $0 }
                ?? NSColor.labelColor.withAlphaComponent(isPointerInside ? 0.07 : 0)
            layer?.backgroundColor = color.withAlphaComponent(isEnabled ? color.alphaComponent : color.alphaComponent * 0.45).cgColor
            layer?.borderWidth = 0
            contentTintColor = stateTintColor ?? (baseColor == nil ? (isEnabled ? .labelColor : .tertiaryLabelColor) : .white)
            alphaValue = isEnabled || stateTintColor != nil ? 1 : 0.65
        }
    }
}

final class WLocMacMapViewController: NSViewController {
    private enum SelectedCopyField: Int {
        case name = 1
        case detail
        case coordinate
    }

    private enum LocationMode: Int {
        case simulated
        case wloc

        var title: String { self == .simulated ? "虚拟定位" : "WLoc" }
    }

    private static let locationModeKey = "AppWLoc.macOS.locationMode"
    private var locationMode = LocationMode(
        rawValue: UserDefaults.standard.integer(forKey: WLocMacMapViewController.locationModeKey)
    ) ?? .simulated
    private var hasSystemLocationToRestore = false
    var showsCertificateTutorial: Bool { locationMode == .wloc }

    private let pacManager = AppWLocPACManager()

    private let mapView = WLocArrowCursorMapView()
    private let searchField = NSSearchField()
    private let searchTable = NSTableView()
    private let favoritesTable = NSTableView()
    private let searchResultsPanel = NSVisualEffectView()
    private let searchResultsTitleLabel = NSTextField.wlocLabel("搜索结果")
    private let searchResultsScroll = NSScrollView()
    private let zoomInButton = WLocMacActionButton(title: "放大地图")
    private let zoomOutButton = WLocMacActionButton(title: "缩小地图")
    private let currentLocationButton = WLocMacActionButton(title: "回到当前位置")
    private let titleLabel = NSTextField.wlocLabel("地图中心")
    private let detailLabel = NSTextField.wlocLabel("")
    private let coordinateLabel = NSTextField.wlocLabel("")
    private let locationModeControl = NSSegmentedControl(labels: [LocationMode.simulated.title, LocationMode.wloc.title], trackingMode: .selectOne, target: nil, action: nil)
    private let locationModeHint = NSTextField(wrappingLabelWithString: "")
    private let lockButton = WLocMacActionButton(title: "锁定位置", color: NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.94, alpha: 1))
    private let advancedLockButton = WLocMacActionButton(title: "高级锁定")
    private let restoreButton = WLocMacActionButton(title: "还原定位")
    private let favoriteButton = WLocMacActionButton(title: "加入收藏")
    private let coordinateInputButton = WLocMacActionButton(title: "经纬度选点")
    private let tutorialButton = WLocMacActionButton(title: "教程与证书")
    private let debugLogButton = WLocMacActionButton(title: "查看日志")
    private let telegramButton = WLocMacActionButton(
        title: "Telegram",
        color: NSColor(calibratedRed: 0.08, green: 0.52, blue: 0.82, alpha: 1)
    )
    private let githubButton = WLocMacActionButton(
        title: "GitHub · Star",
        color: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 1)
    )
    private let appNameLabel = NSTextField.wlocLabel(AppWLocConfig.displayName)
    private let versionLabel = NSTextField.wlocLabel("版本 \(AppWLocConfig.currentVersion)")
    private let updateButton = WLocMacActionButton(title: "检查更新")
    private let updateBadge = NSView()
    private let favoritesCountLabel = NSTextField.wlocLabel("0")
    private let emptyFavoritesView = NSView()
    private var favoritesHeightConstraint: Constraint?
    private let selectedAnnotation = MKPointAnnotation()

    private let geocoder = CLGeocoder()
    private let locationManager = CLLocationManager()
    private var searchResults: [AppWLocPlace] = []
    private var favorites: [AppWLocFavorite] = []
    private var selectedPlace: AppWLocPlace?
    private var hasSelectedAnnotation = false
    private var reverseGeocodeWorkItem: DispatchWorkItem?
    private var tutorialWindow: WLocMacTutorialWindowController?
    private var debugLogWindow: WLocMacDebugLogWindowController?
    private var mapClickGesture: NSClickGestureRecognizer?
    private weak var controlsPanel: NSView?
    private var outsideSearchClickMonitor: Any?
    private var availableUpdate: AppWLocAvailableUpdate?
    private var updateInstaller: WLocMacUpdateInstaller?
    private var updateProgressAlert: NSAlert?
    private var isCheckingUpdates = false
    private var isUpdating = false
    private var isInstallingUpdate = false
    private var shouldQuitAfterUpdateCancellation = false
    private var shouldSelectNextLocationUpdate = false
    private var isRefreshingLocationAfterLock = false
    private var isChangingLocation = false {
        didSet { updateLocationModeControls() }
    }
    private var locationRefreshWorkItem: DispatchWorkItem?

    deinit {
        locationRefreshWorkItem?.cancel()
        if let outsideSearchClickMonitor {
            NSEvent.removeMonitor(outsideSearchClickMonitor)
        }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        layoutViews()
        reloadFavorites()
        let initialPlace = AppWLocPlace(name: "上海", detail: "双击地图可选择新的位置", latitude: 31.2304, longitude: 121.4737)
        updateSelectedPlace(initialPlace)
        updateSelectedAnnotation(with: initialPlace)
        pacManager.performSystemLocation(.status) { [weak self] active, _ in
            guard let self, let active, !self.isChangingLocation else { return }
            self.hasSystemLocationToRestore = active
            self.updateLocationModeControls()
        }
        checkForUpdates(userInitiated: false)
    }

    /// 保留原来的地图和交互，统一设置面板字体、图标与三种主按钮的外观。
    private func configureViews() {
        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = false
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(selectMapPoint(_:)))
        clickGesture.numberOfClicksRequired = 2
        clickGesture.delegate = self
        clickGesture.delaysPrimaryMouseButtonEvents = false
        mapClickGesture = clickGesture
        mapView.addGestureRecognizer(clickGesture)
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                latitudinalMeters: 12000,
                longitudinalMeters: 12000
            ),
            animated: false
        )

        selectedAnnotation.coordinate = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        selectedAnnotation.title = "地图中心"

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        searchField.placeholderString = "搜索地名或地址"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(performSearch)
        searchField.font = .systemFont(ofSize: 13)
        searchField.controlSize = .large
        searchField.focusRingType = .default

        configureTable(searchTable)
        configureTable(favoritesTable)
        favoritesTable.rowHeight = 82
        favoritesTable.style = .plain

        searchResultsPanel.material = .popover
        searchResultsPanel.blendingMode = .withinWindow
        searchResultsPanel.state = .active
        searchResultsPanel.isHidden = true
        searchResultsPanel.wantsLayer = true
        searchResultsPanel.layer?.masksToBounds = false
        searchResultsPanel.layer?.shadowColor = NSColor.black.cgColor
        searchResultsPanel.layer?.shadowOpacity = 0.2
        searchResultsPanel.layer?.shadowRadius = 16
        searchResultsPanel.layer?.shadowOffset = NSSize(width: 0, height: -5)

        searchResultsPanel.layer?.cornerRadius = 16
        searchResultsPanel.clipsToBounds = true

        searchResultsTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        searchResultsTitleLabel.textColor = .secondaryLabelColor
        searchResultsScroll.documentView = searchTable
        searchResultsScroll.hasVerticalScroller = true
        searchResultsScroll.borderType = .noBorder
        searchResultsScroll.drawsBackground = false

        appNameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        versionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        configureIconButton(updateButton, symbol: "arrow.triangle.2.circlepath", label: "检查更新")
        updateBadge.wantsLayer = true
        updateBadge.layer?.cornerRadius = 3
        updateBadge.layer?.backgroundColor = NSColor.systemBlue.cgColor
        updateBadge.isHidden = true
        updateButton.addSubview(updateBadge)
        updateBadge.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(5)
            make.width.height.equalTo(6)
        }
        setUpdateButtonTitle("检查更新")
        updateButton.target = self
        updateButton.action = #selector(openAvailableUpdate)

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.wraps = true
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.cell?.isScrollable = false
        detailLabel.cell?.wraps = true
        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        coordinateLabel.textColor = .secondaryLabelColor
        locationModeControl.segmentDistribution = .fillEqually
        locationModeControl.selectedSegment = locationMode.rawValue
        locationModeControl.setAccessibilityLabel("定位方式")
        locationModeControl.target = self
        locationModeControl.action = #selector(changeLocationMode)
        locationModeHint.font = .systemFont(ofSize: 11)
        locationModeHint.textColor = .secondaryLabelColor
        locationModeHint.preferredMaxLayoutWidth = 292
        locationModeHint.maximumNumberOfLines = 2
        configureCopyMenu(for: titleLabel, field: .name)
        configureCopyMenu(for: detailLabel, field: .detail)
        configureCopyMenu(for: coordinateLabel, field: .coordinate)

        let favoriteMenu = NSMenu(title: "收藏操作")
        favoriteMenu.delegate = self
        let deleteItem = NSMenuItem(title: "删除收藏", action: #selector(deleteFavoriteFromContextMenu), keyEquivalent: "")
        deleteItem.target = self
        favoriteMenu.addItem(deleteItem)
        favoritesTable.menu = favoriteMenu

        configureIconButton(advancedLockButton, symbol: "slider.horizontal.3", label: "高级锁定：设置海拔与定位精度")
        configureIconButton(restoreButton, symbol: "arrow.counterclockwise", label: "还原定位")
        configureIconButton(favoriteButton, symbol: "star", label: "加入收藏")
        configureIconButton(coordinateInputButton, symbol: "scope", label: "输入经纬度选点")
        configureIconButton(debugLogButton, symbol: "doc.text.magnifyingglass", label: "查看日志")
        configureIconButton(zoomInButton, symbol: "plus", label: "放大地图")
        configureIconButton(zoomOutButton, symbol: "minus", label: "缩小地图")
        configureIconButton(currentLocationButton, symbol: "location", label: "回到当前位置")
        lockButton.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        lockButton.font = .systemFont(ofSize: 14, weight: .semibold)
        lockButton.layer?.shadowOpacity = 0
        tutorialButton.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil)
        tutorialButton.font = .systemFont(ofSize: 12, weight: .medium)
        tutorialButton.toolTip = "使用教程、证书下载与安装说明"
        telegramButton.image = WLocMacExternalIcon.image(named: "paperplane.fill", fallback: .telegram, size: NSSize(width: 17, height: 17))
        telegramButton.toolTip = "加入 Telegram 社区：https://t.me/wloc88"
        githubButton.image = WLocMacExternalIcon.image(named: "chevron.left.forwardslash.chevron.right", fallback: .code, size: NSSize(width: 17, height: 17))
        githubButton.toolTip = "查看 GitHub 开源项目，点个 Star 支持 WLoc8.com"

        restoreButton.target = self
        restoreButton.action = #selector(restoreLocation)
        lockButton.target = self
        lockButton.action = #selector(lockCurrentPlace)
        advancedLockButton.target = self
        advancedLockButton.action = #selector(openAdvancedLock)
        favoriteButton.target = self
        favoriteButton.action = #selector(addFavorite)
        coordinateInputButton.target = self
        coordinateInputButton.action = #selector(openCoordinateInput)
        tutorialButton.target = self
        tutorialButton.action = #selector(openTutorial)
        debugLogButton.target = self
        debugLogButton.action = #selector(openDebugLog)
        telegramButton.target = self
        telegramButton.action = #selector(openTelegram)
        githubButton.target = self
        githubButton.action = #selector(openGitHub)
        zoomInButton.target = self
        zoomInButton.action = #selector(zoomIn)
        zoomOutButton.target = self
        zoomOutButton.action = #selector(zoomOut)
        currentLocationButton.target = self
        currentLocationButton.action = #selector(centerOnCurrentLocation)
        updateLocationModeControls()

        // 搜索列表是浮层；监听窗口内点击，可在用户点击浮层之外时自然收起。
        outsideSearchClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissSearchResultsIfNeeded(for: event)
            return event
        }
    }

    /// 搜索和收藏共用轻量列表样式，取消原来整块白底的表格感。
    private func configureTable(_ table: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 64
        table.style = .inset
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.delegate = self
        table.dataSource = self
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
    }

    /// 图标只省略视觉上的文字，保留按钮名称和鼠标提示。
    private func configureIconButton(_ button: NSButton, symbol: String, label: String) {
        button.title = label
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        button.imagePosition = .imageOnly
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.layer?.cornerRadius = 10
    }

    /// 浮动面板按内容决定高度，主操作独占一行，空收藏不再撑出整块留白。
    private func layoutViews() {
        let sidebar = NSBox()
        sidebar.boxType = .custom
        sidebar.titlePosition = .noTitle
        sidebar.contentViewMargins = .zero
        sidebar.fillColor = .textBackgroundColor
        sidebar.borderWidth = 0
        sidebar.cornerRadius = 18
        sidebar.wantsLayer = true
        sidebar.layer?.shadowColor = NSColor.black.cgColor
        sidebar.layer?.shadowOpacity = 0.13
        sidebar.layer?.shadowRadius = 20
        sidebar.layer?.shadowOffset = NSSize(width: 0, height: -8)
        let controlsPanel = WLocMacGlassView(cornerRadius: 12, material: .popover)
        self.controlsPanel = controlsPanel

        view.addSubview(mapView)
        view.addSubview(sidebar)
        view.addSubview(controlsPanel)
        view.addSubview(searchResultsPanel, positioned: .above, relativeTo: nil)
        mapView.snp.makeConstraints { make in make.edges.equalToSuperview() }
        sidebar.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.top.equalToSuperview().inset(64)
            make.bottom.lessThanOrEqualToSuperview().inset(20)
            make.width.equalTo(328)
        }
        controlsPanel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(72)
            make.trailing.equalToSuperview().inset(24)
            make.width.equalTo(44)
            make.height.equalTo(120)
        }
        [zoomInButton, zoomOutButton, currentLocationButton].forEach {
            controlsPanel.contentView.addSubview($0)
            $0.snp.makeConstraints { make in
                make.centerX.equalToSuperview()
                make.width.height.equalTo(32)
            }
        }
        zoomInButton.snp.makeConstraints { make in make.top.equalToSuperview().offset(8) }
        zoomOutButton.snp.makeConstraints { make in make.top.equalTo(zoomInButton.snp.bottom).offset(4) }
        currentLocationButton.snp.makeConstraints { make in make.top.equalTo(zoomOutButton.snp.bottom).offset(4) }

        let header = NSView()
        let brandIcon = NSImageView()
        brandIcon.image = NSImage(systemSymbolName: "mappin.and.ellipse", accessibilityDescription: nil)
        brandIcon.contentTintColor = NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.94, alpha: 1)
        brandIcon.imageScaling = .scaleProportionallyDown
        brandIcon.setAccessibilityElement(false)
        [brandIcon, appNameLabel, versionLabel, updateButton].forEach { header.addSubview($0) }
        brandIcon.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.width.height.equalTo(24)
        }
        appNameLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalTo(brandIcon.snp.trailing).offset(8)
            make.trailing.lessThanOrEqualTo(updateButton.snp.leading).offset(-8)
        }
        versionLabel.snp.makeConstraints { make in
            make.leading.equalTo(appNameLabel)
            make.top.equalTo(appNameLabel.snp.bottom).offset(1)
            make.trailing.lessThanOrEqualTo(updateButton.snp.leading).offset(-8)
        }
        updateButton.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
            make.width.height.equalTo(28)
        }

        let externalLinkStack = NSStackView(views: [telegramButton, githubButton])
        externalLinkStack.orientation = .horizontal
        externalLinkStack.spacing = 8
        externalLinkStack.distribution = .fillEqually
        [telegramButton, githubButton].forEach { button in
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.snp.makeConstraints { make in make.height.equalTo(34) }
        }
        let selectionDivider = NSBox()
        selectionDivider.boxType = .separator
        let favoritesDivider = NSBox()
        favoritesDivider.boxType = .separator
        let selectionHeading = NSView()
        selectionHeading.addSubview(titleLabel)
        selectionHeading.addSubview(favoriteButton)
        titleLabel.preferredMaxLayoutWidth = 254
        titleLabel.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.trailing.equalTo(favoriteButton.snp.leading).offset(-8)
        }
        favoriteButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(-2)
            make.width.height.equalTo(30)
        }

        let toolbar = NSStackView(views: [advancedLockButton, restoreButton, coordinateInputButton, debugLogButton, NSView(), tutorialButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.distribution = .fill
        toolbar.spacing = 6
        toolbar.detachesHiddenViews = true
        [advancedLockButton, restoreButton, coordinateInputButton, debugLogButton].forEach { button in
            button.snp.makeConstraints { make in make.width.height.equalTo(32) }
        }
        tutorialButton.snp.makeConstraints { make in
            make.width.equalTo(124)
            make.height.equalTo(32)
        }
        toolbar.views[4].setContentHuggingPriority(.defaultLow, for: .horizontal)

        let favoriteTitle = NSTextField.wlocLabel("收藏地点")
        favoriteTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        favoritesCountLabel.font = .systemFont(ofSize: 11, weight: .medium)
        favoritesCountLabel.textColor = .secondaryLabelColor
        let favoritesHeading = NSView()
        favoritesHeading.addSubview(favoriteTitle)
        favoritesHeading.addSubview(favoritesCountLabel)
        favoriteTitle.snp.makeConstraints { make in make.leading.centerY.equalToSuperview() }
        favoritesCountLabel.snp.makeConstraints { make in make.trailing.centerY.equalToSuperview() }

        let favoritesArea = NSView()
        let favoritesScroll = NSScrollView()
        favoritesScroll.documentView = favoritesTable
        favoritesScroll.hasVerticalScroller = true
        favoritesScroll.borderType = .noBorder
        favoritesScroll.drawsBackground = false
        favoritesScroll.autohidesScrollers = true
        favoritesScroll.scrollerStyle = .overlay
        favoritesArea.addSubview(favoritesScroll)
        favoritesArea.addSubview(emptyFavoritesView)
        favoritesScroll.snp.makeConstraints { make in make.edges.equalToSuperview() }
        emptyFavoritesView.snp.makeConstraints { make in make.edges.equalToSuperview() }
        let emptyIcon = NSImageView()
        emptyIcon.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        emptyIcon.contentTintColor = .secondaryLabelColor
        emptyIcon.setAccessibilityElement(false)
        emptyIcon.snp.makeConstraints { make in make.width.height.equalTo(22) }
        let emptyTitle = NSTextField.wlocLabel("还没有收藏地点")
        emptyTitle.font = .systemFont(ofSize: 12, weight: .medium)
        let emptyHint = NSTextField.wlocLabel("点击星标，收藏常用地点")
        emptyHint.font = .systemFont(ofSize: 11)
        emptyHint.textColor = .secondaryLabelColor
        let emptyText = NSStackView(views: [emptyTitle, emptyHint])
        emptyText.orientation = .vertical
        emptyText.alignment = .leading
        emptyText.spacing = 3
        let emptyStack = NSStackView(views: [emptyIcon, emptyText])
        emptyStack.orientation = .horizontal
        emptyStack.spacing = 10
        emptyFavoritesView.addSubview(emptyStack)
        emptyStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(8)
        }

        [header, searchField, externalLinkStack, selectionDivider, selectionHeading, detailLabel, coordinateLabel, locationModeControl, locationModeHint,
         lockButton, toolbar, favoritesDivider, favoritesHeading, favoritesArea].forEach {
            sidebar.contentView?.addSubview($0)
        }
        header.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(18)
            make.leading.trailing.equalToSuperview().inset(18)
            make.height.equalTo(36)
        }
        searchField.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(12)
            make.leading.trailing.equalTo(header)
            make.height.equalTo(32)
        }
        externalLinkStack.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(12)
            make.leading.trailing.equalTo(header)
        }
        selectionDivider.snp.makeConstraints { make in
            make.top.equalTo(externalLinkStack.snp.bottom).offset(18)
            make.leading.trailing.equalTo(header)
            make.height.equalTo(1)
        }
        selectionHeading.snp.makeConstraints { make in
            make.top.equalTo(selectionDivider.snp.bottom).offset(16)
            make.leading.trailing.equalTo(header)
            make.height.greaterThanOrEqualTo(28)
        }
        detailLabel.snp.makeConstraints { make in
            make.top.equalTo(selectionHeading.snp.bottom).offset(6)
            make.leading.trailing.equalTo(header)
            make.height.lessThanOrEqualTo(32)
        }
        detailLabel.preferredMaxLayoutWidth = 292
        coordinateLabel.snp.makeConstraints { make in
            make.top.equalTo(detailLabel.snp.bottom).offset(8)
            make.leading.trailing.equalTo(header)
        }
        locationModeControl.snp.makeConstraints { make in
            make.top.equalTo(coordinateLabel.snp.bottom).offset(12)
            make.leading.trailing.equalTo(header)
        }
        locationModeHint.snp.makeConstraints { make in
            make.top.equalTo(locationModeControl.snp.bottom).offset(6)
            make.leading.trailing.equalTo(header)
            make.height.equalTo(30)
        }
        lockButton.snp.makeConstraints { make in
            make.top.equalTo(locationModeHint.snp.bottom).offset(12)
            make.leading.trailing.equalTo(header)
            make.height.equalTo(42)
        }
        toolbar.snp.makeConstraints { make in
            make.top.equalTo(lockButton.snp.bottom).offset(8)
            make.leading.trailing.equalTo(header)
            make.height.equalTo(32)
        }
        favoritesDivider.snp.makeConstraints { make in
            make.top.equalTo(toolbar.snp.bottom).offset(16)
            make.leading.trailing.equalTo(header)
            make.height.equalTo(1)
        }
        favoritesHeading.snp.makeConstraints { make in
            make.top.equalTo(favoritesDivider.snp.bottom).offset(14)
            make.leading.trailing.equalTo(header)
            make.height.equalTo(18)
        }
        favoritesArea.snp.makeConstraints { make in
            make.top.equalTo(favoritesHeading.snp.bottom).offset(8)
            make.leading.trailing.equalTo(header)
            make.bottom.equalToSuperview().inset(16)
            make.height.greaterThanOrEqualTo(44)
            favoritesHeightConstraint = make.height.equalTo(60).priority(750).constraint
        }

        searchResultsPanel.addSubview(searchResultsTitleLabel)
        searchResultsPanel.addSubview(searchResultsScroll)
        searchResultsPanel.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(6)
            make.leading.trailing.equalTo(searchField)
            make.height.equalTo(270)
        }
        searchResultsTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.trailing.equalToSuperview().inset(14)
        }
        searchResultsScroll.snp.makeConstraints { make in
            make.top.equalTo(searchResultsTitleLabel.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview().inset(8)
        }
    }

    /// 更新目标信息，同时让星标反映收藏状态，完整地址仍可通过鼠标提示查看。
    private func updateSelectedPlace(_ place: AppWLocPlace) {
        selectedPlace = place
        titleLabel.stringValue = place.name
        detailLabel.stringValue = place.detail
        coordinateLabel.stringValue = place.coordinateText
        titleLabel.toolTip = place.name
        detailLabel.toolTip = place.detail
        favoriteButton.isEnabled = !AppWLocFavoriteStore.shared.contains(place)
        favoriteButton.stateTintColor = favoriteButton.isEnabled ? nil : NSColor(calibratedRed: 0.7, green: 0.42, blue: 0.04, alpha: 1)
        favoriteButton.title = favoriteButton.isEnabled ? "加入收藏" : "已收藏"
        favoriteButton.image = NSImage(systemSymbolName: favoriteButton.isEnabled ? "star" : "star.fill", accessibilityDescription: nil)
        favoriteButton.imagePosition = .imageOnly
        favoriteButton.toolTip = favoriteButton.title
        favoriteButton.setAccessibilityLabel(favoriteButton.title)
    }

    private func configureCopyMenu(for label: NSTextField, field: SelectedCopyField) {
        label.isSelectable = true
        let menu = NSMenu(title: "复制")
        let item = NSMenuItem(title: "复制", action: #selector(copySelectedPlaceField(_:)), keyEquivalent: "")
        item.target = self
        item.tag = field.rawValue
        menu.addItem(item)
        label.menu = menu
    }

    @objc private func copySelectedPlaceField(_ sender: NSMenuItem) {
        guard let place = selectedPlace,
              let field = SelectedCopyField(rawValue: sender.tag) else { return }
        let value: String
        switch field {
        case .name:
            value = place.name
        case .detail:
            value = place.detail
        case .coordinate:
            value = place.coordinateText
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func moveMap(to place: AppWLocPlace) {
        mapView.setCenter(place.coordinate, animated: false)
        updateSelectedPlace(place)
        updateSelectedAnnotation(with: place)
    }

    private func updateSelectedAnnotation(with place: AppWLocPlace) {
        selectedAnnotation.coordinate = place.coordinate
        selectedAnnotation.title = place.name
        selectedAnnotation.subtitle = place.detail
        if !hasSelectedAnnotation {
            mapView.addAnnotation(selectedAnnotation)
            hasSelectedAnnotation = true
        }
    }

    private func selectCoordinate(_ coordinate: CLLocationCoordinate2D, name: String = "查询中...", detail: String = "") {
        let place = AppWLocPlace(name: name, detail: detail, latitude: coordinate.latitude, longitude: coordinate.longitude)
        updateSelectedPlace(place)
        updateSelectedAnnotation(with: place)

        reverseGeocodeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.geocoder.cancelGeocode()
            self.geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
                guard let placemark = placemarks?.first else { return }
                let detail = AppWLocPlace.detailedAddress(from: placemark)
                let resolvedPlace = AppWLocPlace(
                    name: placemark.name ?? name,
                    detail: detail,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                self.updateSelectedPlace(resolvedPlace)
                self.updateSelectedAnnotation(with: resolvedPlace)
            }
        }
        reverseGeocodeWorkItem = workItem
        AppWLocUtils.mainThreadAfter(0.45) {
            workItem.perform()
        }
    }

    @objc private func openCoordinateInput() {
        let sourceSystems = AppWLocCoordinateSystem.allCases
        let sourcePopup = NSPopUpButton(frame: NSRect(x: 72, y: 88, width: 288, height: 26), pullsDown: false)
        sourcePopup.addItems(withTitles: sourceSystems.map(\.inputTitle))

        let latitudeField = NSTextField(frame: NSRect(x: 72, y: 48, width: 288, height: 26))
        latitudeField.placeholderString = "例如 39.9087"
        let longitudeField = NSTextField(frame: NSRect(x: 72, y: 8, width: 288, height: 26))
        longitudeField.placeholderString = "例如 116.3975"

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 122))
        let sourceLabel = NSTextField.wlocLabel("坐标来源")
        sourceLabel.frame = NSRect(x: 0, y: 93, width: 68, height: 20)
        let latitudeLabel = NSTextField.wlocLabel("纬度")
        latitudeLabel.frame = NSRect(x: 0, y: 53, width: 68, height: 20)
        let longitudeLabel = NSTextField.wlocLabel("经度")
        longitudeLabel.frame = NSRect(x: 0, y: 13, width: 68, height: 20)
        [sourceLabel, latitudeLabel, longitudeLabel, sourcePopup, latitudeField, longitudeField].forEach {
            accessoryView.addSubview($0)
        }

        let alert = NSAlert()
        alert.messageText = "输入经纬度"
        alert.informativeText = "将按选择的坐标系转换后，在 Apple 地图上选中位置。"
        alert.accessoryView = accessoryView
        alert.addButton(withTitle: "在地图上定位")
        alert.addButton(withTitle: "取消")

        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let self,
                  sourceSystems.indices.contains(sourcePopup.indexOfSelectedItem) else { return }
            self.applyCoordinateInput(
                latitudeText: latitudeField.stringValue,
                longitudeText: longitudeField.stringValue,
                sourceSystem: sourceSystems[sourcePopup.indexOfSelectedItem]
            )
        }
    }

    private func applyCoordinateInput(
        latitudeText: String,
        longitudeText: String,
        sourceSystem: AppWLocCoordinateSystem
    ) {
        do {
            let coordinate = try AppWLocCoordinateTool.appleMapCoordinate(
                latitudeText: latitudeText,
                longitudeText: longitudeText,
                sourceSystem: sourceSystem
            )
            hideSearchResults()
            view.window?.makeFirstResponder(nil)
            mapView.setCenter(coordinate, animated: true)
            selectCoordinate(coordinate, name: "经纬度位置")
        } catch {
            showAlert(title: "坐标无效", message: error.localizedDescription)
        }
    }

    /// 收藏数量和空状态跟随列表更新，空列表也有明确的操作指引。
    private func reloadFavorites() {
        favorites = AppWLocFavoriteStore.shared.all()
        favoritesTable.reloadData()
        favoritesCountLabel.stringValue = "\(favorites.count) 个"
        emptyFavoritesView.isHidden = !favorites.isEmpty
        let listHeight = CGFloat(favorites.count) * (favoritesTable.rowHeight + favoritesTable.intercellSpacing.height) + 8
        favoritesHeightConstraint?.update(offset: favorites.isEmpty ? 60 : min(listHeight, 208))
    }

    @objc private func changeLocationMode() {
        guard let mode = LocationMode(rawValue: locationModeControl.selectedSegment) else { return }
        locationMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.locationModeKey)
        AppWLocUtils.debugLog("已切换定位方式：\(mode.title)")
        if !showsCertificateTutorial { tutorialWindow?.close() }
        updateLocationModeControls()
    }

    /// 随定位方式显示提示，并在执行定位操作时禁用切换。
    private func updateLocationModeControls() {
        locationModeControl.isEnabled = !isChangingLocation
        advancedLockButton.isEnabled = !isChangingLocation
        tutorialButton.isHidden = !showsCertificateTutorial
        switch locationMode {
        case .simulated:
            locationModeHint.stringValue = hasSystemLocationToRestore
                ? "虚拟定位配置已保存。可更新坐标，或点击「还原定位」。"
                : "需开启系统定位服务，首次需管理员授权。锁定和还原无需重启 Mac。"
        case .wloc:
            locationModeHint.stringValue = "Apple 已限制定位接口的 MITM 拦截。\nWLoc 可能不生效，建议使用虚拟定位。"
        }
    }

    @objc private func lockCurrentPlace() {
        guard let place = selectedPlace else { return }
        lockSelectedPlace(place)
    }

    @objc private func openAdvancedLock() {
        guard let place = selectedPlace, !isChangingLocation else { return }
        view.window?.makeFirstResponder(nil)
        var initialParameters = AppWLocLockParameters(state: locationMode == .wloc ? AppWLocStateStore.shared.load() : nil)
        if locationMode == .simulated {
            initialParameters.altitude = 0
            initialParameters.horizontalAccuracy = 5
        }
        let controller = WLocMacAdvancedLockViewController(place: place, initialParameters: initialParameters) { [weak self] parameters in
            self?.lockSelectedPlace(place, parameters: parameters)
        }
        presentAsSheet(controller)
    }

    /// 普通和高级锁定都按当前方式提交，共用定位权限检查。
    private func lockSelectedPlace(_ place: AppWLocPlace, parameters: AppWLocLockParameters? = nil) {
        guard !isChangingLocation, canLockWithLocationServices() else { return }
        switch locationMode {
        case .simulated:
            let coordinate = AppWLocCoordinateTool.wlocResponseCoordinate(fromAppleMapCoordinate: place.coordinate)
            performSystemLocation(.lock(latitude: coordinate.latitude, longitude: coordinate.longitude, parameters: parameters))
        case .wloc:
            lock(place, parameters: parameters ?? AppWLocLockParameters())
        }
    }

    private var lockSuccessMessage: String {
        var msg = "锁定成功。请确认已通过“钥匙串访问”→“系统”→“文件”→“导入项目…”导入根证书并设为“始终信任”，然后关闭系统定位服务，等待两秒后再打开。"
        #if DEBUG
        let logPath = AppWLocUtils.debugLogURL?.path ?? "/tmp/AppWLoc/wloc-debug.log"
        msg += "\n\n调试日志：\(logPath)"
        #endif
        return msg
    }

    private func canLockWithLocationServices() -> Bool {
        guard CLLocationManager.locationServicesEnabled() else {
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 锁定已取消：系统定位服务未开启")
            showLocationSettingsAlert(
                title: "定位服务未开启",
                message: "请先前往“系统设置”→“隐私与安全性”→“定位服务”，开启定位服务后再锁定位置。"
            )
            return false
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined:
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 锁定前请求定位权限")
            locationManager.requestWhenInUseAuthorization()
            showLocationSettingsAlert(
                title: "需要定位权限",
                message: "请允许 \(AppWLocConfig.displayName) 使用定位服务，授权后再次点击“锁定位置”。"
            )
        case .denied, .restricted:
            AppWLocUtils.debugLog(
                "\(AppWLocConfig.displayName) macOS 锁定已取消：定位权限 \(authorizationStatusDescription(locationManager.authorizationStatus))"
            )
            showLocationSettingsAlert(
                title: "定位权限未开启",
                message: "请前往“系统设置”→“隐私与安全性”→“定位服务”，允许 \(AppWLocConfig.displayName) 使用定位服务后再试。"
            )
        @unknown default:
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 锁定已取消：未知定位权限状态")
            showLocationSettingsAlert(
                title: "无法使用定位",
                message: "当前定位权限状态不可用，请检查系统定位服务设置。"
            )
        }
        return false
    }

    /// 普通锁定和高级锁定共用代理流程，参数会一起写入锁定状态。
    private func lock(_ place: AppWLocPlace, parameters: AppWLocLockParameters = AppWLocLockParameters(), successMessage: String? = nil) {
        guard !isChangingLocation else { return }
        isChangingLocation = true
        locationRefreshWorkItem?.cancel()
        restoreButton.isEnabled = false
        lockButton.isEnabled = false
        lockButton.title = "锁定中..."
        pacManager.lock(to: place, parameters: parameters) { [weak self] result in
            AppWLocUtils.mainThread {
                guard let self else { return }
                self.isChangingLocation = false
                self.restoreButton.isEnabled = true
                self.lockButton.isEnabled = true
                switch result {
                case .success:
                    self.lockButton.title = "锁定位置"
                    let refresh = DispatchWorkItem { [weak self] in
                        self?.startSystemLocationRefresh(selectResult: false)
                    }
                    self.locationRefreshWorkItem = refresh
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: refresh)
                    self.showAlert(title: "已锁定", message: successMessage ?? self.lockSuccessMessage)
                case .failure(let error):
                    self.lockButton.title = "锁定位置"
                    self.showAlert(title: "启动失败", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func restoreLocation() {
        guard !isChangingLocation else { return }
        if !pacManager.hasPACToRestore, locationMode == .simulated || hasSystemLocationToRestore {
            performSystemLocation(.restore)
            return
        }
        isChangingLocation = true
        locationRefreshWorkItem?.cancel()
        locationRefreshWorkItem = nil
        shouldSelectNextLocationUpdate = false
        isRefreshingLocationAfterLock = false
        locationManager.stopUpdatingLocation()
        restoreButton.isEnabled = false
        lockButton.isEnabled = false
        restoreButton.title = "还原中…"
        restoreButton.imagePosition = .imageOnly

        pacManager.stop(clearState: true) { [weak self] error in
            guard let self else { return }
            self.isChangingLocation = false
            self.restoreButton.isEnabled = true
            self.lockButton.isEnabled = true
            if let error {
                self.restoreButton.title = "重试恢复"
                self.restoreButton.imagePosition = .imageOnly
                self.showAlert(title: "恢复失败", message: "原代理设置尚未全部恢复，请重试。\n\n\(error.localizedDescription)")
            } else {
                self.restoreButton.title = "还原定位"
                self.restoreButton.imagePosition = .imageOnly
                self.showAlert(title: "还原定位", message: "已恢复原代理设置。若连接了 VPN，请先关闭 VPN。然后前往“系统设置 → 隐私与安全性 → 定位服务”，关闭定位服务，等待 2 秒后重新开启，以刷新实际位置。")
            }
        }
    }

    /// 执行本机定位操作，系统服务就绪后提示应用重新取定位。
    private func performSystemLocation(_ operation: AppWLocPACManager.SystemLocationOperation) {
        isChangingLocation = true
        locationRefreshWorkItem?.cancel()
        locationRefreshWorkItem = nil
        shouldSelectNextLocationUpdate = false
        isRefreshingLocationAfterLock = false
        locationManager.stopUpdatingLocation()
        lockButton.isEnabled = false
        restoreButton.isEnabled = false
        lockButton.title = "正在刷新定位…"
        pacManager.performSystemLocation(operation) { [weak self] active, error in
            guard let self else { return }
            if let active { self.hasSystemLocationToRestore = active }
            self.isChangingLocation = false
            self.lockButton.title = "锁定位置"
            self.lockButton.isEnabled = true
            self.restoreButton.isEnabled = true
            if let error {
                self.showAlert(title: "虚拟定位操作失败", message: error.localizedDescription)
            } else if active == true {
                self.showAlert(title: "虚拟位置已设置", message: "定位服务已刷新，请在 Apple 地图或目标应用中重新获取当前位置。")
            } else {
                self.showAlert(title: "虚拟定位已还原", message: "请在目标应用中重新获取当前位置。")
            }
        }
    }

    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        do {
            switch try WLocURLCommandParser.parse(url) {
            case .location(let place):
                applyExternalLocation(place)
            }
            return true
        } catch {
            showAlert(title: "链接无效", message: error.localizedDescription)
            return false
        }
    }

    func stopPACForAppTermination() {
        pacManager.stopForAppTermination()
    }

    private func applyExternalLocation(_ place: AppWLocPlace) {
        guard !isChangingLocation else { return }
        view.window?.makeFirstResponder(nil)
        reverseGeocodeWorkItem?.cancel()
        geocoder.cancelGeocode()
        moveMap(to: place)
        guard locationMode == .wloc else { return }
        lock(place, successMessage: "已通过外部链接保存目标位置并启用 PAC 代理。")
    }

    /// 选中坐标即可收藏，无需等待详细地址解析完成。
    @objc private func addFavorite() {
        guard let place = selectedPlace else { return }
        let favorite = AppWLocFavorite(place: place, alias: "")
        let alert = NSAlert()
        alert.messageText = "加入收藏"
        alert.informativeText = "地点：\(favorite.title)\n地址：\(favorite.detail)\n坐标：\(favorite.coordinateText)"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let aliasField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        aliasField.placeholderString = "输入自定义别名（可选）"
        aliasField.stringValue = ""
        alert.accessoryView = aliasField

        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let alias = aliasField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let favorite = AppWLocFavorite(place: place, alias: alias)
            AppWLocFavoriteStore.shared.add(favorite)
            self.updateSelectedPlace(place)
            self.reloadFavorites()
        }
    }

    @objc func openTutorial() {
        guard showsCertificateTutorial else { return }
        let controller = WLocMacTutorialWindowController()
        tutorialWindow = controller
        controller.showWindow(self)
    }

    /// 主界面和帮助菜单共用日志窗口，重复点击不新建窗口。
    @objc func openDebugLog() {
        if debugLogWindow == nil {
            debugLogWindow = WLocMacDebugLogWindowController()
        }
        debugLogWindow?.showWindow(self)
        pacManager.logDiagnostics { [weak self] in self?.debugLogWindow?.reloadLog() }
    }

    @objc private func openTelegram() {
        openExternalURL(WLocMacExternalLink.telegram)
    }

    @objc private func openGitHub() {
        openExternalURL(WLocMacExternalLink.github)
    }

    private func openExternalURL(_ url: URL) {
        view.window?.makeFirstResponder(nil)
        NSWorkspace.shared.open(url)
    }

    @objc private func performSearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            hideSearchResults()
            return
        }
        searchResultsTitleLabel.stringValue = "搜索中…"
        searchResults.removeAll()
        searchTable.reloadData()
        searchResultsPanel.isHidden = false
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = mapView.region
        MKLocalSearch(request: request).start { [weak self] response, error in
            guard let self else { return }
            if let error {
                self.hideSearchResults()
                self.showAlert(title: "搜索失败", message: error.localizedDescription)
                return
            }
            self.searchResults = response?.mapItems.prefix(12).map { AppWLocPlace(mapItem: $0) } ?? []
            self.searchResultsTitleLabel.stringValue = self.searchResults.isEmpty ? "没有找到结果" : "搜索结果"
            self.searchTable.reloadData()
        }
    }

    private func hideSearchResults() {
        searchResultsPanel.isHidden = true
        searchTable.deselectAll(nil)
    }

    private func dismissSearchResultsIfNeeded(for event: NSEvent) {
        guard !searchResultsPanel.isHidden, event.window === view.window else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        guard let hitView = view.hitTest(point) else {
            hideSearchResults()
            return
        }
        if hitView.isDescendant(of: searchResultsPanel) || hitView.isDescendant(of: searchField) {
            return
        }
        hideSearchResults()
    }

    @objc private func deleteFavoriteFromContextMenu() {
        let row = favoritesTable.clickedRow
        guard favorites.indices.contains(row) else { return }
        let favorite = favorites[row]
        let alert = NSAlert()
        alert.messageText = "删除“\(favorite.displayName)”？"
        alert.informativeText = "删除后无法撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            AppWLocFavoriteStore.shared.remove(id: favorite.id)
            self.reloadFavorites()
            if let selectedPlace = self.selectedPlace {
                self.updateSelectedPlace(selectedPlace)
            }
        }
    }

    /// 启动时静默检查；用户主动检查发现新版时可直接下载并安装。
    func checkForUpdates(userInitiated: Bool) {
        guard !isCheckingUpdates, !isUpdating else { return }
        isCheckingUpdates = true
        updateButton.isEnabled = false
        if userInitiated {
            versionLabel.stringValue = "正在检查更新…"
        }
        AppWLocUpdateChecker.shared.check(platform: .macOS) { [weak self] result in
            guard let self else { return }
            self.isCheckingUpdates = false
            self.updateButton.isEnabled = true
            self.versionLabel.stringValue = "版本 \(AppWLocConfig.currentVersion)"
            switch result {
            case .updateAvailable(let update):
                self.availableUpdate = update
                self.setUpdateButtonTitle("更新 v\(update.version)")
                self.updateButton.toolTip = "下载并安装 WLoc8.com v\(update.version)"
                if userInitiated { self.presentAvailableUpdate(update) }
            case .upToDate(let latestVersion):
                self.availableUpdate = nil
                self.setUpdateButtonTitle("检查更新")
                self.updateButton.toolTip = "检查 GitHub Releases 中的新版本"
                if userInitiated {
                    self.showAlert(title: "已是最新版本", message: "当前版本：\(AppWLocConfig.currentVersion)\n最新版本：\(latestVersion)")
                }
            case .failure(let error):
                if userInitiated {
                    self.showAlert(title: "检查更新失败", message: error.localizedDescription)
                } else {
                    AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 自动检查更新失败：\(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func openAvailableUpdate() {
        if let availableUpdate {
            presentAvailableUpdate(availableUpdate)
        } else {
            checkForUpdates(userInitiated: true)
        }
    }

    /// 更新入口只显示图标，新版本用圆点提示，完整含义留在鼠标提示和无障碍名称里。
    private func setUpdateButtonTitle(_ title: String) {
        updateButton.title = title
        updateButton.imagePosition = .imageOnly
        updateButton.toolTip = title
        updateButton.setAccessibilityLabel(title)
        updateBadge.isHidden = availableUpdate == nil
    }

    private func presentAvailableUpdate(_ update: AppWLocAvailableUpdate) {
        guard !isUpdating, let window = view.window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "发现新版本 v\(update.version)"
        let hasPackage = update.assetName?.lowercased().hasSuffix(".dmg") == true
        alert.informativeText = "当前版本：\(AppWLocConfig.currentVersion)\n\n" + (hasPackage
            ? "将从 GitHub 下载并安装新版本，完成后自动重启应用。更新会先恢复 WLoc 的代理设置。"
            : "该版本尚未提供 macOS 安装包，请前往发布页查看。")
        alert.addButton(withTitle: hasPackage ? "下载并安装" : "查看发布页")
        alert.addButton(withTitle: "稍后")
        if hasPackage { alert.addButton(withTitle: "查看发布页") }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                if hasPackage { self.downloadUpdate(update) } else { self.openExternalURL(update.releasePageURL) }
            } else if response == .alertThirdButtonReturn {
                self.openExternalURL(update.releasePageURL)
            }
        }
    }

    /// 下载期间禁用定位修改，并用可取消的弹窗显示下载和校验进度。
    private func downloadUpdate(_ update: AppWLocAvailableUpdate) {
        guard !isUpdating, !isChangingLocation, let window = view.window else { return }
        do {
            let installer = try WLocMacUpdateInstaller(update: update)
            updateInstaller = installer
            isUpdating = true
            isChangingLocation = true
            [lockButton, restoreButton, updateButton].forEach { $0.isEnabled = false }
            let alert = NSAlert()
            alert.messageText = "更新 v\(update.version)"
            alert.informativeText = "正在连接下载服务…"
            let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 340, height: 18))
            indicator.style = .bar
            indicator.isIndeterminate = true
            indicator.minValue = 0
            indicator.maxValue = 1
            indicator.startAnimation(nil)
            alert.accessoryView = indicator
            alert.addButton(withTitle: "取消")
            updateProgressAlert = alert
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn, self.isUpdating, !self.isInstallingUpdate else { return }
                self.updateInstaller?.cancel()
            }
            installer.download(progress: { [weak alert, weak indicator] fraction, message in
                alert?.informativeText = fraction.map { "\(message) \(Int($0 * 100))%" } ?? message
                indicator?.isIndeterminate = fraction == nil
                if let fraction { indicator?.doubleValue = fraction } else { indicator?.startAnimation(nil) }
            }) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.isInstallingUpdate = true
                    self.updateProgressAlert?.buttons.first?.isEnabled = false
                    self.updateProgressAlert?.informativeText = "正在恢复 WLoc 代理设置并准备安装…"
                    // 先恢复代理再退出，避免更新重启后系统继续使用已停止的定位代理。
                    self.pacManager.stop(clearState: true) { [weak self] error in
                        guard let self else { return }
                        if let error { self.finishUpdate(error: error); return }
                        self.updateInstaller?.install { [weak self] result in
                            guard let self else { return }
                            switch result {
                            case .success:
                                self.finishUpdate(error: nil)
                                NSApp.terminate(nil)
                            case .failure(let error): self.finishUpdate(error: error)
                            }
                        }
                    }
                case .failure(let error): self.finishUpdate(error: error)
                }
            }
        } catch { showAlert(title: "更新失败", message: error.localizedDescription) }
    }

    /// 关闭进度弹窗并恢复按钮，取消不报错，安装失败保留当前版本。
    private func finishUpdate(error: Error?) {
        if error != nil { updateInstaller?.cancel() }
        if let alert = updateProgressAlert { alert.window.sheetParent?.endSheet(alert.window, returnCode: .abort) }
        updateProgressAlert = nil
        updateInstaller = nil
        isUpdating = false
        isInstallingUpdate = false
        isChangingLocation = false
        [lockButton, restoreButton, updateButton].forEach { $0.isEnabled = true }
        if shouldQuitAfterUpdateCancellation {
            shouldQuitAfterUpdateCancellation = false
            NSApp.terminate(nil)
        } else if let error {
            let cocoaError = error as NSError
            let isCancelled = (error as? URLError)?.code == .cancelled
                || (cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError)
            if !isCancelled { showAlert(title: "更新失败", message: error.localizedDescription) }
        }
    }

    /// 退出时先取消未完成的下载；安装完成后再退出，避免中断应用替换。
    func deferTerminationForUpdate() -> Bool {
        guard isUpdating else { return false }
        if !isInstallingUpdate {
            shouldQuitAfterUpdateCancellation = true
            updateInstaller?.cancel()
        }
        return true
    }

    @objc private func zoomIn() {
        view.window?.makeFirstResponder(nil)
        NSCursor.arrow.set()
        zoomMap(by: 0.5)
    }

    @objc private func zoomOut() {
        view.window?.makeFirstResponder(nil)
        NSCursor.arrow.set()
        zoomMap(by: 2.0)
    }

    @objc private func selectMapPoint(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard shouldSelectMapPoint(for: recognizer) else { return }
        hideSearchResults()
        view.window?.makeFirstResponder(nil)
        NSCursor.arrow.set()
        let point = recognizer.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        selectCoordinate(coordinate)
    }

    private func shouldSelectMapPoint(for recognizer: NSGestureRecognizer) -> Bool {
        guard let superview = mapView.superview else { return true }
        let point = recognizer.location(in: superview)
        guard let hitView = mapView.hitTest(point) else { return true }

        if hitView is NSControl {
            return false
        }
        if let controlsPanel, hitView.isDescendant(of: controlsPanel) {
            return false
        }

        return true
    }

    private func zoomMap(by multiplier: CLLocationDegrees) {
        let span = MKCoordinateSpan(
            latitudeDelta: max(mapView.region.span.latitudeDelta * multiplier, 0.0005),
            longitudeDelta: max(mapView.region.span.longitudeDelta * multiplier, 0.0005)
        )
        mapView.setRegion(MKCoordinateRegion(center: mapView.centerCoordinate, span: span), animated: true)
    }

    @objc private func centerOnCurrentLocation() {
        view.window?.makeFirstResponder(nil)
        NSCursor.arrow.set()

        if let location = mapView.userLocation.location ?? locationManager.location {
            centerMap(on: location.coordinate, meters: 0)
            return
        }

        startSystemLocationRefresh(selectResult: true)
    }

    private func startSystemLocationRefresh(selectResult: Bool) {
        guard !isChangingLocation else { return }
        shouldSelectNextLocationUpdate = selectResult
        isRefreshingLocationAfterLock = !selectResult
        mapView.showsUserLocation = true

        let status = locationManager.authorizationStatus
        AppWLocUtils.debugLog(
            "\(AppWLocConfig.displayName) macOS 准备刷新系统定位 selectResult=\(selectResult)，status=\(authorizationStatusDescription(status))"
        )
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 请求定位权限并启动定位刷新")
            locationManager.startUpdatingLocation()
        case .authorizedAlways, .authorizedWhenInUse:
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 启动定位刷新 selectResult=\(selectResult)")
            locationManager.startUpdatingLocation()
        default:
            AppWLocUtils.debugLog(
                "\(AppWLocConfig.displayName) macOS 定位当前不可用，等待用户重新开启定位服务 status=\(authorizationStatusDescription(status))"
            )
            if selectResult {
                shouldSelectNextLocationUpdate = false
                isRefreshingLocationAfterLock = false
                showAlert(title: "无法定位", message: "请在系统设置中允许 \(AppWLocConfig.displayName) 使用定位服务。")
            }
        }
    }

    private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard !isChangingLocation else { return }
        let hasLockedState = AppWLocStateStore.shared.load() != nil
        AppWLocUtils.debugLog(
            "\(AppWLocConfig.displayName) macOS 定位授权变化 status=\(authorizationStatusDescription(status))，afterLock=\(isRefreshingLocationAfterLock)，selectNext=\(shouldSelectNextLocationUpdate)，locked=\(hasLockedState)"
        )
        guard isRefreshingLocationAfterLock || shouldSelectNextLocationUpdate || hasLockedState else { return }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if hasLockedState && !isRefreshingLocationAfterLock && !shouldSelectNextLocationUpdate {
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 检测到已锁定坐标，定位服务恢复后补发定位刷新")
                isRefreshingLocationAfterLock = true
            }
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 定位已恢复，补发定位刷新")
            mapView.showsUserLocation = true
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 定位仍不可用，保持等待")
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 未知定位授权状态")
        }
    }

    private func authorizationStatusDescription(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        @unknown default:
            return "unknown(\(status.rawValue))"
        }
    }

    private func centerMap(on coordinate: CLLocationCoordinate2D, meters: CLLocationDistance) {
        if meters <= 0 {
            mapView.setCenter(coordinate, animated: false)
        } else {
            mapView.setRegion(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters),
                animated: true
            )
        }
        selectCoordinate(coordinate, name: "当前位置", detail: "来自系统定位")
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: view.window ?? NSWindow()) { _ in }
    }

    private func showLocationSettingsAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.openLocationServicesSettings()
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func openLocationServicesSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for settingsURL in settingsURLs {
            guard let url = URL(string: settingsURL) else { continue }
            if NSWorkspace.shared.open(url) {
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 已打开定位服务系统设置：\(settingsURL)")
                return
            }
        }

        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 无法打开定位服务系统设置")
        showAlert(
            title: "无法打开系统设置",
            message: "请手动前往“系统设置”→“隐私与安全性”→“定位服务”。"
        )
    }
}

private final class WLocMacAdvancedLockViewController: NSViewController {
    private let place: AppWLocPlace
    private let initialParameters: AppWLocLockParameters
    private let onLock: (AppWLocLockParameters) -> Void
    private let altitudeField = NSTextField()
    private let horizontalField = NSTextField()
    private let verticalField = NSTextField()
    private let queryButton = NSButton.wlocButton("查询海拔")
    private let statusLabel = NSTextField.wlocWrappingLabel("")
    private var elevationTask: URLSessionDataTask?

    init(place: AppWLocPlace, initialParameters: AppWLocLockParameters, onLock: @escaping (AppWLocLockParameters) -> Void) {
        self.place = place
        self.initialParameters = initialParameters
        self.onLock = onLock
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit { elevationTask?.cancel() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 470))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 表单固定使用打开时选中的位置，避免查询和锁定落在不同的坐标上。
        altitudeField.stringValue = NSNumber(value: initialParameters.altitude).stringValue
        horizontalField.stringValue = String(initialParameters.horizontalAccuracy)
        verticalField.stringValue = String(initialParameters.verticalAccuracy)

        let heading = NSTextField.wlocLabel("高级锁定")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let coordinates = NSTextField.wlocWrappingLabel(String(format: "当前选择\n纬度：%.7f    经度：%.7f", place.latitude, place.longitude))
        coordinates.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        coordinates.isSelectable = true
        let parameterTitle = NSTextField.wlocLabel("定位参数（精度为非负整数）")
        parameterTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        queryButton.target = self
        queryButton.action = #selector(queryElevation)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        let cancelButton = NSButton.wlocButton("取消")
        cancelButton.target = self
        cancelButton.action = #selector(close)
        cancelButton.keyEquivalent = "\u{1b}"
        let lockButton = NSButton.wlocButton("锁定位置")
        lockButton.target = self
        lockButton.action = #selector(confirmLock)
        lockButton.keyEquivalent = "\r"
        lockButton.bezelColor = .controlAccentColor
        let actions = NSStackView(views: [cancelButton, lockButton])
        actions.orientation = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 12

        let stack = NSStackView(views: [
            heading, coordinates, parameterTitle,
            parameterRow(title: "海拔高度（m）", field: altitudeField), queryButton,
            parameterRow(title: "水平精度（m）", field: horizontalField),
            parameterRow(title: "垂直精度（m）", field: verticalField), statusLabel, actions
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        view.addSubview(stack)
        stack.snp.makeConstraints { make in make.edges.equalToSuperview().inset(24) }
        stack.arrangedSubviews.forEach { subview in
            subview.snp.makeConstraints { make in make.width.equalTo(stack) }
        }
        statusLabel.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(32) }
        actions.snp.makeConstraints { make in make.height.equalTo(36) }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        elevationTask?.cancel()
        elevationTask = nil
    }

    private func parameterRow(title: String, field: NSTextField) -> NSView {
        let label = NSTextField.wlocLabel(title)
        label.font = .systemFont(ofSize: 13)
        field.font = .systemFont(ofSize: 16)
        field.setAccessibilityLabel(title)
        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        label.snp.makeConstraints { make in make.width.equalTo(120) }
        field.snp.makeConstraints { make in make.height.equalTo(32) }
        return row
    }

    @objc private func close() { dismiss(self) }

    @objc private func queryElevation() {
        view.window?.makeFirstResponder(nil)
        queryButton.isEnabled = false
        queryButton.title = "查询中…"
        statusLabel.stringValue = ""
        let coordinate = AppWLocCoordinateTool.wlocResponseCoordinate(fromAppleMapCoordinate: place.coordinate)
        elevationTask = AppWLocElevationQuery.query(latitude: coordinate.latitude, longitude: coordinate.longitude) { [weak self] result in
            guard let self, self.elevationTask != nil else { return }
            self.elevationTask = nil
            self.queryButton.isEnabled = true
            self.queryButton.title = "查询海拔"
            switch result {
            case .success(let elevation):
                self.altitudeField.stringValue = NSNumber(value: elevation).stringValue
                self.statusLabel.textColor = .secondaryLabelColor
                self.statusLabel.stringValue = "已填入查询海拔，可继续手动修改。"
            case .failure(let error):
                self.statusLabel.textColor = .systemRed
                self.statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func confirmLock() {
        view.window?.makeFirstResponder(nil)
        do {
            let parameters = try AppWLocLockParameters(
                altitudeText: altitudeField.stringValue,
                horizontalAccuracyText: horizontalField.stringValue,
                verticalAccuracyText: verticalField.stringValue
            )
            elevationTask?.cancel()
            elevationTask = nil
            dismiss(self)
            onLock(parameters)
        } catch {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = error.localizedDescription
        }
    }
}

extension WLocMacMapViewController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            performSearch()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hideSearchResults()
            return true
        }
        return false
    }
}

extension WLocMacMapViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === favoritesTable.menu else { return }
        menu.items.first?.isEnabled = favorites.indices.contains(favoritesTable.clickedRow)
    }
}

extension WLocMacMapViewController: NSGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard gestureRecognizer === mapClickGesture else {
            return true
        }
        return shouldSelectMapPoint(for: gestureRecognizer)
    }
}

extension WLocMacMapViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView == searchTable ? searchResults.count : favorites.count
    }

    /// 两端使用相同的收藏文字规则，缺少名称或地址时收起对应行。
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? WLocMacPlaceCell ?? WLocMacPlaceCell()
        cell.identifier = identifier
        if tableView == searchTable {
            let item = searchResults[row]
            cell.configure(name: item.name, detail: item.detail, coordinate: "", isFavorite: false)
            cell.toolTip = item.detail.isEmpty ? item.name : "\(item.name)\n\(item.detail)"
        } else {
            let favorite = favorites[row]
            let coordinate = favorite.displayAlias.isEmpty && favorite.displayTitle.isEmpty ? "" : favorite.coordinateText
            cell.configure(name: favorite.displayName, detail: favorite.displaySubtitle, coordinate: coordinate, isFavorite: true)
            cell.toolTip = [favorite.displayName, favorite.displaySubtitle, coordinate]
                .filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView == favoritesTable ? WLocMacFavoriteRowView() : nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView, tableView.selectedRow >= 0 else { return }
        if tableView == favoritesTable {
            moveMap(to: favorites[tableView.selectedRow].place)
            return
        }

        moveMap(to: searchResults[tableView.selectedRow])
        hideSearchResults()
    }
}

extension WLocMacMapViewController: MKMapViewDelegate {
    
}

extension WLocMacMapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleLocationAuthorizationChange(status)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleLocationAuthorizationChange(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isChangingLocation else { return }
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        AppWLocUtils.debugLog(
            "\(AppWLocConfig.displayName) macOS 收到定位更新 lat=\(location.coordinate.latitude), lng=\(location.coordinate.longitude)"
        )
        let shouldSelect = shouldSelectNextLocationUpdate
        shouldSelectNextLocationUpdate = false
        isRefreshingLocationAfterLock = false
        if shouldSelect {
            centerMap(on: location.coordinate, meters: 1200)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !isChangingLocation else { return }
        manager.stopUpdatingLocation()
        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 定位刷新失败：\(error.localizedDescription)")
        let shouldShowError = shouldSelectNextLocationUpdate || !isRefreshingLocationAfterLock
        shouldSelectNextLocationUpdate = false
        isRefreshingLocationAfterLock = false
        if shouldShowError {
            showAlert(title: "定位失败", message: error.localizedDescription)
        }
    }
}

private final class WLocMacPlaceCell: NSTableCellView {
    let nameLabel = NSTextField.wlocLabel("")
    let detailLabel = NSTextField.wlocLabel("")
    let coordinateLabel = NSTextField.wlocLabel("")
    private let pinView = NSImageView()
    private let iconBackground = NSView()

    /// 搜索和收藏共用地点图标与分层文字，长地址截断后仍可通过鼠标查看全文。
    init() {
        super.init(frame: .zero)
        textField = nameLabel
        imageView = pinView
        pinView.contentTintColor = .controlAccentColor
        pinView.imageScaling = .scaleProportionallyDown
        pinView.setAccessibilityElement(false)
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        coordinateLabel.textColor = .secondaryLabelColor
        let textStack = NSStackView(views: [nameLabel, detailLabel, coordinateLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        [nameLabel, detailLabel, coordinateLabel].forEach { label in
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.snp.makeConstraints { make in make.width.equalTo(textStack) }
        }
        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 9
        addSubview(iconBackground)
        iconBackground.addSubview(pinView)
        addSubview(textStack)
        iconBackground.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(32)
        }
        pinView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.centerX.equalToSuperview()
            make.width.height.equalTo(17)
        }
        textStack.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalTo(iconBackground.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(12)
        }
    }

    required init?(coder: NSCoder) { nil }

    /// 搜索仍显示定位图标，收藏改用淡蓝星标；空文字行不占据布局空间。
    func configure(name: String, detail: String, coordinate: String, isFavorite: Bool) {
        nameLabel.stringValue = name
        detailLabel.stringValue = detail
        coordinateLabel.stringValue = coordinate
        detailLabel.isHidden = detail.isEmpty
        coordinateLabel.isHidden = coordinate.isEmpty
        pinView.image = NSImage(systemSymbolName: isFavorite ? "star.fill" : "mappin", accessibilityDescription: nil)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            iconBackground.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.09).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            iconBackground.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.09).cgColor
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let selected = backgroundStyle == .emphasized
            nameLabel.textColor = selected ? .white : .labelColor
            detailLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.85) : .secondaryLabelColor
            coordinateLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.85) : .secondaryLabelColor
            pinView.contentTintColor = selected ? .white : .controlAccentColor
        }
    }
}

private final class WLocMacFavoriteRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawBackground(in dirtyRect: NSRect) {
        drawCard(selected: false)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        drawCard(selected: true)
    }

    /// 浅色圆角底区分每条收藏，选中时使用淡蓝底和细描边。
    private func drawCard(selected: Bool) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 3), xRadius: 10, yRadius: 10)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.1) : .controlBackgroundColor).setFill()
        path.fill()
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.35) : NSColor.separatorColor.withAlphaComponent(0.25)).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

private enum WLocMacExternalLink {
    static let telegram = URL(string: "https://t.me/wloc88")!
    static let github = AppWLocConfig.githubRepositoryURL
}

private enum WLocMacExternalIcon {
    enum Fallback {
        case telegram
        case code
    }

    static func image(named systemName: String, fallback: Fallback, size: NSSize) -> NSImage {
        if let systemImage = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            systemImage.size = size
            return systemImage
        }

        return fallbackImage(fallback, size: size)
    }

    private static func fallbackImage(_ icon: Fallback, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.labelColor.set()

        let rect = NSRect(origin: .zero, size: size)
        switch icon {
        case .telegram:
            drawTelegramIcon(in: rect)
        case .code:
            drawCodeIcon(in: rect)
        }

        image.unlockFocus()
        return image
    }

    private static func drawTelegramIcon(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.88))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.1))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.36))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.22))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.42))
        path.close()
        path.fill()
    }

    private static func drawCodeIcon(in rect: NSRect) {
        let left = NSBezierPath()
        left.move(to: NSPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.78))
        left.line(to: NSPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.5))
        left.line(to: NSPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.22))
        left.lineWidth = 2
        left.lineCapStyle = .round
        left.lineJoinStyle = .round
        left.stroke()

        let right = NSBezierPath()
        right.move(to: NSPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.78))
        right.line(to: NSPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.5))
        right.line(to: NSPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.22))
        right.lineWidth = 2
        right.lineCapStyle = .round
        right.lineJoinStyle = .round
        right.stroke()

        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.82))
        slash.line(to: NSPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.18))
        slash.lineWidth = 2
        slash.lineCapStyle = .round
        slash.stroke()
    }
}
