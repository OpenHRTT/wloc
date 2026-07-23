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

private final class WLocMacLinkButton: NSButton {
    private let baseColor: NSColor
    private var trackingAreaToken: NSTrackingArea?
    private var isPointerInside = false

    init(title: String, color: NSColor) {
        baseColor = color
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 10
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

    private func updateAppearance() {
        let alpha: CGFloat = isPointerInside ? 0.92 : 0.78
        layer?.backgroundColor = baseColor.withAlphaComponent(alpha).cgColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
            ]
        )
        contentTintColor = .white
    }
}

final class WLocMacMapViewController: NSViewController {
    private enum SelectedCopyField: Int {
        case name = 1
        case detail
        case coordinate
    }

    private let pacManager = AppWLocPACManager()

    private let mapView = WLocArrowCursorMapView()
    private let searchField = NSSearchField()
    private let searchTable = NSTableView()
    private let favoritesTable = NSTableView()
    private let searchResultsPanel = NSVisualEffectView()
    private let searchResultsTitleLabel = NSTextField.wlocLabel("搜索结果")
    private let searchResultsScroll = NSScrollView()
    private let zoomInButton = NSButton.wlocButton("+")
    private let zoomOutButton = NSButton.wlocButton("−")
    private let currentLocationButton = NSButton.wlocButton("⌖")
    private let titleLabel = NSTextField.wlocLabel("地图中心")
    private let detailLabel = NSTextField.wlocLabel("")
    private let coordinateLabel = NSTextField.wlocLabel("")
    private let lockButton = NSButton.wlocButton("锁定位置")
    private let favoriteButton = NSButton.wlocButton("加入收藏")
    private let tutorialButton = NSButton.wlocButton("教程与证书")
    private let telegramButton = WLocMacLinkButton(
        title: "Telegram",
        color: NSColor(calibratedRed: 0.13, green: 0.60, blue: 0.86, alpha: 1)
    )
    private let githubButton = WLocMacLinkButton(
        title: "GitHub",
        color: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 1)
    )
    private let appNameLabel = NSTextField.wlocLabel(AppWLocConfig.displayName)
    private let versionLabel = NSTextField.wlocLabel("版本 \(AppWLocConfig.currentVersion)")
    private let updateButton = NSButton.wlocButton("")
    private let selectedAnnotation = MKPointAnnotation()

    private let geocoder = CLGeocoder()
    private let locationManager = CLLocationManager()
    private var searchResults: [AppWLocPlace] = []
    private var favorites: [AppWLocFavorite] = []
    private var selectedPlace: AppWLocPlace?
    private var hasSelectedAnnotation = false
    private var reverseGeocodeWorkItem: DispatchWorkItem?
    private var tutorialWindow: WLocMacTutorialWindowController?
    private var mapClickGesture: NSClickGestureRecognizer?
    private weak var controlsPanel: NSView?
    private var outsideSearchClickMonitor: Any?
    private var availableUpdate: AppWLocAvailableUpdate?
    private var shouldSelectNextLocationUpdate = false
    private var isRefreshingLocationAfterLock = false

    deinit {
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
        let initialPlace = AppWLocPlace(name: "上海", detail: "单击地图可选择新的位置", latitude: 31.2304, longitude: 121.4737)
        updateSelectedPlace(initialPlace)
        updateSelectedAnnotation(with: initialPlace)
        checkForUpdates(userInitiated: false)
    }

    private func configureViews() {
        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = false
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(selectMapPoint(_:)))
        clickGesture.numberOfClicksRequired = 1
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
        searchField.font = .systemFont(ofSize: 15)

        configureTable(searchTable)
        configureTable(favoritesTable)
        favoritesTable.rowHeight = 82

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

        searchResultsPanel.layer?.cornerRadius = 20
        searchResultsPanel.clipsToBounds = true

        searchResultsTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        searchResultsTitleLabel.textColor = .secondaryLabelColor
        searchResultsScroll.documentView = searchTable
        searchResultsScroll.hasVerticalScroller = true
        searchResultsScroll.borderType = .noBorder
        searchResultsScroll.drawsBackground = false

        appNameLabel.font = .systemFont(ofSize: 18, weight: .bold)
        versionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        updateButton.isHidden = true
        updateButton.isBordered = false
        updateButton.font = .systemFont(ofSize: 11, weight: .semibold)
        updateButton.wantsLayer = true
        updateButton.layer?.cornerRadius = 9
        updateButton.layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.96, alpha: 0.12).cgColor
        updateButton.contentTintColor = NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.96, alpha: 1)
        updateButton.target = self
        updateButton.action = #selector(openAvailableUpdate)

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.cell?.wraps = true
        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        coordinateLabel.textColor = .secondaryLabelColor
        configureCopyMenu(for: titleLabel, field: .name)
        configureCopyMenu(for: detailLabel, field: .detail)
        configureCopyMenu(for: coordinateLabel, field: .coordinate)

        let favoriteMenu = NSMenu(title: "收藏操作")
        favoriteMenu.delegate = self
        let deleteItem = NSMenuItem(title: "删除收藏", action: #selector(deleteFavoriteFromContextMenu), keyEquivalent: "")
        deleteItem.target = self
        favoriteMenu.addItem(deleteItem)
        favoritesTable.menu = favoriteMenu

        [lockButton, favoriteButton, tutorialButton, telegramButton, githubButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
        }
        telegramButton.image = WLocMacExternalIcon.image(named: "paperplane.fill", fallback: .telegram, size: NSSize(width: 17, height: 17))
        telegramButton.toolTip = "打开 Telegram: https://t.me/wloc88"
        githubButton.image = WLocMacExternalIcon.image(named: "chevron.left.forwardslash.chevron.right", fallback: .code, size: NSSize(width: 17, height: 17))
        githubButton.toolTip = "打开 WLoc8.com GitHub 项目"
        [zoomInButton, zoomOutButton, currentLocationButton].forEach { button in
            if #available(macOS 26.0, *) {
                button.bezelStyle = .glass
            } else {
                button.bezelStyle = .texturedRounded
            }
            button.font = .systemFont(ofSize: 18, weight: .semibold)
        }

        lockButton.target = self
        lockButton.action = #selector(lockCurrentPlace)
        favoriteButton.target = self
        favoriteButton.action = #selector(addFavorite)
        tutorialButton.target = self
        tutorialButton.action = #selector(openTutorial)
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

        // 搜索列表是浮层；监听窗口内点击，可在用户点击浮层之外时自然收起。
        outsideSearchClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissSearchResultsIfNeeded(for: event)
            return event
        }
    }

    private func configureTable(_ table: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 54
        table.delegate = self
        table.dataSource = self
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
    }

    private func layoutViews() {
        let sidebar = WLocMacGlassView(cornerRadius: 28)
        let controlsPanel = WLocMacGlassView(cornerRadius: 8)
        self.controlsPanel = controlsPanel

        view.addSubview(mapView)
        view.addSubview(sidebar)
        view.addSubview(controlsPanel)
        view.addSubview(searchResultsPanel, positioned: .above, relativeTo: nil)

        searchResultsPanel.addSubview(searchResultsTitleLabel)
        searchResultsPanel.addSubview(searchResultsScroll)

        controlsPanel.contentView.addSubview(zoomInButton)
        controlsPanel.contentView.addSubview(zoomOutButton)
        controlsPanel.contentView.addSubview(currentLocationButton)

        mapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        sidebar.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.top.equalToSuperview().inset(64)
            make.bottom.equalToSuperview().inset(24)
            make.width.equalTo(408)
        }
        controlsPanel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(72)
            make.trailing.equalToSuperview().inset(28)
            make.width.equalTo(54)
            make.height.equalTo(164)
        }
        
        zoomInButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(42)
        }
        zoomOutButton.snp.makeConstraints { make in
            make.top.equalTo(zoomInButton.snp.bottom).offset(10)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(zoomInButton)
        }
        currentLocationButton.snp.makeConstraints { make in
            make.top.equalTo(zoomOutButton.snp.bottom).offset(10)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(zoomInButton)
        }

        let favoriteTitle = NSTextField.wlocLabel("收藏地点")
        favoriteTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        favoriteTitle.textColor = .secondaryLabelColor

        let favoritesScroll = NSScrollView()
        favoritesScroll.documentView = favoritesTable
        favoritesScroll.hasVerticalScroller = true
        favoritesScroll.borderType = .noBorder

        let actionStack = NSStackView(views: [lockButton, favoriteButton])
        actionStack.orientation = .horizontal
        actionStack.spacing = 10
        actionStack.distribution = .fillEqually

        let secondaryActionStack = NSStackView(views: [tutorialButton])
        secondaryActionStack.orientation = .vertical
        secondaryActionStack.spacing = 15
        secondaryActionStack.distribution = .fillEqually

        let externalLinkStack = NSStackView(views: [telegramButton, githubButton])
        externalLinkStack.orientation = .horizontal
        externalLinkStack.spacing = 10
        externalLinkStack.distribution = .fillEqually
        secondaryActionStack.addArrangedSubview(externalLinkStack)

        externalLinkStack.snp.makeConstraints { make in
            make.width.equalTo(secondaryActionStack).offset(-36)
        }

        [lockButton, favoriteButton, tutorialButton, telegramButton, githubButton].forEach { button in
            button.snp.makeConstraints { make in
                make.height.equalTo(36)
            }
        }

        [appNameLabel, versionLabel, updateButton, searchField, titleLabel, detailLabel, coordinateLabel, actionStack, secondaryActionStack, favoriteTitle, favoritesScroll].forEach {
            sidebar.contentView.addSubview($0)
        }

        appNameLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(20)
            make.leading.equalToSuperview().inset(18)
        }
        versionLabel.snp.makeConstraints { make in
            make.leading.equalTo(appNameLabel)
            make.top.equalTo(appNameLabel.snp.bottom).offset(2)
        }
        updateButton.snp.makeConstraints { make in
            make.centerY.equalTo(versionLabel)
            make.leading.equalTo(versionLabel.snp.trailing).offset(6)
            make.trailing.lessThanOrEqualToSuperview().inset(18)
            make.height.equalTo(22)
        }
        searchField.snp.makeConstraints { make in
            make.top.equalTo(versionLabel.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(18)
            make.height.equalTo(36)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(18)
            make.leading.trailing.equalTo(searchField)
        }
        detailLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalTo(searchField)
        }
        coordinateLabel.snp.makeConstraints { make in
            make.top.equalTo(detailLabel.snp.bottom).offset(8)
            make.leading.trailing.equalTo(searchField)
        }
        actionStack.snp.makeConstraints { make in
            make.top.equalTo(coordinateLabel.snp.bottom).offset(16)
            make.leading.trailing.equalTo(searchField)
        }
        secondaryActionStack.snp.makeConstraints { make in
            make.top.equalTo(actionStack.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview()
        }
        favoriteTitle.snp.makeConstraints { make in
            make.top.equalTo(secondaryActionStack.snp.bottom).offset(20)
            make.leading.trailing.equalTo(searchField)
        }
        favoritesScroll.snp.makeConstraints { make in
            make.top.equalTo(favoriteTitle.snp.bottom).offset(8)
            make.leading.trailing.equalTo(searchField)
            make.bottom.equalToSuperview().inset(16)
        }

        searchResultsPanel.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(8)
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

    private func updateSelectedPlace(_ place: AppWLocPlace) {
        selectedPlace = place
        titleLabel.stringValue = place.name
        detailLabel.stringValue = place.detail
        coordinateLabel.stringValue = place.coordinateText
        favoriteButton.isEnabled = !AppWLocFavoriteStore.shared.contains(place)
        favoriteButton.title = favoriteButton.isEnabled ? "加入收藏" : "已收藏"
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

    private func reloadFavorites() {
        favorites = AppWLocFavoriteStore.shared.all()
        favoritesTable.reloadData()
    }

    @objc private func lockCurrentPlace() {
        guard let place = selectedPlace else { return }
        var msg = "锁定成功。请确认已通过“钥匙串访问”→“系统”→“文件”→“导入项目…”导入根证书并设为“始终信任”，然后关闭系统定位服务，等待两秒后再打开。"
        #if DEBUG
        let logPath = AppWLocUtils.debugLogURL?.path ?? "/tmp/AppWLoc/wloc-debug.log"
        msg += "\n\n调试日志：\(logPath)"
        #endif
        lock(place, successMessage:msg)
    }

    private func lock(_ place: AppWLocPlace, successMessage: String) {
        lockButton.isEnabled = false
        lockButton.title = "锁定中..."
        pacManager.lock(to: place) { [weak self] result in
            AppWLocUtils.mainThread {
                guard let self else { return }
                self.lockButton.isEnabled = true
                switch result {
                case .success:
                    self.lockButton.title = "锁定位置"
                    AppWLocUtils.mainThreadAfter(2.0) { [weak self] in
                        self?.startSystemLocationRefresh(selectResult: false)
                    }
                    self.showAlert(title: "已锁定", message: successMessage)
                case .failure(let error):
                    self.lockButton.title = "锁定位置"
                    self.showAlert(title: "启动失败", message: error.localizedDescription)
                }
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
        view.window?.makeFirstResponder(nil)
        reverseGeocodeWorkItem?.cancel()
        geocoder.cancelGeocode()
        moveMap(to: place)
        lock(place, successMessage: "已通过外部链接保存目标位置并启用 PAC 代理。")
    }

    @objc private func addFavorite() {
        guard let place = selectedPlace else { return }
        let savedDetail = place.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !savedDetail.isEmpty,
              place.name != "查询中...",
              savedDetail != "单击地图可选择新的位置" else {
            showAlert(title: "地址尚未获取", message: "请等待详细地址显示后再加入收藏。")
            return
        }
        let alert = NSAlert()
        alert.messageText = "加入收藏"
        alert.informativeText = "地点：\(place.name)\n地址：\(savedDetail)\n坐标：\(place.coordinateText)"
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
        let controller = WLocMacTutorialWindowController()
        tutorialWindow = controller
        controller.showWindow(self)
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
        let favoriteName = favorite.alias.isEmpty ? favorite.title : favorite.alias
        alert.messageText = "删除“\(favoriteName)”？"
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

    func checkForUpdates(userInitiated: Bool) {
        if userInitiated {
            versionLabel.stringValue = "正在检查更新…"
        }
        AppWLocUpdateChecker.shared.check(platform: .macOS) { [weak self] result in
            guard let self else { return }
            self.versionLabel.stringValue = "版本 \(AppWLocConfig.currentVersion)"
            switch result {
            case .updateAvailable(let update):
                self.availableUpdate = update
                self.updateButton.attributedTitle = NSAttributedString(
                    string: "更新 v\(update.version)",
                    attributes: [
                        .foregroundColor: NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.96, alpha: 1),
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
                    ]
                )
                self.updateButton.toolTip = "下载 WLoc8.com v\(update.version)"
                self.updateButton.isHidden = false
            case .upToDate(let latestVersion):
                self.availableUpdate = nil
                self.updateButton.isHidden = true
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
        guard let availableUpdate else { return }
        openExternalURL(availableUpdate.downloadURL)
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

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? NSTextField.wlocLabel("")
        textField.identifier = identifier
        textField.lineBreakMode = .byTruncatingTail
        if tableView == searchTable {
            textField.maximumNumberOfLines = 2
            textField.font = .systemFont(ofSize: 13)
            let item = searchResults[row]
            textField.stringValue = item.detail.isEmpty ? item.name : "\(item.name)\n\(item.detail)"
        } else {
            textField.maximumNumberOfLines = 4
            textField.font = .systemFont(ofSize: 12)
            let favorite = favorites[row]
            textField.stringValue = [
                "别名：\(favorite.displayAlias)",
                "地点：\(favorite.title)",
                "地址：\(favorite.displayDetail)",
                "坐标：\(favorite.coordinateText)"
            ].joined(separator: "\n")
        }
        return textField
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
